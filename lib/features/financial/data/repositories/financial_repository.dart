import 'dart:async';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fatoora/features/auth/data/repositories/auth_repository.dart';
import 'package:fatoora/features/customers/data/models/customer_model.dart';
import 'package:fatoora/features/customers/data/models/customer_transaction_model.dart';
import 'package:fatoora/features/financial/data/models/cash_movement_model.dart';
import 'package:fatoora/features/financial/data/models/financial_dashboard_snapshot.dart';
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

  Future<FinancialDashboardSnapshot> fetchDashboard({
    String companyId = AuthRepository.defaultCompanyId,
  }) {
    return _run(() async {
      final user = await _contextReader.requireApprovedUser();
      final resolvedCompanyId = _resolveCompanyId(companyId, user);
      final customers = await _fetchCustomers(resolvedCompanyId, user);
      final invoices = await _fetchInvoices(resolvedCompanyId, user);
      final receipts = await _fetchReceipts(resolvedCompanyId, user);
      final salesReturns = await _fetchSalesReturns(resolvedCompanyId, user);
      final cashMovements = await _fetchCashMovements(resolvedCompanyId, user);

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
      final cashInHand = _cashInHand(cashMovements);
      final invoiceById = {
        for (final invoice in financialInvoices) invoice.id: invoice,
      };
      double returnedFor(PaymentType type) => salesReturns
          .where(
            (salesReturn) =>
                invoiceById[salesReturn.originalInvoiceId]?.paymentType == type,
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
        cashInHand: cashInHand,
        invoiceCount: financialInvoices.length,
        customerCount: customers.where((customer) => customer.active).length,
        receiptCount: receipts.length,
        recentInvoices: _recentInvoices(invoices),
        recentReceipts: _recentReceipts(receipts),
        topCustomers: _topCustomers(receivableCustomers),
        cashBySalesRep: _amountsByRepFromMovements(cashMovements),
        salesByRep: _amountsByRepFromInvoices(financialInvoices, salesReturns),
        salesByRepSummary: _salesSummaryByRep(
          invoices: financialInvoices,
          receipts: receipts,
          movements: cashMovements,
          salesReturns: salesReturns,
        ),
        weeklyInvoiceValues: _weeklyInvoiceValues(
          financialInvoices,
          salesReturns,
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
        fromDate: fromDate,
        toDate: toDate,
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
      final movements = await _fetchCashMovements(
        resolvedCompanyId,
        user,
        fromDate: fromDate,
        toDate: toDate,
      );
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
        cashInHand: _round(totalIn - totalOut),
        totalIn: totalIn,
        totalOut: totalOut,
        cashBySalesRep: _amountsByRepFromMovements(movements),
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
      if (!user.isAdmin || salesRepId.trim().isEmpty || amount <= 0) {
        throw const FinancialRepositoryException(
          FinancialRepositoryError.permissionDenied,
        );
      }
      final document = _cashMovements(resolvedCompanyId).doc();
      final referenceNumber =
          'SET-${settlementDate.year}${settlementDate.month.toString().padLeft(2, '0')}${settlementDate.day.toString().padLeft(2, '0')}-${document.id.substring(0, math.min(6, document.id.length)).toUpperCase()}';
      await document
          .set({
            'id': document.id,
            'companyId': resolvedCompanyId,
            'salesRepId': salesRepId.trim(),
            'salesRepName': salesRepName.trim(),
            'type': 'settlement_to_admin',
            'movementType': 'settlement_to_admin',
            'direction': 'out',
            'amount': _round(amount),
            'referenceId': document.id,
            'referenceNumber': referenceNumber,
            'sourceCollection': 'cash_movements',
            'sourceId': document.id,
            'sourceNumber': referenceNumber,
            'customerId': '',
            'customerName': '',
            'date': Timestamp.fromDate(settlementDate),
            'movementDate': Timestamp.fromDate(settlementDate),
            'notes': notes.trim(),
            'createdByUid': user.uid,
            'createdByName': user.name,
            'createdByRole': user.role,
            'createdAt': FieldValue.serverTimestamp(),
          })
          .timeout(const Duration(seconds: 20));
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
    final snapshot = await query
        .limit(700)
        .get()
        .timeout(const Duration(seconds: 20));
    final customers = snapshot.docs
        .map(CustomerModel.fromFirestore)
        .toList(growable: false);
    return customers;
  }

  Future<List<InvoiceModel>> _fetchInvoices(
    String companyId,
    BusinessUserContext user,
  ) async {
    Query<Map<String, dynamic>> query = _invoices(companyId);
    if (user.isSalesRep) {
      query = query.where('salesRepId', isEqualTo: user.uid);
    }
    final snapshot = await query
        .limit(700)
        .get()
        .timeout(const Duration(seconds: 20));
    final invoices = snapshot.docs
        .map(InvoiceModel.fromFirestore)
        .toList(growable: false);
    return invoices;
  }

  Future<List<ReceiptModel>> _fetchReceipts(
    String companyId,
    BusinessUserContext user,
  ) async {
    Query<Map<String, dynamic>> query = _receipts(companyId);
    if (user.isSalesRep) {
      query = query.where('salesRepId', isEqualTo: user.uid);
    }
    final snapshot = await query
        .limit(700)
        .get()
        .timeout(const Duration(seconds: 20));
    final receipts = snapshot.docs
        .map(ReceiptModel.fromFirestore)
        .toList(growable: false);
    return receipts;
  }

  Future<List<SalesReturnModel>> _fetchSalesReturns(
    String companyId,
    BusinessUserContext user,
  ) async {
    Query<Map<String, dynamic>> query = _salesReturns(companyId);
    if (user.isSalesRep) {
      query = query.where('salesRepId', isEqualTo: user.uid);
    }
    final snapshot = await query
        .limit(700)
        .get()
        .timeout(const Duration(seconds: 20));
    return snapshot.docs
        .map(SalesReturnModel.fromFirestore)
        .where(
          (salesReturn) =>
              salesReturn.isConfirmed && salesReturn.financialPosted,
        )
        .toList(growable: false);
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
        .limit(900)
        .get()
        .timeout(const Duration(seconds: 20));
    final transactions = snapshot.docs
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
      query = query.where('salesRepId', isEqualTo: user.uid);
    }
    final snapshot = await query
        .limit(900)
        .get()
        .timeout(const Duration(seconds: 20));
    final movements = snapshot.docs
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

  List<FinancialCustomerBalance> _buildReceivableCustomers(
    List<CustomerModel> customers,
    List<CustomerTransactionModel> transactions, {
    bool hasDateFilter = false,
  }) {
    final lastTransactionByCustomer = <String, DateTime>{};
    for (final transaction in transactions) {
      final existing = lastTransactionByCustomer[transaction.customerId];
      if (existing == null || transaction.transactionDate.isAfter(existing)) {
        lastTransactionByCustomer[transaction.customerId] =
            transaction.transactionDate;
      }
    }
    final balances = customers
        .where((customer) => customer.active && customer.currentBalance > 0)
        .map(
          (customer) => FinancialCustomerBalance(
            customer: customer,
            balance: _round(customer.currentBalance),
            lastTransactionDate: lastTransactionByCustomer[customer.id],
          ),
        )
        .where((item) => !hasDateFilter || item.lastTransactionDate != null)
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

  List<FinancialRepAmount> _amountsByRepFromMovements(
    List<CashMovementModel> movements,
  ) {
    final amounts = <String, double>{};
    final names = <String, String>{};
    for (final movement in movements) {
      if (movement.salesRepId.isEmpty) continue;
      amounts[movement.salesRepId] =
          (amounts[movement.salesRepId] ?? 0) + movement.signedAmount;
      names[movement.salesRepId] = movement.salesRepName;
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
  }) {
    final rows = <String, _MutableRepSales>{};
    _MutableRepSales rowFor(String id, String name) {
      return rows.putIfAbsent(id, () => _MutableRepSales(id, name));
    }

    final invoiceById = {for (final invoice in invoices) invoice.id: invoice};
    for (final salesReturn in salesReturns) {
      if (salesReturn.salesRepId.isEmpty) continue;
      final row = rowFor(salesReturn.salesRepId, salesReturn.salesRepName);
      row.totalSales -= salesReturn.grandTotal;
      switch (invoiceById[salesReturn.originalInvoiceId]?.paymentType) {
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
      rowFor(movement.salesRepId, movement.salesRepName).cashInHand +=
          movement.signedAmount;
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

  List<double> _weeklyInvoiceValues(
    List<InvoiceModel> invoices,
    List<SalesReturnModel> salesReturns,
  ) {
    final today = _dateOnly(DateTime.now());
    final start = today.subtract(const Duration(days: 6));
    final values = List<double>.filled(7, 0);
    for (final invoice in invoices) {
      final date = _dateOnly(invoice.invoiceDate);
      if (date.isBefore(start) || date.isAfter(today)) continue;
      final index = date.difference(start).inDays;
      values[index] = _round(values[index] + invoice.grandTotal);
    }
    for (final salesReturn in salesReturns) {
      final date = _dateOnly(salesReturn.returnDate);
      if (date.isBefore(start) || date.isAfter(today)) continue;
      final index = date.difference(start).inDays;
      values[index] = _round(values[index] - salesReturn.grandTotal);
    }
    return values;
  }

  double _cashInHand(List<CashMovementModel> movements) {
    return _round(
      movements.fold<double>(
        0,
        (total, movement) => total + movement.signedAmount,
      ),
    );
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
      'failed-precondition' => FinancialRepositoryError.invalidData,
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
