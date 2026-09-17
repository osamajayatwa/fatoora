import 'dart:async';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:fatoora/core/data/firestore_query_pager.dart';
import 'package:fatoora/core/firebase/trusted_callable_client.dart';
import 'package:fatoora/features/auth/data/repositories/auth_repository.dart';
import 'package:fatoora/features/customers/data/models/customer_model.dart';
import 'package:fatoora/features/expenses/data/models/expense_model.dart';
import 'package:fatoora/features/financial/data/models/cash_movement_model.dart';
import 'package:fatoora/features/financial/data/models/company_cash_opening_balance_model.dart';
import 'package:fatoora/features/financial/data/models/financial_dashboard_snapshot.dart';
import 'package:fatoora/features/financial/data/services/cash_ledger_calculator.dart';
import 'package:fatoora/features/invoices/data/models/invoice_enums.dart';
import 'package:fatoora/features/invoices/data/models/invoice_model.dart';
import 'package:fatoora/features/receipts/data/models/receipt_model.dart';
import 'package:fatoora/features/sales_returns/data/models/sales_return_model.dart';
import 'package:fatoora/features/shared/business/business_user_context.dart';
import 'package:firebase_auth/firebase_auth.dart';

enum FinancialRepositoryError {
  unauthenticated,
  permissionDenied,
  unavailable,
  timeout,
  alreadyExists,
  invalidData,
  unknown,
}

class FinancialRepositoryException implements Exception {
  const FinancialRepositoryException(this.error, [this.cause]);

  final FinancialRepositoryError error;
  final Object? cause;
}

class FinancialReceivablesPage {
  const FinancialReceivablesPage({
    required this.snapshot,
    required this.cursor,
    required this.hasMore,
  });

  final FinancialReceivablesSnapshot snapshot;
  final FirestorePageCursor? cursor;
  final bool hasMore;
}

class FinancialCashPage {
  const FinancialCashPage({
    required this.snapshot,
    required this.cursor,
    required this.hasMore,
  });

  final FinancialCashSnapshot snapshot;
  final FirestorePageCursor? cursor;
  final bool hasMore;
}

class FinancialRepository {
  FinancialRepository({
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

  CollectionReference<Map<String, dynamic>> _customers(String companyId) {
    return _firestore
        .collection('companies')
        .doc(companyId)
        .collection('customers');
  }

  CollectionReference<Map<String, dynamic>> _invoices(String companyId) {
    return _firestore
        .collection('companies')
        .doc(companyId)
        .collection('invoices');
  }

  CollectionReference<Map<String, dynamic>> _receipts(String companyId) {
    return _firestore
        .collection('companies')
        .doc(companyId)
        .collection('receipts');
  }

  CollectionReference<Map<String, dynamic>> _salesReturns(String companyId) {
    return _firestore
        .collection('companies')
        .doc(companyId)
        .collection('sales_returns');
  }

  CollectionReference<Map<String, dynamic>> _cashMovements(String companyId) {
    return _firestore
        .collection('companies')
        .doc(companyId)
        .collection('cash_movements');
  }

  CollectionReference<Map<String, dynamic>> _expenses(String companyId) {
    return _firestore
        .collection('companies')
        .doc(companyId)
        .collection('expenses');
  }

  Future<FinancialDashboardSnapshot> fetchDashboard({
    String companyId = AuthRepository.defaultCompanyId,
    DateTime? fromDate,
    DateTime? toDate,
  }) {
    return _run(() async {
      final user = await _contextReader.requireApprovedUser();
      final resolvedCompanyId = _resolveCompanyId(companyId, user);
      final start = _startOfDay(fromDate ?? DateTime(2020));
      final end = _endOfDay(toDate ?? DateTime.now());
      final results = await Future.wait<Object>([
        _trustedCallableClient
            .callAuthenticated<Map<String, dynamic>>('getDashboardSnapshot', {
              'companyId': resolvedCompanyId,
              'from': start.millisecondsSinceEpoch,
              'to': end.millisecondsSinceEpoch,
            }),
        _fetchRecentInvoices(
          resolvedCompanyId,
          user,
          fromDate: start,
          toDate: end,
        ),
        _fetchRecentReceipts(
          resolvedCompanyId,
          user,
          fromDate: start,
          toDate: end,
        ),
        _fetchTopReceivableCustomers(resolvedCompanyId, user),
      ]);
      final callable = results[0] as HttpsCallableResult<Map<String, dynamic>>;
      final data = callable.data;
      final recentInvoices = results[1] as List<InvoiceModel>;
      final recentReceipts = results[2] as List<ReceiptModel>;
      final topCustomers = results[3] as List<FinancialCustomerBalance>;
      final repSummaries = _repSalesSummaries(data['salesByRepSummary']);
      final salesByRep = _repAmounts(data['salesByRep']);
      final cashByRep = _repAmounts(data['cashBySalesRep']);

      return FinancialDashboardSnapshot(
        totalSales: _number(data['totalSales']),
        cashSales: _number(data['cashSales']),
        creditSales: _number(data['creditSales']),
        partialSales: _number(data['partialSales']),
        totalReceivables: _number(data['totalReceivables']),
        cashInHand: _number(data['cashInHand']),
        companyCash: _number(data['companyCash']),
        repCashOutstanding: _number(data['repCashOutstanding']),
        totalExpenses: _number(data['totalExpenses']),
        pendingExpenseCount: _integer(data['pendingExpenseCount']),
        reimbursementsPayable: _number(data['reimbursementsPayable']),
        invoiceCount: _integer(data['invoiceCount']),
        customerCount: _integer(data['customerCount']),
        receiptCount: _integer(data['receiptCount']),
        recentInvoices: recentInvoices,
        recentReceipts: recentReceipts,
        topCustomers: topCustomers,
        cashBySalesRep: cashByRep,
        repCashOutstandingBySalesRep: cashByRep,
        salesByRep: salesByRep,
        salesByRepSummary: repSummaries,
        weeklyInvoiceValues: _numberList(data['weeklyInvoiceValues']),
      );
    });
  }

  Future<FinancialReceivablesSnapshot> fetchReceivables({
    String companyId = AuthRepository.defaultCompanyId,
    DateTime? fromDate,
    DateTime? toDate,
  }) {
    return _run(() async {
      final user = await _contextReader.requireApprovedUser();
      final resolvedCompanyId = _resolveCompanyId(companyId, user);
      final customers = await _fetchCustomers(resolvedCompanyId, user);
      final effectiveDate = toDate ?? fromDate;
      final historicalBalances = effectiveDate == null
          ? const <String, _ProjectedReceivableBalance>{}
          : await _fetchProjectedReceivableBalances(
              resolvedCompanyId,
              customers.map((customer) => customer.id).toList(growable: false),
              _endOfDay(effectiveDate).add(const Duration(milliseconds: 1)),
            );
      final receivableCustomers = _buildReceivableCustomers(
        customers,
        historicalBalances,
        hasDateFilter: effectiveDate != null,
      );
      return FinancialReceivablesSnapshot(
        customers: receivableCustomers,
        totalReceivables: _round(
          receivableCustomers.fold<double>(
            0,
            (total, item) => total + item.balance,
          ),
        ),
      );
    });
  }

  Future<FinancialReceivablesPage> fetchCurrentReceivablesPage({
    String companyId = AuthRepository.defaultCompanyId,
    FirestorePageCursor? after,
    int pageSize = 40,
  }) {
    return _run(() async {
      final user = await _contextReader.requireApprovedUser();
      final resolvedCompanyId = _resolveCompanyId(companyId, user);
      Query<Map<String, dynamic>> query = _customers(resolvedCompanyId)
          .where('active', isEqualTo: true)
          .where('currentBalance', isGreaterThan: 0);
      if (user.isSalesRep) {
        query = query.where('createdByUid', isEqualTo: user.uid);
      }
      final results = await Future.wait<Object>([
        query
            .orderBy('currentBalance', descending: true)
            .orderBy(FieldPath.documentId)
            .getPage(
              decode: CustomerModel.fromFirestore,
              after: after,
              pageSize: pageSize,
            ),
        query.aggregate(sum('currentBalance')).get(),
      ]);
      final page = results[0] as FirestorePage<CustomerModel>;
      final aggregate = results[1] as AggregateQuerySnapshot;
      return FinancialReceivablesPage(
        snapshot: FinancialReceivablesSnapshot(
          customers: page.items
              .map(
                (customer) => FinancialCustomerBalance(
                  customer: customer,
                  balance: _round(customer.currentBalance),
                ),
              )
              .toList(growable: false),
          totalReceivables: _round(aggregate.getSum('currentBalance') ?? 0),
        ),
        cursor: page.cursor,
        hasMore: page.hasMore,
      );
    });
  }

  Future<FinancialCashSnapshot> fetchCash({
    String companyId = AuthRepository.defaultCompanyId,
    DateTime? fromDate,
    DateTime? toDate,
  }) {
    return _run(() async {
      final user = await _contextReader.requireApprovedUser();
      final resolvedCompanyId = _resolveCompanyId(companyId, user);
      final periodStart = fromDate == null ? null : _startOfDay(fromDate);
      final periodEnd = toDate == null ? null : _endOfDay(toDate);
      final results = await Future.wait<Object>([
        _fetchCashMovements(
          resolvedCompanyId,
          user,
          fromDate: periodStart,
          toDate: periodEnd,
        ),
        _trustedCallableClient
            .callAuthenticated<Map<String, dynamic>>('getCashOpeningBalance', {
              'companyId': resolvedCompanyId,
              'fromInclusive':
                  (periodStart ?? DateTime(1970)).millisecondsSinceEpoch,
            }),
      ]);
      final movements = results[0] as List<CashMovementModel>;
      final openingResult =
          results[1] as HttpsCallableResult<Map<String, dynamic>>;
      final openingData = openingResult.data;
      final cashLedger = CashLedgerCalculator.calculate(movements);
      final companyCash = user.isAdmin
          ? _round(
              _number(openingData['companyCashOpening']) +
                  cashLedger.companyCash,
            )
          : 0.0;
      final repCashOutstanding = _round(
        _number(openingData['repCashOpening']) + cashLedger.repCashOutstanding,
      );
      final cashByRep = {
        for (final amount in _repAmounts(
          openingData['repCashOpeningBySalesRep'],
        ))
          amount.salesRepId: amount,
      };
      for (final amount in cashLedger.repCashOutstandingBySalesRep) {
        final opening = cashByRep[amount.salesRepId];
        cashByRep[amount.salesRepId] = FinancialRepAmount(
          salesRepId: amount.salesRepId,
          salesRepName: amount.salesRepName.isNotEmpty
              ? amount.salesRepName
              : opening?.salesRepName ?? '',
          amount: _round((opening?.amount ?? 0) + amount.amount),
        );
      }
      final cashBySalesRep = cashByRep.values.toList(growable: false)
        ..sort((left, right) => right.amount.compareTo(left.amount));
      final totalIn = _round(
        movements
            .where((movement) => movement.isIn)
            .fold<double>(0, (total, movement) => total + movement.amount),
      );
      final totalOut = _round(
        movements
            .where((movement) => movement.isOut)
            .fold<double>(0, (total, movement) => total + movement.amount),
      );
      return FinancialCashSnapshot(
        movements: movements,
        openingBalance: _number(openingData['openingBalance']),
        closingBalance: _round(user.isAdmin ? companyCash : repCashOutstanding),
        cashInHand: _round(user.isAdmin ? companyCash : repCashOutstanding),
        companyCash: _round(companyCash),
        repCashOutstanding: _round(repCashOutstanding),
        totalIn: totalIn,
        totalOut: totalOut,
        cashBySalesRep: cashBySalesRep,
        repCashOutstandingBySalesRep: cashBySalesRep,
      );
    });
  }

  Future<FinancialCashPage> fetchCashPage({
    String companyId = AuthRepository.defaultCompanyId,
    DateTime? fromDate,
    DateTime? toDate,
    FirestorePageCursor? after,
    int pageSize = 50,
  }) {
    return _run(() async {
      final user = await _contextReader.requireApprovedUser();
      final resolvedCompanyId = _resolveCompanyId(companyId, user);
      final periodStart = fromDate == null ? null : _startOfDay(fromDate);
      final periodEnd = toDate == null ? null : _endOfDay(toDate);
      final openingCutoff = periodStart ?? DateTime(1970);
      final closingCutoff = periodEnd == null
          ? DateTime(9999, 12, 31, 23, 59, 59, 999)
          : periodEnd.add(const Duration(milliseconds: 1));
      final results = await Future.wait<Object>([
        _fetchCashMovementsPage(
          resolvedCompanyId,
          user,
          fromDate: periodStart,
          toDate: periodEnd,
          after: after,
          pageSize: pageSize,
        ),
        _trustedCallableClient
            .callAuthenticated<Map<String, dynamic>>('getCashOpeningBalance', {
              'companyId': resolvedCompanyId,
              'fromInclusive': openingCutoff.millisecondsSinceEpoch,
            }),
        _trustedCallableClient
            .callAuthenticated<Map<String, dynamic>>('getCashOpeningBalance', {
              'companyId': resolvedCompanyId,
              'fromInclusive': closingCutoff.millisecondsSinceEpoch,
            }),
        _fetchCashMovementTotals(
          resolvedCompanyId,
          user,
          fromDate: periodStart,
          toDate: periodEnd,
        ),
      ]);
      final page = results[0] as FirestorePage<CashMovementModel>;
      final opening =
          (results[1] as HttpsCallableResult<Map<String, dynamic>>).data;
      final closing =
          (results[2] as HttpsCallableResult<Map<String, dynamic>>).data;
      final totals = results[3] as ({double totalIn, double totalOut});
      final companyCash = user.isAdmin
          ? _number(closing['companyCashOpening'])
          : 0.0;
      final repCashOutstanding = _number(closing['repCashOpening']);
      final cashBySalesRep = _repAmounts(closing['repCashOpeningBySalesRep'])
        ..sort((left, right) => right.amount.compareTo(left.amount));
      return FinancialCashPage(
        snapshot: FinancialCashSnapshot(
          movements: page.items,
          openingBalance: _number(opening['openingBalance']),
          closingBalance: _round(
            user.isAdmin ? companyCash : repCashOutstanding,
          ),
          cashInHand: _round(user.isAdmin ? companyCash : repCashOutstanding),
          companyCash: _round(companyCash),
          repCashOutstanding: _round(repCashOutstanding),
          totalIn: totals.totalIn,
          totalOut: totals.totalOut,
          cashBySalesRep: cashBySalesRep,
          repCashOutstandingBySalesRep: cashBySalesRep,
        ),
        cursor: page.cursor,
        hasMore: page.hasMore,
      );
    });
  }

  Future<FirestorePage<CashMovementModel>> fetchCashMovementDetailsPage({
    String companyId = AuthRepository.defaultCompanyId,
    DateTime? fromDate,
    DateTime? toDate,
    FirestorePageCursor? after,
    int pageSize = 50,
  }) {
    return _run(() async {
      final user = await _contextReader.requireApprovedUser();
      final resolvedCompanyId = _resolveCompanyId(companyId, user);
      return _fetchCashMovementsPage(
        resolvedCompanyId,
        user,
        fromDate: fromDate == null ? null : _startOfDay(fromDate),
        toDate: toDate == null ? null : _endOfDay(toDate),
        after: after,
        pageSize: pageSize,
      );
    });
  }

  Future<void> recordCashSettlement({
    String companyId = AuthRepository.defaultCompanyId,
    required String salesRepId,
    required String salesRepName,
    required double amount,
    required DateTime settlementDate,
    String notes = '',
  }) {
    return _run(() async {
      final user = await _contextReader.requireApprovedUser();
      final resolvedCompanyId = _resolveCompanyId(companyId, user);
      if (!user.isAdmin) {
        throw const FinancialRepositoryException(
          FinancialRepositoryError.permissionDenied,
        );
      }
      final idempotencyKey = _cashMovements(resolvedCompanyId).doc().id;
      await _trustedCallableClient
          .callAuthenticated<void>('recordCashSettlement', {
            'companyId': resolvedCompanyId,
            'idempotencyKey': idempotencyKey,
            'salesRepId': salesRepId,
            'salesRepName': salesRepName,
            'amount': amount,
            'settlementDate': settlementDate.millisecondsSinceEpoch,
            'notes': notes,
          })
          .timeout(const Duration(seconds: 30));
    });
  }

  Future<CompanyCashOpeningBalanceModel?> getCompanyCashOpeningBalance({
    String companyId = AuthRepository.defaultCompanyId,
  }) {
    return _run(() async {
      final user = await _contextReader.requireApprovedUser();
      final resolvedCompanyId = _resolveCompanyId(companyId, user);
      if (!user.isAdmin) {
        throw const FinancialRepositoryException(
          FinancialRepositoryError.permissionDenied,
        );
      }
      final document = await _cashMovements(
        resolvedCompanyId,
      ).doc(CompanyCashOpeningBalanceModel.movementId).get();
      if (!document.exists) return null;
      final opening = CompanyCashOpeningBalanceModel.fromFirestore(document);
      final data = document.data() ?? const <String, dynamic>{};
      if (!opening.isValidOpeningBalance ||
          opening.companyId != resolvedCompanyId ||
          data['cashAccount'] != CashMovementModel.companyCashAccount ||
          data['movementType'] != 'opening_balance' ||
          data['type'] != 'opening_balance' ||
          data['direction'] != 'in') {
        throw const FinancialRepositoryException(
          FinancialRepositoryError.invalidData,
        );
      }
      return opening;
    });
  }

  Future<void> postCompanyCashOpeningBalance({
    String companyId = AuthRepository.defaultCompanyId,
    required double amount,
    String note = '',
  }) {
    return _run(() async {
      final user = await _contextReader.requireApprovedUser();
      final resolvedCompanyId = _resolveCompanyId(companyId, user);
      if (!user.isAdmin ||
          user.uid != CompanyCashOpeningBalanceModel.authorizedUid ||
          user.email.trim().toLowerCase() !=
              CompanyCashOpeningBalanceModel.authorizedEmail) {
        throw const FinancialRepositoryException(
          FinancialRepositoryError.permissionDenied,
        );
      }
      await _trustedCallableClient
          .callAuthenticated<Map<String, dynamic>>(
            'postCompanyCashOpeningBalance',
            {'companyId': resolvedCompanyId, 'amount': amount, 'note': note},
          )
          .timeout(const Duration(seconds: 30));
    });
  }

  Future<List<InvoiceModel>> _fetchRecentInvoices(
    String companyId,
    BusinessUserContext user, {
    required DateTime fromDate,
    required DateTime toDate,
  }) async {
    Query<Map<String, dynamic>> query = _invoices(companyId)
        .where(
          'invoiceDate',
          isGreaterThanOrEqualTo: Timestamp.fromDate(fromDate),
        )
        .where('invoiceDate', isLessThanOrEqualTo: Timestamp.fromDate(toDate));
    if (user.isSalesRep) {
      query = query.where('salesRepId', isEqualTo: user.uid);
    }
    final snapshot = await query
        .orderBy('invoiceDate', descending: true)
        .orderBy(FieldPath.documentId, descending: true)
        .limit(5)
        .get();
    return snapshot.docs
        .map(InvoiceModel.fromFirestore)
        .toList(growable: false);
  }

  Future<List<ReceiptModel>> _fetchRecentReceipts(
    String companyId,
    BusinessUserContext user, {
    required DateTime fromDate,
    required DateTime toDate,
  }) async {
    Query<Map<String, dynamic>> query = _receipts(companyId)
        .where(
          'receiptDate',
          isGreaterThanOrEqualTo: Timestamp.fromDate(fromDate),
        )
        .where('receiptDate', isLessThanOrEqualTo: Timestamp.fromDate(toDate));
    if (user.isSalesRep) {
      query = query.where('salesRepId', isEqualTo: user.uid);
    }
    final snapshot = await query
        .orderBy('receiptDate', descending: true)
        .orderBy(FieldPath.documentId, descending: true)
        .limit(5)
        .get();
    return snapshot.docs
        .map(ReceiptModel.fromFirestore)
        .toList(growable: false);
  }

  Future<List<FinancialCustomerBalance>> _fetchTopReceivableCustomers(
    String companyId,
    BusinessUserContext user,
  ) async {
    Query<Map<String, dynamic>> query = _customers(companyId)
        .where('active', isEqualTo: true)
        .where('currentBalance', isGreaterThan: 0);
    if (user.isSalesRep) {
      query = query.where('createdByUid', isEqualTo: user.uid);
    }
    final snapshot = await query
        .orderBy('currentBalance', descending: true)
        .orderBy(FieldPath.documentId)
        .limit(3)
        .get();
    return snapshot.docs
        .map(CustomerModel.fromFirestore)
        .map(
          (customer) => FinancialCustomerBalance(
            customer: customer,
            balance: _round(customer.currentBalance),
          ),
        )
        .toList(growable: false);
  }

  List<FinancialRepAmount> _repAmounts(Object? value) {
    if (value is! List) return const [];
    return value
        .whereType<Map>()
        .map((raw) {
          final map = raw.map((key, value) => MapEntry(key.toString(), value));
          return FinancialRepAmount(
            salesRepId: map['salesRepId']?.toString() ?? '',
            salesRepName: map['salesRepName']?.toString() ?? '',
            amount: _number(map['amount']),
          );
        })
        .toList(growable: false);
  }

  List<FinancialRepSalesSummary> _repSalesSummaries(Object? value) {
    if (value is! List) return const [];
    return value
        .whereType<Map>()
        .map((raw) {
          final map = raw.map((key, value) => MapEntry(key.toString(), value));
          return FinancialRepSalesSummary(
            salesRepId: map['salesRepId']?.toString() ?? '',
            salesRepName: map['salesRepName']?.toString() ?? '',
            totalSales: _number(map['totalSales']),
            cashSales: _number(map['cashSales']),
            creditSales: _number(map['creditSales']),
            partialSales: _number(map['partialSales']),
            receiptsCollected: _number(map['receiptsCollected']),
            cashInHand: _number(map['cashInHand']),
            invoiceCount: _integer(map['invoiceCount']),
          );
        })
        .toList(growable: false);
  }

  List<double> _numberList(Object? value) {
    if (value is! List) return const [0, 0, 0, 0, 0, 0, 0];
    final result = value.map(_number).toList(growable: false);
    return result.length == 7 ? result : const [0, 0, 0, 0, 0, 0, 0];
  }

  double _number(Object? value) {
    if (value is num && value.isFinite) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  int _integer(Object? value) {
    if (value is num && value.isFinite) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  Future<List<CustomerModel>> _fetchCustomers(
    String companyId,
    BusinessUserContext user,
  ) async {
    Query<Map<String, dynamic>> query = _customers(companyId);
    if (user.isSalesRep) {
      query = query.where('createdByUid', isEqualTo: user.uid);
    }
    final documents = await query.orderBy(FieldPath.documentId).getAllPages();
    final customers = documents
        .map(CustomerModel.fromFirestore)
        .toList(growable: false);
    return customers;
  }

  // Kept as an explicit full-export path; dashboards use bounded aggregates.
  // ignore: unused_element
  Future<List<InvoiceModel>> _fetchInvoices(
    String companyId,
    BusinessUserContext user, {
    DateTime? fromDate,
    DateTime? toDate,
  }) async {
    Query<Map<String, dynamic>> query = _invoices(companyId);
    if (user.isSalesRep) {
      query = query.where('salesRepId', isEqualTo: user.uid);
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
    final snapshot = await query
        .orderBy('invoiceDate', descending: true)
        .orderBy(FieldPath.documentId, descending: true)
        .getAllPages();
    final invoices = snapshot
        .map(InvoiceModel.fromFirestore)
        .toList(growable: false);
    return invoices;
  }

  // ignore: unused_element
  Future<List<ReceiptModel>> _fetchReceipts(
    String companyId,
    BusinessUserContext user, {
    DateTime? fromDate,
    DateTime? toDate,
  }) async {
    Query<Map<String, dynamic>> query = _receipts(companyId);
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
        .orderBy(FieldPath.documentId, descending: true)
        .getAllPages();
    final receipts = snapshot
        .map(ReceiptModel.fromFirestore)
        .toList(growable: false);
    return receipts;
  }

  // ignore: unused_element
  Future<List<SalesReturnModel>> _fetchSalesReturns(
    String companyId,
    BusinessUserContext user, {
    DateTime? fromDate,
    DateTime? toDate,
  }) async {
    Query<Map<String, dynamic>> query = _salesReturns(companyId);
    if (user.isSalesRep) {
      query = query.where('salesRepId', isEqualTo: user.uid);
    }
    if (fromDate != null) {
      query = query.where(
        'returnDate',
        isGreaterThanOrEqualTo: Timestamp.fromDate(_startOfDay(fromDate)),
      );
    }
    if (toDate != null) {
      query = query.where(
        'returnDate',
        isLessThanOrEqualTo: Timestamp.fromDate(_endOfDay(toDate)),
      );
    }
    final snapshot = await query
        .orderBy('returnDate', descending: true)
        .orderBy(FieldPath.documentId, descending: true)
        .getAllPages();
    return snapshot
        .map(SalesReturnModel.fromFirestore)
        .where(
          (salesReturn) =>
              salesReturn.isConfirmed && salesReturn.financialPosted,
        )
        .toList(growable: false);
  }

  // ignore: unused_element
  Future<Map<String, PaymentType>> _fetchOriginalInvoicePaymentTypes(
    String companyId,
    List<InvoiceModel> periodInvoices,
    List<SalesReturnModel> salesReturns,
  ) async {
    final paymentTypes = {
      for (final invoice in periodInvoices) invoice.id: invoice.paymentType,
    };
    final missingIds = salesReturns
        .map((salesReturn) => salesReturn.originalInvoiceId)
        .where((id) => id.isNotEmpty && !paymentTypes.containsKey(id))
        .toSet();
    final ids = missingIds.toList(growable: false);
    const maximumConcurrentQueries = 6;
    for (
      var windowStart = 0;
      windowStart < ids.length;
      windowStart += 30 * maximumConcurrentQueries
    ) {
      final windowEnd = math.min(
        windowStart + (30 * maximumConcurrentQueries),
        ids.length,
      );
      final queries = <Future<QuerySnapshot<Map<String, dynamic>>>>[];
      for (var start = windowStart; start < windowEnd; start += 30) {
        final chunk = ids.sublist(start, math.min(start + 30, windowEnd));
        queries.add(
          _invoices(companyId)
              .where(FieldPath.documentId, whereIn: chunk)
              .get()
              .timeout(const Duration(seconds: 20)),
        );
      }
      final snapshots = await Future.wait(queries);
      for (final snapshot in snapshots.expand((result) => result.docs)) {
        final invoice = InvoiceModel.fromFirestore(snapshot);
        paymentTypes[invoice.id] = invoice.paymentType;
      }
    }
    return paymentTypes;
  }

  Future<Map<String, _ProjectedReceivableBalance>>
  _fetchProjectedReceivableBalances(
    String companyId,
    List<String> customerIds,
    DateTime atExclusive,
  ) async {
    const batchSize = 100;
    const maximumConcurrentBatches = 4;
    final result = <String, _ProjectedReceivableBalance>{};
    for (
      var windowStart = 0;
      windowStart < customerIds.length;
      windowStart += batchSize * maximumConcurrentBatches
    ) {
      final windowEnd = math.min(
        windowStart + batchSize * maximumConcurrentBatches,
        customerIds.length,
      );
      final calls = <Future<HttpsCallableResult<Map<String, dynamic>>>>[];
      for (var start = windowStart; start < windowEnd; start += batchSize) {
        calls.add(
          _trustedCallableClient.callAuthenticated<Map<String, dynamic>>(
            'getReceivableBalances',
            {
              'companyId': companyId,
              'customerIds': customerIds.sublist(
                start,
                math.min(start + batchSize, windowEnd),
              ),
              'atExclusive': atExclusive.millisecondsSinceEpoch,
            },
          ),
        );
      }
      for (final response in await Future.wait(calls)) {
        final values = response.data['balances'];
        if (values is! List) continue;
        for (final raw in values.whereType<Map>()) {
          final customerId = raw['customerId']?.toString().trim() ?? '';
          if (customerId.isEmpty) continue;
          final lastActivityValue = raw['lastActivityAt'];
          result[customerId] = _ProjectedReceivableBalance(
            balance: _number(raw['balance']),
            lastActivityDate: lastActivityValue is num
                ? DateTime.fromMillisecondsSinceEpoch(lastActivityValue.toInt())
                : null,
          );
        }
      }
    }
    return result;
  }

  Future<List<CashMovementModel>> _fetchCashMovements(
    String companyId,
    BusinessUserContext user, {
    DateTime? fromDate,
    DateTime? toDate,
  }) async {
    Query<Map<String, dynamic>> query = _cashMovements(companyId);
    if (user.isSalesRep) {
      query = query
          .where('salesRepId', isEqualTo: user.uid)
          .where('cashAccount', isEqualTo: CashMovementModel.repCashAccount);
    }
    if (fromDate != null) {
      query = query.where(
        'date',
        isGreaterThanOrEqualTo: Timestamp.fromDate(_startOfDay(fromDate)),
      );
    }
    if (toDate != null) {
      query = query.where(
        'date',
        isLessThanOrEqualTo: Timestamp.fromDate(_endOfDay(toDate)),
      );
    }
    final snapshot = await query
        .orderBy('date', descending: true)
        .orderBy(FieldPath.documentId, descending: true)
        .getAllPages();
    final movements = snapshot
        .map(CashMovementModel.fromFirestore)
        .where((movement) {
          final afterFrom =
              fromDate == null ||
              !movement.date.isBefore(_startOfDay(fromDate));
          final beforeTo =
              toDate == null || !movement.date.isAfter(_endOfDay(toDate));
          return afterFrom && beforeTo;
        })
        .toList(growable: false);
    movements.sort((a, b) => b.date.compareTo(a.date));
    return movements;
  }

  Future<FirestorePage<CashMovementModel>> _fetchCashMovementsPage(
    String companyId,
    BusinessUserContext user, {
    DateTime? fromDate,
    DateTime? toDate,
    FirestorePageCursor? after,
    required int pageSize,
  }) async {
    Query<Map<String, dynamic>> query = _cashMovements(companyId);
    if (user.isSalesRep) {
      query = query
          .where('salesRepId', isEqualTo: user.uid)
          .where('cashAccount', isEqualTo: CashMovementModel.repCashAccount);
    }
    if (fromDate != null) {
      query = query.where(
        'date',
        isGreaterThanOrEqualTo: Timestamp.fromDate(fromDate),
      );
    }
    if (toDate != null) {
      query = query.where(
        'date',
        isLessThanOrEqualTo: Timestamp.fromDate(toDate),
      );
    }
    return query
        .orderBy('date', descending: true)
        .orderBy(FieldPath.documentId, descending: true)
        .getPage(
          decode: CashMovementModel.fromFirestore,
          after: after,
          pageSize: pageSize,
        );
  }

  Future<({double totalIn, double totalOut})> _fetchCashMovementTotals(
    String companyId,
    BusinessUserContext user, {
    DateTime? fromDate,
    DateTime? toDate,
  }) async {
    Query<Map<String, dynamic>> base = _cashMovements(companyId);
    if (user.isSalesRep) {
      base = base
          .where('salesRepId', isEqualTo: user.uid)
          .where('cashAccount', isEqualTo: CashMovementModel.repCashAccount);
    }
    if (fromDate != null) {
      base = base.where(
        'date',
        isGreaterThanOrEqualTo: Timestamp.fromDate(fromDate),
      );
    }
    if (toDate != null) {
      base = base.where(
        'date',
        isLessThanOrEqualTo: Timestamp.fromDate(toDate),
      );
    }
    final results = await Future.wait([
      base.where('direction', isEqualTo: 'in').aggregate(sum('amount')).get(),
      base.where('direction', isEqualTo: 'out').aggregate(sum('amount')).get(),
    ]);
    return (
      totalIn: _round(results[0].getSum('amount') ?? 0),
      totalOut: _round(results[1].getSum('amount') ?? 0),
    );
  }

  // ignore: unused_element
  Future<List<ExpenseModel>> _fetchExpenses(
    String companyId,
    BusinessUserContext user,
  ) async {
    Query<Map<String, dynamic>> query = _expenses(companyId);
    if (user.isSalesRep) {
      query = query.where('paidByUid', isEqualTo: user.uid);
    }
    final snapshot = await query
        .orderBy('expenseDate', descending: true)
        .orderBy(FieldPath.documentId, descending: true)
        .getAllPages();
    final expenses = snapshot
        .map(ExpenseModel.fromFirestore)
        .toList(growable: false);
    expenses.sort((a, b) => b.expenseDate.compareTo(a.expenseDate));
    return expenses;
  }

  List<FinancialCustomerBalance> _buildReceivableCustomers(
    List<CustomerModel> customers,
    Map<String, _ProjectedReceivableBalance> historicalBalances, {
    bool hasDateFilter = false,
  }) {
    final balances = customers
        .where((customer) {
          final balance = hasDateFilter
              ? historicalBalances[customer.id]?.balance ?? 0
              : customer.currentBalance;
          return customer.active && balance > 0;
        })
        .map(
          (customer) => FinancialCustomerBalance(
            customer: customer,
            balance: _round(
              hasDateFilter
                  ? historicalBalances[customer.id]?.balance ?? 0
                  : customer.currentBalance,
            ),
            lastTransactionDate:
                historicalBalances[customer.id]?.lastActivityDate,
          ),
        )
        .toList(growable: false);
    balances.sort((a, b) => b.balance.compareTo(a.balance));
    return balances;
  }

  // ignore: unused_element
  List<InvoiceModel> _recentInvoices(List<InvoiceModel> invoices) {
    final sorted = List<InvoiceModel>.of(invoices)
      ..sort((a, b) => b.invoiceDate.compareTo(a.invoiceDate));
    return sorted.take(5).toList(growable: false);
  }

  // ignore: unused_element
  List<ReceiptModel> _recentReceipts(List<ReceiptModel> receipts) {
    final sorted = List<ReceiptModel>.of(receipts)
      ..sort((a, b) => b.receiptDate.compareTo(a.receiptDate));
    return sorted.take(5).toList(growable: false);
  }

  // ignore: unused_element
  List<FinancialCustomerBalance> _topCustomers(
    List<FinancialCustomerBalance> customers,
  ) {
    return customers.take(3).toList(growable: false);
  }

  // ignore: unused_element
  List<FinancialRepAmount> _amountsByRepFromInvoices(
    List<InvoiceModel> invoices,
    List<SalesReturnModel> salesReturns,
  ) {
    final amounts = <String, double>{};
    final names = <String, String>{};
    for (final invoice in invoices) {
      if (invoice.salesRepId.isEmpty) continue;
      amounts[invoice.salesRepId] =
          (amounts[invoice.salesRepId] ?? 0) + invoice.grandTotal;
      names[invoice.salesRepId] = invoice.salesRepName;
    }
    for (final salesReturn in salesReturns) {
      if (salesReturn.salesRepId.isEmpty) continue;
      amounts[salesReturn.salesRepId] =
          (amounts[salesReturn.salesRepId] ?? 0) - salesReturn.grandTotal;
      names[salesReturn.salesRepId] = salesReturn.salesRepName;
    }
    final rows = amounts.entries
        .map(
          (entry) => FinancialRepAmount(
            salesRepId: entry.key,
            salesRepName: names[entry.key] ?? '',
            amount: _round(entry.value),
          ),
        )
        .toList(growable: false);
    rows.sort((a, b) => b.amount.compareTo(a.amount));
    return rows;
  }

  // ignore: unused_element
  List<FinancialRepSalesSummary> _salesSummaryByRep({
    required List<InvoiceModel> invoices,
    required List<ReceiptModel> receipts,
    required List<CashMovementModel> movements,
    required List<SalesReturnModel> salesReturns,
    required Map<String, PaymentType> originalInvoicePaymentTypes,
  }) {
    final rows = <String, _MutableRepSales>{};
    _MutableRepSales rowFor(String id, String name) {
      return rows.putIfAbsent(id, () => _MutableRepSales(id, name));
    }

    for (final salesReturn in salesReturns) {
      if (salesReturn.salesRepId.isEmpty) continue;
      final row = rowFor(salesReturn.salesRepId, salesReturn.salesRepName);
      row.totalSales -= salesReturn.grandTotal;
      switch (originalInvoicePaymentTypes[salesReturn.originalInvoiceId]) {
        case PaymentType.cash:
          row.cashSales -= salesReturn.grandTotal;
          break;
        case PaymentType.credit:
          row.creditSales -= salesReturn.grandTotal;
          break;
        case PaymentType.partial:
          row.partialSales -= salesReturn.grandTotal;
          break;
        case null:
          break;
      }
    }

    for (final invoice in invoices) {
      if (invoice.salesRepId.isEmpty) continue;
      final row = rowFor(invoice.salesRepId, invoice.salesRepName);
      row.totalSales += invoice.grandTotal;
      row.invoiceCount += 1;
      switch (invoice.paymentType) {
        case PaymentType.cash:
          row.cashSales += invoice.grandTotal;
          break;
        case PaymentType.credit:
          row.creditSales += invoice.grandTotal;
          break;
        case PaymentType.partial:
          row.partialSales += invoice.grandTotal;
          break;
      }
    }

    for (final receipt in receipts) {
      if (receipt.salesRepId.isEmpty) continue;
      rowFor(receipt.salesRepId, receipt.salesRepName).receiptsCollected +=
          receipt.amount;
    }

    for (final movement in movements) {
      if (movement.salesRepId.isEmpty) continue;
      final repCashEffect = CashLedgerCalculator.repCashOutstandingEffect(
        movement,
      );
      if (repCashEffect == 0) continue;
      rowFor(movement.salesRepId, movement.salesRepName).cashInHand +=
          repCashEffect;
    }

    final summaries = rows.values
        .map(
          (row) => FinancialRepSalesSummary(
            salesRepId: row.salesRepId,
            salesRepName: row.salesRepName,
            totalSales: _round(row.totalSales),
            cashSales: _round(row.cashSales),
            creditSales: _round(row.creditSales),
            partialSales: _round(row.partialSales),
            receiptsCollected: _round(row.receiptsCollected),
            cashInHand: _round(row.cashInHand),
            invoiceCount: row.invoiceCount,
          ),
        )
        .toList(growable: false);
    summaries.sort((a, b) => b.totalSales.compareTo(a.totalSales));
    return summaries;
  }

  // ignore: unused_element
  double _postedExpenseTotal(
    List<ExpenseModel> expenses, {
    DateTime? fromDate,
    DateTime? toDate,
  }) {
    return _round(
      expenses
          .where(
            (expense) =>
                expense.isPostedOrApproved &&
                (fromDate == null ||
                    !expense.expenseDate.isBefore(_startOfDay(fromDate))) &&
                (toDate == null ||
                    !expense.expenseDate.isAfter(_endOfDay(toDate))),
          )
          .fold<double>(0, (total, expense) => total + expense.amount),
    );
  }

  // ignore: unused_element
  List<double> _weeklyInvoiceValues(
    List<InvoiceModel> invoices,
    List<SalesReturnModel> salesReturns, {
    DateTime? throughDate,
  }) {
    final today = _dateOnly(DateTime.now());
    final requestedEnd = throughDate == null ? today : _dateOnly(throughDate);
    final chartEnd = requestedEnd.isAfter(today) ? today : requestedEnd;
    final start = chartEnd.subtract(const Duration(days: 6));
    final values = List<double>.filled(7, 0);
    for (final invoice in invoices) {
      final date = _dateOnly(invoice.invoiceDate);
      if (date.isBefore(start) || date.isAfter(chartEnd)) continue;
      final index = date.difference(start).inDays;
      values[index] = _round(values[index] + invoice.grandTotal);
    }
    for (final salesReturn in salesReturns) {
      final date = _dateOnly(salesReturn.returnDate);
      if (date.isBefore(start) || date.isAfter(chartEnd)) continue;
      final index = date.difference(start).inDays;
      values[index] = _round(values[index] - salesReturn.grandTotal);
    }
    return values;
  }

  String _resolveCompanyId(String requested, BusinessUserContext user) {
    final companyId = requested.trim().isEmpty
        ? AuthRepository.defaultCompanyId
        : requested.trim();
    if (companyId != user.companyId) {
      throw const FinancialRepositoryException(
        FinancialRepositoryError.permissionDenied,
      );
    }
    return companyId;
  }

  DateTime _dateOnly(DateTime date) =>
      DateTime(date.year, date.month, date.day);

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
    } on FinancialRepositoryException {
      rethrow;
    } on BusinessUserContextException catch (error) {
      throw FinancialRepositoryException(_mapContextError(error.error), error);
    } on TimeoutException catch (error) {
      throw FinancialRepositoryException(
        FinancialRepositoryError.timeout,
        error,
      );
    } on FirebaseException catch (error) {
      throw FinancialRepositoryException(_mapFirebaseError(error.code), error);
    } catch (error) {
      throw FinancialRepositoryException(
        FinancialRepositoryError.unknown,
        error,
      );
    }
  }

  FinancialRepositoryError _mapContextError(BusinessUserContextError error) {
    return switch (error) {
      BusinessUserContextError.unauthenticated ||
      BusinessUserContextError.profileMissing =>
        FinancialRepositoryError.unauthenticated,
      BusinessUserContextError.permissionDenied =>
        FinancialRepositoryError.permissionDenied,
      BusinessUserContextError.invalidProfile =>
        FinancialRepositoryError.invalidData,
      BusinessUserContextError.timeout => FinancialRepositoryError.timeout,
    };
  }

  FinancialRepositoryError _mapFirebaseError(String code) {
    return switch (code) {
      'permission-denied' => FinancialRepositoryError.permissionDenied,
      'unauthenticated' => FinancialRepositoryError.unauthenticated,
      'unavailable' ||
      'deadline-exceeded' => FinancialRepositoryError.unavailable,
      'invalid-argument' ||
      'failed-precondition' ||
      'data-loss' => FinancialRepositoryError.invalidData,
      'already-exists' => FinancialRepositoryError.alreadyExists,
      _ => FinancialRepositoryError.unknown,
    };
  }
}

class _ProjectedReceivableBalance {
  const _ProjectedReceivableBalance({
    required this.balance,
    required this.lastActivityDate,
  });

  final double balance;
  final DateTime? lastActivityDate;
}

class _MutableRepSales {
  _MutableRepSales(this.salesRepId, this.salesRepName);

  final String salesRepId;
  String salesRepName;
  double totalSales = 0;
  double cashSales = 0;
  double creditSales = 0;
  double partialSales = 0;
  double receiptsCollected = 0;
  double cashInHand = 0;
  int invoiceCount = 0;
}
