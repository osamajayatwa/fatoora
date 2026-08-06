import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:fatoora/core/data/firestore_query_pager.dart';
import 'package:fatoora/core/firebase/trusted_callable_client.dart';
import 'package:fatoora/features/auth/data/repositories/auth_repository.dart';
import 'package:fatoora/features/expenses/data/models/expense_model.dart';
import 'package:fatoora/features/shared/business/business_user_context.dart';
import 'package:firebase_auth/firebase_auth.dart';

enum ExpenseRepositoryError {
  unauthenticated,
  permissionDenied,
  unavailable,
  timeout,
  notFound,
  invalidData,
  invalidState,
  unknown,
}

class ExpenseRepositoryException implements Exception {
  const ExpenseRepositoryException(this.error, [this.cause]);

  final ExpenseRepositoryError error;
  final Object? cause;
}

class ExpenseRepository {
  ExpenseRepository({
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

  CollectionReference<Map<String, dynamic>> _expenses(String companyId) {
    return _firestore
        .collection('companies')
        .doc(companyId)
        .collection('expenses');
  }

  Future<List<ExpenseModel>> fetchExpenses({
    String companyId = AuthRepository.defaultCompanyId,
    String searchText = '',
    ExpenseStatus? status,
    ExpenseCategory? category,
    DateTime? fromDate,
    DateTime? toDate,
  }) {
    return _run(() async {
      final user = await _contextReader.requireApprovedUser();
      final resolvedCompanyId = _resolveCompanyId(companyId, user);
      Query<Map<String, dynamic>> query = _expenses(resolvedCompanyId);
      if (user.isSalesRep) {
        query = query.where('paidByUid', isEqualTo: user.uid);
      }
      if (status != null) {
        query = query.where('status', isEqualTo: status.value);
      }
      if (category != null) {
        query = query.where('category', isEqualTo: category.value);
      }
      if (fromDate != null) {
        query = query.where(
          'expenseDate',
          isGreaterThanOrEqualTo: Timestamp.fromDate(_startOfDay(fromDate)),
        );
      }
      if (toDate != null) {
        query = query.where(
          'expenseDate',
          isLessThanOrEqualTo: Timestamp.fromDate(_endOfDay(toDate)),
        );
      }
      final documents = await query
          .orderBy('expenseDate', descending: true)
          .orderBy(FieldPath.documentId, descending: true)
          .getAllPages();
      final needle = searchText.trim().toLowerCase();
      final expenses = documents
          .map(ExpenseModel.fromFirestore)
          .where((expense) {
            final afterFrom =
                fromDate == null ||
                !expense.expenseDate.isBefore(_startOfDay(fromDate));
            final beforeTo =
                toDate == null ||
                !expense.expenseDate.isAfter(_endOfDay(toDate));
            final matchesStatus = status == null || expense.status == status;
            final matchesCategory =
                category == null || expense.category == category;
            final matchesSearch =
                needle.isEmpty ||
                expense.description.toLowerCase().contains(needle) ||
                expense.paidByName.toLowerCase().contains(needle) ||
                expense.customCategoryName.toLowerCase().contains(needle) ||
                expense.id.toLowerCase().contains(needle);
            return afterFrom &&
                beforeTo &&
                matchesStatus &&
                matchesCategory &&
                matchesSearch;
          })
          .toList(growable: false);
      expenses.sort((a, b) => b.expenseDate.compareTo(a.expenseDate));
      return expenses;
    });
  }

  Future<ExpenseModel> fetchExpenseById({
    String companyId = AuthRepository.defaultCompanyId,
    required String expenseId,
  }) {
    return _run(() async {
      final user = await _contextReader.requireApprovedUser();
      final resolvedCompanyId = _resolveCompanyId(companyId, user);
      final document = await _expenses(
        resolvedCompanyId,
      ).doc(expenseId.trim()).get().timeout(const Duration(seconds: 20));
      if (!document.exists) {
        throw const ExpenseRepositoryException(ExpenseRepositoryError.notFound);
      }
      final expense = ExpenseModel.fromFirestore(document);
      if (!_canRead(expense, user)) {
        throw const ExpenseRepositoryException(
          ExpenseRepositoryError.permissionDenied,
        );
      }
      return expense;
    });
  }

  Future<ExpenseModel> createExpense({
    String companyId = AuthRepository.defaultCompanyId,
    required double amount,
    required DateTime expenseDate,
    required ExpenseCategory category,
    String customCategoryName = '',
    String description = '',
    String paymentMethod = 'cash',
    required ExpenseFundingSource fundingSource,
  }) {
    return _run(() async {
      final user = await _contextReader.requireApprovedUser();
      final resolvedCompanyId = _resolveCompanyId(companyId, user);
      final idempotencyKey = _expenses(resolvedCompanyId).doc().id;
      final result = await _trustedCallableClient
          .callAuthenticated<Map<String, dynamic>>('createExpense', {
            'companyId': resolvedCompanyId,
            'idempotencyKey': idempotencyKey,
            'amount': amount,
            'expenseDate': expenseDate.millisecondsSinceEpoch,
            'category': category.value,
            'customCategoryName': customCategoryName,
            'description': description,
            'fundingSource': fundingSource.value,
          })
          .timeout(const Duration(seconds: 30));
      final expenseId = result.data['expenseId'] as String?;
      if (expenseId == null || expenseId.isEmpty) {
        throw const ExpenseRepositoryException(
          ExpenseRepositoryError.invalidData,
        );
      }
      final snapshot = await _expenses(
        resolvedCompanyId,
      ).doc(expenseId).get().timeout(const Duration(seconds: 20));
      if (!snapshot.exists) {
        throw const ExpenseRepositoryException(ExpenseRepositoryError.notFound);
      }
      return ExpenseModel.fromFirestore(snapshot);
    });
  }

  Future<void> approveExpense({
    String companyId = AuthRepository.defaultCompanyId,
    required String expenseId,
  }) {
    return _run(() async {
      final user = await _contextReader.requireApprovedUser();
      final resolvedCompanyId = _resolveCompanyId(companyId, user);
      await _trustedCallableClient
          .callAuthenticated<void>('approveExpense', {
            'companyId': resolvedCompanyId,
            'expenseId': expenseId.trim(),
          })
          .timeout(const Duration(seconds: 30));
    });
  }

  Future<void> rejectExpense({
    String companyId = AuthRepository.defaultCompanyId,
    required String expenseId,
    required String reason,
  }) {
    return _run(() async {
      final user = await _contextReader.requireApprovedUser();
      final resolvedCompanyId = _resolveCompanyId(companyId, user);
      if (!user.isAdmin) {
        throw const ExpenseRepositoryException(
          ExpenseRepositoryError.permissionDenied,
        );
      }
      final safeReason = reason.trim();
      if (safeReason.isEmpty) {
        throw const ExpenseRepositoryException(
          ExpenseRepositoryError.invalidData,
        );
      }
      final expenseRef = _expenses(resolvedCompanyId).doc(expenseId.trim());
      await _firestore
          .runTransaction((transaction) async {
            final snapshot = await transaction.get(expenseRef);
            if (!snapshot.exists) {
              throw const ExpenseRepositoryException(
                ExpenseRepositoryError.notFound,
              );
            }
            final expense = ExpenseModel.fromFirestore(snapshot);
            if (expense.status != ExpenseStatus.pending) {
              throw const ExpenseRepositoryException(
                ExpenseRepositoryError.invalidState,
              );
            }
            transaction.update(expenseRef, {
              'status': ExpenseStatus.rejected.value,
              'reimbursementStatus': ExpenseReimbursementStatus.none.value,
              'rejectedByUid': user.uid,
              'rejectedByName': user.name,
              'rejectedAt': FieldValue.serverTimestamp(),
              'rejectionReason': safeReason,
              'updatedAt': FieldValue.serverTimestamp(),
            });
          })
          .timeout(const Duration(seconds: 20));
    });
  }

  bool _canRead(ExpenseModel expense, BusinessUserContext user) {
    return user.isAdmin ||
        expense.paidByUid == user.uid ||
        expense.salesRepId == user.uid;
  }

  String _resolveCompanyId(String requested, BusinessUserContext user) {
    final companyId = requested.trim().isEmpty
        ? AuthRepository.defaultCompanyId
        : requested.trim();
    if (companyId != user.companyId) {
      throw const ExpenseRepositoryException(
        ExpenseRepositoryError.permissionDenied,
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
    } on ExpenseRepositoryException {
      rethrow;
    } on BusinessUserContextException catch (error) {
      throw ExpenseRepositoryException(_mapContextError(error.error), error);
    } on TimeoutException catch (error) {
      throw ExpenseRepositoryException(ExpenseRepositoryError.timeout, error);
    } on FirebaseException catch (error) {
      throw ExpenseRepositoryException(_mapFirebaseError(error.code), error);
    } catch (error) {
      throw ExpenseRepositoryException(ExpenseRepositoryError.unknown, error);
    }
  }

  ExpenseRepositoryError _mapContextError(BusinessUserContextError error) {
    return switch (error) {
      BusinessUserContextError.unauthenticated ||
      BusinessUserContextError.profileMissing =>
        ExpenseRepositoryError.unauthenticated,
      BusinessUserContextError.permissionDenied =>
        ExpenseRepositoryError.permissionDenied,
      BusinessUserContextError.invalidProfile =>
        ExpenseRepositoryError.invalidData,
      BusinessUserContextError.timeout => ExpenseRepositoryError.timeout,
    };
  }

  ExpenseRepositoryError _mapFirebaseError(String code) {
    return switch (code) {
      'permission-denied' => ExpenseRepositoryError.permissionDenied,
      'unauthenticated' => ExpenseRepositoryError.unauthenticated,
      'unavailable' ||
      'deadline-exceeded' => ExpenseRepositoryError.unavailable,
      'invalid-argument' ||
      'failed-precondition' => ExpenseRepositoryError.invalidData,
      _ => ExpenseRepositoryError.unknown,
    };
  }
}
