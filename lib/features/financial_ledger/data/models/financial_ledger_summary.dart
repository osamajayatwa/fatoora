class FinancialLedgerSummary {
  const FinancialLedgerSummary({
    this.entryCount = 0,
    this.sales = 0,
    this.cashSales = 0,
    this.creditSales = 0,
    this.receipts = 0,
    this.expenses = 0,
    this.returns = 0,
    this.settlements = 0,
    this.receivables = 0,
    this.companyCashNet = 0,
    this.repCashIn = 0,
    this.repCashOut = 0,
  });

  final int entryCount;
  final double sales;
  final double cashSales;
  final double creditSales;
  final double receipts;
  final double expenses;
  final double returns;
  final double settlements;
  final double receivables;
  final double companyCashNet;
  final double repCashIn;
  final double repCashOut;
}
