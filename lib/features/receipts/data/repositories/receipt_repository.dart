import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:fatoora/core/data/firestore_query_pager.dart';
import 'package:fatoora/core/firebase/trusted_callable_client.dart';
import 'package:fatoora/features/auth/data/repositories/auth_repository.dart';
import 'package:fatoora/features/receipts/data/models/receipt_model.dart';
import 'package:fatoora/features/shared/business/business_user_context.dart';
import 'package:firebase_auth/firebase_auth.dart';

enum ReceiptRepositoryError {
  unauthenticated,
  permissionDenied,
  createDisabled,
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

  CollectionReference<Map<String, dynamic>> _receipts(String companyId) {
    return _firestore
        .collection('companies')
        .doc(companyId)
        .collection('receipts');
  }

  Future<List<ReceiptModel>> fetchReceipts({
    String companyId = AuthRepository.defaultCompanyId,
    DateTime? fromDate,
    DateTime? toDate,
    String searchText = '',
    int pageSize = 150,
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
      final documents = await query
          .orderBy('receiptDate', descending: true)
          .orderBy(FieldPath.documentId, descending: true)
          .getAllPages(pageSize: pageSize);
      final receipts = documents
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
    bool payFullBalance = false,
  }) {
    return _run(() async {
      final user = await _contextReader.requireApprovedUser();
      final resolvedCompanyId = _resolveCompanyId(companyId, user);
      final idempotencyKey = _receipts(resolvedCompanyId).doc().id;
      final result = await _trustedCallableClient
          .callAuthenticated<Map<String, dynamic>>('createReceipt', {
            'companyId': resolvedCompanyId,
            'idempotencyKey': idempotencyKey,
            'customerId': customerId,
            'amount': amount,
            'paymentMethod': paymentMethod,
            'receiptDate': receiptDate.millisecondsSinceEpoch,
            'notes': notes,
            'payFullBalance': payFullBalance,
          })
          .timeout(const Duration(seconds: 30));
      final receiptId = result.data['receiptId'] as String?;
      if (receiptId == null || receiptId.isEmpty) {
        throw const ReceiptRepositoryException(
          ReceiptRepositoryError.invalidData,
        );
      }
      final snapshot = await _receipts(
        resolvedCompanyId,
      ).doc(receiptId).get().timeout(const Duration(seconds: 20));
      if (!snapshot.exists) {
        throw const ReceiptRepositoryException(ReceiptRepositoryError.notFound);
      }
      return ReceiptModel.fromFirestore(snapshot);
    });
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
