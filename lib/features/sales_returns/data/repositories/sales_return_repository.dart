import 'dart:async';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fatoora/core/settings/business_settings_defaults.dart';
import 'package:fatoora/core/settings/business_permission_resolver.dart';
import 'package:fatoora/features/auth/data/repositories/auth_repository.dart';
import 'package:fatoora/features/customers/data/models/customer_model.dart';
import 'package:fatoora/features/invoices/data/models/invoice_enums.dart';
import 'package:fatoora/features/invoices/data/models/invoice_item_snapshot.dart';
import 'package:fatoora/features/invoices/data/models/invoice_model.dart';
import 'package:fatoora/features/items/data/models/item_model.dart';
import 'package:fatoora/features/sales_returns/data/models/sales_return_enums.dart';
import 'package:fatoora/features/sales_returns/data/models/sales_return_item_model.dart';
import 'package:fatoora/features/sales_returns/data/models/sales_return_model.dart';
import 'package:fatoora/features/settings/data/models/app_settings_model.dart';
import 'package:fatoora/features/settings/data/models/document_settings_model.dart';
import 'package:fatoora/features/shared/business/business_user_context.dart';
import 'package:firebase_auth/firebase_auth.dart';

enum SalesReturnRepositoryError {
  unauthenticated,
  permissionDenied,
  createDisabled,
  unavailable,
  timeout,
  notFound,
  invalidData,
  invalidState,
  quantityExceeded,
  alreadyPosted,
  unknown,
}

class SalesReturnRepositoryException implements Exception {
  const SalesReturnRepositoryException(this.error, [this.cause]);

  final SalesReturnRepositoryError error;
  final Object? cause;
}

class SalesReturnQuantityFailure {
  const SalesReturnQuantityFailure({
    required this.itemName,
    required this.requestedQuantity,
    required this.availableQuantity,
  });

  final String itemName;
  final double requestedQuantity;
  final double availableQuantity;
}

class SalesReturnRepository {
  SalesReturnRepository({
    FirebaseFirestore? firestore,
    FirebaseAuth? firebaseAuth,
    BusinessUserContextReader? contextReader,
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _contextReader =
           contextReader ??
           BusinessUserContextReader(
             firestore: firestore,
             firebaseAuth: firebaseAuth,
           );

  final FirebaseFirestore _firestore;
  final BusinessUserContextReader _contextReader;

  CollectionReference<Map<String, dynamic>> _returns(String companyId) {
    return _firestore
        .collection('companies')
        .doc(companyId)
        .collection('sales_returns');
  }

  CollectionReference<Map<String, dynamic>> _invoices(String companyId) {
    return _firestore
        .collection('companies')
        .doc(companyId)
        .collection('invoices');
  }

  CollectionReference<Map<String, dynamic>> _customers(String companyId) {
    return _firestore
        .collection('companies')
        .doc(companyId)
        .collection('customers');
  }

  CollectionReference<Map<String, dynamic>> _transactions(String companyId) {
    return _firestore
        .collection('companies')
        .doc(companyId)
        .collection('customer_transactions');
  }

  CollectionReference<Map<String, dynamic>> _cashMovements(String companyId) {
    return _firestore
        .collection('companies')
        .doc(companyId)
        .collection('cash_movements');
  }

  CollectionReference<Map<String, dynamic>> _stockMovements(String companyId) {
    return _firestore
        .collection('companies')
        .doc(companyId)
        .collection('stock_movements');
  }

  CollectionReference<Map<String, dynamic>> get _items =>
      _firestore.collection('items');

  DocumentReference<Map<String, dynamic>> _returnCounter(
    String companyId,
    int year,
  ) {
    return _firestore
        .collection('companies')
        .doc(companyId)
        .collection('counters')
        .doc('sales_returns_$year');
  }

  DocumentReference<Map<String, dynamic>> _appSettings(String companyId) {
    return _firestore
        .collection('companies')
        .doc(companyId)
        .collection('settings')
        .doc('app');
  }

  Future<List<SalesReturnModel>> fetchSalesReturns({
    String companyId = AuthRepository.defaultCompanyId,
    SalesReturnStatus? status,
    String searchText = '',
    DateTime? fromDate,
    DateTime? toDate,
    int maxResults = 150,
  }) {
    return _run(() async {
      final user = await _contextReader.requireApprovedUser();
      final resolvedCompanyId = _resolveCompanyId(companyId, user);
      Query<Map<String, dynamic>> query = _returns(resolvedCompanyId);
      if (user.isSalesRep) {
        query = query.where('salesRepId', isEqualTo: user.uid);
      }
      final snapshot = await query
          .limit(maxResults)
          .get()
          .timeout(const Duration(seconds: 20));
      final normalizedSearch = searchText.trim().toLowerCase();
      final result = snapshot.docs
          .map(SalesReturnModel.fromFirestore)
          .where((salesReturn) {
            final matchesStatus =
                status == null || salesReturn.status == status;
            final matchesFrom =
                fromDate == null ||
                !salesReturn.returnDate.isBefore(_startOfDay(fromDate));
            final matchesTo =
                toDate == null ||
                !salesReturn.returnDate.isAfter(_endOfDay(toDate));
            final matchesSearch =
                normalizedSearch.isEmpty ||
                salesReturn.returnNumber.toLowerCase().contains(
                  normalizedSearch,
                ) ||
                salesReturn.originalInvoiceNumber.toLowerCase().contains(
                  normalizedSearch,
                ) ||
                (salesReturn.customerSnapshot?.name.toLowerCase() ?? '')
                    .contains(normalizedSearch) ||
                salesReturn.salesRepName.toLowerCase().contains(
                  normalizedSearch,
                );
            return matchesStatus && matchesFrom && matchesTo && matchesSearch;
          })
          .toList(growable: false);
      result.sort((a, b) => b.returnDate.compareTo(a.returnDate));
      return result;
    });
  }

  Future<SalesReturnModel?> getSalesReturnById({
    String companyId = AuthRepository.defaultCompanyId,
    required String returnId,
  }) {
    return _run(() async {
      final user = await _contextReader.requireApprovedUser();
      final resolvedCompanyId = _resolveCompanyId(companyId, user);
      final snapshot = await _returns(
        resolvedCompanyId,
      ).doc(returnId).get().timeout(const Duration(seconds: 20));
      if (!snapshot.exists) return null;
      final salesReturn = SalesReturnModel.fromFirestore(snapshot);
      _requireCanAccessReturn(user, salesReturn);
      return salesReturn;
    });
  }

  Future<Map<String, double>> getConfirmedReturnedQuantities({
    String companyId = AuthRepository.defaultCompanyId,
    required String originalInvoiceId,
  }) {
    return _run(() async {
      final user = await _contextReader.requireApprovedUser();
      final resolvedCompanyId = _resolveCompanyId(companyId, user);
      return _fetchConfirmedReturnedQuantities(
        companyId: resolvedCompanyId,
        originalInvoiceId: originalInvoiceId,
        user: user,
      );
    });
  }

  Future<SalesReturnModel> saveDraft({required SalesReturnModel salesReturn}) {
    return _run(() async {
      final user = await _contextReader.requireApprovedUser();
      final companyId = _resolveCompanyId(salesReturn.companyId, user);
      final permissions = await _loadPermissions(companyId, user);
      if (!permissions.createReturns) {
        throw const SalesReturnRepositoryException(
          SalesReturnRepositoryError.createDisabled,
        );
      }
      final fallbackQuantities = await _fetchConfirmedReturnedQuantities(
        companyId: companyId,
        originalInvoiceId: salesReturn.originalInvoiceId,
        user: user,
      );
      late SalesReturnModel saved;
      final returnRef = salesReturn.id.trim().isEmpty
          ? _returns(companyId).doc()
          : _returns(companyId).doc(salesReturn.id.trim());

      await _firestore
          .runTransaction((transaction) async {
            final invoiceRef = _invoices(
              companyId,
            ).doc(salesReturn.originalInvoiceId.trim());
            final invoiceSnapshot = await transaction.get(invoiceRef);
            if (!invoiceSnapshot.exists) {
              throw const SalesReturnRepositoryException(
                SalesReturnRepositoryError.notFound,
              );
            }
            final invoice = InvoiceModel.fromFirestore(invoiceSnapshot);
            _requireEligibleInvoice(user, invoice);

            final existingSnapshot = await transaction.get(returnRef);
            SalesReturnModel? existing;
            if (existingSnapshot.exists) {
              existing = SalesReturnModel.fromFirestore(existingSnapshot);
              _requireCanAccessReturn(user, existing);
              if (!existing.isDraft) {
                throw const SalesReturnRepositoryException(
                  SalesReturnRepositoryError.invalidState,
                );
              }
            }

            if (existing != null &&
                existing.originalInvoiceId != salesReturn.originalInvoiceId) {
              throw const SalesReturnRepositoryException(
                SalesReturnRepositoryError.invalidData,
              );
            }
            _ReturnNumberAllocation? numberAllocation;
            final returnNumber = existing?.returnNumber.isNotEmpty == true
                ? existing!.returnNumber
                : (numberAllocation = await _allocateReturnNumber(
                    transaction: transaction,
                    companyId: companyId,
                    returnDate: salesReturn.returnDate,
                  )).number;
            final normalized = _normalizeReturn(
              input: salesReturn,
              originalInvoice: invoice,
              user: user,
              id: returnRef.id,
              returnNumber: returnNumber,
              status: SalesReturnStatus.draft,
              createdAt: existing?.createdAt ?? DateTime.now(),
              updatedAt: DateTime.now(),
              existing: existing,
            );
            _validateAvailableQuantities(
              salesReturn: normalized,
              originalInvoice: invoice,
              alreadyReturned: fallbackQuantities,
            );
            saved = normalized;
            transaction.set(returnRef, {
              ...normalized.toMap(),
              'createdAt': existing == null
                  ? FieldValue.serverTimestamp()
                  : Timestamp.fromDate(existing.createdAt),
              'updatedAt': FieldValue.serverTimestamp(),
            });
            if (numberAllocation != null) {
              transaction.set(
                numberAllocation.counterRef,
                numberAllocation.counterData,
                SetOptions(merge: true),
              );
            }
          })
          .timeout(const Duration(seconds: 20));
      return saved;
    });
  }

  Future<SalesReturnModel> confirmSalesReturn({
    required SalesReturnModel salesReturn,
  }) {
    return _run(() async {
      final user = await _contextReader.requireApprovedUser();
      final companyId = _resolveCompanyId(salesReturn.companyId, user);
      final permissions = await _loadPermissions(companyId, user);
      if (!permissions.createReturns) {
        throw const SalesReturnRepositoryException(
          SalesReturnRepositoryError.createDisabled,
        );
      }
      final fallbackQuantities = await _fetchConfirmedReturnedQuantities(
        companyId: companyId,
        originalInvoiceId: salesReturn.originalInvoiceId,
        user: user,
      );
      late SalesReturnModel confirmed;
      final returnRef = salesReturn.id.trim().isEmpty
          ? _returns(companyId).doc()
          : _returns(companyId).doc(salesReturn.id.trim());

      await _firestore
          .runTransaction((transaction) async {
            final invoiceRef = _invoices(
              companyId,
            ).doc(salesReturn.originalInvoiceId.trim());
            final invoiceSnapshot = await transaction.get(invoiceRef);
            if (!invoiceSnapshot.exists) {
              throw const SalesReturnRepositoryException(
                SalesReturnRepositoryError.notFound,
              );
            }
            final originalInvoice = InvoiceModel.fromFirestore(invoiceSnapshot);
            _requireEligibleInvoice(user, originalInvoice);

            final existingSnapshot = await transaction.get(returnRef);
            SalesReturnModel? existing;
            if (existingSnapshot.exists) {
              existing = SalesReturnModel.fromFirestore(existingSnapshot);
              _requireCanAccessReturn(user, existing);
              if (existing.originalInvoiceId != salesReturn.originalInvoiceId) {
                throw const SalesReturnRepositoryException(
                  SalesReturnRepositoryError.invalidData,
                );
              }
              if (existing.isConfirmed) {
                if (existing.financialPosted && existing.inventoryPosted) {
                  confirmed = existing;
                  return;
                }
                throw const SalesReturnRepositoryException(
                  SalesReturnRepositoryError.alreadyPosted,
                );
              }
              if (!existing.isDraft) {
                throw const SalesReturnRepositoryException(
                  SalesReturnRepositoryError.invalidState,
                );
              }
            }

            final source = existing ?? salesReturn;
            _ReturnNumberAllocation? numberAllocation;
            final returnNumber = existing?.returnNumber.isNotEmpty == true
                ? existing!.returnNumber
                : (numberAllocation = await _allocateReturnNumber(
                    transaction: transaction,
                    companyId: companyId,
                    returnDate: source.returnDate,
                  )).number;
            var normalized = _normalizeReturn(
              input: source,
              originalInvoice: originalInvoice,
              user: user,
              id: returnRef.id,
              returnNumber: returnNumber,
              status: SalesReturnStatus.confirmed,
              createdAt: existing?.createdAt ?? DateTime.now(),
              updatedAt: DateTime.now(),
              existing: existing,
            );

            final rawAllocation = invoiceSnapshot
                .data()?['returnedQuantitiesByItem'];
            final alreadyReturned = rawAllocation is Map
                ? _readQuantityMap(rawAllocation)
                : fallbackQuantities;
            _validateAvailableQuantities(
              salesReturn: normalized,
              originalInvoice: originalInvoice,
              alreadyReturned: alreadyReturned,
            );

            final inventoryPosting = await _buildInventoryPosting(
              transaction: transaction,
              salesReturn: normalized,
              user: user,
            );
            final financialPosting = await _buildFinancialPosting(
              transaction: transaction,
              salesReturn: normalized,
              user: user,
            );
            final allocation = _nextAllocationMap(
              current: alreadyReturned,
              salesReturn: normalized,
            );

            normalized = normalized.copyWith(
              financialPosted: true,
              inventoryPosted: true,
              financialPostedAt: DateTime.now(),
              inventoryPostedAt: DateTime.now(),
              stockMovementIds: inventoryPosting.movementRefs
                  .map((reference) => reference.id)
                  .toList(growable: false),
              customerTransactionIds:
                  financialPosting.customerTransactionRef == null
                  ? const []
                  : [financialPosting.customerTransactionRef!.id],
              cashMovementIds: financialPosting.cashMovementRef == null
                  ? const []
                  : [financialPosting.cashMovementRef!.id],
            );
            confirmed = normalized;

            transaction.set(returnRef, {
              ...normalized.toMap(),
              'createdAt': existing == null
                  ? FieldValue.serverTimestamp()
                  : Timestamp.fromDate(existing.createdAt),
              'updatedAt': FieldValue.serverTimestamp(),
            });
            if (numberAllocation != null) {
              transaction.set(
                numberAllocation.counterRef,
                numberAllocation.counterData,
                SetOptions(merge: true),
              );
            }
            transaction.update(invoiceRef, {
              // This is an allocation projection, not a second return ledger.
              // It gives the transaction one document to guard against two
              // simultaneous returns exceeding the original invoice quantity.
              'returnedQuantitiesByItem': allocation,
              'lastSalesReturnId': returnRef.id,
              'updatedAt': FieldValue.serverTimestamp(),
            });
            _applyInventoryPosting(transaction, inventoryPosting);
            _applyFinancialPosting(transaction, financialPosting);
          })
          .timeout(const Duration(seconds: 20));
      return confirmed;
    });
  }

  Future<Map<String, double>> _fetchConfirmedReturnedQuantities({
    required String companyId,
    required String originalInvoiceId,
    required BusinessUserContext user,
  }) async {
    if (originalInvoiceId.trim().isEmpty) return const {};
    Query<Map<String, dynamic>> query = _returns(companyId);
    if (user.isSalesRep) {
      query = query.where('salesRepId', isEqualTo: user.uid);
    } else {
      query = query.where('originalInvoiceId', isEqualTo: originalInvoiceId);
    }
    final snapshot = await query
        .limit(250)
        .get()
        .timeout(const Duration(seconds: 20));
    final result = <String, double>{};
    for (final document in snapshot.docs) {
      final salesReturn = SalesReturnModel.fromFirestore(document);
      if (salesReturn.originalInvoiceId != originalInvoiceId ||
          !salesReturn.isConfirmed) {
        continue;
      }
      for (final item in salesReturn.items) {
        final lineId = item.originalInvoiceItemId;
        if (lineId.isEmpty) continue;
        result[lineId] = _round((result[lineId] ?? 0) + item.returnedQuantity);
      }
    }
    return result;
  }

  Future<_ReturnNumberAllocation> _allocateReturnNumber({
    required Transaction transaction,
    required String companyId,
    required DateTime returnDate,
  }) async {
    final year = returnDate.year;
    final settingsSnapshot = await transaction.get(_appSettings(companyId));
    final documents = AppSettingsModel.fromMap(
      settingsSnapshot.data(),
    ).documentSettings;
    final prefix = BusinessSettingsDefaults.prefix(
      documents.salesReturnPrefix,
      DocumentSettingsModel.defaults.salesReturnPrefix,
    );
    final counterRef = _returnCounter(companyId, year);
    final counter = await transaction.get(counterRef);
    final current = counter.data()?['lastNumber'];
    final next = current is num ? current.toInt() + 1 : 1;
    final counterData = {
      'id': counterRef.id,
      'companyId': companyId,
      'year': year,
      'lastNumber': next,
      'prefix': prefix,
      'updatedAt': FieldValue.serverTimestamp(),
    };
    return _ReturnNumberAllocation(
      number: BusinessSettingsDefaults.documentNumber(
        prefix: prefix,
        year: year,
        sequence: next,
      ),
      counterRef: counterRef,
      counterData: counterData,
    );
  }

  Future<EffectiveBusinessPermissions> _loadPermissions(
    String companyId,
    BusinessUserContext user,
  ) async {
    final snapshot = await _appSettings(
      companyId,
    ).get().timeout(const Duration(seconds: 20));
    final settings = AppSettingsModel.fromMap(snapshot.data());
    return EffectiveBusinessPermissions.fromUser(
      user,
      settings.permissionSettings,
    );
  }

  SalesReturnModel _normalizeReturn({
    required SalesReturnModel input,
    required InvoiceModel originalInvoice,
    required BusinessUserContext user,
    required String id,
    required String returnNumber,
    required SalesReturnStatus status,
    required DateTime createdAt,
    required DateTime updatedAt,
    SalesReturnModel? existing,
  }) {
    if (originalInvoice.invoiceStatus != InvoiceStatus.confirmed ||
        originalInvoice.customerSnapshot == null ||
        originalInvoice.customerId.trim().isEmpty) {
      throw const SalesReturnRepositoryException(
        SalesReturnRepositoryError.invalidState,
      );
    }
    if (input.reason.trim().isEmpty || input.items.isEmpty) {
      throw const SalesReturnRepositoryException(
        SalesReturnRepositoryError.invalidData,
      );
    }

    final invoiceItemsByLineId = <String, InvoiceItemSnapshot>{
      for (var index = 0; index < originalInvoice.items.length; index++)
        originalInvoiceItemId(originalInvoice.id, index):
            originalInvoice.items[index],
    };
    final seenLineIds = <String>{};
    final normalizedItems = <SalesReturnItemModel>[];
    for (final returnItem in input.items) {
      final lineId = returnItem.originalInvoiceItemId.trim();
      final invoiceItem = invoiceItemsByLineId[lineId];
      if (invoiceItem == null || !seenLineIds.add(lineId)) {
        throw const SalesReturnRepositoryException(
          SalesReturnRepositoryError.invalidData,
        );
      }
      final quantity = _round(returnItem.returnedQuantity);
      if (quantity <= 0 || !quantity.isFinite) {
        throw const SalesReturnRepositoryException(
          SalesReturnRepositoryError.invalidData,
        );
      }
      final unitPrice = _netUnitPrice(invoiceItem);
      final taxPercent = _round(
        invoiceItem.taxPercent.clamp(0, 100).toDouble(),
      );
      final subtotal = _round(quantity * unitPrice);
      final taxAmount = _round(subtotal * taxPercent / 100);
      normalizedItems.add(
        SalesReturnItemModel(
          itemId: invoiceItem.itemId,
          itemName: invoiceItem.itemName,
          itemCode: invoiceItem.itemCode,
          unit: invoiceItem.unit,
          returnedQuantity: quantity,
          unitPrice: unitPrice,
          taxPercent: taxPercent,
          subtotal: subtotal,
          taxAmount: taxAmount,
          total: _round(subtotal + taxAmount),
          originalInvoiceItemId: lineId,
        ),
      );
    }
    final subtotal = _round(
      normalizedItems.fold<double>(0, (total, item) => total + item.subtotal),
    );
    final totalTax = _round(
      normalizedItems.fold<double>(0, (total, item) => total + item.taxAmount),
    );
    final grandTotal = _round(subtotal + totalTax);
    if (grandTotal <= 0) {
      throw const SalesReturnRepositoryException(
        SalesReturnRepositoryError.invalidData,
      );
    }

    final sourceRepId = originalInvoice.salesRepId.trim().isEmpty
        ? originalInvoice.createdByUid
        : originalInvoice.salesRepId;
    final sourceRepName = originalInvoice.salesRepName.trim().isEmpty
        ? originalInvoice.createdByName
        : originalInvoice.salesRepName;
    return SalesReturnModel(
      id: id,
      companyId: originalInvoice.companyId,
      returnNumber: returnNumber,
      originalInvoiceId: originalInvoice.id,
      originalInvoiceNumber: originalInvoice.invoiceNumber,
      customerId: originalInvoice.customerId,
      customerSnapshot: originalInvoice.customerSnapshot,
      items: normalizedItems,
      subtotal: subtotal,
      totalTax: totalTax,
      grandTotal: grandTotal,
      refundType: input.refundType,
      returnDate: input.returnDate,
      reason: input.reason.trim(),
      status: status,
      salesRepId: sourceRepId,
      salesRepName: _validName(sourceRepName),
      createdByUid: existing?.createdByUid ?? user.uid,
      createdByName: _validName(existing?.createdByName ?? user.name),
      createdByRole: existing?.createdByRole ?? user.role,
      financialPosted: existing?.financialPosted ?? false,
      inventoryPosted: existing?.inventoryPosted ?? false,
      financialPostedAt: existing?.financialPostedAt,
      inventoryPostedAt: existing?.inventoryPostedAt,
      stockMovementIds: existing?.stockMovementIds ?? const [],
      customerTransactionIds: existing?.customerTransactionIds ?? const [],
      cashMovementIds: existing?.cashMovementIds ?? const [],
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  void _validateAvailableQuantities({
    required SalesReturnModel salesReturn,
    required InvoiceModel originalInvoice,
    required Map<String, double> alreadyReturned,
  }) {
    final invoiceItemsByLineId = <String, InvoiceItemSnapshot>{
      for (var index = 0; index < originalInvoice.items.length; index++)
        originalInvoiceItemId(originalInvoice.id, index):
            originalInvoice.items[index],
    };
    for (final item in salesReturn.items) {
      final original = invoiceItemsByLineId[item.originalInvoiceItemId];
      if (original == null) {
        throw const SalesReturnRepositoryException(
          SalesReturnRepositoryError.invalidData,
        );
      }
      final available = _round(
        math
            .max(
              original.quantity -
                  (alreadyReturned[item.originalInvoiceItemId] ?? 0),
              0,
            )
            .toDouble(),
      );
      if (item.returnedQuantity <= 0 || item.returnedQuantity > available) {
        throw SalesReturnRepositoryException(
          SalesReturnRepositoryError.quantityExceeded,
          SalesReturnQuantityFailure(
            itemName: item.itemName,
            requestedQuantity: item.returnedQuantity,
            availableQuantity: available,
          ),
        );
      }
    }
  }

  Future<_InventoryPosting> _buildInventoryPosting({
    required Transaction transaction,
    required SalesReturnModel salesReturn,
    required BusinessUserContext user,
  }) async {
    final quantitiesByItem = <String, double>{};
    for (final item in salesReturn.items) {
      final itemId = item.itemId.trim();
      if (itemId.isEmpty || itemId.startsWith('manual-')) continue;
      quantitiesByItem[itemId] = _round(
        (quantitiesByItem[itemId] ?? 0) + item.returnedQuantity,
      );
    }
    final updates = <_InventoryItemUpdate>[];
    final movementRefs = <DocumentReference<Map<String, dynamic>>>[];
    final movementData = <Map<String, dynamic>>[];
    for (final entry in quantitiesByItem.entries) {
      final itemRef = _items.doc(entry.key);
      final itemSnapshot = await transaction.get(itemRef);
      if (!itemSnapshot.exists) {
        throw const SalesReturnRepositoryException(
          SalesReturnRepositoryError.notFound,
        );
      }
      final item = ItemModel.fromFirestore(itemSnapshot);
      if (item.deleted) {
        throw const SalesReturnRepositoryException(
          SalesReturnRepositoryError.invalidState,
        );
      }
      if (!item.trackStock) continue;
      final quantity = _round(entry.value);
      if (quantity <= 0) continue;
      final before = item.currentStock;
      final after = _round(before + quantity);
      final movementRef = _stockMovements(
        salesReturn.companyId,
      ).doc('${salesReturn.id}_${item.id}_sales_return');
      final existingMovement = await transaction.get(movementRef);
      if (existingMovement.exists) {
        throw const SalesReturnRepositoryException(
          SalesReturnRepositoryError.alreadyPosted,
        );
      }
      updates.add(
        _InventoryItemUpdate(
          itemRef: itemRef,
          data: {
            'currentStock': after,
            'inventoryUpdatedAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          },
        ),
      );
      movementRefs.add(movementRef);
      movementData.add({
        'id': movementRef.id,
        'companyId': salesReturn.companyId,
        'warehouseId': item.warehouseId.trim().isEmpty
            ? ItemModel.defaultWarehouseId
            : item.warehouseId,
        'itemId': item.id,
        'itemName': item.name,
        'itemCode': item.code,
        'movementType': 'sales_return',
        'direction': 'in',
        'quantity': quantity,
        'quantityBefore': before,
        'quantityAfter': after,
        'referenceType': 'sales_return',
        'referenceId': salesReturn.id,
        'referenceNumber': salesReturn.returnNumber,
        'movementDate': Timestamp.fromDate(salesReturn.returnDate),
        'notes': salesReturn.reason,
        'createdByUid': user.uid,
        'createdByName': user.name,
        'createdByRole': user.role,
        'createdAt': FieldValue.serverTimestamp(),
      });
    }
    return _InventoryPosting(
      itemUpdates: updates,
      movementRefs: movementRefs,
      movementData: movementData,
    );
  }

  Future<_FinancialPosting> _buildFinancialPosting({
    required Transaction transaction,
    required SalesReturnModel salesReturn,
    required BusinessUserContext user,
  }) async {
    DocumentReference<Map<String, dynamic>>? customerRef;
    Map<String, dynamic>? customerUpdate;
    DocumentReference<Map<String, dynamic>>? customerTransactionRef;
    Map<String, dynamic>? customerTransactionData;
    DocumentReference<Map<String, dynamic>>? cashMovementRef;
    Map<String, dynamic>? cashMovementData;

    if (salesReturn.refundType == RefundType.creditCustomerBalance) {
      customerRef = _customers(
        salesReturn.companyId,
      ).doc(salesReturn.customerId);
      final customerSnapshot = await transaction.get(customerRef);
      if (!customerSnapshot.exists) {
        throw const SalesReturnRepositoryException(
          SalesReturnRepositoryError.notFound,
        );
      }
      final customer = CustomerModel.fromFirestore(customerSnapshot);
      _requireCanAccessCustomer(user, customer);
      final balanceAfter = _round(
        customer.currentBalance - salesReturn.grandTotal,
      );
      customerUpdate = {
        'currentBalance': balanceAfter,
        'totalSales': customer.totalSales,
        'totalPaid': customer.totalPaid,
        'updatedAt': FieldValue.serverTimestamp(),
      };
      customerTransactionRef = _transactions(
        salesReturn.companyId,
      ).doc('${salesReturn.id}_credit');
      final existingTransaction = await transaction.get(customerTransactionRef);
      if (existingTransaction.exists) {
        throw const SalesReturnRepositoryException(
          SalesReturnRepositoryError.alreadyPosted,
        );
      }
      customerTransactionData = {
        'id': customerTransactionRef.id,
        'companyId': salesReturn.companyId,
        'customerId': customer.id,
        'customerName': customer.name,
        'transactionType': 'sales_return',
        'referenceId': salesReturn.id,
        'sourceCollection': 'sales_returns',
        'sourceId': salesReturn.id,
        'sourceNumber': salesReturn.returnNumber,
        'transactionDate': Timestamp.fromDate(salesReturn.returnDate),
        'debitAmount': 0,
        'creditAmount': salesReturn.grandTotal,
        'balanceAfter': balanceAfter,
        'notes': salesReturn.reason,
        'createdByUid': user.uid,
        'createdByName': user.name,
        'createdByRole': user.role,
        'salesRepId': salesReturn.salesRepId,
        'salesRepName': salesReturn.salesRepName,
        'createdAt': FieldValue.serverTimestamp(),
      };
    } else {
      cashMovementRef = _cashMovements(
        salesReturn.companyId,
      ).doc('${salesReturn.id}_cash_refund');
      final existingMovement = await transaction.get(cashMovementRef);
      if (existingMovement.exists) {
        throw const SalesReturnRepositoryException(
          SalesReturnRepositoryError.alreadyPosted,
        );
      }
      cashMovementData = {
        'id': cashMovementRef.id,
        'companyId': salesReturn.companyId,
        'movementType': 'sales_return',
        'type': 'sales_return_cash_refund',
        'direction': 'out',
        'amount': salesReturn.grandTotal,
        'paymentType': salesReturn.refundType.value,
        'customerId': salesReturn.customerId,
        'customerName': salesReturn.customerSnapshot?.name ?? '',
        'referenceId': salesReturn.id,
        'referenceNumber': salesReturn.returnNumber,
        'sourceCollection': 'sales_returns',
        'sourceId': salesReturn.id,
        'sourceNumber': salesReturn.returnNumber,
        'date': Timestamp.fromDate(salesReturn.returnDate),
        'movementDate': Timestamp.fromDate(salesReturn.returnDate),
        'notes': salesReturn.reason,
        'salesRepId': salesReturn.salesRepId,
        'salesRepName': salesReturn.salesRepName,
        'createdByUid': user.uid,
        'createdByName': user.name,
        'createdByRole': user.role,
        'createdAt': FieldValue.serverTimestamp(),
      };
    }
    return _FinancialPosting(
      customerRef: customerRef,
      customerUpdate: customerUpdate,
      customerTransactionRef: customerTransactionRef,
      customerTransactionData: customerTransactionData,
      cashMovementRef: cashMovementRef,
      cashMovementData: cashMovementData,
    );
  }

  Map<String, double> _nextAllocationMap({
    required Map<String, double> current,
    required SalesReturnModel salesReturn,
  }) {
    final next = Map<String, double>.from(current);
    for (final item in salesReturn.items) {
      next[item.originalInvoiceItemId] = _round(
        (next[item.originalInvoiceItemId] ?? 0) + item.returnedQuantity,
      );
    }
    return next;
  }

  void _applyInventoryPosting(
    Transaction transaction,
    _InventoryPosting posting,
  ) {
    for (final update in posting.itemUpdates) {
      transaction.update(update.itemRef, update.data);
    }
    for (var index = 0; index < posting.movementRefs.length; index++) {
      transaction.set(posting.movementRefs[index], posting.movementData[index]);
    }
  }

  void _applyFinancialPosting(
    Transaction transaction,
    _FinancialPosting posting,
  ) {
    if (posting.customerRef != null && posting.customerUpdate != null) {
      transaction.update(posting.customerRef!, posting.customerUpdate!);
    }
    if (posting.customerTransactionRef != null &&
        posting.customerTransactionData != null) {
      transaction.set(
        posting.customerTransactionRef!,
        posting.customerTransactionData!,
      );
    }
    if (posting.cashMovementRef != null && posting.cashMovementData != null) {
      transaction.set(posting.cashMovementRef!, posting.cashMovementData!);
    }
  }

  void _requireEligibleInvoice(BusinessUserContext user, InvoiceModel invoice) {
    if (invoice.invoiceStatus != InvoiceStatus.confirmed) {
      throw const SalesReturnRepositoryException(
        SalesReturnRepositoryError.invalidState,
      );
    }
    if (user.isAdmin) return;
    if (user.isSalesRep &&
        (invoice.salesRepId == user.uid || invoice.createdByUid == user.uid)) {
      return;
    }
    throw const SalesReturnRepositoryException(
      SalesReturnRepositoryError.permissionDenied,
    );
  }

  void _requireCanAccessReturn(
    BusinessUserContext user,
    SalesReturnModel salesReturn,
  ) {
    if (user.isAdmin) return;
    if (user.isSalesRep &&
        (salesReturn.salesRepId == user.uid ||
            salesReturn.createdByUid == user.uid)) {
      return;
    }
    throw const SalesReturnRepositoryException(
      SalesReturnRepositoryError.permissionDenied,
    );
  }

  void _requireCanAccessCustomer(
    BusinessUserContext user,
    CustomerModel customer,
  ) {
    if (user.isAdmin) return;
    if (user.isSalesRep && customer.createdByUid == user.uid) return;
    throw const SalesReturnRepositoryException(
      SalesReturnRepositoryError.permissionDenied,
    );
  }

  String _resolveCompanyId(String requested, BusinessUserContext user) {
    final companyId = requested.trim().isEmpty
        ? AuthRepository.defaultCompanyId
        : requested.trim();
    if (companyId != user.companyId) {
      throw const SalesReturnRepositoryException(
        SalesReturnRepositoryError.permissionDenied,
      );
    }
    return companyId;
  }

  double _netUnitPrice(InvoiceItemSnapshot item) {
    if (item.quantity <= 0) return 0;
    return _round(math.max(item.subtotal - item.discount, 0) / item.quantity);
  }

  Map<String, double> _readQuantityMap(Map<dynamic, dynamic> source) {
    final result = <String, double>{};
    for (final entry in source.entries) {
      final key = entry.key?.toString().trim() ?? '';
      final value = entry.value;
      if (key.isEmpty || value is! num || !value.isFinite) continue;
      result[key] = _round(value.toDouble());
    }
    return result;
  }

  DateTime _startOfDay(DateTime date) =>
      DateTime(date.year, date.month, date.day);

  DateTime _endOfDay(DateTime date) =>
      DateTime(date.year, date.month, date.day, 23, 59, 59, 999);

  double _round(double value) {
    if (!value.isFinite) return 0;
    return (value * 1000).roundToDouble() / 1000;
  }

  String _validName(String value) =>
      value.trim().isEmpty || value.trim().toLowerCase() == 'undefined'
      ? 'User'
      : value.trim();

  Future<T> _run<T>(Future<T> Function() operation) async {
    try {
      return await operation();
    } on SalesReturnRepositoryException {
      rethrow;
    } on BusinessUserContextException catch (error) {
      throw SalesReturnRepositoryException(
        _mapContextError(error.error),
        error,
      );
    } on TimeoutException catch (error) {
      throw SalesReturnRepositoryException(
        SalesReturnRepositoryError.timeout,
        error,
      );
    } on FirebaseException catch (error) {
      throw SalesReturnRepositoryException(
        _mapFirebaseError(error.code),
        error,
      );
    } catch (error) {
      throw SalesReturnRepositoryException(
        SalesReturnRepositoryError.unknown,
        error,
      );
    }
  }

  SalesReturnRepositoryError _mapContextError(BusinessUserContextError error) {
    return switch (error) {
      BusinessUserContextError.unauthenticated ||
      BusinessUserContextError.profileMissing =>
        SalesReturnRepositoryError.unauthenticated,
      BusinessUserContextError.permissionDenied =>
        SalesReturnRepositoryError.permissionDenied,
      BusinessUserContextError.invalidProfile =>
        SalesReturnRepositoryError.invalidData,
      BusinessUserContextError.timeout => SalesReturnRepositoryError.timeout,
    };
  }

  SalesReturnRepositoryError _mapFirebaseError(String code) {
    return switch (code) {
      'permission-denied' => SalesReturnRepositoryError.permissionDenied,
      'unauthenticated' => SalesReturnRepositoryError.unauthenticated,
      'unavailable' ||
      'deadline-exceeded' => SalesReturnRepositoryError.unavailable,
      'not-found' => SalesReturnRepositoryError.notFound,
      'failed-precondition' ||
      'aborted' => SalesReturnRepositoryError.invalidState,
      _ => SalesReturnRepositoryError.unknown,
    };
  }
}

String originalInvoiceItemId(String invoiceId, int index) =>
    '$invoiceId:$index';

class _InventoryPosting {
  const _InventoryPosting({
    required this.itemUpdates,
    required this.movementRefs,
    required this.movementData,
  });

  final List<_InventoryItemUpdate> itemUpdates;
  final List<DocumentReference<Map<String, dynamic>>> movementRefs;
  final List<Map<String, dynamic>> movementData;
}

class _ReturnNumberAllocation {
  const _ReturnNumberAllocation({
    required this.number,
    required this.counterRef,
    required this.counterData,
  });

  final String number;
  final DocumentReference<Map<String, dynamic>> counterRef;
  final Map<String, dynamic> counterData;
}

class _InventoryItemUpdate {
  const _InventoryItemUpdate({required this.itemRef, required this.data});

  final DocumentReference<Map<String, dynamic>> itemRef;
  final Map<String, dynamic> data;
}

class _FinancialPosting {
  const _FinancialPosting({
    required this.customerRef,
    required this.customerUpdate,
    required this.customerTransactionRef,
    required this.customerTransactionData,
    required this.cashMovementRef,
    required this.cashMovementData,
  });

  final DocumentReference<Map<String, dynamic>>? customerRef;
  final Map<String, dynamic>? customerUpdate;
  final DocumentReference<Map<String, dynamic>>? customerTransactionRef;
  final Map<String, dynamic>? customerTransactionData;
  final DocumentReference<Map<String, dynamic>>? cashMovementRef;
  final Map<String, dynamic>? cashMovementData;
}
