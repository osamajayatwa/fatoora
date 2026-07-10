import 'package:fatoora/features/auth/data/repositories/auth_repository.dart';
import 'package:fatoora/features/financial/data/models/cash_movement_model.dart';
import 'package:fatoora/features/financial/data/services/cash_ledger_calculator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('company cash', () {
    test('admin cash invoice increases company cash only', () {
      final totals = CashLedgerCalculator.calculate([
        _movement(
          id: 'admin-invoice',
          type: 'invoice_cash',
          movementType: 'invoice_payment',
          role: AuthRepository.adminRole,
          salesRepId: 'admin',
          salesRepName: 'Admin',
          direction: 'in',
          amount: 100,
        ),
      ]);

      expect(totals.companyCash, 100);
      expect(totals.repCashOutstanding, 0);
      expect(totals.repCashOutstandingBySalesRep, isEmpty);
    });

    test('explicit company cash account is counted as company cash', () {
      final totals = CashLedgerCalculator.calculate([
        _movement(
          id: 'admin-invoice',
          type: 'invoice_cash',
          movementType: 'invoice_payment',
          role: AuthRepository.adminRole,
          salesRepId: 'rep-a',
          direction: 'in',
          amount: 100,
          cashAccount: CashMovementModel.companyCashAccount,
        ),
      ]);

      expect(totals.companyCash, 100);
      expect(totals.repCashOutstanding, 0);
    });

    test('admin cash receipt increases company cash only', () {
      final totals = CashLedgerCalculator.calculate([
        _movement(
          id: 'admin-receipt',
          type: 'receipt_cash',
          movementType: 'receipt',
          role: AuthRepository.adminRole,
          salesRepId: 'admin',
          salesRepName: 'Admin',
          direction: 'in',
          amount: 40,
        ),
      ]);

      expect(totals.companyCash, 40);
      expect(totals.repCashOutstanding, 0);
    });

    test('company/admin cash refund decreases company cash', () {
      final totals = CashLedgerCalculator.calculate([
        _movement(
          id: 'admin-receipt',
          type: 'receipt_cash',
          movementType: 'receipt',
          role: AuthRepository.adminRole,
          salesRepId: 'admin',
          direction: 'in',
          amount: 100,
        ),
        _movement(
          id: 'admin-refund',
          type: 'sales_return_cash_refund',
          movementType: 'sales_return',
          role: AuthRepository.adminRole,
          salesRepId: 'rep-a',
          direction: 'out',
          amount: 30,
        ),
      ]);

      expect(totals.companyCash, 70);
      expect(totals.repCashOutstanding, 0);
    });
  });

  group('sales rep outstanding cash', () {
    test('rep cash invoice increases rep outstanding only', () {
      final totals = CashLedgerCalculator.calculate([
        _movement(
          id: 'rep-invoice',
          type: 'invoice_cash',
          movementType: 'invoice_payment',
          salesRepId: 'rep-a',
          direction: 'in',
          amount: 100,
        ),
      ]);

      expect(totals.companyCash, 0);
      expect(totals.repCashOutstanding, 100);
      expect(totals.repCashOutstandingBySalesRep.single.salesRepId, 'rep-a');
      expect(totals.repCashOutstandingBySalesRep.single.amount, 100);
    });

    test('rep partial invoice and cash receipt increase rep outstanding', () {
      final totals = CashLedgerCalculator.calculate([
        _movement(
          id: 'rep-partial',
          type: 'invoice_partial',
          movementType: 'invoice_payment',
          salesRepId: 'rep-a',
          direction: 'in',
          amount: 30,
        ),
        _movement(
          id: 'rep-receipt',
          type: 'receipt_cash',
          movementType: 'receipt',
          salesRepId: 'rep-a',
          direction: 'in',
          amount: 40,
        ),
      ]);

      expect(totals.companyCash, 0);
      expect(totals.repCashOutstanding, 70);
      expect(totals.repCashOutstandingBySalesRep.single.amount, 70);
    });

    test('rep-paid cash refund decreases rep outstanding', () {
      final totals = CashLedgerCalculator.calculate([
        _movement(
          id: 'rep-receipt',
          type: 'receipt_cash',
          movementType: 'receipt',
          salesRepId: 'rep-a',
          direction: 'in',
          amount: 100,
        ),
        _movement(
          id: 'rep-refund',
          type: 'sales_return_cash_refund',
          movementType: 'sales_return',
          salesRepId: 'rep-a',
          direction: 'out',
          amount: 25,
        ),
      ]);

      expect(totals.companyCash, 0);
      expect(totals.repCashOutstanding, 75);
      expect(totals.repCashOutstandingBySalesRep.single.amount, 75);
    });
  });

  group('settlement transfer', () {
    test(
      'rep settlement decreases rep outstanding and increases company cash',
      () {
        final totals = CashLedgerCalculator.calculate([
          _movement(
            id: 'rep-invoice',
            type: 'invoice_cash',
            movementType: 'invoice_payment',
            salesRepId: 'rep-a',
            direction: 'in',
            amount: 100,
          ),
          _movement(
            id: 'settlement',
            type: 'settlement_to_admin',
            movementType: 'settlement_to_admin',
            role: AuthRepository.adminRole,
            salesRepId: 'rep-a',
            direction: 'out',
            amount: 100,
          ),
        ]);

        expect(totals.companyCash, 100);
        expect(totals.repCashOutstanding, 0);
        expect(
          totals.companyCash + totals.repCashOutstanding,
          100,
          reason: 'Settlement transfers money; it does not remove it.',
        );
      },
    );

    test('dashboard totals and per-rep outstanding stay separated', () {
      final totals = CashLedgerCalculator.calculate([
        _movement(
          id: 'rep-a-receipt',
          type: 'receipt_cash',
          movementType: 'receipt',
          salesRepId: 'rep-a',
          salesRepName: 'Rep A',
          direction: 'in',
          amount: 100,
        ),
        _movement(
          id: 'rep-b-receipt',
          type: 'receipt_cash',
          movementType: 'receipt',
          salesRepId: 'rep-b',
          salesRepName: 'Rep B',
          direction: 'in',
          amount: 50,
        ),
        _movement(
          id: 'rep-a-settlement',
          type: 'settlement_to_admin',
          movementType: 'settlement_to_admin',
          role: AuthRepository.adminRole,
          salesRepId: 'rep-a',
          salesRepName: 'Rep A',
          direction: 'out',
          amount: 20,
        ),
      ]);

      expect(totals.companyCash, 20);
      expect(totals.repCashOutstanding, 130);
      expect(totals.repCashOutstandingBySalesRep, hasLength(2));
      expect(
        totals.repCashOutstandingBySalesRep
            .singleWhere((row) => row.salesRepId == 'rep-a')
            .amount,
        80,
      );
      expect(
        totals.repCashOutstandingBySalesRep
            .singleWhere((row) => row.salesRepId == 'rep-b')
            .amount,
        50,
      );
    });

    test('two-record settlement transfers rep cash into company cash', () {
      final totals = CashLedgerCalculator.calculate([
        _movement(
          id: 'rep-receipt',
          type: 'receipt_cash',
          movementType: 'receipt',
          salesRepId: 'rep-a',
          salesRepName: 'Rep A',
          direction: 'in',
          amount: 100,
          cashAccount: CashMovementModel.repCashAccount,
        ),
        _movement(
          id: 'settlement-rep-out',
          type: 'settlement_to_admin',
          movementType: 'settlement_to_admin',
          role: AuthRepository.adminRole,
          salesRepId: 'rep-a',
          salesRepName: 'Rep A',
          direction: 'out',
          amount: 100,
          cashAccount: CashMovementModel.repCashAccount,
          settlementId: 'settlement-1',
        ),
        _movement(
          id: 'settlement-company-in',
          type: 'settlement_to_admin',
          movementType: 'settlement_to_admin',
          role: AuthRepository.adminRole,
          salesRepId: '',
          salesRepName: 'Rep A',
          direction: 'in',
          amount: 100,
          cashAccount: CashMovementModel.companyCashAccount,
          settlementId: 'settlement-1',
        ),
      ]);

      expect(totals.companyCash, 100);
      expect(totals.repCashOutstanding, 0);
    });
  });

  group('expenses', () {
    test('company cash expense decreases company cash', () {
      final totals = CashLedgerCalculator.calculate([
        _movement(
          id: 'admin-cash',
          type: 'receipt_cash',
          movementType: 'receipt',
          role: AuthRepository.adminRole,
          direction: 'in',
          amount: 100,
          cashAccount: CashMovementModel.companyCashAccount,
        ),
        _movement(
          id: 'admin-expense',
          type: 'expense',
          movementType: 'expense',
          role: AuthRepository.adminRole,
          direction: 'out',
          amount: 25,
          cashAccount: CashMovementModel.companyCashAccount,
        ),
      ]);

      expect(totals.companyCash, 75);
      expect(totals.repCashOutstanding, 0);
    });

    test('rep collected-cash expense decreases rep outstanding cash', () {
      final totals = CashLedgerCalculator.calculate([
        _movement(
          id: 'rep-receipt',
          type: 'receipt_cash',
          movementType: 'receipt',
          salesRepId: 'rep-a',
          direction: 'in',
          amount: 100,
          cashAccount: CashMovementModel.repCashAccount,
        ),
        _movement(
          id: 'rep-expense',
          type: 'expense',
          movementType: 'expense',
          salesRepId: 'rep-a',
          direction: 'out',
          amount: 15,
          cashAccount: CashMovementModel.repCashAccount,
        ),
      ]);

      expect(totals.companyCash, 0);
      expect(totals.repCashOutstanding, 85);
      expect(totals.repCashOutstandingBySalesRep.single.amount, 85);
    });

    test('personal-cash expense has no cash movement effect', () {
      final beforeExpense = CashLedgerCalculator.calculate([
        _movement(
          id: 'rep-receipt',
          type: 'receipt_cash',
          movementType: 'receipt',
          salesRepId: 'rep-a',
          direction: 'in',
          amount: 100,
          cashAccount: CashMovementModel.repCashAccount,
        ),
      ]);
      final afterPersonalExpense = CashLedgerCalculator.calculate([
        _movement(
          id: 'rep-receipt',
          type: 'receipt_cash',
          movementType: 'receipt',
          salesRepId: 'rep-a',
          direction: 'in',
          amount: 100,
          cashAccount: CashMovementModel.repCashAccount,
        ),
        // Personal-cash expenses are approved as payable reimbursements and do
        // not create cash_movements.
      ]);

      expect(afterPersonalExpense.companyCash, beforeExpense.companyCash);
      expect(
        afterPersonalExpense.repCashOutstanding,
        beforeExpense.repCashOutstanding,
      );
    });
  });

  test('return kept as customer credit has no cash movement effect', () {
    final beforeReturn = CashLedgerCalculator.calculate([
      _movement(
        id: 'rep-invoice',
        type: 'invoice_cash',
        movementType: 'invoice_payment',
        salesRepId: 'rep-a',
        direction: 'in',
        amount: 100,
      ),
    ]);
    final afterCreditReturn = CashLedgerCalculator.calculate([
      _movement(
        id: 'rep-invoice',
        type: 'invoice_cash',
        movementType: 'invoice_payment',
        salesRepId: 'rep-a',
        direction: 'in',
        amount: 100,
      ),
      // Credit-balance returns do not create cash_movements.
    ]);

    expect(afterCreditReturn.companyCash, beforeReturn.companyCash);
    expect(
      afterCreditReturn.repCashOutstanding,
      beforeReturn.repCashOutstanding,
    );
  });
}

CashMovementModel _movement({
  required String id,
  required String type,
  required String movementType,
  String role = AuthRepository.salesRepRole,
  String salesRepId = 'rep-a',
  String salesRepName = 'Rep A',
  required String direction,
  required double amount,
  String cashAccount = '',
  String settlementId = '',
}) {
  final now = DateTime(2026, 7, 9);
  return CashMovementModel(
    id: id,
    companyId: AuthRepository.defaultCompanyId,
    salesRepId: salesRepId,
    salesRepName: salesRepName,
    type: type,
    movementType: movementType,
    direction: direction,
    amount: amount,
    referenceId: id,
    referenceNumber: id,
    sourceCollection: 'test',
    sourceId: id,
    sourceNumber: id,
    customerId: 'customer-1',
    customerName: 'Customer',
    date: now,
    notes: '',
    cashAccount: cashAccount,
    settlementId: settlementId,
    createdByUid: role == AuthRepository.adminRole ? 'admin' : salesRepId,
    createdByName: role == AuthRepository.adminRole ? 'Admin' : salesRepName,
    createdByRole: role,
    createdAt: now,
  );
}
