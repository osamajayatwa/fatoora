import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:fatoora/core/data/firestore_query_pager.dart';
import 'package:fatoora/core/firebase/trusted_callable_client.dart';
import 'package:fatoora/core/finance/financial_posting_calculator.dart';
import 'package:fatoora/core/settings/business_settings_defaults.dart';
import 'package:fatoora/core/settings/business_permission_resolver.dart';
import 'package:fatoora/features/auth/data/repositories/auth_repository.dart';
import 'package:fatoora/features/customers/data/models/customer_model.dart';
import 'package:fatoora/features/invoices/data/models/invoice_enums.dart';
import 'package:fatoora/features/invoices/data/models/invoice_item_snapshot.dart';
import 'package:fatoora/features/invoices/data/models/invoice_list_query.dart';
import 'package:fatoora/features/invoices/data/models/invoice_model.dart';
import 'package:fatoora/features/items/data/models/item_model.dart';
import 'package:fatoora/features/rep_inventory/data/models/rep_inventory_enums.dart';
import 'package:fatoora/features/settings/data/models/app_settings_model.dart';
import 'package:fatoora/features/settings/data/models/document_settings_model.dart';
import 'package:fatoora/features/shared/business/business_user_context.dart';
import 'package:firebase_auth/firebase_auth.dart';

enum InvoiceRepositoryError {
  unauthenticated,
  permissionDenied,
  priceEditDisabled,
  discountDisabled,
  unavailable,
  timeout,
  notFound,
  invalidData,
  invalidState,
  locked,
  unknown,
}

class InvoiceRepositoryException implements Exception {
  const InvoiceRepositoryException(this.error, [this.cause]);

  final InvoiceRepositoryError error;
  final Object? cause;
}

class InsufficientStockFailure {
  const InsufficientStockFailure({
    required this.itemName,
    required this.requestedQuantity,
    required this.availableQuantity,
  });

  final String itemName;
  final double requestedQuantity;
  final double availableQuantity;
}

class InvoiceRepository {
  InvoiceRepository({
    FirebaseFirestore? firestore,
    FirebaseFunctions? functions,
    FirebaseAuth? firebaseAuth,
    BusinessUserContextReader? contextReader,
    TrustedCallableClient? trustedCallableClient,
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _trustedCallableClient =
           trustedCallableClient ??
           TrustedCallableClient.forDefaultApp(
             firebaseAuth: firebaseAuth,
             functions: functions,
           ),
       _contextReader =
           contextReader ??
           BusinessUserContextReader(
             firestore: firestore,
             firebaseAuth: firebaseAuth,
           );

  final FirebaseFirestore _firestore;
  final TrustedCallableClient _trustedCallableClient;
  final BusinessUserContextReader _contextReader;

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

  CollectionReference<Map<String, dynamic>> get _items =>
      _firestore.collection('items');

  DocumentReference<Map<String, dynamic>> _invoiceCounter(
    String companyId,
    int year,
  ) {
    return _firestore
        .collection('companies')
        .doc(companyId)
        .collection('counters')
        .doc('invoices_$year');
  }

  DocumentReference<Map<String, dynamic>> _appSettings(String companyId) {
    return _firestore
        .collection('companies')
        .doc(companyId)
        .collection('settings')
        .doc('app');
  }

  Future<List<InvoiceModel>> getInvoices({
    required String companyId,
    InvoiceType? type,
    InvoiceStatus? status,
    PaymentStatus? paymentStatus,
    InvoiceReturnStatus? returnStatus,
    String? salesRepId,
    String? customerId,
    DateTime? fromDate,
    DateTime? toDate,
    String? searchText,
    InvoiceSortField sortField = InvoiceSortField.invoiceDate,
    InvoiceSortDirection sortDirection = InvoiceSortDirection.descending,
  }) {
    return _run(() async {
      final user = await _contextReader.requireApprovedUser();
      final resolvedCompanyId = _resolveCompanyId(companyId, user);
      final query = _invoiceListQuery(
        companyId: resolvedCompanyId,
        user: user,
        type: type,
        status: status,
        paymentStatus: paymentStatus,
        returnStatus: returnStatus,
        salesRepId: salesRepId,
        customerId: customerId,
        fromDate: fromDate,
        toDate: toDate,
        searchText: searchText,
        sortField: sortField,
        sortDirection: sortDirection,
      );
      final documents = await query.getAllPages();
      return documents.map(InvoiceModel.fromFirestore).toList();
    });
  }

  Future<FirestorePage<InvoiceModel>> getInvoicesPage({
    required String companyId,
    InvoiceType? type,
    InvoiceStatus? status,
    PaymentStatus? paymentStatus,
    InvoiceReturnStatus? returnStatus,
    String? salesRepId,
    String? customerId,
    DateTime? fromDate,
    DateTime? toDate,
    String? searchText,
    InvoiceSortField sortField = InvoiceSortField.invoiceDate,
    InvoiceSortDirection sortDirection = InvoiceSortDirection.descending,
    FirestorePageCursor? after,
    int pageSize = 50,
  }) {
    return _run(() async {
      final user = await _contextReader.requireApprovedUser();
      final resolvedCompanyId = _resolveCompanyId(companyId, user);
      final query = _invoiceListQuery(
        companyId: resolvedCompanyId,
        user: user,
        type: type,
        status: status,
        paymentStatus: paymentStatus,
        returnStatus: returnStatus,
        salesRepId: salesRepId,
        customerId: customerId,
        fromDate: fromDate,
        toDate: toDate,
        searchText: searchText,
        sortField: sortField,
        sortDirection: sortDirection,
      );
      return query.getPage(
        decode: InvoiceModel.fromFirestore,
        after: after,
        pageSize: pageSize,
      );
    });
  }

  Future<List<InvoiceFilterOption>> getInvoiceCustomerFilterOptions({
    required String companyId,
    String searchText = '',
    int limit = 30,
  }) {
    return _run(() async {
      final user = await _contextReader.requireApprovedUser();
      final resolvedCompanyId = _resolveCompanyId(companyId, user);
      Query<Map<String, dynamic>> query = _customers(
        resolvedCompanyId,
      ).where('active', isEqualTo: true);
      if (user.isSalesRep) {
        query = query.where('createdByUid', isEqualTo: user.uid);
      }
      final normalizedSearch = _normalize(searchText);
      if (normalizedSearch.isNotEmpty) {
        query = query.where('searchKeywords', arrayContains: normalizedSearch);
      }
      final snapshot = await query
          .orderBy('nameLower')
          .limit(limit.clamp(1, 50).toInt())
          .get()
          .timeout(const Duration(seconds: 20));
      return snapshot.docs
          .where((document) {
            final name = document.data()['name']?.toString().trim() ?? '';
            return name.isNotEmpty && name.toLowerCase() != 'undefined';
          })
          .map((document) {
            final data = document.data();
            return InvoiceFilterOption(
              id: document.id,
              label: data['name']!.toString().trim(),
              subtitle: data['phone']?.toString().trim() ?? '',
            );
          })
          .toList(growable: false);
    });
  }

  Future<List<InvoiceFilterOption>> getInvoiceSalesRepFilterOptions({
    required String companyId,
    String searchText = '',
    int limit = 50,
  }) {
    return _run(() async {
      final user = await _contextReader.requireApprovedUser();
      final resolvedCompanyId = _resolveCompanyId(companyId, user);
      final normalizedSearch = _normalize(searchText);
      if (user.isSalesRep) {
        final option = InvoiceFilterOption(
          id: user.uid,
          label: user.name,
          subtitle: user.email,
        );
        return normalizedSearch.isEmpty ||
                _normalize(option.label).contains(normalizedSearch) ||
                _normalize(option.subtitle).contains(normalizedSearch)
            ? [option]
            : const [];
      }

      final snapshot = await _firestore
          .collection('users')
          .where('role', whereIn: const ['admin', 'sales_rep'])
          .where('active', isEqualTo: true)
          .where('approvalStatus', isEqualTo: 'approved')
          .limit(200)
          .get()
          .timeout(const Duration(seconds: 20));
      final options =
          snapshot.docs
              .where((document) {
                final data = document.data();
                if (data['active'] != true ||
                    data['approvalStatus'] != 'approved' ||
                    data['name']?.toString().trim().isEmpty != false ||
                    data['name']?.toString().trim().toLowerCase() ==
                        'undefined' ||
                    (data['companyId']?.toString().trim().isNotEmpty == true &&
                        data['companyId']?.toString().trim() !=
                            resolvedCompanyId)) {
                  return false;
                }
                if (normalizedSearch.isEmpty) return true;
                final name = _normalize(data['name']?.toString() ?? '');
                final email = _normalize(data['email']?.toString() ?? '');
                return name.contains(normalizedSearch) ||
                    email.contains(normalizedSearch);
              })
              .map((document) {
                final data = document.data();
                return InvoiceFilterOption(
                  id: document.id,
                  label: data['name']!.toString().trim(),
                  subtitle: data['email']?.toString().trim() ?? '',
                );
              })
              .toList(growable: false)
            ..sort(
              (left, right) =>
                  _normalize(left.label).compareTo(_normalize(right.label)),
            );
      return options.take(limit.clamp(1, 100).toInt()).toList(growable: false);
    });
  }

  Query<Map<String, dynamic>> _invoiceListQuery({
    required String companyId,
    required BusinessUserContext user,
    required InvoiceType? type,
    required InvoiceStatus? status,
    required PaymentStatus? paymentStatus,
    required InvoiceReturnStatus? returnStatus,
    required String? salesRepId,
    required String? customerId,
    required DateTime? fromDate,
    required DateTime? toDate,
    required String? searchText,
    required InvoiceSortField sortField,
    required InvoiceSortDirection sortDirection,
  }) {
    final hasDateRange = fromDate != null || toDate != null;
    if (hasDateRange && sortField != InvoiceSortField.invoiceDate) {
      throw const InvoiceRepositoryException(
        InvoiceRepositoryError.invalidData,
      );
    }
    if (fromDate != null &&
        toDate != null &&
        _dateOnly(fromDate).isAfter(_dateOnly(toDate))) {
      throw const InvoiceRepositoryException(
        InvoiceRepositoryError.invalidData,
      );
    }

    Query<Map<String, dynamic>> query = _invoices(companyId);
    final requestedSalesRepId = salesRepId?.trim() ?? '';
    if (user.isSalesRep) {
      query = query.where('salesRepId', isEqualTo: user.uid);
    } else if (requestedSalesRepId.isNotEmpty) {
      query = query.where('salesRepId', isEqualTo: requestedSalesRepId);
    }
    final requestedCustomerId = customerId?.trim() ?? '';
    if (requestedCustomerId.isNotEmpty) {
      query = query.where('customerId', isEqualTo: requestedCustomerId);
    }
    if (type != null) {
      query = query.where('invoiceType', isEqualTo: type.value);
    }
    if (status != null) {
      query = query.where('invoiceStatus', isEqualTo: status.value);
    }
    if (paymentStatus != null) {
      query = query.where('paymentStatus', isEqualTo: paymentStatus.value);
    }
    if (returnStatus != null) {
      query = query.where('returnStatus', isEqualTo: returnStatus.value);
    }
    if (fromDate != null) {
      query = query.where(
        'invoiceDate',
        isGreaterThanOrEqualTo: Timestamp.fromDate(_dateOnly(fromDate)),
      );
    }
    if (toDate != null) {
      query = query.where(
        'invoiceDate',
        isLessThan: Timestamp.fromDate(
          _dateOnly(toDate).add(const Duration(days: 1)),
        ),
      );
    }
    final normalizedSearch = _normalize(searchText ?? '');
    if (normalizedSearch.isNotEmpty) {
      query = query.where('searchKeywords', arrayContains: normalizedSearch);
    }

    final descending = sortDirection.descending;
    return query
        .orderBy(sortField.firestoreField, descending: descending)
        .orderBy(FieldPath.documentId, descending: descending);
  }

  Stream<List<InvoiceModel>> watchInvoices({
    required String companyId,
    InvoiceType? type,
    InvoiceStatus? status,
  }) async* {
    final user = await _contextReader.requireApprovedUser();
    final resolvedCompanyId = _resolveCompanyId(companyId, user);
    Query<Map<String, dynamic>> query = _invoices(resolvedCompanyId);
    if (user.isSalesRep) {
      query = query.where('salesRepId', isEqualTo: user.uid);
    }
    if (type != null) query = query.where('invoiceType', isEqualTo: type.value);
    if (status != null) {
      query = query.where('invoiceStatus', isEqualTo: status.value);
    }
    yield* query
        .orderBy('invoiceDate', descending: true)
        .orderBy(FieldPath.documentId, descending: true)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs.map(InvoiceModel.fromFirestore).toList(),
        );
  }

  Future<InvoiceModel?> getInvoiceById({
    required String companyId,
    required String invoiceId,
  }) {
    return _run(() async {
      final user = await _contextReader.requireApprovedUser();
      final resolvedCompanyId = _resolveCompanyId(companyId, user);
      final document = await _invoices(
        resolvedCompanyId,
      ).doc(invoiceId).get().timeout(const Duration(seconds: 20));
      if (!document.exists) return null;
      final invoice = InvoiceModel.fromFirestore(document);
      _requireCanAccessInvoice(user, invoice);
      return invoice;
    });
  }

  Future<String> createInvoice({required InvoiceModel invoice}) {
    return _run(() async {
      final shouldConfirm = invoice.invoiceStatus == InvoiceStatus.confirmed;
      final user = await _contextReader.requireApprovedUser();
      final companyId = _resolveCompanyId(invoice.companyId, user);
      final document = invoice.id.trim().isEmpty
          ? _invoices(companyId).doc()
          : _invoices(companyId).doc(invoice.id.trim());

      await _firestore
          .runTransaction((transaction) async {
            final now = DateTime.now();
            final itemSnapshots =
                <String, DocumentSnapshot<Map<String, dynamic>>>{};
            final settingsSnapshot = await transaction.get(
              _appSettings(companyId),
            );
            final settings = AppSettingsModel.fromMap(settingsSnapshot.data());
            final permissions = EffectiveBusinessPermissions.fromUser(
              user,
              settings.permissionSettings,
            );
            await _enforceLinePermissions(
              transaction: transaction,
              permissions: permissions,
              items: invoice.items,
              existingItems: null,
              itemSnapshots: itemSnapshots,
            );
            final rawCustomerId = invoice.customerSnapshot?.id.trim() ?? '';
            await _readCustomerForInvoice(
              transaction: transaction,
              companyId: companyId,
              customerId: rawCustomerId,
              user: user,
            );
            final numberAllocation = await _allocateInvoiceNumber(
              transaction: transaction,
              companyId: companyId,
              invoiceDate: invoice.invoiceDate,
              documentSettings: settings.documentSettings,
            );
            final normalized = _normalizeInvoice(
              invoice: invoice.copyWith(invoiceStatus: InvoiceStatus.draft),
              user: user,
              id: document.id,
              companyId: companyId,
              invoiceNumber: numberAllocation.number,
              createdAt: now,
              updatedAt: now,
              preserveCreator: false,
            );
            transaction.set(
              numberAllocation.counterRef,
              numberAllocation.counterData,
              SetOptions(merge: true),
            );
            transaction.set(document, {
              ...normalized.toMap(),
              'createdAt': FieldValue.serverTimestamp(),
              'updatedAt': FieldValue.serverTimestamp(),
            });
          })
          .timeout(const Duration(seconds: 20));
      if (shouldConfirm) {
        await _trustedCallableClient
            .callAuthenticated<void>('confirmInvoice', {
              'companyId': companyId,
              'invoiceId': document.id,
            })
            .timeout(const Duration(seconds: 30));
      }
      return document.id;
    });
  }

  Future<void> updateInvoice({required InvoiceModel invoice}) {
    return _run(() async {
      final shouldConfirm = invoice.invoiceStatus == InvoiceStatus.confirmed;
      final user = await _contextReader.requireApprovedUser();
      if (invoice.id.trim().isEmpty || invoice.companyId.trim().isEmpty) {
        throw const InvoiceRepositoryException(
          InvoiceRepositoryError.invalidData,
        );
      }
      final companyId = _resolveCompanyId(invoice.companyId, user);
      final document = _invoices(companyId).doc(invoice.id);
      await _firestore
          .runTransaction((transaction) async {
            final itemSnapshots =
                <String, DocumentSnapshot<Map<String, dynamic>>>{};
            final snapshot = await transaction.get(document);
            if (!snapshot.exists) {
              throw const InvoiceRepositoryException(
                InvoiceRepositoryError.notFound,
              );
            }
            final existing = InvoiceModel.fromFirestore(snapshot);
            _requireCanAccessInvoice(user, existing);
            if (existing.isDraft && existing.financialPosted) {
              throw const InvoiceRepositoryException(
                InvoiceRepositoryError.invalidState,
              );
            }
            if (existing.isDraft && existing.inventoryPosted) {
              throw const InvoiceRepositoryException(
                InvoiceRepositoryError.invalidState,
              );
            }
            if (!existing.canEdit) {
              throw const InvoiceRepositoryException(
                InvoiceRepositoryError.locked,
              );
            }

            final settingsSnapshot = await transaction.get(
              _appSettings(companyId),
            );
            final permissions = EffectiveBusinessPermissions.fromUser(
              user,
              AppSettingsModel.fromMap(
                settingsSnapshot.data(),
              ).permissionSettings,
            );
            await _enforceLinePermissions(
              transaction: transaction,
              permissions: permissions,
              items: invoice.items,
              existingItems: existing.items,
              itemSnapshots: itemSnapshots,
            );

            final normalized = _normalizeInvoice(
              invoice: invoice.copyWith(invoiceStatus: InvoiceStatus.draft),
              user: user,
              id: existing.id,
              companyId: companyId,
              invoiceNumber: existing.invoiceNumber,
              createdAt: existing.createdAt,
              updatedAt: DateTime.now(),
              preserveCreator: true,
              existing: existing,
            );

            await _readCustomerForInvoice(
              transaction: transaction,
              companyId: companyId,
              customerId: normalized.customerId,
              user: user,
            );
            transaction.update(document, {
              ...normalized.toMap(),
              'createdAt': Timestamp.fromDate(existing.createdAt),
              'updatedAt': FieldValue.serverTimestamp(),
            });
          })
          .timeout(const Duration(seconds: 20));
      if (shouldConfirm) {
        await _trustedCallableClient
            .callAuthenticated<void>('confirmInvoice', {
              'companyId': companyId,
              'invoiceId': invoice.id,
            })
            .timeout(const Duration(seconds: 30));
      }
    });
  }

  Future<void> deleteDraftInvoice({
    required String companyId,
    required String invoiceId,
  }) {
    return _run(() async {
      final user = await _contextReader.requireApprovedUser();
      final resolvedCompanyId = _resolveCompanyId(companyId, user);
      final document = _invoices(resolvedCompanyId).doc(invoiceId);
      await _firestore
          .runTransaction((transaction) async {
            final snapshot = await transaction.get(document);
            if (!snapshot.exists) {
              throw const InvoiceRepositoryException(
                InvoiceRepositoryError.notFound,
              );
            }
            final invoice = InvoiceModel.fromFirestore(snapshot);
            _requireCanAccessInvoice(user, invoice);
            if (!invoice.canDelete) {
              throw const InvoiceRepositoryException(
                InvoiceRepositoryError.invalidState,
              );
            }
            transaction.delete(document);
          })
          .timeout(const Duration(seconds: 20));
    });
  }

  Future<void> markPendingSubmit({
    required String companyId,
    required String invoiceId,
  }) {
    return _run(() async {
      final user = await _contextReader.requireApprovedUser();
      final resolvedCompanyId = _resolveCompanyId(companyId, user);
      final document = _invoices(resolvedCompanyId).doc(invoiceId);
      await _firestore
          .runTransaction((transaction) async {
            final snapshot = await transaction.get(document);
            if (!snapshot.exists) {
              throw const InvoiceRepositoryException(
                InvoiceRepositoryError.notFound,
              );
            }
            final invoice = InvoiceModel.fromFirestore(snapshot);
            _requireCanAccessInvoice(user, invoice);
            final canSubmit =
                invoice.invoiceType == InvoiceType.electronic &&
                (invoice.invoiceStatus == InvoiceStatus.draft ||
                    invoice.invoiceStatus == InvoiceStatus.rejected);
            if (!canSubmit) {
              throw const InvoiceRepositoryException(
                InvoiceRepositoryError.invalidState,
              );
            }
            transaction.update(document, {
              'invoiceStatus': InvoiceStatus.pendingSubmit.value,
              'updatedAt': FieldValue.serverTimestamp(),
            });
          })
          .timeout(const Duration(seconds: 20));
    });
  }

  Future<void> submitElectronicInvoicePlaceholder({
    required String companyId,
    required String invoiceId,
  }) {
    return _run(() async {
      throw const InvoiceRepositoryException(
        InvoiceRepositoryError.invalidState,
      );
    });
  }

  Future<_InvoiceNumberAllocation> _allocateInvoiceNumber({
    required Transaction transaction,
    required String companyId,
    required DateTime invoiceDate,
    required DocumentSettingsModel documentSettings,
  }) async {
    final year = invoiceDate.year;
    final prefix = BusinessSettingsDefaults.prefix(
      documentSettings.invoicePrefix,
      DocumentSettingsModel.defaults.invoicePrefix,
    );
    final counterRef = _invoiceCounter(companyId, year);
    final counter = await transaction.get(counterRef);
    final current = counter.data()?['lastNumber'];
    final next = current is num ? current.toInt() + 1 : 1;
    final data = {
      'id': counterRef.id,
      'companyId': companyId,
      'year': year,
      'lastNumber': next,
      'prefix': prefix,
      'updatedAt': FieldValue.serverTimestamp(),
    };
    return _InvoiceNumberAllocation(
      number: BusinessSettingsDefaults.documentNumber(
        prefix: prefix,
        year: year,
        sequence: next,
      ),
      counterRef: counterRef,
      counterData: data,
    );
  }

  Future<CustomerModel> _readCustomerForInvoice({
    required Transaction transaction,
    required String companyId,
    required String customerId,
    required BusinessUserContext user,
  }) async {
    if (customerId.trim().isEmpty) {
      throw const InvoiceRepositoryException(
        InvoiceRepositoryError.invalidData,
      );
    }
    final customerRef = _customers(companyId).doc(customerId);
    final customerSnapshot = await transaction.get(customerRef);
    if (!customerSnapshot.exists) {
      throw const InvoiceRepositoryException(InvoiceRepositoryError.notFound);
    }
    final customer = CustomerModel.fromFirestore(customerSnapshot);
    if (!customer.active) {
      throw const InvoiceRepositoryException(
        InvoiceRepositoryError.invalidState,
      );
    }
    _requireCanAccessCustomer(user, customer);
    return customer;
  }

  Future<void> _enforceLinePermissions({
    required Transaction transaction,
    required EffectiveBusinessPermissions permissions,
    required List<InvoiceItemSnapshot> items,
    required List<InvoiceItemSnapshot>? existingItems,
    required Map<String, DocumentSnapshot<Map<String, dynamic>>> itemSnapshots,
  }) async {
    if (!permissions.applyDiscount && items.any((item) => item.discount > 0)) {
      throw const InvoiceRepositoryException(
        InvoiceRepositoryError.discountDisabled,
      );
    }
    if (permissions.editCatalogPrice) return;
    for (final item in items) {
      if (item.lineType == InvoiceLineType.custom ||
          (item.itemId?.startsWith('manual-') ?? false)) {
        continue;
      }
      final itemId = item.itemId;
      if (itemId == null || itemId.trim().isEmpty) {
        throw const InvoiceRepositoryException(
          InvoiceRepositoryError.invalidData,
        );
      }
      InvoiceItemSnapshot? existing;
      for (final candidate in existingItems ?? const <InvoiceItemSnapshot>[]) {
        if (candidate.itemId == itemId) {
          existing = candidate;
          break;
        }
      }
      if (existing != null) {
        if ((existing.unitPrice - item.unitPrice).abs() > 0.0005) {
          throw const InvoiceRepositoryException(
            InvoiceRepositoryError.priceEditDisabled,
          );
        }
        continue;
      }
      final snapshot = await _readItemOnce(
        transaction: transaction,
        itemId: itemId,
        itemSnapshots: itemSnapshots,
      );
      if (!snapshot.exists) {
        throw const InvoiceRepositoryException(
          InvoiceRepositoryError.priceEditDisabled,
        );
      }
      final catalogItem = ItemModel.fromFirestore(snapshot);
      if ((catalogItem.price - item.unitPrice).abs() > 0.0005) {
        throw const InvoiceRepositoryException(
          InvoiceRepositoryError.priceEditDisabled,
        );
      }
    }
  }

  InvoiceModel _normalizeInvoice({
    required InvoiceModel invoice,
    required BusinessUserContext user,
    required String id,
    required String companyId,
    required String invoiceNumber,
    required DateTime createdAt,
    required DateTime updatedAt,
    required bool preserveCreator,
    InvoiceModel? existing,
  }) {
    if (invoice.customerSnapshot == null ||
        invoice.customerSnapshot!.id.trim().isEmpty ||
        invoice.customerSnapshot!.name.trim().isEmpty) {
      throw const InvoiceRepositoryException(
        InvoiceRepositoryError.invalidData,
      );
    }
    if (invoice.items.isEmpty || invoice.grandTotal < 0) {
      throw const InvoiceRepositoryException(
        InvoiceRepositoryError.invalidData,
      );
    }
    for (final line in invoice.items) {
      final validCommon =
          line.itemName.trim().isNotEmpty &&
          line.quantity > 0 &&
          line.unitPrice > 0;
      final validIdentity = line.lineType == InvoiceLineType.catalog
          ? (line.itemId?.trim().isNotEmpty ?? false)
          : line.isLegacyManual ||
                (line.itemId == null &&
                    line.description.trim().isNotEmpty &&
                    line.unit.trim().isNotEmpty);
      if (!validCommon || !validIdentity) {
        throw const InvoiceRepositoryException(
          InvoiceRepositoryError.invalidData,
        );
      }
    }
    if (_dateOnly(invoice.dueDate).isBefore(_dateOnly(invoice.invoiceDate))) {
      throw const InvoiceRepositoryException(
        InvoiceRepositoryError.invalidData,
      );
    }

    final payment = _calculatePayment(
      hasReceivedPayment: invoice.hasReceivedPayment,
      grandTotal: invoice.grandTotal,
      requestedPaidAmount: invoice.paidAmount,
    );
    final creatorUid = preserveCreator ? existing!.createdByUid : user.uid;
    final creatorName = preserveCreator ? existing!.createdByName : user.name;
    final creatorRole = preserveCreator ? existing!.createdByRole : user.role;
    final salesRepId = preserveCreator ? existing!.salesRepId : user.uid;
    final salesRepName = preserveCreator ? existing!.salesRepName : user.name;
    final sourceType = preserveCreator
        ? existing!.stockSourceType
        : user.isSalesRep
        ? InventorySourceType.salesRep
        : InventorySourceType.companyWarehouse;
    final sourceRepId = sourceType == InventorySourceType.salesRep
        ? (preserveCreator ? existing!.stockSourceSalesRepId : user.uid)
        : '';
    final sourceId = sourceType == InventorySourceType.salesRep
        ? sourceRepId
        : ItemModel.defaultWarehouseId;

    return invoice
        .copyWith(
          id: id,
          companyId: companyId,
          invoiceNumber: invoiceNumber,
          invoiceStatus: invoice.invoiceStatus,
          paymentType: payment.type,
          paymentStatus: payment.status,
          hasReceivedPayment: invoice.hasReceivedPayment,
          invoiceDate: invoice.invoiceDate,
          dueDate: invoice.dueDate,
          createdAt: createdAt,
          updatedAt: updatedAt,
          createdByUid: creatorUid,
          createdByName: _validName(creatorName),
          createdByRole: creatorRole,
          salesRepId: salesRepId,
          salesRepName: _validName(salesRepName),
          customerId: invoice.customerSnapshot!.id,
          paidAmount: payment.paidAmount,
          remainingAmount: payment.remainingAmount,
          paymentMethod: payment.type.value,
          isLocked: existing?.isLocked ?? false,
          financialPosted: existing?.financialPosted ?? false,
          financialPostedAt: existing?.financialPostedAt,
          financialPostedByUid: existing?.financialPostedByUid ?? '',
          financialPostedByName: existing?.financialPostedByName ?? '',
          customerTransactionIds: existing?.customerTransactionIds ?? const [],
          cashMovementIds: existing?.cashMovementIds ?? const [],
          inventoryPosted: existing?.inventoryPosted ?? false,
          inventoryPostedAt: existing?.inventoryPostedAt,
          inventoryPostedByUid: existing?.inventoryPostedByUid ?? '',
          inventoryPostedByName: existing?.inventoryPostedByName ?? '',
          inventoryMovementIds: existing?.inventoryMovementIds ?? const [],
          stockSourceType: sourceType,
          stockSourceId: sourceId,
          stockSourceSalesRepId: sourceRepId,
          government: existing?.government ?? invoice.government,
        )
        .withSearchFields();
  }

  _CalculatedPayment _calculatePayment({
    required bool hasReceivedPayment,
    required double grandTotal,
    required double requestedPaidAmount,
  }) {
    try {
      final impact = FinancialPostingCalculator.invoicePayment(
        total: grandTotal,
        hasReceivedPayment: hasReceivedPayment,
        requestedPaidAmount: requestedPaidAmount,
      );
      return _CalculatedPayment(
        type: switch (impact.state) {
          FinancialPaymentState.unpaid => PaymentType.credit,
          FinancialPaymentState.partiallyPaid => PaymentType.partial,
          FinancialPaymentState.paid => PaymentType.cash,
        },
        paidAmount: impact.paidAmount,
        remainingAmount: impact.receivableAmount,
        status: switch (impact.state) {
          FinancialPaymentState.unpaid => PaymentStatus.unpaid,
          FinancialPaymentState.partiallyPaid => PaymentStatus.partiallyPaid,
          FinancialPaymentState.paid => PaymentStatus.paid,
        },
      );
    } on FormatException {
      throw const InvoiceRepositoryException(
        InvoiceRepositoryError.invalidData,
      );
    }
  }

  Future<DocumentSnapshot<Map<String, dynamic>>> _readItemOnce({
    required Transaction transaction,
    required String itemId,
    required Map<String, DocumentSnapshot<Map<String, dynamic>>> itemSnapshots,
  }) async {
    final cached = itemSnapshots[itemId];
    if (cached != null) return cached;

    final snapshot = await transaction.get(_items.doc(itemId));
    itemSnapshots[itemId] = snapshot;
    return snapshot;
  }

  void _requireCanAccessInvoice(
    BusinessUserContext user,
    InvoiceModel invoice,
  ) {
    if (user.isAdmin) return;
    if (user.isSalesRep && invoice.salesRepId == user.uid) {
      return;
    }
    throw const InvoiceRepositoryException(
      InvoiceRepositoryError.permissionDenied,
    );
  }

  void _requireCanAccessCustomer(
    BusinessUserContext user,
    CustomerModel customer,
  ) {
    if (user.isAdmin) return;
    if (user.isSalesRep && customer.createdByUid == user.uid) return;
    throw const InvoiceRepositoryException(
      InvoiceRepositoryError.permissionDenied,
    );
  }

  String _resolveCompanyId(String requested, BusinessUserContext user) {
    final companyId = requested.trim().isEmpty
        ? AuthRepository.defaultCompanyId
        : requested.trim();
    if (companyId != user.companyId) {
      throw const InvoiceRepositoryException(
        InvoiceRepositoryError.permissionDenied,
      );
    }
    return companyId;
  }

  String _validName(String value) {
    final name = value.trim();
    if (name.isEmpty || name.toLowerCase() == 'undefined') {
      throw const InvoiceRepositoryException(
        InvoiceRepositoryError.invalidData,
      );
    }
    return name;
  }

  DateTime _dateOnly(DateTime date) =>
      DateTime(date.year, date.month, date.day);

  Future<T> _run<T>(Future<T> Function() operation) async {
    try {
      return await operation();
    } on InvoiceRepositoryException {
      rethrow;
    } on BusinessUserContextException catch (error) {
      throw InvoiceRepositoryException(_mapContextError(error.error), error);
    } on TimeoutException catch (error) {
      throw InvoiceRepositoryException(InvoiceRepositoryError.timeout, error);
    } on FirebaseFunctionsException catch (error) {
      throw InvoiceRepositoryException(_mapFunctionError(error.code), error);
    } on FirebaseException catch (error) {
      throw InvoiceRepositoryException(_mapFirebaseError(error.code), error);
    } on FormatException catch (error) {
      throw InvoiceRepositoryException(
        InvoiceRepositoryError.invalidData,
        error,
      );
    } catch (error) {
      throw InvoiceRepositoryException(InvoiceRepositoryError.unknown, error);
    }
  }

  InvoiceRepositoryError _mapContextError(BusinessUserContextError error) {
    return switch (error) {
      BusinessUserContextError.unauthenticated =>
        InvoiceRepositoryError.unauthenticated,
      BusinessUserContextError.profileMissing =>
        InvoiceRepositoryError.unauthenticated,
      BusinessUserContextError.permissionDenied =>
        InvoiceRepositoryError.permissionDenied,
      BusinessUserContextError.invalidProfile =>
        InvoiceRepositoryError.invalidData,
      BusinessUserContextError.timeout => InvoiceRepositoryError.timeout,
    };
  }

  InvoiceRepositoryError _mapFirebaseError(String code) {
    return switch (code) {
      'permission-denied' => InvoiceRepositoryError.permissionDenied,
      'unauthenticated' => InvoiceRepositoryError.unauthenticated,
      'unavailable' ||
      'deadline-exceeded' => InvoiceRepositoryError.unavailable,
      'not-found' => InvoiceRepositoryError.notFound,
      'failed-precondition' || 'aborted' => InvoiceRepositoryError.invalidState,
      _ => InvoiceRepositoryError.unknown,
    };
  }

  InvoiceRepositoryError _mapFunctionError(String code) {
    return switch (code) {
      'unauthenticated' => InvoiceRepositoryError.unauthenticated,
      'permission-denied' => InvoiceRepositoryError.permissionDenied,
      'not-found' => InvoiceRepositoryError.notFound,
      'failed-precondition' ||
      'invalid-argument' => InvoiceRepositoryError.invalidState,
      'unavailable' ||
      'deadline-exceeded' => InvoiceRepositoryError.unavailable,
      _ => InvoiceRepositoryError.unknown,
    };
  }

  String _normalize(String value) => value.trim().toLowerCase();
}

class _CalculatedPayment {
  const _CalculatedPayment({
    required this.type,
    required this.paidAmount,
    required this.remainingAmount,
    required this.status,
  });

  final PaymentType type;
  final double paidAmount;
  final double remainingAmount;
  final PaymentStatus status;
}

class _InvoiceNumberAllocation {
  const _InvoiceNumberAllocation({
    required this.number,
    required this.counterRef,
    required this.counterData,
  });

  final String number;
  final DocumentReference<Map<String, dynamic>> counterRef;
  final Map<String, dynamic> counterData;
}
