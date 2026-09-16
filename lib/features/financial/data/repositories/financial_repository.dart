import 'dart:async';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:fatoora/core/data/firestore_query_pager.dart';
import 'package:fatoora/core/firebase/trusted_callable_client.dart';
import 'package:fatoora/features/auth/data/repositories/auth_repository.dart';
import 'package:fatoora/features/customers/data/models/customer_model.dart';
import 'package:fatoora/features/customers/data/models/customer_transaction_model.dart';
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
      final results = await Future.wait<Object>([
        _fetchCustomers(resolvedCompanyId, user),
        _fetchInvoices(
          resolvedCompanyId,
          user,
          fromDate: fromDate,
          toDate: toDate,
        ),
        _fetchReceipts(
          resolvedCompanyId,
          user,
          fromDate: fromDate,
          toDate: toDate,
        ),
        _fetchSalesReturns(
          resolvedCompanyId,
          user,
          fromDate: fromDate,
          toDate: toDate,
        ),
        _fetchCashMovements(resolvedCompanyId, user),
        _fetchExpenses(resolvedCompanyId, user),
      ]);
      final customers = results[0] as List<CustomerModel>;
      final invoices = results[1] as List<InvoiceModel>;
      final receipts = results[2] as List<ReceiptModel>;
      final salesReturns = results[3] as List<SalesReturnModel>;
      final cashMovements = results[4] as List<CashMovementModel>;
      final expenses = results[5] as List<ExpenseModel>;
      final originalInvoicePaymentTypes =
          await _fetchOriginalInvoicePaymentTypes(
            resolvedCompanyId,
            invoices,
            salesReturns,
          );
      final cashLedger = CashLedgerCalculator.calculate(cashMovements);
      final companyCash = user.isAdmin ? cashLedger.companyCash : 0.0;
      final repCashOutstanding = cashLedger.repCashOutstanding;
      final totalExpenses = _postedExpenseTotal(
        expenses,
        fromDate: fromDate,
        toDate: toDate,
      );
      final pendingExpenseCount = expenses
          .where((expense) => expense.status == ExpenseStatus.pending)
          .length;
      final reimbursementsPayable = _round(
        expenses
            .where(
              (expense) =>
                  expense.reimbursementStatus ==
                  ExpenseReimbursementStatus.payable,
            )
            .fold<double>(0, (total, expense) => total + expense.amount),
      );

      final financialInvoices = invoices
          .where((invoice) => invoice.financialPosted && invoice.isFinancial)
          .toList(growable: false);
      final receivableCustomers = _buildReceivableCustomers(
        customers,
        const [],
      );
      final totalReceivables = _round(
        receivableCustomers.fold<double>(
          0,
          (total, item) => total + item.balance,
        ),
      );
      final effectiveCash = user.isAdmin ? companyCash : repCashOutstanding;
      double returnedFor(PaymentType type) => salesReturns
          .where(
            (salesReturn) =>
                originalInvoicePaymentTypes[salesReturn.originalInvoiceId] ==
                type,
          )
          .fold<double>(
            0,
            (total, salesReturn) => total + salesReturn.grandTotal,
          );
      final returnedTotal = salesReturns.fold<double>(
        0,
        (total, salesReturn) => total + salesReturn.grandTotal,
      );

      return FinancialDashboardSnapshot(
        totalSales: _round(
          financialInvoices.fold<double>(
                0,
                (total, invoice) => total + invoice.grandTotal,
              ) -
              returnedTotal,
        ),
        cashSales: _round(
          financialInvoices
                  .where((invoice) => invoice.paymentType == PaymentType.cash)
                  .fold<double>(
                    0,
                    (total, invoice) => total + invoice.grandTotal,
                  ) -
              returnedFor(PaymentType.cash),
        ),
        creditSales: _round(
          financialInvoices
                  .where((invoice) => invoice.paymentType == PaymentType.credit)
                  .fold<double>(
                    0,
                    (total, invoice) => total + invoice.grandTotal,
                  ) -
              returnedFor(PaymentType.credit),
        ),
        partialSales: _round(
          financialInvoices
                  .where(
                    (invoice) => invoice.paymentType == PaymentType.partial,
                  )
                  .fold<double>(
                    0,
                    (total, invoice) => total + invoice.grandTotal,
                  ) -
              returnedFor(PaymentType.partial),
        ),
        totalReceivables: totalReceivables,
        cashInHand: _round(effectiveCash),
        companyCash: _round(companyCash),
        repCashOutstanding: _round(repCashOutstanding),
        totalExpenses: totalExpenses,
        pendingExpenseCount: pendingExpenseCount,
        reimbursementsPayable: reimbursementsPayable,
        invoiceCount: financialInvoices.length,
        customerCount: customers.where((customer) => customer.active).length,
        receiptCount: receipts.length,
        recentInvoices: _recentInvoices(invoices),
        recentReceipts: _recentReceipts(receipts),
        topCustomers: _topCustomers(receivableCustomers),
        cashBySalesRep: cashLedger.repCashOutstandingBySalesRep,
        repCashOutstandingBySalesRep: cashLedger.repCashOutstandingBySalesRep,
        salesByRep: _amountsByRepFromInvoices(financialInvoices, salesReturns),
        salesByRepSummary: _salesSummaryByRep(
          invoices: financialInvoices,
          receipts: receipts,
          movements: cashMovements,
          salesReturns: salesReturns,
          originalInvoicePaymentTypes: originalInvoicePaymentTypes,
        ),
        weeklyInvoiceValues: _weeklyInvoiceValues(
          financialInvoices,
          salesReturns,
          throughDate: toDate,
        ),
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
      final transactions = await _fetchTransactions(
        resolvedCompanyId,
        user,
        toDate: toDate ?? fromDate,
      );
      final receivableCustomers = _buildReceivableCustomers(
        customers,
        transactions,
        hasDateFilter: fromDate != null || toDate != null,
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

  Future<FinancialCashSnapshot> fetchCash({
    String companyId = AuthRepository.defaultCompanyId,
    DateTime? fromDate,
    DateTime? toDate,
  }) {
    return _run(() async {
      final user = await _contextReader.requireApprovedUser();
      final resolvedCompanyId = _resolveCompanyId(companyId, user);
      final allMovements = await _fetchCashMovements(resolvedCompanyId, user);
      final periodStart = fromDate == null ? null : _startOfDay(fromDate);
      final periodEnd = toDate == null ? null : _endOfDay(toDate);
      final openingMovements = periodStart == null
          ? const <CashMovementModel>[]
          : allMovements
                .where((movement) => movement.date.isBefore(periodStart))
                .toList(growable: false);
      final movements = allMovements
          .where((movement) {
            return (periodStart == null ||
                    !movement.date.isBefore(periodStart)) &&
                (periodEnd == null || !movement.date.isAfter(periodEnd));
          })
          .toList(growable: false);
      final closingMovements = allMovements
          .where((movement) {
            return periodEnd == null || !movement.date.isAfter(periodEnd);
          })
          .toList(growable: false);
      final openingLedger = CashLedgerCalculator.calculate(openingMovements);
      final cashLedger = CashLedgerCalculator.calculate(closingMovements);
      final companyCash = user.isAdmin ? cashLedger.companyCash : 0.0;
      final repCashOutstanding = cashLedger.repCashOutstanding;
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
        openingBalance: _round(
          user.isAdmin
              ? openingLedger.companyCash
              : openingLedger.repCashOutstanding,
        ),
        closingBalance: _round(user.isAdmin ? companyCash : repCashOutstanding),
        cashInHand: _round(user.isAdmin ? companyCash : repCashOutstanding),
        companyCash: _round(companyCash),
        repCashOutstanding: _round(repCashOutstanding),
        totalIn: totalIn,
        totalOut: totalOut,
        cashBySalesRep: cashLedger.repCashOutstandingBySalesRep,
        repCashOutstandingBySalesRep: cashLedger.repCashOutstandingBySalesRep,
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

  Future<List<CustomerTransactionModel>> _fetchTransactions(
    String companyId,
    BusinessUserContext user, {
    DateTime? fromDate,
    DateTime? toDate,
  }) async {
    Query<Map<String, dynamic>> query = _transactions(companyId);
    if (user.isSalesRep) {
      query = query.where('salesRepId', isEqualTo: user.uid);
    }
    if (fromDate != null) {
      query = query.where(
        'transactionDate',
        isGreaterThanOrEqualTo: Timestamp.fromDate(_startOfDay(fromDate)),
      );
    }
    if (toDate != null) {
      query = query.where(
        'transactionDate',
        isLessThanOrEqualTo: Timestamp.fromDate(_endOfDay(toDate)),
      );
    }
    final snapshot = await query
        .orderBy('transactionDate', descending: true)
        .orderBy(FieldPath.documentId, descending: true)
        .getAllPages();
    final transactions = snapshot
        .map(CustomerTransactionModel.fromFirestore)
        .toList(growable: false);
    transactions.sort((a, b) => b.transactionDate.compareTo(a.transactionDate));
    return transactions;
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
    List<CustomerTransactionModel> transactions, {
    bool hasDateFilter = false,
  }) {
    final lastTransactionByCustomer = <String, DateTime>{};
    final historicalBalances = <String, double>{};
    for (final transaction in transactions) {
      final existing = lastTransactionByCustomer[transaction.customerId];
      if (existing == null || transaction.transactionDate.isAfter(existing)) {
        lastTransactionByCustomer[transaction.customerId] =
            transaction.transactionDate;
      }
      historicalBalances[transaction.customerId] = _round(
        (historicalBalances[transaction.customerId] ?? 0) +
            transaction.debitAmount -
            transaction.creditAmount,
      );
    }
    final balances = customers
        .where((customer) {
          final balance = hasDateFilter
              ? historicalBalances[customer.id] ?? 0
              : customer.currentBalance;
          return customer.active && balance > 0;
        })
        .map(
          (customer) => FinancialCustomerBalance(
            customer: customer,
            balance: _round(
              hasDateFilter
                  ? historicalBalances[customer.id] ?? 0
                  : customer.currentBalance,
            ),
            lastTransactionDate: lastTransactionByCustomer[customer.id],
          ),
        )
        .toList(growable: false);
    balances.sort((a, b) => b.balance.compareTo(a.balance));
    return balances;
  }

  List<InvoiceModel> _recentInvoices(List<InvoiceModel> invoices) {
    final sorted = List<InvoiceModel>.of(invoices)
      ..sort((a, b) => b.invoiceDate.compareTo(a.invoiceDate));
    return sorted.take(5).toList(growable: false);
  }

  List<ReceiptModel> _recentReceipts(List<ReceiptModel> receipts) {
    final sorted = List<ReceiptModel>.of(receipts)
      ..sort((a, b) => b.receiptDate.compareTo(a.receiptDate));
    return sorted.take(5).toList(growable: false);
  }

  List<FinancialCustomerBalance> _topCustomers(
    List<FinancialCustomerBalance> customers,
  ) {
    return customers.take(3).toList(growable: false);
  }

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
