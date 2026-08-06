import 'package:fatoora/features/customers/data/models/customer_transaction_model.dart';

class CustomerStatementSnapshot {
  const CustomerStatementSnapshot({
    required this.transactions,
    required this.openingBalance,
    required this.totalDebit,
    required this.totalCredit,
    required this.closingBalance,
  });

  factory CustomerStatementSnapshot.fromTransactions({
    required List<CustomerTransactionModel> transactions,
    required double openingBalance,
  }) {
    var runningBalance = _round(openingBalance);
    final normalizedTransactions = transactions
        .map((transaction) {
          runningBalance = _round(
            runningBalance + transaction.debitAmount - transaction.creditAmount,
          );
          return transaction.copyWith(balanceAfter: runningBalance);
        })
        .toList(growable: false);
    final totalDebit = _round(
      transactions.fold<double>(
        0,
        (sum, transaction) => sum + transaction.debitAmount,
      ),
    );
    final totalCredit = _round(
      transactions.fold<double>(
        0,
        (sum, transaction) => sum + transaction.creditAmount,
      ),
    );
    return CustomerStatementSnapshot(
      transactions: List.unmodifiable(normalizedTransactions),
      openingBalance: _round(openingBalance),
      totalDebit: totalDebit,
      totalCredit: totalCredit,
      closingBalance: runningBalance,
    );
  }

  final List<CustomerTransactionModel> transactions;
  final double openingBalance;
  final double totalDebit;
  final double totalCredit;
  final double closingBalance;

  static double _round(double value) {
    if (!value.isFinite) return 0;
    return (value * 1000).roundToDouble() / 1000;
  }
}
