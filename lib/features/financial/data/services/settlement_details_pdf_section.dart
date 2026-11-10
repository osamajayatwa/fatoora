import 'dart:typed_data';

import 'package:fatoora/core/pdf/app_pdf_assets.dart';
import 'package:fatoora/core/pdf/app_pdf_direction.dart';
import 'package:fatoora/core/pdf/business_pdf_configuration.dart';
import 'package:fatoora/core/pdf/business_pdf_widgets.dart';
import 'package:fatoora/features/financial/data/models/settlement_details.dart';
import 'package:fatoora/features/financial/data/services/settlement_details_formatter.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Existing cash PDF service delegates its injected, offline detail presentation
/// here. No settings resolver, Firebase read or partial-page export fallback.
Future<Uint8List> buildSettlementDetailsPdf({
  required SettlementDetailsReport details,
  required BusinessPdfConfiguration configuration,
  required String representativeLabel,
  required String settlementLabel,
}) async {
  final assets = await AppPdfAssets.load(loadLogo: configuration.showLogo),
      loc = configuration.localization;
  final fmt = SettlementDetailsFormatter(arabic: loc.isArabic),
      h = details.header;
  final document = pw.Document(
    theme: assets.theme,
    title: '${fmt.t('title')} - $settlementLabel',
    author: configuration.companySettings.name,
    creator: 'Fatoora',
  );
  pw.Widget text(
    String value, {
    bool ltr = false,
    bool bold = false,
    double size = 8,
  }) => ltr && !AppPdfDirection.hasArabic(value)
      ? pw.Text(
          value,
          textDirection: pw.TextDirection.ltr,
          style: pw.TextStyle(
            fontSize: size,
            fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
          ),
        )
      : AppPdfDirection.text(
          value,
          fallbackDirection: loc.textDirection,
          style: pw.TextStyle(
            fontSize: size,
            fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
          ),
        );
  final actorKeys = <String, String>{};
  final actors = <SettlementActor>[];
  String actorKey(SettlementActor actor) {
    if (actor.uid == null) return fmt.t('not_recorded');
    final identity = '${actor.uid}\u0000${actor.name}\u0000${actor.role}';
    return actorKeys.putIfAbsent(identity, () {
      actors.add(actor);
      return 'A${actors.length.toString().padLeft(2, '0')}';
    });
  }

  final data = <List<List<SettlementDisplayField>>>[];
  for (final row in details.rows) {
    final roles = <String, List<String>>{};
    void addRole(String label, SettlementActor actor) {
      roles.putIfAbsent(actorKey(actor), () => []).add(label);
    }

    addRole(fmt.t('creator'), row.sourceCreator);
    addRole(fmt.t('movement_creator'), row.movementCreator);
    addRole(fmt.t('collector'), row.collector);
    addRole(fmt.t('posting_actor'), row.postingActor);
    for (final seller in row.raw['originalSellers'] as List) {
      addRole(
        fmt.t('seller'),
        SettlementActor.fromJson({
          'uid': seller['uid'],
          'name': seller['name'],
          'role': null,
          'basis': 'recorded_invoice_seller',
        }),
      );
    }
    data.add([
      [
        SettlementDisplayField('', fmt.category(row, h.settlementId)),
        SettlementDisplayField('', row.sourceNumber ?? row.sourceId, ltr: true),
        SettlementDisplayField('', row.sourcePath, ltr: true),
        SettlementDisplayField('', row.businessDate.dateUtc, ltr: true),
        SettlementDisplayField('', row.committedAt.isoUtc, ltr: true),
        SettlementDisplayField('', '${fmt.t('movement_id')}: ${row.id}'),
        for (final ref in row.references)
          SettlementDisplayField(
            fmt.t('linked_document'),
            '${ref.number ?? ref.id}\n${ref.path}',
            ltr: true,
          ),
        for (final f
            in fmt
                .rowFields(row)
                .where(
                  (f) =>
                      f.label == fmt.t('receivable_annotations') ||
                      f.label == fmt.t('source_version'),
                ))
          f,
      ],
      [
        SettlementDisplayField('', fmt.t(row.signed.isNegative ? 'out' : 'in')),
        SettlementDisplayField(
          '',
          fmt.money(row.signed, h.currency, signed: true),
          ltr: true,
        ),
      ],
      [
        SettlementDisplayField('', row.holderUid, ltr: true),
        for (final entry in roles.entries)
          SettlementDisplayField(
            '',
            '${entry.value.join(' / ')}: ${entry.key}',
          ),
      ],
    ]);
  }
  pw.Widget table(
    List<String> labels,
    List<List<List<SettlementDisplayField>>> data,
  ) {
    final tableRows = <pw.TableRow>[
      pw.TableRow(
        repeat: true,
        decoration: const pw.BoxDecoration(color: PdfColors.grey200),
        children: [
          for (final label in (loc.isArabic ? labels.reversed : labels))
            pw.Padding(
              padding: const pw.EdgeInsets.all(6),
              child: text(label, bold: true, size: 9),
            ),
        ],
      ),
    ];
    for (var index = 0; index < data.length; index++) {
      final cells = data[index].map((f) => _fragments(f, maximum: 40)).toList();
      final chunks = cells
          .map((c) => (c.length + 6) ~/ 7)
          .reduce((a, b) => a > b ? a : b);
      for (var chunk = 0; chunk < chunks; chunk++) {
        tableRows.add(
          pw.TableRow(
            decoration: pw.BoxDecoration(
              color: index.isEven ? PdfColors.white : PdfColors.grey50,
            ),
            children: [
              for (final cell in (loc.isArabic ? cells.reversed : cells))
                pw.Padding(
                  padding: const pw.EdgeInsets.all(5),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                    children: [
                      for (final f in cell.skip(chunk * 7).take(7))
                        text(f.value, ltr: f.ltr, bold: f.label.isNotEmpty),
                    ],
                  ),
                ),
            ],
          ),
        );
      }
    }
    return pw.Table(
      columnWidths: {
        0: pw.FlexColumnWidth(loc.isArabic ? 4.5 : 3.5),
        1: const pw.FlexColumnWidth(2),
        2: pw.FlexColumnWidth(loc.isArabic ? 3.5 : 4.5),
      },
      border: pw.TableBorder.all(color: PdfColors.grey300, width: .4),
      children: tableRows,
    );
  }

  document.addPage(
    pw.MultiPage(
      pageTheme: BusinessPdfWidgets.pageTheme(
        assets,
        textDirection: loc.textDirection,
      ),
      maxPages: 30 + details.rows.length * 4,
      header: (_) => BusinessPdfWidgets.pageHeader(
        assets: assets,
        configuration: configuration,
        title: fmt.t('title'),
        // Keep repeated furniture bounded; the complete label is in the body.
        subtitle: settlementLabel.length <= 80
            ? settlementLabel
            : h.settlementId,
      ),
      footer: (context) => BusinessPdfWidgets.pageFooter(
        context: context,
        loc: loc,
        text: fmt.provenance(details.origin, footer: true),
      ),
      build: (_) => [
        text(
          fmt.provenance(details.origin),
          bold: true,
          size: 10,
        ),
        pw.SizedBox(height: 6),
        text(
          fmt.t(details.verified ? 'verified' : 'blocked'),
          bold: true,
          size: 11,
        ),
        pw.SizedBox(height: 8),
        text(fmt.t('explanation')),
        pw.SizedBox(height: 12),
        ..._fragments([
          SettlementDisplayField(fmt.t('company'), h.companyId, ltr: true),
          SettlementDisplayField(
            fmt.t('representative'),
            '$representativeLabel\n${h.representativeId}',
          ),
          SettlementDisplayField(
            fmt.t('settlement'),
            '$settlementLabel\n${h.settlementId}',
            ltr: true,
          ),
          SettlementDisplayField(fmt.t('cutoff'), h.cutoff.isoUtc, ltr: true),
        ]).map(
          (f) => text(f.value, ltr: f.ltr, bold: f.label.isNotEmpty, size: 9),
        ),
        pw.SizedBox(height: 12),
        BusinessPdfWidgets.infoGrid(
          loc: loc,
          items: [
            for (final f in fmt.summary(details.certifiedTotals, h.currency))
              PdfInfoItem(f.label, f.value, bold: true),
          ],
        ),
        if ((h.raw['issues'] as List).isNotEmpty) ...[
          pw.SizedBox(height: 12),
          text(fmt.t('evidence_gaps'), bold: true),
          for (final issue in h.raw['issues'] as List)
            ..._fragments([
              SettlementDisplayField(
                issue['code'] as String,
                issue['path'] as String,
                ltr: true,
              ),
            ]).map((f) => text(f.value, ltr: f.ltr)),
        ],
        // Start the audit table together with its heading and repeated columns.
        pw.NewPage(),
        BusinessPdfWidgets.sectionTitle(fmt.t('observed')),
        text(fmt.t('dates_hint')),
        pw.SizedBox(height: 6),
        table([
          fmt.t('source'),
          fmt.t('amount_direction'),
          '${fmt.t('holder')} / ${fmt.t('actor_keys')}',
        ], data),
        pw.NewPage(),
        BusinessPdfWidgets.sectionTitle(fmt.t('actor_keys')),
        text(fmt.t('actor_keys_hint')),
        table(
          [fmt.t('actor_keys'), fmt.t('identifier'), fmt.t('recorded_name')],
          [
            for (var i = 0; i < actors.length; i++)
              [
                [
                  SettlementDisplayField(
                    '',
                    'A${(i + 1).toString().padLeft(2, '0')}',
                    ltr: true,
                  ),
                ],
                [SettlementDisplayField('', actors[i].uid!, ltr: true)],
                [
                  SettlementDisplayField(
                    '',
                    actors[i].name ?? fmt.t('not_recorded'),
                  ),
                  if (actors[i].role != null)
                    SettlementDisplayField('', actors[i].role!),
                ],
              ],
          ],
        ),
        pw.SizedBox(height: 14),
        text(fmt.t('report'), bold: true),
        text(h.evidenceDigest, ltr: true),
        pw.SizedBox(height: 6),
        text(fmt.t('snapshot'), bold: true),
        text(h.snapshotDigest, ltr: true),
      ],
    ),
  );
  return document.save();
}

// Bounded physical subrows prevent a single long name/reference from becoming
// an unbreakable PDF table row. Every character is retained; no maxLines/ellipsis.
List<SettlementDisplayField> _fragments(
  List<SettlementDisplayField> fields, {
  int maximum = 80,
}) {
  final result = <SettlementDisplayField>[];
  for (final field in fields) {
    if (field.label.isNotEmpty) {
      result.add(SettlementDisplayField('label', field.label));
    }
    for (final line in field.value.split('\n')) {
      var start = 0;
      while (start < line.length) {
        var end = (start + maximum).clamp(0, line.length);
        if (end < line.length) {
          final space = line.lastIndexOf(' ', end);
          if (space > start + 8) end = space + 1;
        }
        result.add(
          SettlementDisplayField(
            '',
            line.substring(start, end),
            ltr: field.ltr,
          ),
        );
        start = end;
      }
    }
  }
  return result;
}
