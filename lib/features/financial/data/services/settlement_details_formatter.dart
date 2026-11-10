import 'package:fatoora/core/finance/exact_decimal.dart';
import 'package:fatoora/features/financial/data/models/settlement_details.dart';

/// One vocabulary and exact formatter for the existing card and PDF.
final class SettlementDetailsFormatter {
  const SettlementDetailsFormatter({this.arabic = false});
  final bool arabic;
  String t(String key) => (arabic ? _ar : _en)[key] ?? key;
  String provenance(SettlementDetailsOrigin origin, {bool footer = false}) => t(
    switch (origin) {
      SettlementDetailsOrigin.syntheticFixture => footer ? 'footer' : 'fixture',
      SettlementDetailsOrigin.authenticatedEmulator =>
        footer ? 'authenticated_footer' : 'authenticated',
      SettlementDetailsOrigin.authenticatedStaging =>
        footer ? 'staging_footer' : 'staging',
    },
  );
  String money(BigInt? units, String currency, {bool signed = false}) =>
      units == null
      ? t('unknown')
      : '${signed && !units.isNegative ? '+' : ''}$currency ${ExactDecimal.formatUnits(units, 3)}';
  String actor(SettlementActor value) => [
    if (value.name?.isNotEmpty == true) value.name!,
    value.uid ?? t('not_recorded'),
  ].join(' · ');
  String category(SettlementDetailRow row, String? settlementId) => t(
    row.category == 'settlement'
        ? row.sourceId == settlementId
              ? 'current_transfer'
              : 'previous_settlement'
        : row.category,
  );
  List<SettlementDisplayField> summary(
    Map<String, BigInt>? totals,
    String currency,
  ) => [
    for (final key in SettlementDetailPage.totalKeys)
      SettlementDisplayField(
        t(key),
        money(totals?[key], currency),
        ltr: totals != null,
      ),
  ];
  List<SettlementDisplayField> rowFields(SettlementDetailRow row) => [
    SettlementDisplayField(t('movement'), row.path, ltr: true),
    SettlementDisplayField(
      t('source'),
      '${row.sourceNumber ?? t('not_recorded')}\n${row.sourcePath}',
      ltr: true,
    ),
    SettlementDisplayField(
      t('business_date'),
      row.businessDate.dateUtc,
      ltr: true,
    ),
    SettlementDisplayField(t('committed'), row.committedAt.isoUtc, ltr: true),
    SettlementDisplayField(
      t('direction'),
      t(row.signed.isNegative ? 'out' : 'in'),
    ),
    SettlementDisplayField(t('holder'), row.holderUid, ltr: true),
    SettlementDisplayField(t('creator'), actor(row.sourceCreator)),
    SettlementDisplayField(t('movement_creator'), actor(row.movementCreator)),
    SettlementDisplayField(t('collector'), actor(row.collector)),
    SettlementDisplayField(t('posting_actor'), actor(row.postingActor)),
    for (final seller in (row.raw['originalSellers'] as List))
      SettlementDisplayField(
        t('seller'),
        '${seller['name'] ?? t('not_recorded')} · ${seller['uid'] ?? t('not_recorded')}',
      ),
    for (final ref in row.references)
      SettlementDisplayField(
        t('linked_document'),
        '${ref.number ?? ref.id}\n${ref.path}',
        ltr: true,
      ),
    if ((row.raw['source'] as Map)['versionAfterCutoff'] == true ||
        row.references.any((ref) => ref.versionAfterCutoff))
      SettlementDisplayField(t('source_version'), t('later_source_version')),
    if ((row.raw['receivableAllocations'] as List).isNotEmpty)
      SettlementDisplayField(
        t('receivable_annotations'),
        (row.raw['receivableAllocations'] as List)
            .map(
              (a) =>
                  '${a['invoiceId']}: ${ExactDecimal.formatUnits(settlementUnits(a['amountUnits']), 3)}',
            )
            .join('\n'),
        ltr: true,
      ),
  ];
  static const _en = {
    'title': 'Settlement details',
    'amount_direction': 'Amount / direction',
    'actor_keys': 'Recorded actor keys',
    'actor_keys_hint':
        'Actor keys below identify recorded participants only. They do not allocate cash to sales.',
    'identifier': 'Identifier',
    'recorded_name': 'Recorded name / role',
    'fixture': 'Synthetic preview · no live connection',
    'authenticated': 'Authenticated emulator evidence · synthetic test data',
    'staging': 'Authenticated staging evidence',
    'staging_footer':
        'Staging cash evidence · no settlement-to-invoice allocations',
    'expired': 'Snapshot expired or changed · details cleared',
    'restart': 'Start a new verified snapshot',
    'denied': 'Viewing permission changed · details cleared',
    'authenticated_footer':
        'Authenticated emulator test evidence. Cash explanation only; no source allocations or financial certification.',
    'explanation':
        'Cash-position explanation, not settlement-to-invoice allocation. Linked invoices are recorded receivable references only.',
    'verified': 'Verified cash reconstruction',
    'blocked': 'Blocked historical evidence · totals unavailable',
    'incomplete': 'Details incomplete · totals withheld',
    'coverage': 'Source coverage incomplete · opening and carry not evaluated',
    'unknown': 'Unavailable / unverified',
    'not_recorded': 'Not recorded',
    'load': 'Load settlement details',
    'load_all': 'Load all detail pages',
    'more': 'Load next detail page',
    'retry': 'Retry page',
    'error':
        'The detail page could not be validated. Retry without changing the snapshot.',
    'loading': 'Loading and validating details…',
    'progress': 'Detail pages',
    'observed': 'Observed cash movements',
    'dates_hint':
        'Rows follow account commit order. Each row retains its business date, commit timestamp and movement ID.',
    'representative': 'Representative',
    'company': 'Company scope',
    'settlement': 'Settlement',
    'cutoff': 'Settlement cutoff (UTC)',
    'report': 'Report digest',
    'snapshot': 'Snapshot digest',
    'openingUnits': 'Verified opening cash',
    'carryUnits': 'Cash carried forward',
    'activitySinceCarryUnits': 'Net activity since carry',
    'cashAvailableBeforeUnits': 'Cash before settlement',
    'transferredUnits': 'Current transfer',
    'remainingUnits': 'Remaining at settlement',
    'currentBalanceUnits': 'Balance at report observation',
    'opening': 'Opening cash',
    'invoice_collection': 'Cash / partial invoice collection',
    'receipt_collection': 'Customer receipt',
    'cash_refund': 'Actual cash refund',
    'cash_expense': 'Approved cash-funded expense',
    'receipt_cancellation': 'Receipt cancellation',
    'previous_settlement': 'Previous settlement',
    'current_transfer': 'Current settlement transfer',
    'unsupported_adjustment': 'Unverified adjustment',
    'source': 'Source document / reference',
    'movement': 'Cash movement reference',
    'movement_id': 'Movement ID',
    'source_version': 'Source version evidence',
    'business_date': 'Business date (UTC)',
    'committed': 'Account commit order (UTC)',
    'holder': 'Paying / collecting cash holder',
    'creator': 'Source creator',
    'movement_creator': 'Movement creator',
    'collector': 'Collector',
    'posting_actor': 'Posting / approving actor',
    'seller': 'Original seller',
    'linked_document': 'Evidenced linked document',
    'later_source_version':
        'Current source version is later than the settlement cutoff',
    'receivable_annotations':
        'Recorded receivable allocations (not settlement allocations)',
    'in': 'IN',
    'out': 'OUT',
    'evidence_gaps': 'Evidence gaps',
    'footer':
        'Synthetic presentation only. This is not a financial certificate.',
  };
  static const _ar = {
    'title': 'تفاصيل التسوية',
    'amount_direction': 'المبلغ / الاتجاه',
    'actor_keys': 'مفاتيح المشاركين المسجلين',
    'actor_keys_hint':
        'تشير المفاتيح أدناه إلى المشاركين المسجلين فقط، ولا تخصص النقد على المبيعات.',
    'identifier': 'المعرف',
    'recorded_name': 'الاسم / الدور المسجل',
    'fixture': 'معاينة اصطناعية · بدون اتصال بالبيانات الفعلية',
    'authenticated': 'أدلة موثقة من المحاكي · بيانات اختبار اصطناعية',
    'staging': 'أدلة موثقة من بيئة الاختبار المرحلية',
    'staging_footer': 'أدلة نقدية مرحلية · لا تتضمن تخصيص التسوية للفواتير',
    'expired': 'انتهت اللقطة أو تغيرت · تم مسح التفاصيل',
    'restart': 'بدء لقطة موثقة جديدة',
    'denied': 'تغيرت صلاحية العرض · تم مسح التفاصيل',
    'authenticated_footer':
        'أدلة اختبار موثقة من المحاكي. شرح للنقد فقط دون تخصيصات للمصادر أو شهادة مالية.',
    'explanation':
        'شرح لحركة النقد وليس تخصيصاً للتسوية على الفواتير. الفواتير المرتبطة مراجع موثقة للذمم فقط.',
    'verified': 'إعادة بناء حركة النقد متحققة',
    'blocked': 'الأدلة التاريخية غير مكتملة · الإجماليات غير متاحة',
    'incomplete': 'التفاصيل غير مكتملة · الإجماليات محجوبة',
    'coverage': 'تغطية المصادر غير مكتملة · لم يتم التحقق من الافتتاحي والمرحل',
    'unknown': 'غير متاح / غير متحقق',
    'not_recorded': 'غير مسجل',
    'load': 'تحميل تفاصيل التسوية',
    'load_all': 'تحميل كل صفحات التفاصيل',
    'more': 'تحميل صفحة التفاصيل التالية',
    'retry': 'إعادة محاولة الصفحة',
    'error': 'تعذر التحقق من صفحة التفاصيل. أعد المحاولة دون تغيير اللقطة.',
    'loading': 'جارٍ تحميل التفاصيل والتحقق منها…',
    'progress': 'صفحات التفاصيل',
    'observed': 'حركات النقد المسجلة',
    'dates_hint':
        'الحركات بترتيب تسجيل الحساب، مع حفظ تاريخ الحركة ووقت التسجيل ومعرفها لكل حركة.',
    'representative': 'المندوب',
    'company': 'نطاق الشركة',
    'settlement': 'التسوية',
    'cutoff': 'وقت التسوية (UTC)',
    'report': 'بصمة التقرير',
    'snapshot': 'بصمة اللقطة',
    'openingUnits': 'النقد الافتتاحي المتحقق',
    'carryUnits': 'النقد المرحل',
    'activitySinceCarryUnits': 'صافي الحركة منذ الترحيل',
    'cashAvailableBeforeUnits': 'النقد قبل التسوية',
    'transferredUnits': 'المبلغ المحول حالياً',
    'remainingUnits': 'النقد المتبقي عند التسوية',
    'currentBalanceUnits': 'الرصيد عند رصد التقرير',
    'opening': 'النقد الافتتاحي',
    'invoice_collection': 'تحصيل فاتورة نقدية / جزئية',
    'receipt_collection': 'سند قبض عميل',
    'cash_refund': 'رد نقدي فعلي',
    'cash_expense': 'مصروف معتمد من النقد',
    'receipt_cancellation': 'إلغاء سند قبض',
    'previous_settlement': 'تسوية سابقة',
    'current_transfer': 'تحويل التسوية الحالية',
    'unsupported_adjustment': 'تعديل غير متحقق',
    'source': 'المستند المصدر / المرجع',
    'movement': 'مرجع حركة النقد',
    'movement_id': 'معرف الحركة',
    'source_version': 'دليل نسخة المصدر',
    'business_date': 'تاريخ الحركة (UTC)',
    'committed': 'ترتيب تسجيل الحساب (UTC)',
    'holder': 'حائز النقد الدافع / المحصل',
    'creator': 'منشئ المستند',
    'movement_creator': 'منشئ الحركة',
    'collector': 'المحصل',
    'posting_actor': 'منفذ الترحيل / الاعتماد',
    'seller': 'البائع الأصلي',
    'linked_document': 'مستند مرتبط بأدلة',
    'later_source_version': 'نسخة المصدر الحالية أحدث من وقت التسوية',
    'receivable_annotations': 'تخصيصات الذمم المسجلة (ليست تخصيصات للتسوية)',
    'in': 'وارد',
    'out': 'صادر',
    'evidence_gaps': 'نواقص الأدلة',
    'footer': 'عرض اصطناعي فقط. لا يمثل شهادة مالية.',
  };
}

final class SettlementDisplayField {
  const SettlementDisplayField(this.label, this.value, {this.ltr = false});
  final String label, value;
  final bool ltr;
}
