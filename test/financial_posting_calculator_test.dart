import 'package:fatoora/core/finance/financial_posting_calculator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('invoice payment impact', () {
    test('cash invoice is paid with no receivable', () {
      final impact = FinancialPostingCalculator.invoicePayment(
        total: 500,
        hasReceivedPayment: true,
        requestedPaidAmount: 500,
      );

      expect(impact.paidAmount, 500);
      expect(impact.receivableAmount, 0);
      expect(impact.state, FinancialPaymentState.paid);
    });

    test('credit invoice is unpaid with full receivable', () {
      final impact = FinancialPostingCalculator.invoicePayment(
        total: 500,
        hasReceivedPayment: false,
        requestedPaidAmount: 0,
      );

      expect(impact.paidAmount, 0);
      expect(impact.receivableAmount, 500);
      expect(impact.state, FinancialPaymentState.unpaid);
    });

    test('upfront payment creates a partial receivable', () {
      final impact = FinancialPostingCalculator.invoicePayment(
        total: 500,
        hasReceivedPayment: true,
        requestedPaidAmount: 200,
      );

      expect(impact.paidAmount, 200);
      expect(impact.receivableAmount, 300);
      expect(impact.state, FinancialPaymentState.partiallyPaid);
    });
  });

  group('receipt validation', () {
    test('partial and full balance payments are accepted', () {
      expect(
        FinancialPostingCalculator.receiptAmount(
          requestedAmount: 300,
          customerBalance: 500,
        ),
        300,
      );
      expect(
        FinancialPostingCalculator.receiptAmount(
          requestedAmount: 500,
          customerBalance: 500,
        ),
        500,
      );
    });

    test('overpayment is rejected', () {
      expect(
        () => FinancialPostingCalculator.receiptAmount(
          requestedAmount: 501,
          customerBalance: 500,
        ),
        throwsFormatException,
      );
    });
  });

  group('return financial impact', () {
    test('unpaid return removes receivable without refund', () {
      final impact = FinancialPostingCalculator.salesReturn(
        returnTotal: 500,
        outstandingReceivable: 500,
        refundPaidPortionToCash: true,
      );

      expect(impact.salesReduction, 500);
      expect(impact.receivableReduction, 500);
      expect(impact.customerCreditAmount, 0);
      expect(impact.cashRefundAmount, 0);
    });

    test('paid return becomes customer credit by default', () {
      final impact = FinancialPostingCalculator.salesReturn(
        returnTotal: 500,
        outstandingReceivable: 0,
        refundPaidPortionToCash: false,
      );

      expect(impact.receivableReduction, 0);
      expect(impact.customerCreditAmount, 500);
      expect(impact.cashRefundAmount, 0);
    });

    test('paid return can create an actual cash refund', () {
      final impact = FinancialPostingCalculator.salesReturn(
        returnTotal: 500,
        outstandingReceivable: 0,
        refundPaidPortionToCash: true,
      );

      expect(impact.receivableReduction, 0);
      expect(impact.customerCreditAmount, 0);
      expect(impact.cashRefundAmount, 500);
    });

    test('partially paid return clears debt before credit or refund', () {
      final credit = FinancialPostingCalculator.salesReturn(
        returnTotal: 500,
        outstandingReceivable: 200,
        refundPaidPortionToCash: false,
      );
      final refund = FinancialPostingCalculator.salesReturn(
        returnTotal: 500,
        outstandingReceivable: 200,
        refundPaidPortionToCash: true,
      );

      expect(credit.receivableReduction, 200);
      expect(credit.customerCreditAmount, 300);
      expect(refund.receivableReduction, 200);
      expect(refund.cashRefundAmount, 300);
    });
  });
}
