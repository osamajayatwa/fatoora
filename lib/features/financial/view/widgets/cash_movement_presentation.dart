import 'package:fatoora/features/financial/data/models/cash_movement_model.dart';

/// Groups only a verified, stored rep-out/company-in settlement pair.
/// A side that is not in the current page remains visible on its own.
List<List<CashMovementModel>> cashMovementPresentationGroups(
  List<CashMovementModel> movements,
) {
  final used = <String>{};
  final result = <List<CashMovementModel>>[];
  for (final movement in movements) {
    if (!used.add(movement.id)) continue;
    if (movement.settlementId.isEmpty) {
      result.add([movement]);
      continue;
    }
    final counterpart = movements
        .where(
          (other) =>
              other.id != movement.id &&
              !used.contains(other.id) &&
              other.settlementId == movement.settlementId &&
              other.amount == movement.amount &&
              ((movement.isRepCashAccount &&
                      movement.isOut &&
                      other.isCompanyCashAccount &&
                      other.isIn) ||
                  (movement.isCompanyCashAccount &&
                      movement.isIn &&
                      other.isRepCashAccount &&
                      other.isOut)),
        )
        .firstOrNull;
    if (counterpart == null) {
      result.add([movement]);
    } else {
      used.add(counterpart.id);
      result.add(
        movement.isRepCashAccount
            ? [movement, counterpart]
            : [counterpart, movement],
      );
    }
  }
  return result;
}

String? cashAccountLabelKey(CashMovementModel movement) =>
    switch (movement.cashAccount) {
      CashMovementModel.companyCashAccount => 'financial_company_cash',
      CashMovementModel.repCashAccount => 'ledger_rep_cash',
      _ => null,
    };
