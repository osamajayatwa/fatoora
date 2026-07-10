import 'package:fatoora/features/customers/data/models/customer_model.dart';
import 'package:fatoora/features/financial/data/models/cash_movement_model.dart';
import 'package:fatoora/features/invoices/data/models/invoice_model.dart';
import 'package:fatoora/features/receipts/data/models/receipt_model.dart';

class FinancialDashboardSnapshot {
  const FinancialDashboardSnapshot({
    required this.totalSales,
    required this.cashSales,
    required this.creditSales,
    required this.partialSales,
    required this.totalReceivables,
    required this.cashInHand,
    this.companyCash = 0,
    this.repCashOutstanding = 0,
    this.totalExpenses = 0,
    this.pendingExpenseCount = 0,
    this.reimbursementsPayable = 0,
    required this.invoiceCount,
    required this.customerCount,
    required this.receiptCount,
    required this.recentInvoices,
    required this.recentReceipts,
    required this.topCustomers,
    required this.cashBySalesRep,
    this.repCashOutstandingBySalesRep = const [],
    required this.salesByRep,
    required this.salesByRepSummary,
    required this.weeklyInvoiceValues,
  });

  const FinancialDashboardSnapshot.empty()
    : totalSales = 0,
      cashSales = 0,
      creditSales = 0,
      partialSales = 0,
      totalReceivables = 0,
      cashInHand = 0,
      companyCash = 0,
      repCashOutstanding = 0,
      totalExpenses = 0,
      pendingExpenseCount = 0,
      reimbursementsPayable = 0,
      invoiceCount = 0,
      customerCount = 0,
      receiptCount = 0,
      recentInvoices = const [],
      recentReceipts = const [],
      topCustomers = const [],
      cashBySalesRep = const [],
      repCashOutstandingBySalesRep = const [],
      salesByRep = const [],
      salesByRepSummary = const [],
      weeklyInvoiceValues = const [0, 0, 0, 0, 0, 0, 0];

  final double totalSales;
  final double cashSales;
  final double creditSales;
  final double partialSales;
  final double totalReceivables;

  /// Backward-compatible effective cash value.
  ///
  /// New UI should prefer [companyCash] for admin/company cash and
  /// [repCashOutstanding] for sales-rep-held unsettled cash.
  final double cashInHand;
  final double companyCash;
  final double repCashOutstanding;
  final double totalExpenses;
  final int pendingExpenseCount;
  final double reimbursementsPayable;
  final int invoiceCount;
  final int customerCount;
  final int receiptCount;
  final List<InvoiceModel> recentInvoices;
  final List<ReceiptModel> recentReceipts;
  final List<FinancialCustomerBalance> topCustomers;

  /// Backward-compatible alias for [repCashOutstandingBySalesRep].
  final List<FinancialRepAmount> cashBySalesRep;
  final List<FinancialRepAmount> repCashOutstandingBySalesRep;
  final List<FinancialRepAmount> salesByRep;
  final List<FinancialRepSalesSummary> salesByRepSummary;
  final List<double> weeklyInvoiceValues;
}

class FinancialCustomerBalance {
  const FinancialCustomerBalance({
    required this.customer,
    required this.balance,
    this.lastTransactionDate,
  });

  final CustomerModel customer;
  final double balance;
  final DateTime? lastTransactionDate;
}

class FinancialRepAmount {
  const FinancialRepAmount({
    required this.salesRepId,
    required this.salesRepName,
    required this.amount,
  });

  final String salesRepId;
  final String salesRepName;
  final double amount;
}

class FinancialRepSalesSummary {
  const FinancialRepSalesSummary({
    required this.salesRepId,
    required this.salesRepName,
    required this.totalSales,
    required this.cashSales,
    required this.creditSales,
    required this.partialSales,
    required this.receiptsCollected,
    required this.cashInHand,
    required this.invoiceCount,
  });

  final String salesRepId;
  final String salesRepName;
  final double totalSales;
  final double cashSales;
  final double creditSales;
  final double partialSales;
  final double receiptsCollected;
  final double cashInHand;
  final int invoiceCount;
}

class FinancialReceivablesSnapshot {
  const FinancialReceivablesSnapshot({
    required this.customers,
    required this.totalReceivables,
  });

  final List<FinancialCustomerBalance> customers;
  final double totalReceivables;
}

class FinancialCashSnapshot {
  const FinancialCashSnapshot({
    required this.movements,
    required this.cashInHand,
    this.companyCash = 0,
    this.repCashOutstanding = 0,
    required this.totalIn,
    required this.totalOut,
    required this.cashBySalesRep,
    this.repCashOutstandingBySalesRep = const [],
  });

  final List<CashMovementModel> movements;

  /// Backward-compatible effective cash value.
  ///
  /// Admin views should use [companyCash]. Sales-rep views should use
  /// [repCashOutstanding].
  final double cashInHand;
  final double companyCash;
  final double repCashOutstanding;
  final double totalIn;
  final double totalOut;

  /// Backward-compatible alias for [repCashOutstandingBySalesRep].
  final List<FinancialRepAmount> cashBySalesRep;
  final List<FinancialRepAmount> repCashOutstandingBySalesRep;
}
