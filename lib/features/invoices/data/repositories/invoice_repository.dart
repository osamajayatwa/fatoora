import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:fatoora/core/finance/financial_posting_calculator.dart';
import 'package:fatoora/core/settings/business_settings_defaults.dart';
import 'package:fatoora/core/settings/business_permission_resolver.dart';
import 'package:fatoora/features/auth/data/repositories/auth_repository.dart';
import 'package:fatoora/features/customers/data/models/customer_model.dart';
import 'package:fatoora/features/invoices/data/models/invoice_enums.dart';
import 'package:fatoora/features/invoices/data/models/invoice_item_snapshot.dart';
import 'package:fatoora/features/invoices/data/models/invoice_model.dart';
import 'package:fatoora/features/invoices/data/services/jofotara_placeholder_service.dart';
import 'package:fatoora/features/items/data/models/item_model.dart';
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
    FirebaseAuth? firebaseAuth,
    BusinessUserContextReader? contextReader,
    JofotaraPlaceholderService? jofotaraService,
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _contextReader =
           contextReader ??
           BusinessUserContextReader(
             firestore: firestore,
             firebaseAuth: firebaseAuth,
           ),
       _jofotaraService = jofotaraService ?? JofotaraPlaceholderService();

  final FirebaseFirestore _firestore;
  final BusinessUserContextReader _contextReader;
  final JofotaraPlaceholderService _jofotaraService;

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

  CollectionReference<Map<String, dynamic>> get _items =>
      _firestore.collection('items');

  CollectionReference<Map<String, dynamic>> _stockMovements(String companyId) {
    return _firestore
        .collection('companies')
        .doc(companyId)
        .collection('stock_movements');
  }

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
    DateTime? fromDate,
    DateTime? toDate,
    String? searchText,
  }) {
    return _run(() async {
      final user = await _contextReader.requireApprovedUser();
      final resolvedCompanyId = _resolveCompanyId(companyId, user);
      Query<Map<String, dynamic>> query = _invoices(resolvedCompanyId);
      if (user.isSalesRep) {
        query = query.where('salesRepId', isEqualTo: user.uid);
      }
      if (type != null) {
        query = query.where('invoiceType', isEqualTo: type.value);
      }
      if (status != null) {
        query = query.where('invoiceStatus', isEqualTo: status.value);
      }
      if (fromDate != null) {
        query = query.where(
          'invoiceDate',
          isGreaterThanOrEqualTo: Timestamp.fromDate(_startOfDay(fromDate)),
        );
      }
      if (toDate != null) {
        query = query.where(
          'invoiceDate',
          isLessThanOrEqualTo: Timestamp.fromDate(_endOfDay(toDate)),
        );
      }
      final normalizedSearch = _normalize(searchText ?? '');
      if (normalizedSearch.isNotEmpty) {
        query = query.where('searchKeywords', arrayContains: normalizedSearch);
      }
      final snapshot = await query
          .orderBy('invoiceDate', descending: true)
          .limit(150)
          .get()
          .timeout(const Duration(seconds: 20));
      return snapshot.docs.map(InvoiceModel.fromFirestore).toList();
    });
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
        .limit(150)
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
            final customer = await _readCustomerForInvoice(
              transaction: transaction,
              companyId: companyId,
              customerId: rawCustomerId,
              user: user,
            );
            final paymentPreview = _calculatePayment(
              hasReceivedPayment: invoice.hasReceivedPayment,
              grandTotal: invoice.grandTotal,
              requestedPaidAmount: invoice.paidAmount,
            );
            if (invoice.invoiceStatus == InvoiceStatus.confirmed) {
              await _guardAgainstDuplicatePosting(
                transaction: transaction,
                companyId: companyId,
                invoiceId: document.id,
                needsPaymentTransaction: paymentPreview.paidAmount > 0,
                needsCashMovement: paymentPreview.paidAmount > 0,
              );
            }
            final numberAllocation = await _allocateInvoiceNumber(
              transaction: transaction,
              companyId: companyId,
              invoiceDate: invoice.invoiceDate,
              documentSettings: settings.documentSettings,
            );
            var normalized = _normalizeInvoice(
              invoice: invoice,
              user: user,
              id: document.id,
              companyId: companyId,
              invoiceNumber: numberAllocation.number,
              createdAt: now,
              updatedAt: now,
              preserveCreator: false,
            );
            final posting = normalized.invoiceStatus == InvoiceStatus.confirmed
                ? _buildFinancialPosting(
                    invoice: normalized,
                    customer: customer,
                  )
                : null;
            final inventoryPosting =
                normalized.invoiceStatus == InvoiceStatus.confirmed
                ? await _buildInventoryPosting(
                    transaction: transaction,
                    invoice: normalized,
                    user: user,
                    itemSnapshots: itemSnapshots,
                  )
                : null;
            if (posting != null) {
              normalized = _withFinancialPostingMetadata(
                invoice: normalized,
                posting: posting,
                user: user,
                postedAt: now,
              );
            }
            if (inventoryPosting != null) {
              normalized = _withInventoryPostingMetadata(
                invoice: normalized,
                posting: inventoryPosting,
                user: user,
                postedAt: now,
              );
            }

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

            if (posting != null) _applyFinancialPosting(transaction, posting);
            if (inventoryPosting != null) {
              _applyInventoryPosting(transaction, inventoryPosting);
            }
          })
          .timeout(const Duration(seconds: 20));
      return document.id;
    });
  }

  Future<void> updateInvoice({required InvoiceModel invoice}) {
    return _run(() async {
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

            var normalized = _normalizeInvoice(
              invoice: invoice,
              user: user,
              id: existing.id,
              companyId: companyId,
              invoiceNumber: existing.invoiceNumber,
              createdAt: existing.createdAt,
              updatedAt: DateTime.now(),
              preserveCreator: true,
              existing: existing,
            );

            final customer = await _readCustomerForInvoice(
              transaction: transaction,
              companyId: companyId,
              customerId: normalized.customerId,
              user: user,
            );
            final shouldPost =
                !existing.financialPosted &&
                normalized.invoiceStatus == InvoiceStatus.confirmed;
            final shouldPostInventory =
                !existing.inventoryPosted &&
                normalized.invoiceStatus == InvoiceStatus.confirmed;
            if (shouldPost || shouldPostInventory) {
              _FinancialPosting? posting;
              if (shouldPost) {
                await _guardAgainstDuplicatePosting(
                  transaction: transaction,
                  companyId: companyId,
                  invoiceId: normalized.id,
                  needsPaymentTransaction: normalized.paidAmount > 0,
                  needsCashMovement: normalized.paidAmount > 0,
                );
                posting = _buildFinancialPosting(
                  invoice: normalized,
                  customer: customer,
                );
                normalized = _withFinancialPostingMetadata(
                  invoice: normalized,
                  posting: posting,
                  user: user,
                  postedAt: DateTime.now(),
                );
              }
              final inventoryPosting = shouldPostInventory
                  ? await _buildInventoryPosting(
                      transaction: transaction,
                      invoice: normalized,
                      user: user,
                      itemSnapshots: itemSnapshots,
                    )
                  : null;
              if (inventoryPosting != null) {
                normalized = _withInventoryPostingMetadata(
                  invoice: normalized,
                  posting: inventoryPosting,
                  user: user,
                  postedAt: DateTime.now(),
                );
              }
              transaction.update(document, {
                ...normalized.toMap(),
                'createdAt': Timestamp.fromDate(existing.createdAt),
                'updatedAt': FieldValue.serverTimestamp(),
              });
              if (posting != null) {
                _applyFinancialPosting(transaction, posting);
              }
              if (inventoryPosting != null) {
                _applyInventoryPosting(transaction, inventoryPosting);
              }
              return;
            }

            transaction.update(document, {
              ...normalized.toMap(),
              'createdAt': Timestamp.fromDate(existing.createdAt),
              'updatedAt': FieldValue.serverTimestamp(),
            });
          })
          .timeout(const Duration(seconds: 20));
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
    return _run(
      () => _jofotaraService
          .submitInvoice(companyId: companyId, invoiceId: invoiceId)
          .timeout(const Duration(seconds: 30)),
    );
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
      if (item.itemId.trim().isEmpty || item.itemId.startsWith('manual-')) {
        continue;
      }
      InvoiceItemSnapshot? existing;
      for (final candidate in existingItems ?? const <InvoiceItemSnapshot>[]) {
        if (candidate.itemId == item.itemId) {
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
        itemId: item.itemId,
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

  Future<void> _guardAgainstDuplicatePosting({
    required Transaction transaction,
    required String companyId,
    required String invoiceId,
    required bool needsPaymentTransaction,
    required bool needsCashMovement,
  }) async {
    final debitSnapshot = await transaction.get(
      _invoiceCustomerTransactionRef(companyId, invoiceId),
    );
    if (debitSnapshot.exists) {
      throw const InvoiceRepositoryException(
        InvoiceRepositoryError.invalidState,
      );
    }
    if (needsPaymentTransaction) {
      final paymentSnapshot = await transaction.get(
        _invoicePaymentTransactionRef(companyId, invoiceId),
      );
      if (paymentSnapshot.exists) {
        throw const InvoiceRepositoryException(
          InvoiceRepositoryError.invalidState,
        );
      }
    }
    if (needsCashMovement) {
      final movementSnapshot = await transaction.get(
        _invoiceCashMovementRef(companyId, invoiceId),
      );
      if (movementSnapshot.exists) {
        throw const InvoiceRepositoryException(
          InvoiceRepositoryError.invalidState,
        );
      }
    }
  }

  DocumentReference<Map<String, dynamic>> _invoicePaymentTransactionRef(
    String companyId,
    String invoiceId,
  ) {
    return _transactions(companyId).doc('${invoiceId}_payment');
  }

  DocumentReference<Map<String, dynamic>> _invoiceCustomerTransactionRef(
    String companyId,
    String invoiceId,
  ) {
    return _transactions(companyId).doc('${invoiceId}_debit');
  }

  DocumentReference<Map<String, dynamic>> _invoiceCashMovementRef(
    String companyId,
    String invoiceId,
  ) {
    return _cashMovements(companyId).doc('${invoiceId}_cash');
  }

  _FinancialPosting _buildFinancialPosting({
    required InvoiceModel invoice,
    required CustomerModel customer,
  }) {
    final customerRef = _customers(invoice.companyId).doc(customer.id);
    final newBalance = _round(
      customer.currentBalance + invoice.remainingAmount,
    );
    final customerUpdate = <String, dynamic>{
      'currentBalance': newBalance,
      'totalSales': _round(customer.totalSales + invoice.grandTotal),
      'totalPaid': _round(customer.totalPaid + invoice.paidAmount),
      'updatedAt': FieldValue.serverTimestamp(),
    };

    final debitRef = _invoiceCustomerTransactionRef(
      invoice.companyId,
      invoice.id,
    );
    final debitBalance = _round(customer.currentBalance + invoice.grandTotal);
    final transactionRefs = <DocumentReference<Map<String, dynamic>>>[debitRef];
    final transactionData = <Map<String, dynamic>>[
      {
        'id': debitRef.id,
        'companyId': invoice.companyId,
        'customerId': customer.id,
        'customerName': customer.name,
        'transactionType': 'invoice',
        'type': 'invoice',
        'referenceId': invoice.id,
        'invoiceId': invoice.id,
        'invoiceNumber': invoice.invoiceNumber,
        'sourceCollection': 'invoices',
        'sourceId': invoice.id,
        'sourceNumber': invoice.invoiceNumber,
        'transactionDate': Timestamp.fromDate(invoice.invoiceDate),
        'debitAmount': invoice.grandTotal,
        'creditAmount': 0,
        'amount': invoice.grandTotal,
        'signedAmount': invoice.grandTotal,
        'balanceAfter': debitBalance,
        'notes': invoice.notes,
        'createdByUid': invoice.createdByUid,
        'createdByName': invoice.createdByName,
        'createdByRole': invoice.createdByRole,
        'salesRepId': invoice.salesRepId,
        'salesRepName': invoice.salesRepName,
        'createdAt': FieldValue.serverTimestamp(),
      },
    ];

    if (invoice.paidAmount > 0) {
      final paymentRef = _invoicePaymentTransactionRef(
        invoice.companyId,
        invoice.id,
      );
      transactionRefs.add(paymentRef);
      transactionData.add({
        'id': paymentRef.id,
        'companyId': invoice.companyId,
        'customerId': customer.id,
        'customerName': customer.name,
        'transactionType': 'payment',
        'type': 'payment',
        'referenceId': invoice.id,
        'invoiceId': invoice.id,
        'invoiceNumber': invoice.invoiceNumber,
        'sourceCollection': 'invoices',
        'sourceId': invoice.id,
        'sourceNumber': invoice.invoiceNumber,
        'transactionDate': Timestamp.fromDate(invoice.invoiceDate),
        'debitAmount': 0,
        'creditAmount': invoice.paidAmount,
        'amount': invoice.paidAmount,
        'signedAmount': -invoice.paidAmount,
        'balanceAfter': newBalance,
        'notes': invoice.notes,
        'createdByUid': invoice.createdByUid,
        'createdByName': invoice.createdByName,
        'createdByRole': invoice.createdByRole,
        'salesRepId': invoice.salesRepId,
        'salesRepName': invoice.salesRepName,
        'createdAt': FieldValue.serverTimestamp(),
      });
    }

    DocumentReference<Map<String, dynamic>>? movementRef;
    Map<String, dynamic>? movementData;
    if (invoice.paidAmount > 0) {
      movementRef = _invoiceCashMovementRef(invoice.companyId, invoice.id);
      movementData = {
        'id': movementRef.id,
        'companyId': invoice.companyId,
        'movementType': 'invoice_payment',
        'type': invoice.paymentType == PaymentType.partial
            ? 'invoice_partial'
            : 'invoice_cash',
        'direction': 'in',
        'amount': invoice.paidAmount,
        'paymentType': invoice.paymentType.value,
        'customerId': customer.id,
        'customerName': customer.name,
        'referenceId': invoice.id,
        'referenceNumber': invoice.invoiceNumber,
        'sourceCollection': 'invoices',
        'sourceId': invoice.id,
        'sourceNumber': invoice.invoiceNumber,
        'date': Timestamp.fromDate(invoice.invoiceDate),
        'movementDate': Timestamp.fromDate(invoice.invoiceDate),
        'notes': invoice.notes,
        'salesRepId': invoice.salesRepId,
        'salesRepName': invoice.salesRepName,
        'createdByUid': invoice.createdByUid,
        'createdByName': invoice.createdByName,
        'createdByRole': invoice.createdByRole,
        'createdAt': FieldValue.serverTimestamp(),
      };
    }

    return _FinancialPosting(
      customerRef: customerRef,
      customerUpdate: customerUpdate,
      customerTransactionRefs: transactionRefs,
      customerTransactionData: transactionData,
      cashMovementRef: movementRef,
      cashMovementData: movementData,
    );
  }

  InvoiceModel _withFinancialPostingMetadata({
    required InvoiceModel invoice,
    required _FinancialPosting posting,
    required BusinessUserContext user,
    required DateTime postedAt,
  }) {
    return invoice.copyWith(
      financialPosted: true,
      financialPostedAt: postedAt,
      financialPostedByUid: user.uid,
      financialPostedByName: user.name,
      customerTransactionIds: posting.customerTransactionRefs
          .map((reference) => reference.id)
          .toList(growable: false),
      cashMovementIds: posting.cashMovementRef == null
          ? const []
          : [posting.cashMovementRef!.id],
    );
  }

  void _applyFinancialPosting(
    Transaction transaction,
    _FinancialPosting posting,
  ) {
    transaction.update(posting.customerRef, posting.customerUpdate);
    for (
      var index = 0;
      index < posting.customerTransactionRefs.length;
      index++
    ) {
      transaction.set(
        posting.customerTransactionRefs[index],
        posting.customerTransactionData[index],
      );
    }
    final cashMovementRef = posting.cashMovementRef;
    final cashMovementData = posting.cashMovementData;
    if (cashMovementRef != null && cashMovementData != null) {
      transaction.set(cashMovementRef, cashMovementData);
    }
  }

  Future<_InventoryPosting> _buildInventoryPosting({
    required Transaction transaction,
    required InvoiceModel invoice,
    required BusinessUserContext user,
    required Map<String, DocumentSnapshot<Map<String, dynamic>>> itemSnapshots,
  }) async {
    final quantitiesByItem = <String, double>{};
    final snapshotByItem = <String, String>{};
    for (final item in invoice.items) {
      final itemId = item.itemId.trim();
      if (itemId.isEmpty || itemId.startsWith('manual-')) continue;
      quantitiesByItem[itemId] = _round(
        (quantitiesByItem[itemId] ?? 0) + item.quantity,
      );
      snapshotByItem[itemId] = item.itemName;
    }

    final itemUpdates = <_InventoryItemUpdate>[];
    final movementRefs = <DocumentReference<Map<String, dynamic>>>[];
    final movementData = <Map<String, dynamic>>[];

    for (final entry in quantitiesByItem.entries) {
      final itemRef = _items.doc(entry.key);
      final itemSnapshot = await _readItemOnce(
        transaction: transaction,
        itemId: entry.key,
        itemSnapshots: itemSnapshots,
      );
      if (!itemSnapshot.exists) continue;
      final item = ItemModel.fromFirestore(itemSnapshot);
      if (item.deleted || !item.trackStock) continue;
      final requestedQuantity = _round(entry.value);
      if (requestedQuantity <= 0) continue;
      final quantityBefore = item.currentStock;
      if (quantityBefore < requestedQuantity) {
        throw InvoiceRepositoryException(
          InvoiceRepositoryError.invalidState,
          InsufficientStockFailure(
            itemName: item.name.isEmpty
                ? (snapshotByItem[entry.key] ?? entry.key)
                : item.name,
            requestedQuantity: requestedQuantity,
            availableQuantity: quantityBefore,
          ),
        );
      }
      final quantityAfter = _round(quantityBefore - requestedQuantity);
      final movementRef = _stockMovements(
        invoice.companyId,
      ).doc('${invoice.id}_${item.id}_invoice_sale');
      final existingMovement = await transaction.get(movementRef);
      if (existingMovement.exists) {
        throw const InvoiceRepositoryException(
          InvoiceRepositoryError.invalidState,
        );
      }
      itemUpdates.add(
        _InventoryItemUpdate(
          itemRef: itemRef,
          data: {
            'currentStock': quantityAfter,
            'inventoryUpdatedAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          },
        ),
      );
      movementRefs.add(movementRef);
      movementData.add({
        'id': movementRef.id,
        'companyId': invoice.companyId,
        'warehouseId': item.warehouseId.trim().isEmpty
            ? ItemModel.defaultWarehouseId
            : item.warehouseId,
        'itemId': item.id,
        'itemName': item.name,
        'itemCode': item.code,
        'movementType': 'invoice_sale',
        'direction': 'out',
        'quantity': requestedQuantity,
        'quantityBefore': quantityBefore,
        'quantityAfter': quantityAfter,
        'referenceType': 'invoice',
        'referenceId': invoice.id,
        'referenceNumber': invoice.invoiceNumber,
        'movementDate': Timestamp.fromDate(invoice.invoiceDate),
        'notes': invoice.notes,
        'createdByUid': invoice.createdByUid,
        'createdByName': invoice.createdByName,
        'createdByRole': invoice.createdByRole,
        'createdAt': FieldValue.serverTimestamp(),
      });
    }

    return _InventoryPosting(
      itemUpdates: itemUpdates,
      movementRefs: movementRefs,
      movementData: movementData,
    );
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

  InvoiceModel _withInventoryPostingMetadata({
    required InvoiceModel invoice,
    required _InventoryPosting posting,
    required BusinessUserContext user,
    required DateTime postedAt,
  }) {
    return invoice.copyWith(
      inventoryPosted: true,
      inventoryPostedAt: postedAt,
      inventoryPostedByUid: user.uid,
      inventoryPostedByName: user.name,
      inventoryMovementIds: posting.movementRefs
          .map((reference) => reference.id)
          .toList(growable: false),
    );
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

  double _round(double value) {
    if (!value.isFinite) return 0;
    return (value * 1000).roundToDouble() / 1000;
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

  DateTime _startOfDay(DateTime date) =>
      DateTime(date.year, date.month, date.day);

  DateTime _endOfDay(DateTime date) {
    return DateTime(date.year, date.month, date.day, 23, 59, 59, 999);
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

class _FinancialPosting {
  const _FinancialPosting({
    required this.customerRef,
    required this.customerUpdate,
    required this.customerTransactionRefs,
    required this.customerTransactionData,
    required this.cashMovementRef,
    required this.cashMovementData,
  });

  final DocumentReference<Map<String, dynamic>> customerRef;
  final Map<String, dynamic> customerUpdate;
  final List<DocumentReference<Map<String, dynamic>>> customerTransactionRefs;
  final List<Map<String, dynamic>> customerTransactionData;
  final DocumentReference<Map<String, dynamic>>? cashMovementRef;
  final Map<String, dynamic>? cashMovementData;
}

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

class _InventoryItemUpdate {
  const _InventoryItemUpdate({required this.itemRef, required this.data});

  final DocumentReference<Map<String, dynamic>> itemRef;
  final Map<String, dynamic> data;
}
