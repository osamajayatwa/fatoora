import 'package:fatoora/features/customers/data/models/customer_statement_snapshot.dart';
import 'package:fatoora/features/customers/data/models/customer_transaction_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('statement summary includes opening balance and period movements', () {
    final snapshot = CustomerStatementSnapshot.fromTransactions(
      openingBalance: 25,
      transactions: [
        _transaction(id: 'invoice', debit: 100, balanceAfter: 125),
        _transaction(id: 'receipt', credit: 40, balanceAfter: 85),
      ],
    );

    expect(snapshot.openingBalance, 25);
    expect(snapshot.totalDebit, 100);
    expect(snapshot.totalCredit, 40);
    expect(snapshot.closingBalance, 85);
    expect(snapshot.transactions[0].balanceAfter, 125);
    expect(snapshot.transactions[1].balanceAfter, 85);
  });

  test(
    'statement replaces stale stored balances with chronological balances',
    () {
      final snapshot = CustomerStatementSnapshot.fromTransactions(
        openingBalance: 1500,
        transactions: [
          _transaction(id: 'invoice', debit: 100, balanceAfter: 100),
          _transaction(id: 'receipt', credit: 40, balanceAfter: 60),
        ],
      );

      expect(snapshot.transactions[0].balanceAfter, 1600);
      expect(snapshot.transactions[1].balanceAfter, 1560);
      expect(snapshot.closingBalance, 1560);
    },
  );

  test('empty statement period keeps the opening balance', () {
    final snapshot = CustomerStatementSnapshot.fromTransactions(
      openingBalance: 17.5,
      transactions: const [],
    );

    expect(snapshot.totalDebit, 0);
    expect(snapshot.totalCredit, 0);
    expect(snapshot.closingBalance, 17.5);
  });
}

CustomerTransactionModel _transaction({
  required String id,
  double debit = 0,
  double credit = 0,
  required double balanceAfter,
}) {
  final now = DateTime(2026, 6, 29);
  return CustomerTransactionModel(
    id: id,
    companyId: 'default_company',
    customerId: 'customer-1',
    customerName: 'Customer',
    transactionType: debit > 0 ? 'invoice' : 'receipt',
    sourceCollection: debit > 0 ? 'invoices' : 'receipts',
    sourceId: id,
    sourceNumber: id,
    transactionDate: now,
    debitAmount: debit,
    creditAmount: credit,
    balanceAfter: balanceAfter,
    notes: '',
    createdByUid: 'rep-1',
    createdByName: 'Sales Rep',
    createdByRole: 'sales_rep',
    salesRepId: 'rep-1',
    salesRepName: 'Sales Rep',
    createdAt: now,
  );
}
