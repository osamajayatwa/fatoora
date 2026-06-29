import 'dart:math' as math;

enum FinancialPaymentState { unpaid, partiallyPaid, paid }

class InvoicePaymentImpact {
  const InvoicePaymentImpact({
    required this.total,
    required this.paidAmount,
    required this.receivableAmount,
    required this.state,
  });

  final double total;
  final double paidAmount;
  final double receivableAmount;
  final FinancialPaymentState state;
}

class ReturnFinancialImpact {
  const ReturnFinancialImpact({
    required this.salesReduction,
    required this.receivableReduction,
    required this.customerCreditAmount,
    required this.cashRefundAmount,
  });

  final double salesReduction;
  final double receivableReduction;
  final double customerCreditAmount;
  final double cashRefundAmount;

  double get customerBalanceReduction =>
      receivableReduction + customerCreditAmount;
}

class FinancialPostingCalculator {
  const FinancialPostingCalculator._();

  static InvoicePaymentImpact invoicePayment({
    required double total,
    required bool hasReceivedPayment,
    required double requestedPaidAmount,
  }) {
    final safeTotal = _round(math.max(total, 0));
    final paid = _round(requestedPaidAmount);
    if (!hasReceivedPayment) {
      if (paid != 0) throw const FormatException('Unexpected paid amount.');
      return InvoicePaymentImpact(
        total: safeTotal,
        paidAmount: 0,
        receivableAmount: safeTotal,
        state: FinancialPaymentState.unpaid,
      );
    }
    if (paid <= 0 || paid > safeTotal) {
      throw const FormatException('Invalid paid amount.');
    }
    final receivable = _round(safeTotal - paid);
    return InvoicePaymentImpact(
      total: safeTotal,
      paidAmount: paid,
      receivableAmount: receivable,
      state: receivable == 0
          ? FinancialPaymentState.paid
          : FinancialPaymentState.partiallyPaid,
    );
  }

  static ReturnFinancialImpact salesReturn({
    required double returnTotal,
    required double outstandingReceivable,
    required bool refundPaidPortionToCash,
  }) {
    final total = _round(math.max(returnTotal, 0));
    final outstanding = _round(math.max(outstandingReceivable, 0));
    final receivableReduction = _round(math.min(total, outstanding));
    final paidPortion = _round(total - receivableReduction);
    return ReturnFinancialImpact(
      salesReduction: total,
      receivableReduction: receivableReduction,
      customerCreditAmount: refundPaidPortionToCash ? 0 : paidPortion,
      cashRefundAmount: refundPaidPortionToCash ? paidPortion : 0,
    );
  }

  static double receiptAmount({
    required double requestedAmount,
    required double customerBalance,
  }) {
    final amount = _round(requestedAmount);
    final balance = _round(math.max(customerBalance, 0));
    if (amount <= 0 || amount > balance) {
      throw const FormatException('Receipt exceeds the receivable balance.');
    }
    return amount;
  }

  static double _round(double value) {
    if (!value.isFinite) return 0;
    return (value * 1000).roundToDouble() / 1000;
  }
}
