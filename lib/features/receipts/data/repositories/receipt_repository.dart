import 'dart:async';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fatoora/core/settings/business_settings_defaults.dart';
import 'package:fatoora/features/auth/data/repositories/auth_repository.dart';
import 'package:fatoora/features/customers/data/models/customer_model.dart';
import 'package:fatoora/features/receipts/data/models/receipt_model.dart';
import 'package:fatoora/features/settings/data/models/app_settings_model.dart';
import 'package:fatoora/features/settings/data/models/document_settings_model.dart';
import 'package:fatoora/features/shared/business/business_user_context.dart';
import 'package:firebase_auth/firebase_auth.dart';

enum ReceiptRepositoryError {
  unauthenticated,
  permissionDenied,
  unavailable,
  timeout,
  notFound,
  invalidData,
  unknown,
}

class ReceiptRepositoryException implements Exception {
  const ReceiptRepositoryException(this.error, [this.cause]);

  final ReceiptRepositoryError error;
  final Object? cause;
}

class ReceiptRepository {
  ReceiptRepository({
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

  CollectionReference<Map<String, dynamic>> _customers(String companyId) {
    return _firestore
        .collection('companies')
        .doc(companyId)
        .collection('customers');
  }

  CollectionReference<Map<String, dynamic>> _receipts(String companyId) {
    return _firestore
        .collection('companies')
        .doc(companyId)
        .collection('receipts');
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

  DocumentReference<Map<String, dynamic>> _receiptCounter(
    String companyId,
    int year,
  ) {
    return _firestore
        .collection('companies')
        .doc(companyId)
        .collection('counters')
        .doc('receipts_$year');
  }

  DocumentReference<Map<String, dynamic>> _appSettings(String companyId) {
    return _firestore
        .collection('companies')
        .doc(companyId)
        .collection('settings')
        .doc('app');
  }

  Future<List<ReceiptModel>> fetchReceipts({
    String companyId = AuthRepository.defaultCompanyId,
    DateTime? fromDate,
    DateTime? toDate,
    String searchText = '',
    int maxResults = 150,
  }) {
    return _run(() async {
      final user = await _contextReader.requireApprovedUser();
      final resolvedCompanyId = _resolveCompanyId(companyId, user);
      Query<Map<String, dynamic>> query = _receipts(resolvedCompanyId);
      if (user.isSalesRep) {
        query = query.where('salesRepId', isEqualTo: user.uid);
      }
      if (fromDate != null) {
        query = query.where(
          'receiptDate',
          isGreaterThanOrEqualTo: Timestamp.fromDate(_startOfDay(fromDate)),
        );
      }
      if (toDate != null) {
        query = query.where(
          'receiptDate',
          isLessThanOrEqualTo: Timestamp.fromDate(_endOfDay(toDate)),
        );
      }
      final snapshot = await query
          .orderBy('receiptDate', descending: true)
          .limit(maxResults)
          .get()
          .timeout(const Duration(seconds: 20));
      final receipts = snapshot.docs
          .map(ReceiptModel.fromFirestore)
          .toList(growable: false);
      final normalizedSearch = searchText.trim().toLowerCase();
      if (normalizedSearch.isEmpty) return receipts;
      return receipts
          .where((receipt) {
            return receipt.receiptNumber.toLowerCase().contains(
                  normalizedSearch,
                ) ||
                receipt.customerSnapshot.name.toLowerCase().contains(
                  normalizedSearch,
                ) ||
                receipt.salesRepName.toLowerCase().contains(normalizedSearch) ||
                receipt.paymentMethod.toLowerCase().contains(normalizedSearch);
          })
          .toList(growable: false);
    });
  }

  Future<ReceiptModel?> getReceiptById({
    String companyId = AuthRepository.defaultCompanyId,
    required String receiptId,
  }) {
    return _run(() async {
      final user = await _contextReader.requireApprovedUser();
      final resolvedCompanyId = _resolveCompanyId(companyId, user);
      final document = await _receipts(
        resolvedCompanyId,
      ).doc(receiptId).get().timeout(const Duration(seconds: 20));
      if (!document.exists) return null;
      final receipt = ReceiptModel.fromFirestore(document);
      _requireCanAccessReceipt(user, receipt);
      return receipt;
    });
  }

  Future<ReceiptModel> createReceipt({
    String companyId = AuthRepository.defaultCompanyId,
    required String customerId,
    required double amount,
    required String paymentMethod,
    required DateTime receiptDate,
    String notes = '',
  }) {
    return _run(() async {
      final user = await _contextReader.requireApprovedUser();
      final resolvedCompanyId = _resolveCompanyId(companyId, user);
      if (!amount.isFinite || amount <= 0) {
        throw const ReceiptRepositoryException(
          ReceiptRepositoryError.invalidData,
        );
      }

      late ReceiptModel created;
      await _firestore
          .runTransaction((transaction) async {
            final customerRef = _customers(resolvedCompanyId).doc(customerId);
            final customerSnapshot = await transaction.get(customerRef);
            if (!customerSnapshot.exists) {
              throw const ReceiptRepositoryException(
                ReceiptRepositoryError.notFound,
              );
            }
            final customer = CustomerModel.fromFirestore(customerSnapshot);
            _requireCanAccessCustomer(user, customer);

            final receiptNumber = await _nextReceiptNumber(
              transaction: transaction,
              companyId: resolvedCompanyId,
              receiptDate: receiptDate,
            );
            final receiptRef = _receipts(resolvedCompanyId).doc();
            final customerTransactionRef = _receiptCustomerTransactionRef(
              resolvedCompanyId,
              receiptRef.id,
            );
            final movementRef = _receiptCashMovementRef(
              resolvedCompanyId,
              receiptRef.id,
            );
            await _guardAgainstDuplicatePosting(
              transaction: transaction,
              customerTransactionRef: customerTransactionRef,
              cashMovementRef: movementRef,
            );
            final now = DateTime.now();
            final roundedAmount = _round(amount);
            final normalizedPaymentMethod = paymentMethod.trim().isEmpty
                ? 'cash'
                : paymentMethod.trim().toLowerCase();
            created = ReceiptModel(
              id: receiptRef.id,
              companyId: resolvedCompanyId,
              receiptNumber: receiptNumber,
              receiptDate: receiptDate,
              customerId: customer.id,
              customerSnapshot: customer.toInvoiceSnapshot(),
              amount: roundedAmount,
              paymentMethod: normalizedPaymentMethod,
              notes: notes.trim(),
              salesRepId: user.uid,
              salesRepName: user.name,
              createdByUid: user.uid,
              createdByName: user.name,
              createdByRole: user.role,
              customerTransactionIds: [customerTransactionRef.id],
              cashMovementIds: normalizedPaymentMethod == 'cash'
                  ? [movementRef.id]
                  : const [],
              createdAt: now,
              updatedAt: now,
            );

            final newBalance = _round(customer.currentBalance - roundedAmount);
            transaction.set(receiptRef, {
              ...created.toMap(),
              'createdAt': FieldValue.serverTimestamp(),
              'updatedAt': FieldValue.serverTimestamp(),
            });
            transaction.update(customerRef, {
              'currentBalance': newBalance,
              'totalPaid': _round(customer.totalPaid + roundedAmount),
              'updatedAt': FieldValue.serverTimestamp(),
            });

            transaction.set(customerTransactionRef, {
              'id': customerTransactionRef.id,
              'companyId': resolvedCompanyId,
              'customerId': customer.id,
              'customerName': customer.name,
              'transactionType': 'receipt',
              'referenceId': receiptRef.id,
              'sourceCollection': 'receipts',
              'sourceId': receiptRef.id,
              'sourceNumber': receiptNumber,
              'transactionDate': Timestamp.fromDate(receiptDate),
              'debitAmount': 0,
              'creditAmount': roundedAmount,
              'balanceAfter': newBalance,
              'notes': notes.trim(),
              'createdByUid': user.uid,
              'createdByName': user.name,
              'createdByRole': user.role,
              'salesRepId': user.uid,
              'salesRepName': user.name,
              'createdAt': FieldValue.serverTimestamp(),
            });

            if (created.paymentMethod == 'cash') {
              transaction.set(movementRef, {
                'id': movementRef.id,
                'companyId': resolvedCompanyId,
                'movementType': 'receipt',
                'type': 'receipt_cash',
                'direction': 'in',
                'amount': roundedAmount,
                'paymentType': created.paymentMethod,
                'customerId': customer.id,
                'customerName': customer.name,
                'referenceId': receiptRef.id,
                'referenceNumber': receiptNumber,
                'sourceCollection': 'receipts',
                'sourceId': receiptRef.id,
                'sourceNumber': receiptNumber,
                'date': Timestamp.fromDate(receiptDate),
                'movementDate': Timestamp.fromDate(receiptDate),
                'notes': notes.trim(),
                'salesRepId': user.uid,
                'salesRepName': user.name,
                'createdByUid': user.uid,
                'createdByName': user.name,
                'createdByRole': user.role,
                'createdAt': FieldValue.serverTimestamp(),
              });
            }
          })
          .timeout(const Duration(seconds: 20));

      return created;
    });
  }

  Future<void> _guardAgainstDuplicatePosting({
    required Transaction transaction,
    required DocumentReference<Map<String, dynamic>> customerTransactionRef,
    required DocumentReference<Map<String, dynamic>> cashMovementRef,
  }) async {
    final customerTransactionSnapshot = await transaction.get(
      customerTransactionRef,
    );
    if (customerTransactionSnapshot.exists) {
      throw const ReceiptRepositoryException(
        ReceiptRepositoryError.invalidData,
      );
    }
    final movementSnapshot = await transaction.get(cashMovementRef);
    if (movementSnapshot.exists) {
      throw const ReceiptRepositoryException(
        ReceiptRepositoryError.invalidData,
      );
    }
  }

  DocumentReference<Map<String, dynamic>> _receiptCustomerTransactionRef(
    String companyId,
    String receiptId,
  ) {
    return _transactions(companyId).doc('${receiptId}_credit');
  }

  DocumentReference<Map<String, dynamic>> _receiptCashMovementRef(
    String companyId,
    String receiptId,
  ) {
    return _cashMovements(companyId).doc('${receiptId}_cash');
  }

  Future<String> _nextReceiptNumber({
    required Transaction transaction,
    required String companyId,
    required DateTime receiptDate,
  }) async {
    final year = receiptDate.year;
    final settingsSnapshot = await transaction.get(_appSettings(companyId));
    final documents = AppSettingsModel.fromMap(
      settingsSnapshot.data(),
    ).documentSettings;
    final prefix = BusinessSettingsDefaults.prefix(
      documents.receiptPrefix,
      DocumentSettingsModel.defaults.receiptPrefix,
    );
    final counterRef = _receiptCounter(companyId, year);
    final counter = await transaction.get(counterRef);
    final current = counter.data()?['lastNumber'];
    final next = current is num ? current.toInt() + 1 : 1;
    transaction.set(counterRef, {
      'id': counterRef.id,
      'companyId': companyId,
      'year': year,
      'lastNumber': next,
      'prefix': prefix,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    return BusinessSettingsDefaults.documentNumber(
      prefix: prefix,
      year: year,
      sequence: next,
    );
  }

  void _requireCanAccessCustomer(
    BusinessUserContext user,
    CustomerModel customer,
  ) {
    if (user.isAdmin) return;
    if (user.isSalesRep && customer.createdByUid == user.uid) return;
    throw const ReceiptRepositoryException(
      ReceiptRepositoryError.permissionDenied,
    );
  }

  void _requireCanAccessReceipt(
    BusinessUserContext user,
    ReceiptModel receipt,
  ) {
    if (user.isAdmin) return;
    if (user.isSalesRep && receipt.salesRepId == user.uid) return;
    throw const ReceiptRepositoryException(
      ReceiptRepositoryError.permissionDenied,
    );
  }

  String _resolveCompanyId(String requested, BusinessUserContext user) {
    final companyId = requested.trim().isEmpty
        ? AuthRepository.defaultCompanyId
        : requested.trim();
    if (companyId != user.companyId) {
      throw const ReceiptRepositoryException(
        ReceiptRepositoryError.permissionDenied,
      );
    }
    return companyId;
  }

  double _round(double value) {
    if (!value.isFinite) return 0;
    return (math.max(value, -999999999) * 1000).roundToDouble() / 1000;
  }

  DateTime _startOfDay(DateTime date) =>
      DateTime(date.year, date.month, date.day);

  DateTime _endOfDay(DateTime date) =>
      DateTime(date.year, date.month, date.day, 23, 59, 59, 999);

  Future<T> _run<T>(Future<T> Function() operation) async {
    try {
      return await operation();
    } on ReceiptRepositoryException {
      rethrow;
    } on BusinessUserContextException catch (error) {
      throw ReceiptRepositoryException(_mapContextError(error.error), error);
    } on TimeoutException catch (error) {
      throw ReceiptRepositoryException(ReceiptRepositoryError.timeout, error);
    } on FirebaseException catch (error) {
      throw ReceiptRepositoryException(_mapFirebaseError(error.code), error);
    } catch (error) {
      throw ReceiptRepositoryException(ReceiptRepositoryError.unknown, error);
    }
  }

  ReceiptRepositoryError _mapContextError(BusinessUserContextError error) {
    return switch (error) {
      BusinessUserContextError.unauthenticated =>
        ReceiptRepositoryError.unauthenticated,
      BusinessUserContextError.profileMissing =>
        ReceiptRepositoryError.unauthenticated,
      BusinessUserContextError.permissionDenied =>
        ReceiptRepositoryError.permissionDenied,
      BusinessUserContextError.invalidProfile =>
        ReceiptRepositoryError.invalidData,
      BusinessUserContextError.timeout => ReceiptRepositoryError.timeout,
    };
  }

  ReceiptRepositoryError _mapFirebaseError(String code) {
    return switch (code) {
      'permission-denied' => ReceiptRepositoryError.permissionDenied,
      'unauthenticated' => ReceiptRepositoryError.unauthenticated,
      'unavailable' ||
      'deadline-exceeded' => ReceiptRepositoryError.unavailable,
      'not-found' => ReceiptRepositoryError.notFound,
      _ => ReceiptRepositoryError.unknown,
    };
  }
}
