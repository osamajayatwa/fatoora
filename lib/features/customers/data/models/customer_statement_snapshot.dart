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
    final totalDebit = transactions.fold<double>(
      0,
      (sum, transaction) => sum + transaction.debitAmount,
    );
    final totalCredit = transactions.fold<double>(
      0,
      (sum, transaction) => sum + transaction.creditAmount,
    );
    return CustomerStatementSnapshot(
      transactions: List.unmodifiable(transactions),
      openingBalance: openingBalance,
      totalDebit: totalDebit,
      totalCredit: totalCredit,
      closingBalance: openingBalance + totalDebit - totalCredit,
    );
  }

  final List<CustomerTransactionModel> transactions;
  final double openingBalance;
  final double totalDebit;
  final double totalCredit;
  final double closingBalance;
}
