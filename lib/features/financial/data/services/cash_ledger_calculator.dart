import 'package:fatoora/features/auth/data/repositories/auth_repository.dart';
import 'package:fatoora/features/financial/data/models/cash_movement_model.dart';
import 'package:fatoora/features/financial/data/models/financial_dashboard_snapshot.dart';

class CashLedgerTotals {
  const CashLedgerTotals({
    required this.companyCash,
    required this.repCashOutstanding,
    required this.repCashOutstandingBySalesRep,
  });

  final double companyCash;
  final double repCashOutstanding;
  final List<FinancialRepAmount> repCashOutstandingBySalesRep;
}

class CashLedgerCalculator {
  const CashLedgerCalculator._();

  static CashLedgerTotals calculate(List<CashMovementModel> movements) {
    var companyCash = 0.0;
    var repCashOutstanding = 0.0;
    final repAmounts = <String, double>{};
    final repNames = <String, String>{};

    for (final movement in movements) {
      companyCash = _round(companyCash + companyCashEffect(movement));

      final repEffect = repCashOutstandingEffect(movement);
      if (repEffect == 0 || movement.salesRepId.isEmpty) continue;
      repCashOutstanding = _round(repCashOutstanding + repEffect);
      repAmounts[movement.salesRepId] = _round(
        (repAmounts[movement.salesRepId] ?? 0) + repEffect,
      );
      repNames[movement.salesRepId] = movement.salesRepName;
    }

    final byRep = repAmounts.entries
        .map(
          (entry) => FinancialRepAmount(
            salesRepId: entry.key,
            salesRepName: repNames[entry.key] ?? '',
            amount: _round(entry.value),
          ),
        )
        .toList(growable: false);
    byRep.sort((a, b) => b.amount.compareTo(a.amount));

    return CashLedgerTotals(
      companyCash: _round(companyCash),
      repCashOutstanding: _round(repCashOutstanding),
      repCashOutstandingBySalesRep: byRep,
    );
  }

  static double companyCashEffect(CashMovementModel movement) {
    if (movement.hasCashAccount) {
      return movement.isCompanyCashAccount ? movement.signedAmount : 0;
    }
    if (_isSettlementToAdmin(movement)) return _round(movement.amount);
    if (_isAdminCashAdjustment(movement)) return movement.signedAmount;
    if (!_isAdminCollector(movement)) return 0;
    if (_isCashCollection(movement)) return _round(movement.amount);
    if (_isSalesReturnCashRefund(movement)) return _round(-movement.amount);
    return 0;
  }

  static double repCashOutstandingEffect(CashMovementModel movement) {
    if (movement.hasCashAccount) {
      return movement.isRepCashAccount ? movement.signedAmount : 0;
    }
    if (_isSettlementToAdmin(movement)) return _round(-movement.amount);
    if (!_isSalesRepCollector(movement)) return 0;
    if (_isCashCollection(movement)) return _round(movement.amount);
    if (_isSalesReturnCashRefund(movement)) return _round(-movement.amount);
    return 0;
  }

  static bool _isCashCollection(CashMovementModel movement) {
    final type = movement.effectiveType;
    return movement.isIn &&
        (type == 'invoice_cash' ||
            type == 'invoice_partial' ||
            type == 'receipt_cash' ||
            movement.movementType == 'invoice_payment' ||
            movement.movementType == 'receipt');
  }

  static bool _isSalesReturnCashRefund(CashMovementModel movement) {
    return movement.isOut &&
        (movement.effectiveType == 'sales_return_cash_refund' ||
            movement.type == 'sales_return_cash_refund');
  }

  static bool _isSettlementToAdmin(CashMovementModel movement) {
    return movement.effectiveType == 'settlement_to_admin' ||
        movement.movementType == 'settlement_to_admin';
  }

  static bool _isAdminCashAdjustment(CashMovementModel movement) {
    return movement.effectiveType == 'adjustment' &&
        _isAdminCollector(movement);
  }

  static bool _isAdminCollector(CashMovementModel movement) {
    return movement.createdByRole == AuthRepository.adminRole;
  }

  static bool _isSalesRepCollector(CashMovementModel movement) {
    return movement.createdByRole == AuthRepository.salesRepRole;
  }

  static double _round(double value) {
    if (!value.isFinite) return 0;
    return (value * 1000).roundToDouble() / 1000;
  }
}
