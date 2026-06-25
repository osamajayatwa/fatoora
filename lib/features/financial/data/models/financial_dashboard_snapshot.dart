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
    required this.invoiceCount,
    required this.customerCount,
    required this.receiptCount,
    required this.recentInvoices,
    required this.recentReceipts,
    required this.topCustomers,
    required this.cashBySalesRep,
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
      invoiceCount = 0,
      customerCount = 0,
      receiptCount = 0,
      recentInvoices = const [],
      recentReceipts = const [],
      topCustomers = const [],
      cashBySalesRep = const [],
      salesByRep = const [],
      salesByRepSummary = const [],
      weeklyInvoiceValues = const [0, 0, 0, 0, 0, 0, 0];

  final double totalSales;
  final double cashSales;
  final double creditSales;
  final double partialSales;
  final double totalReceivables;
  final double cashInHand;
  final int invoiceCount;
  final int customerCount;
  final int receiptCount;
  final List<InvoiceModel> recentInvoices;
  final List<ReceiptModel> recentReceipts;
  final List<FinancialCustomerBalance> topCustomers;
  final List<FinancialRepAmount> cashBySalesRep;
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
    required this.totalIn,
    required this.totalOut,
    required this.cashBySalesRep,
  });

  final List<CashMovementModel> movements;
  final double cashInHand;
  final double totalIn;
  final double totalOut;
  final List<FinancialRepAmount> cashBySalesRep;
}
