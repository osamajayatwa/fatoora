import 'package:fatoora/core/finance/exact_decimal.dart';
import 'package:fatoora/features/financial/data/models/cash_movement_model.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// Pair only a unique, exact rep-OUT/company-IN pair in the current result.
/// Missing, ambiguous or off-page counterparts remain individually visible.
List<List<CashMovementModel>> cashMovementPresentationGroups(
  List<CashMovementModel> movements,
) {
  final buckets = <String, List<CashMovementModel>>{};
  for (final m in movements) {
    if (m.settlementId.isNotEmpty) {
      buckets.putIfAbsent('${m.companyId}/${m.settlementId}', () => []).add(m);
    }
  }
  final used = <String>{};
  final result = <List<CashMovementModel>>[];
  for (final m in movements) {
    if (used.contains(m.id)) continue;
    final pair =
        buckets['${m.companyId}/${m.settlementId}'] ??
        const <CashMovementModel>[];
    if (pair.length == 2 &&
        pair[0].id != pair[1].id &&
        pair.every((x) => x.hasVerifiedHolder && x.amountUnits != null) &&
        pair[0].amountUnits == pair[1].amountUnits &&
        pair.where((x) => x.isRepCashAccount && x.isOut).length == 1 &&
        pair.where((x) => x.isCompanyCashAccount && x.isIn).length == 1) {
      used.addAll(pair.map((x) => x.id));
      result.add([
        pair.firstWhere((x) => x.isOut),
        pair.firstWhere((x) => x.isIn),
      ]);
    } else {
      used.add(m.id);
      result.add([m]);
    }
  }
  return result;
}

String? cashAccountLabelKey(CashMovementModel m) => switch (m.cashAccount) {
  CashMovementModel.companyCashAccount => 'financial_company_cash',
  CashMovementModel.repCashAccount => 'ledger_rep_cash',
  _ => null,
};

String cashMoneyText(
  BigInt? units, {
  required String Function(String) t,
  bool arabic = false,
}) => units == null
    ? t('cash_unavailable')
    : '${arabic ? '\u062f.\u0623' : 'JOD'} ${ExactDecimal.formatUnits(units, 3)}';

String cashAmountText(
  CashMovementModel m, {
  required String Function(String) t,
  bool arabic = false,
}) => m.amountUnits == null
    ? t('cash_unavailable')
    : '${m.isOut
          ? '-'
          : m.isIn
          ? '+'
          : ''}${cashMoneyText(m.amountUnits, t: t, arabic: arabic)}';

String cashAccountText(CashMovementModel m, String Function(String) t) {
  if (!m.hasVerifiedHolder) return t('cash_unavailable');
  if (m.isCompanyCashAccount) return t('financial_company_cash');
  if (m.isRepCashAccount && m.holderUid != null) {
    return '${t('ledger_rep_cash')} (${m.holderUid})';
  }
  return t('cash_unavailable');
}

String cashDirectionText(CashMovementModel m, String Function(String) t) =>
    m.isIn
    ? t('cash_direction_in')
    : m.isOut
    ? t('cash_direction_out')
    : t('cash_unavailable');

String cashTypeText(CashMovementModel m, String Function(String) t) {
  if (m.effectiveType.isEmpty) return t('cash_unavailable');
  final key = 'financial_movement_${m.effectiveType}';
  final label = t(key);
  return label == key ? m.effectiveType : label;
}

class CashMovementDetail {
  const CashMovementDetail(
    this.key,
    this.value, {
    this.forceLtr = false,
    this.available = true,
  });
  final String key, value;
  final bool forceLtr, available;
}

/// Shared UI/PDF read projection: only stored fields or documented legacy aliases.
/// Original creator / collector / poster are not inferred from each other's roles.
List<CashMovementDetail> cashMovementDetails(
  CashMovementModel m, {
  required String Function(String) t,
  required String Function(DateTime) timestamp,
  bool arabic = false,
}) {
  CashMovementDetail field(String key, String value, {bool ltr = false}) =>
      CashMovementDetail(
        key,
        value.isEmpty ? t('cash_unavailable') : value,
        forceLtr: ltr,
        available: value.isNotEmpty,
      );
  String actor(String id, String name) =>
      [if (name.isNotEmpty) name, if (id.isNotEmpty) '[$id]'].join(' ');
  String money(BigInt? units) =>
      units == null ? '' : cashMoneyText(units, t: t, arabic: arabic);
  final methodKey = 'cash_method_${m.paymentMethod}';
  final method = m.paymentMethod.isEmpty
      ? ''
      : t(methodKey) == methodKey
      ? m.paymentMethod
      : t(methodKey);
  return [
    field('cash_detail_id', m.id, ltr: true),
    field('financial_type', m.effectiveType.isEmpty ? '' : cashTypeText(m, t)),
    field(
      'cash_detail_source',
      [m.sourceCollection, m.sourceId].where((s) => s.isNotEmpty).join('/'),
      ltr: true,
    ),
    field('financial_reference', m.effectiveReferenceNumber, ltr: true),
    field('cash_detail_reference_id', m.referenceId, ltr: true),
    field(
      'cash_detail_counterparty',
      m.customerId.isNotEmpty || m.customerName.isNotEmpty
          ? actor(m.customerId, m.customerName)
          : actor(m.detail('counterpartyId'), m.detail('counterpartyName')),
    ),
    field('cash_detail_creator', actor(m.createdByUid, m.createdByName)),
    field('cash_detail_creator_role', m.createdByRole),
    field(
      'cash_detail_source_creator',
      actor(m.sourceCreatorUid, m.sourceCreatorName),
    ),
    field('cash_detail_seller', actor(m.sellerId, m.sellerName)),
    field('cash_detail_collector', actor(m.collectorUid, m.collectorName)),
    field('cash_detail_poster', actor(m.postingActorUid, m.postingActorName)),
    field(
      'cash_detail_responsible',
      actor(m.detail('responsibleRepId'), m.detail('responsibleRepName')),
    ),
    field('cash_detail_stored_rep', actor(m.salesRepId, m.salesRepName)),
    field('cash_account', m.hasVerifiedHolder ? cashAccountText(m, t) : ''),
    field(
      'cash_detail_account_id',
      m.detail('treasuryAccountId').isNotEmpty
          ? m.detail('treasuryAccountId')
          : !m.hasVerifiedHolder
          ? ''
          : m.isCompanyCashAccount
          ? 'company_cash'
          : m.holderUid == null
          ? ''
          : 'rep_${m.holderUid}',
      ltr: true,
    ),
    field('payment_method', method),
    field('cash_detail_payment_state', m.detail('paymentType')),
    field('cash_direction', m.hasDirection ? cashDirectionText(m, t) : ''),
    field('financial_amount', money(m.amountUnits), ltr: true),
    field(
      'cash_detail_business_date',
      m.date == null ? '' : timestamp(m.date!),
      ltr: true,
    ),
    field(
      'cash_detail_recorded_at',
      m.createdAt == null ? '' : timestamp(m.createdAt!),
      ltr: true,
    ),
    field('cash_detail_balance_before', money(m.balanceBeforeUnits), ltr: true),
    field('cash_detail_balance_after', money(m.balanceAfterUnits), ltr: true),
    field('cash_detail_settlement', m.settlementId, ltr: true),
    field('cash_detail_transfer', m.detail('transferId'), ltr: true),
    field(
      'cash_detail_counterpart',
      m.detail('counterpartMovementId'),
      ltr: true,
    ),
    field('cash_detail_reversal', m.detail('reversesMovementId'), ltr: true),
    field(
      'cash_detail_cancellation',
      m.detail('reversesReceiptId').isNotEmpty
          ? m.detail('reversesReceiptId')
          : m.detail('cancelledSourceId'),
      ltr: true,
    ),
    field(
      'cash_detail_refund_sources',
      m.references('originalCollectionSourceIds').join(', '),
      ltr: true,
    ),
    field(
      'cash_detail_original_invoice',
      [
        m.detail('originalInvoiceId'),
        m.detail('originalInvoiceNumber'),
      ].where((s) => s.isNotEmpty).join(' / '),
      ltr: true,
    ),
    field(
      'cash_detail_audit',
      [
        m.detail('auditEventId'),
        m.detail('operationId'),
        m.detail('journalEntryId'),
      ].where((s) => s.isNotEmpty).join(' / '),
      ltr: true,
    ),
    field(
      'cash_detail_reason',
      m.detail('reason').isNotEmpty
          ? m.detail('reason')
          : m.detail('cancellationReason'),
    ),
    field('notes', m.notes),
  ];
}

/// Extends the current card/table detail presentation; no route or data fetch.
class CashMovementDetails extends StatelessWidget {
  const CashMovementDetails({
    super.key,
    required this.movement,
    this.initiallyExpanded = false,
  });
  final CashMovementModel movement;
  final bool initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    final fields = cashMovementDetails(
      movement,
      t: (key) => key.tr,
      timestamp: (date) => date.toIso8601String(),
      arabic: Get.locale?.languageCode == 'ar',
    );
    return ExpansionTile(
      key: ValueKey('cash-details-${movement.id}'),
      initiallyExpanded: initiallyExpanded,
      tilePadding: EdgeInsets.zero,
      title: Text('cash_details'.tr),
      children: [
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: Text('cash_details_hint'.tr),
        ),
        if (movement.hasTraceGaps)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text('cash_trace_gap'.tr),
          ),
        for (final field in fields)
          Padding(
            key: ValueKey('cash-${movement.id}-${field.key}'),
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: SizedBox(
              width: double.infinity,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    field.key.tr,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  SelectableText(
                    field.value,
                    textDirection: field.forceLtr ? TextDirection.ltr : null,
                  ),
                ],
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text('cash_balance_hint'.tr),
        ),
      ],
    );
  }
}
