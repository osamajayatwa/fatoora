import 'package:fatoora/core/constants/color.dart';
import 'package:fatoora/features/financial/controllers/settlement_details_preview_controller.dart';
import 'package:fatoora/features/financial/data/models/settlement_details.dart';
import 'package:fatoora/features/financial/data/services/settlement_details_formatter.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// Embedded in the existing pair card/details. The parent supplies an explicit
/// fixture or an authenticated emulator source; production wiring stays disabled.
class SettlementDetailsPanel extends StatelessWidget {
  const SettlementDetailsPanel({
    super.key,
    required this.fixtures,
    this.arabic,
    this.onExport,
  });
  final SettlementDetailsSource fixtures;
  final bool? arabic;
  final Future<void> Function(SettlementDetailsReport)? onExport;
  @override
  Widget build(
    BuildContext context,
  ) => GetBuilder<SettlementDetailsPreviewController>(
    key: ObjectKey(fixtures),
    init: SettlementDetailsPreviewController(fixtures),
    global: false,
    builder: (controller) {
      final fmt = SettlementDetailsFormatter(
        arabic: arabic ?? Get.locale?.languageCode == 'ar',
      );
      final h = controller.assembly.header;
      return Directionality(
        textDirection: fmt.arabic ? TextDirection.rtl : TextDirection.ltr,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Divider(height: 32),
            Text(
              fmt.t('title'),
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: AppColor.secondaryColor,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            _notice(
              context,
              fmt.provenance(fixtures.origin),
              AppColor.secondaryColor,
            ),
            const SizedBox(height: 8),
            Text(
              fmt.t('explanation'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 14),
            if (h != null)
              _field(
                context,
                SettlementDisplayField(
                  fmt.t('company'),
                  h.companyId,
                  ltr: true,
                ),
              ),
            _field(
              context,
              SettlementDisplayField(
                fmt.t('representative'),
                '${fixtures.representativeLabel}\n${fixtures.representativeId}',
              ),
            ),
            _field(
              context,
              SettlementDisplayField(
                fmt.t('settlement'),
                '${fixtures.settlementLabel}\n${fixtures.settlementId}',
                ltr: true,
              ),
            ),
            if (h != null) ...[
              _field(
                context,
                SettlementDisplayField(
                  fmt.t('cutoff'),
                  h.cutoff.isoUtc,
                  ltr: true,
                ),
              ),
              Text(
                '${fmt.t('progress')}: ${controller.assembly.loadedPages} / ${h.pageCount}',
                key: const ValueKey('settlement-detail-progress'),
              ),
            ],
            const SizedBox(height: 10),
            if (controller.state == SettlementPreviewState.verified)
              _notice(context, fmt.t('verified'), AppColor.secondaryColor),
            if (controller.state == SettlementPreviewState.blocked)
              _notice(context, fmt.t('blocked'), AppColor.error),
            if (controller.state == SettlementPreviewState.incomplete)
              _notice(context, fmt.t('incomplete'), AppColor.darkGrey),
            if (controller.state == SettlementPreviewState.coverageIncomplete)
              _notice(context, fmt.t('coverage'), AppColor.error),
            if (controller.state == SettlementPreviewState.error)
              _notice(context, fmt.t('error'), AppColor.error),
            if (controller.state == SettlementPreviewState.expired) ...[
              _notice(context, fmt.t('expired'), AppColor.error),
              OutlinedButton(
                onPressed: controller.restart,
                child: Text(fmt.t('restart')),
              ),
            ],
            if (controller.state == SettlementPreviewState.denied)
              _notice(context, fmt.t('denied'), AppColor.error),
            if (h != null ||
                controller.state == SettlementPreviewState.coverageIncomplete)
              LayoutBuilder(
                builder: (context, constraints) {
                  final columns =
                      constraints.maxWidth >= 760 &&
                          MediaQuery.textScalerOf(context).scale(1) <= 1.3
                      ? 3
                      : constraints.maxWidth >= 440 &&
                            MediaQuery.textScalerOf(context).scale(1) <= 1.5
                      ? 2
                      : 1;
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        for (final f in fmt.summary(
                          controller.totals,
                          h?.currency ?? 'JOD',
                        ))
                          SizedBox(
                            width:
                                (constraints.maxWidth - 10 * (columns - 1)) /
                                columns,
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: context.appSurfaceMuted,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: context.appBorder),
                              ),
                              child: _field(context, f),
                            ),
                          ),
                      ],
                    ),
                  );
                },
              ),
            if (h != null && (h.raw['issues'] as List).isNotEmpty) ...[
              Text(
                fmt.t('evidence_gaps'),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              for (final issue in h.raw['issues'] as List)
                _field(
                  context,
                  SettlementDisplayField(
                    issue['code'] as String,
                    issue['path'] as String,
                    ltr: true,
                  ),
                ),
            ],
            if (controller.state == SettlementPreviewState.loading) ...[
              const LinearProgressIndicator(),
              const SizedBox(height: 8),
              Text(fmt.t('loading')),
            ],
            if (controller.canLoad && !controller.loadingAll)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: OutlinedButton.icon(
                  key: const ValueKey('settlement-load-all'),
                  onPressed: controller.loadAll,
                  icon: const Icon(Icons.download_outlined),
                  label: Text(fmt.t('load_all')),
                ),
              ),
            if (controller.canLoad && !controller.loadingAll)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: OutlinedButton.icon(
                  key: const ValueKey('settlement-load-page'),
                  onPressed: controller.loadingAll ? null : controller.loadNext,
                  icon: const Icon(Icons.receipt_long_outlined),
                  label: Text(
                    fmt.t(
                      controller.state == SettlementPreviewState.error
                          ? 'retry'
                          : controller.assembly.loadedPages == 0
                          ? 'load'
                          : 'more',
                    ),
                  ),
                ),
              ),
            if (controller.assembly.complete && onExport != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: OutlinedButton.icon(
                  key: const ValueKey('settlement-preview-pdf'),
                  onPressed: () async {
                    try {
                      await onExport!(controller.reportForPdf());
                    } on StateError {
                      controller.invalidate(SettlementPreviewState.expired);
                      controller.update();
                    }
                  },
                  icon: const Icon(Icons.picture_as_pdf_outlined),
                  label: Text(
                    fmt.arabic
                        ? fixtures.origin ==
                                  SettlementDetailsOrigin.syntheticFixture
                              ? 'معاينة PDF اصطناعية'
                              : 'PDF للأدلة الموثقة'
                        : fixtures.origin ==
                              SettlementDetailsOrigin.syntheticFixture
                        ? 'Preview synthetic PDF'
                        : 'Authenticated evidence PDF',
                  ),
                ),
              ),
            if (controller.assembly.rows.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                fmt.t('observed'),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              Text(
                fmt.t('dates_hint'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              // Render only the current 64-row page; validated earlier rows remain
              // in the assembly. Previous pages are revisitable without reads.
              _SettlementRowPages(controller: controller, fmt: fmt),
            ],
            if (h != null)
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: Text(fmt.t('report')),
                children: [
                  _field(
                    context,
                    SettlementDisplayField(
                      fmt.t('report'),
                      h.evidenceDigest,
                      ltr: true,
                    ),
                  ),
                  _field(
                    context,
                    SettlementDisplayField(
                      fmt.t('snapshot'),
                      h.snapshotDigest,
                      ltr: true,
                    ),
                  ),
                ],
              ),
          ],
        ),
      );
    },
  );
}

Widget _notice(BuildContext context, String text, Color color) => Container(
  padding: const EdgeInsets.all(10),
  decoration: BoxDecoration(
    color: color.withValues(alpha: .08),
    borderRadius: BorderRadius.circular(8),
    border: Border.all(color: color.withValues(alpha: .3)),
  ),
  child: Text(
    text,
    style: TextStyle(color: color, fontWeight: FontWeight.w600),
  ),
);
Widget _field(BuildContext context, SettlementDisplayField f) => Padding(
  padding: const EdgeInsets.symmetric(vertical: 4),
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        f.label,
        style: Theme.of(
          context,
        ).textTheme.labelMedium?.copyWith(color: context.appMutedText),
      ),
      const SizedBox(height: 3),
      SelectableText(
        f.value,
        textDirection: f.ltr ? TextDirection.ltr : null,
        style: Theme.of(context).textTheme.bodyMedium,
      ),
    ],
  ),
);

class _SettlementRowPages extends StatefulWidget {
  const _SettlementRowPages({required this.controller, required this.fmt});
  final SettlementDetailsPreviewController controller;
  final SettlementDetailsFormatter fmt;
  @override
  State<_SettlementRowPages> createState() => _SettlementRowPagesState();
}

class _SettlementRowPagesState extends State<_SettlementRowPages> {
  int _page = 0, _loaded = 0;
  @override
  Widget build(BuildContext context) {
    final c = widget.controller, fmt = widget.fmt;
    if (_loaded != c.assembly.loadedPages) {
      final firstNewPage = _loaded;
      _loaded = c.assembly.loadedPages;
      _page = firstNewPage < _loaded ? firstNewPage : 0;
    }
    final rows = c.assembly.rows.skip(_page * 64).take(64);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (var i = 0; i < _loaded; i++)
              ChoiceChip(
                label: Text('${i + 1}'),
                selected: _page == i,
                onSelected: (_) => setState(() => _page = i),
              ),
          ],
        ),
        for (final row in rows)
          _row(
            context,
            row,
            fmt,
            c.assembly.header!.currency,
            c.fixtures.settlementId,
          ),
      ],
    );
  }

  Widget _row(
    BuildContext context,
    SettlementDetailRow row,
    SettlementDetailsFormatter fmt,
    String currency,
    String settlementId,
  ) => Card(
    margin: const EdgeInsets.symmetric(vertical: 6),
    elevation: 0,
    shape: RoundedRectangleBorder(
      side: BorderSide(color: context.appBorder),
      borderRadius: BorderRadius.circular(10),
    ),
    child: ExpansionTile(
      key: ValueKey('settlement-row-${row.id}'),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            fmt.category(row, settlementId),
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          Text(
            row.sourceNumber ?? row.sourceId,
            textDirection: TextDirection.ltr,
          ),
          Text(
            '${row.businessDate.dateUtc} · ${fmt.t(row.signed.isNegative ? 'out' : 'in')}',
            textDirection: TextDirection.ltr,
          ),
          Text(
            fmt.money(row.signed, currency, signed: true),
            textDirection: TextDirection.ltr,
            style: TextStyle(
              color: row.signed.isNegative
                  ? AppColor.primaryColor
                  : AppColor.secondaryColor,
              fontWeight: FontWeight.w800,
            ),
          ),
          Text(
            '${fmt.t('holder')}: ${row.holderUid}',
            textDirection: TextDirection.ltr,
          ),
        ],
      ),
      childrenPadding: const EdgeInsets.all(12),
      children: [for (final f in fmt.rowFields(row)) _field(context, f)],
    ),
  );
}
