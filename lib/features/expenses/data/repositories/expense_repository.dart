import 'dart:async';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fatoora/features/auth/data/repositories/auth_repository.dart';
import 'package:fatoora/features/expenses/data/models/expense_model.dart';
import 'package:fatoora/features/financial/data/models/cash_movement_model.dart';
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

  CollectionReference<Map<String, dynamic>> _expenses(String companyId) {
    return _firestore
        .collection('companies')
        .doc(companyId)
        .collection('expenses');
  }

  CollectionReference<Map<String, dynamic>> _cashMovements(String companyId) {
    return _firestore
        .collection('companies')
        .doc(companyId)
        .collection('cash_movements');
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
      final snapshot = await query
          .limit(700)
          .get()
          .timeout(const Duration(seconds: 20));
      final needle = searchText.trim().toLowerCase();
      final expenses = snapshot.docs
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
      final roundedAmount = _round(amount);
      _validateExpenseInput(
        amount: roundedAmount,
        category: category,
        customCategoryName: customCategoryName,
      );

      final expenseRef = _expenses(resolvedCompanyId).doc();
      final now = DateTime.now();
      final effectiveFundingSource = user.isAdmin
          ? ExpenseFundingSource.companyCash
          : fundingSource;
      if (user.isSalesRep &&
          effectiveFundingSource == ExpenseFundingSource.companyCash) {
        throw const ExpenseRepositoryException(
          ExpenseRepositoryError.permissionDenied,
        );
      }
      final isImmediateCompanyCash =
          user.isAdmin &&
          effectiveFundingSource == ExpenseFundingSource.companyCash;
      final status = isImmediateCompanyCash
          ? ExpenseStatus.posted
          : ExpenseStatus.pending;
      final reimbursementStatus = ExpenseReimbursementStatus.none;
      final cashMovementRef = isImmediateCompanyCash
          ? _cashMovements(resolvedCompanyId).doc('${expenseRef.id}_cash_out')
          : null;
      final expense = ExpenseModel(
        id: expenseRef.id,
        companyId: resolvedCompanyId,
        amount: roundedAmount,
        expenseDate: expenseDate,
        category: category,
        customCategoryName: customCategoryName.trim(),
        description: description.trim(),
        paidByUid: user.uid,
        paidByName: user.name,
        paidByRole: user.role,
        salesRepId: user.isSalesRep ? user.uid : '',
        salesRepName: user.isSalesRep ? user.name : '',
        paymentMethod: paymentMethod.trim().isEmpty
            ? 'cash'
            : paymentMethod.trim(),
        fundingSource: effectiveFundingSource,
        status: status,
        cashMovementId: cashMovementRef?.id ?? '',
        reimbursementStatus: reimbursementStatus,
        approvedByUid: isImmediateCompanyCash ? user.uid : '',
        approvedByName: isImmediateCompanyCash ? user.name : '',
        approvedAt: isImmediateCompanyCash ? now : null,
        rejectedByUid: '',
        rejectedByName: '',
        rejectedAt: null,
        rejectionReason: '',
        createdByUid: user.uid,
        createdByName: user.name,
        createdByRole: user.role,
        createdAt: now,
        updatedAt: now,
      );

      final batch = _firestore.batch();
      batch.set(expenseRef, {
        ...expense.toMap(),
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        if (isImmediateCompanyCash) 'approvedAt': FieldValue.serverTimestamp(),
      });
      if (cashMovementRef != null) {
        batch.set(
          cashMovementRef,
          _cashMovementData(
            companyId: resolvedCompanyId,
            movementId: cashMovementRef.id,
            expense: expense,
            user: user,
            cashAccount: CashMovementModel.companyCashAccount,
            salesRepId: '',
            salesRepName: '',
          ),
        );
      }
      await batch.commit().timeout(const Duration(seconds: 20));
      return expense;
    });
  }

  Future<void> approveExpense({
    String companyId = AuthRepository.defaultCompanyId,
    required String expenseId,
  }) {
    return _run(() async {
      final user = await _contextReader.requireApprovedUser();
      final resolvedCompanyId = _resolveCompanyId(companyId, user);
      if (!user.isAdmin) {
        throw const ExpenseRepositoryException(
          ExpenseRepositoryError.permissionDenied,
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
            if (expense.usesRepCollectedCash) {
              if (expense.salesRepId.isEmpty || expense.amount <= 0) {
                throw const ExpenseRepositoryException(
                  ExpenseRepositoryError.invalidData,
                );
              }
              final movementRef = _cashMovements(
                resolvedCompanyId,
              ).doc('${expense.id}_cash_out');
              transaction.set(
                movementRef,
                _cashMovementData(
                  companyId: resolvedCompanyId,
                  movementId: movementRef.id,
                  expense: expense,
                  user: user,
                  cashAccount: CashMovementModel.repCashAccount,
                  salesRepId: expense.salesRepId,
                  salesRepName: expense.salesRepName,
                ),
              );
              transaction.update(expenseRef, {
                'status': ExpenseStatus.approved.value,
                'cashMovementId': movementRef.id,
                'reimbursementStatus': ExpenseReimbursementStatus.none.value,
                'approvedByUid': user.uid,
                'approvedByName': user.name,
                'approvedAt': FieldValue.serverTimestamp(),
                'updatedAt': FieldValue.serverTimestamp(),
              });
              return;
            }
            if (expense.usesPersonalCash) {
              transaction.update(expenseRef, {
                'status': ExpenseStatus.approved.value,
                'cashMovementId': '',
                'reimbursementStatus': ExpenseReimbursementStatus.payable.value,
                'approvedByUid': user.uid,
                'approvedByName': user.name,
                'approvedAt': FieldValue.serverTimestamp(),
                'updatedAt': FieldValue.serverTimestamp(),
              });
              return;
            }
            throw const ExpenseRepositoryException(
              ExpenseRepositoryError.invalidState,
            );
          })
          .timeout(const Duration(seconds: 20));
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

  Map<String, dynamic> _cashMovementData({
    required String companyId,
    required String movementId,
    required ExpenseModel expense,
    required BusinessUserContext user,
    required String cashAccount,
    required String salesRepId,
    required String salesRepName,
  }) {
    final referenceNumber = _expenseReference(expense.expenseDate, expense.id);
    return {
      'id': movementId,
      'companyId': companyId,
      'movementType': 'expense',
      'type': 'expense',
      'direction': 'out',
      'amount': expense.amount,
      'cashAccount': cashAccount,
      'paymentType': expense.paymentMethod,
      'customerId': '',
      'customerName': '',
      'referenceId': expense.id,
      'referenceNumber': referenceNumber,
      'sourceCollection': 'expenses',
      'sourceId': expense.id,
      'sourceNumber': referenceNumber,
      'date': Timestamp.fromDate(expense.expenseDate),
      'movementDate': Timestamp.fromDate(expense.expenseDate),
      'notes': expense.description,
      'salesRepId': salesRepId,
      'salesRepName': salesRepName,
      'createdByUid': user.uid,
      'createdByName': user.name,
      'createdByRole': user.role,
      'createdAt': FieldValue.serverTimestamp(),
    };
  }

  bool _canRead(ExpenseModel expense, BusinessUserContext user) {
    return user.isAdmin ||
        expense.paidByUid == user.uid ||
        expense.salesRepId == user.uid;
  }

  void _validateExpenseInput({
    required double amount,
    required ExpenseCategory category,
    required String customCategoryName,
  }) {
    if (amount <= 0) {
      throw const ExpenseRepositoryException(
        ExpenseRepositoryError.invalidData,
      );
    }
    if (category == ExpenseCategory.other &&
        customCategoryName.trim().length < 2) {
      throw const ExpenseRepositoryException(
        ExpenseRepositoryError.invalidData,
      );
    }
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

  String _expenseReference(DateTime date, String id) {
    final prefix =
        'EXP-${date.year}${date.month.toString().padLeft(2, '0')}${date.day.toString().padLeft(2, '0')}';
    return '$prefix-${id.substring(0, math.min(6, id.length)).toUpperCase()}';
  }

  DateTime _startOfDay(DateTime date) =>
      DateTime(date.year, date.month, date.day);

  DateTime _endOfDay(DateTime date) =>
      DateTime(date.year, date.month, date.day, 23, 59, 59, 999);

  double _round(double value) {
    if (!value.isFinite) return 0;
    return (value * 1000).roundToDouble() / 1000;
  }

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
