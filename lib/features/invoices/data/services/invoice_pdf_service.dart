import 'dart:typed_data';

import 'package:fatoora/core/pdf/app_pdf_assets.dart';
import 'package:fatoora/core/pdf/app_pdf_localization.dart';
import 'package:fatoora/core/pdf/business_pdf_configuration.dart';
import 'package:fatoora/core/pdf/business_pdf_settings_resolver.dart';
import 'package:fatoora/core/pdf/business_pdf_widgets.dart';
import 'package:fatoora/features/invoices/data/models/invoice_enums.dart';
import 'package:fatoora/features/invoices/data/models/invoice_model.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

class InvoicePdfService {
  const InvoicePdfService._();

  static final PdfColor _ink = PdfColor.fromInt(0xff20384f);
  static final PdfColor _accent = PdfColor.fromInt(0xff247ba0);
  static final PdfColor _softAccent = PdfColor.fromInt(0xffeaf3f7);
  static final PdfColor _line = PdfColor.fromInt(0xffd8e0e6);
  static final PdfColor _muted = PdfColor.fromInt(0xff667785);

  static Future<Uint8List> build(
    InvoiceModel invoice, {
    BusinessPdfConfiguration? configuration,
  }) async {
    final pdfConfiguration =
        configuration ??
        await BusinessPdfSettingsResolver.resolve(
          companyId: invoice.companyId,
          includeUserPreferences: true,
        );
    final assets = await AppPdfAssets.load(loadLogo: pdfConfiguration.showLogo);
    final loc = pdfConfiguration.localization;
    final document = pw.Document(
      theme: assets.theme,
      title: '${loc.t('invoice')} ${invoice.invoiceNumber}',
      author: pdfConfiguration.companySettings.name,
      creator: 'Fatoora',
    );
    final qrCodeData = invoice.isElectronic
        ? invoice.government?.qrCode.trim()
        : null;
    final showQrCode = qrCodeData != null && qrCodeData.isNotEmpty;
    final notes = pdfConfiguration.invoiceNotes(invoice.notes);

    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(24, 18, 24, 20),
        theme: assets.theme,
        textDirection: loc.textDirection,
        maxPages: 100,
        header: (context) => _header(
          assets: assets,
          configuration: pdfConfiguration,
          invoice: invoice,
        ),
        footer: (context) =>
            _pageFooter(context: context, configuration: pdfConfiguration),
        build: (_) => [
          _overview(invoice: invoice, loc: loc),
          pw.SizedBox(height: 10),
          _itemsTable(invoice: invoice, loc: loc),
          pw.SizedBox(height: 10),
          _financialSummary(
            invoice: invoice,
            loc: loc,
            qrCodeData: showQrCode ? qrCodeData : null,
          ),
          if (notes.trim().isNotEmpty) ...[
            pw.NewPage(freeSpace: 72),
            pw.SizedBox(height: 9),
            _notesSection(notes: notes, loc: loc),
          ],
        ],
      ),
    );
    return document.save();
  }

  static pw.Widget _header({
    required AppPdfAssets assets,
    required BusinessPdfConfiguration configuration,
    required InvoiceModel invoice,
  }) {
    final loc = configuration.localization;
    final company = configuration.companySettings;
    final companyLines = configuration.showCompanyInfo
        ? [
            [
              company.phone,
              company.email,
              company.website,
            ].where((value) => value.trim().isNotEmpty).join(' | '),
            [
              company.address,
              company.country,
            ].where((value) => value.trim().isNotEmpty).join(' | '),
          ].where((value) => value.isNotEmpty).toList(growable: false)
        : const <String>[];
    final logo = configuration.showLogo && assets.logo != null
        ? pw.Container(
            width: 42,
            height: 42,
            alignment: pw.Alignment.center,
            child: pw.Image(assets.logo!, fit: pw.BoxFit.contain),
          )
        : null;

    final companyBlock = pw.Expanded(
      child: pw.Column(
        crossAxisAlignment: loc.startCrossAxis,
        children: [
          if (configuration.showCompanyInfo && company.name.trim().isNotEmpty)
            _mixedText(
              company.name,
              loc: loc,
              style: pw.TextStyle(
                color: _ink,
                fontSize: 13,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          for (final line in companyLines)
            pw.Padding(
              padding: const pw.EdgeInsets.only(top: 2),
              child: _mixedText(
                line,
                loc: loc,
                style: pw.TextStyle(color: _muted, fontSize: 7.2),
              ),
            ),
        ],
      ),
    );
    final invoiceBlock = pw.Column(
      crossAxisAlignment: loc.isArabic
          ? pw.CrossAxisAlignment.start
          : pw.CrossAxisAlignment.end,
      children: [
        _localizedLabel(
          key: invoice.isElectronic ? 'tax_invoice' : 'sales_invoice',
          loc: loc,
          color: _ink,
          fontSize: 16,
          fontWeight: pw.FontWeight.bold,
          crossAxisAlignment: loc.isArabic
              ? pw.CrossAxisAlignment.start
              : pw.CrossAxisAlignment.end,
        ),
        pw.SizedBox(height: 3),
        pw.Container(
          padding: const pw.EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          decoration: pw.BoxDecoration(
            color: _softAccent,
            borderRadius: pw.BorderRadius.circular(3),
          ),
          child: pw.Text(
            invoice.invoiceNumber,
            textDirection: pw.TextDirection.ltr,
            style: pw.TextStyle(
              color: _accent,
              fontSize: 8.5,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
        ),
      ],
    );
    final rowChildren = loc.isArabic
        ? <pw.Widget>[
            invoiceBlock,
            pw.SizedBox(width: 14),
            companyBlock,
            if (logo != null) ...[pw.SizedBox(width: 9), logo],
          ]
        : <pw.Widget>[
            if (logo != null) ...[logo, pw.SizedBox(width: 9)],
            companyBlock,
            pw.SizedBox(width: 14),
            invoiceBlock,
          ];

    return pw.Directionality(
      textDirection: loc.textDirection,
      child: pw.Container(
        padding: const pw.EdgeInsets.only(bottom: 8),
        margin: const pw.EdgeInsets.only(bottom: 9),
        decoration: pw.BoxDecoration(
          border: pw.Border(bottom: pw.BorderSide(color: _accent, width: 1.2)),
        ),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: rowChildren,
        ),
      ),
    );
  }

  static pw.Widget _overview({
    required InvoiceModel invoice,
    required AppPdfLocalization loc,
  }) {
    final customer = invoice.customerSnapshot;
    final customerPanel = _informationPanel(
      titleKey: 'customer_info',
      loc: loc,
      rows: [
        _LabelValue('customer', customer?.name ?? '', strong: true),
        _LabelValue('phone', customer?.phone ?? '', forceLtr: true),
        _LabelValue(
          'address',
          [
            customer?.address ?? '',
            customer?.city ?? '',
          ].where((value) => value.trim().isNotEmpty).join(' | '),
        ),
      ],
    );
    final invoicePanel = _informationPanel(
      titleKey: 'invoice',
      loc: loc,
      rows: [
        _LabelValue(
          'invoice_date',
          loc.date(invoice.invoiceDate),
          forceLtr: true,
        ),
        _LabelValue('due_date', loc.date(invoice.dueDate), forceLtr: true),
        _LabelValue(
          'invoice_status',
          loc.enumValue(invoice.invoiceStatus.value),
        ),
        _LabelValue(
          'payment_status',
          loc.enumValue(invoice.paymentStatus.value),
        ),
        _LabelValue('sales_rep', invoice.salesRepName),
      ],
    );
    final panels = loc.isArabic
        ? <pw.Widget>[invoicePanel, customerPanel]
        : <pw.Widget>[customerPanel, invoicePanel];

    return pw.Directionality(
      textDirection: loc.textDirection,
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Expanded(child: panels.first),
          pw.SizedBox(width: 10),
          pw.Expanded(child: panels.last),
        ],
      ),
    );
  }

  static pw.Widget _informationPanel({
    required String titleKey,
    required AppPdfLocalization loc,
    required List<_LabelValue> rows,
  }) {
    final visibleRows = rows
        .where((row) => row.value.trim().isNotEmpty)
        .toList(growable: false);
    return pw.Container(
      padding: const pw.EdgeInsets.all(8),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: _line, width: .6),
        borderRadius: pw.BorderRadius.circular(4),
      ),
      child: pw.Column(
        crossAxisAlignment: loc.startCrossAxis,
        children: [
          _localizedLabel(
            key: titleKey,
            loc: loc,
            color: _accent,
            fontSize: 8,
            fontWeight: pw.FontWeight.bold,
          ),
          pw.SizedBox(height: 5),
          for (final row in visibleRows) _labelValueRow(row: row, loc: loc),
        ],
      ),
    );
  }

  static pw.Widget _labelValueRow({
    required _LabelValue row,
    required AppPdfLocalization loc,
  }) {
    final label = pw.SizedBox(
      width: 67,
      child: _localizedLabel(
        key: row.labelKey,
        loc: loc,
        color: _muted,
        fontSize: 6.7,
      ),
    );
    final value = pw.Expanded(
      child: _mixedText(
        row.value.trim().isEmpty ? '-' : row.value,
        loc: loc,
        forceDirection: row.forceLtr ? pw.TextDirection.ltr : null,
        style: pw.TextStyle(
          color: _ink,
          fontSize: 7.5,
          fontWeight: row.strong ? pw.FontWeight.bold : pw.FontWeight.normal,
        ),
      ),
    );
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 2.5),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: loc.isArabic
            ? [value, pw.SizedBox(width: 5), label]
            : [label, pw.SizedBox(width: 5), value],
      ),
    );
  }

  static pw.Widget _itemsTable({
    required InvoiceModel invoice,
    required AppPdfLocalization loc,
  }) {
    final headerKeys = [
      'item',
      'quantity',
      'unit',
      'unit_price',
      'discount',
      'tax',
      'line_total',
    ];
    final headers = headerKeys
        .map(
          (key) => _localizedLabel(
            key: key,
            loc: loc,
            color: PdfColors.white,
            fontSize: 6.6,
            fontWeight: pw.FontWeight.bold,
            crossAxisAlignment: pw.CrossAxisAlignment.center,
          ),
        )
        .toList(growable: false);
    final cellStyle = pw.TextStyle(color: _ink, fontSize: 7.1);
    final data = invoice.items
        .map(
          (item) => <pw.Widget>[
            _mixedText(
              [
                item.itemName,
                item.description,
              ].where((value) => value.trim().isNotEmpty).join('\n'),
              loc: loc,
              style: cellStyle,
            ),
            _ltrText(loc.quantity(item.quantity), style: cellStyle),
            _mixedText(item.unit, loc: loc, style: cellStyle),
            _ltrText(loc.money(item.unitPrice), style: cellStyle),
            _ltrText(loc.money(item.discount), style: cellStyle),
            _ltrText(loc.money(item.taxAmount), style: cellStyle),
            _ltrText(loc.money(item.total), style: cellStyle),
          ],
        )
        .toList(growable: false);
    final displayHeaders = loc.isArabic
        ? headers.reversed.toList(growable: false)
        : headers;
    final displayData = loc.isArabic
        ? data
              .map((row) => row.reversed.toList(growable: false))
              .toList(growable: false)
        : data;
    final flexes = loc.isArabic
        ? const [1.25, .95, .95, 1.15, .7, .75, 3.25]
        : const [3.25, .75, .7, 1.15, .95, .95, 1.25];
    final widths = <int, pw.TableColumnWidth>{
      for (var index = 0; index < flexes.length; index++)
        index: pw.FlexColumnWidth(flexes[index]),
    };
    final itemColumn = loc.isArabic ? 6 : 0;
    final alignments = <int, pw.AlignmentGeometry>{
      for (var index = 0; index < flexes.length; index++)
        index: index == itemColumn
            ? loc.startAlignment
            : pw.Alignment.centerRight,
    };

    return pw.TableHelper.fromTextArray(
      headers: displayHeaders,
      data: displayData,
      headerCount: 1,
      columnWidths: widths,
      tableDirection: loc.textDirection,
      headerDirection: loc.textDirection,
      headerAlignments: alignments,
      cellAlignments: alignments,
      headerPadding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      cellPadding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3.1),
      headerDecoration: pw.BoxDecoration(color: _ink),
      headerStyle: pw.TextStyle(
        color: PdfColors.white,
        fontSize: 7.1,
        fontWeight: pw.FontWeight.bold,
      ),
      cellStyle: pw.TextStyle(color: _ink, fontSize: 7.1),
      oddRowDecoration: const pw.BoxDecoration(color: PdfColors.grey100),
      border: pw.TableBorder(
        top: pw.BorderSide(color: _ink, width: .7),
        bottom: pw.BorderSide(color: _line, width: .6),
        left: pw.BorderSide(color: _line, width: .45),
        right: pw.BorderSide(color: _line, width: .45),
        horizontalInside: pw.BorderSide(color: _line, width: .35),
      ),
    );
  }

  static pw.Widget _financialSummary({
    required InvoiceModel invoice,
    required AppPdfLocalization loc,
    required String? qrCodeData,
  }) {
    final paymentBlock = pw.Expanded(
      child: pw.Column(
        crossAxisAlignment: loc.startCrossAxis,
        children: [
          _localizedLabel(
            key: 'payment',
            loc: loc,
            color: _accent,
            fontSize: 8,
            fontWeight: pw.FontWeight.bold,
          ),
          pw.SizedBox(height: 5),
          _compactValue(
            labelKey: 'payment_type',
            value: loc.enumValue(invoice.paymentType.value),
            loc: loc,
          ),
          _compactValue(
            labelKey: 'payment_status',
            value: loc.enumValue(invoice.paymentStatus.value),
            loc: loc,
          ),
          pw.SizedBox(height: 7),
          _signatures(loc),
        ],
      ),
    );
    final supportingBlock = pw.Container(
      padding: const pw.EdgeInsets.all(8),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: _line, width: .6),
        borderRadius: pw.BorderRadius.circular(4),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          paymentBlock,
          if (qrCodeData != null) ...[
            pw.SizedBox(width: 10),
            pw.Container(
              padding: const pw.EdgeInsets.all(3),
              decoration: pw.BoxDecoration(
                color: PdfColors.white,
                border: pw.Border.all(color: _line, width: .45),
                borderRadius: pw.BorderRadius.circular(3),
              ),
              child: BusinessPdfWidgets.qrCode(qrCodeData, size: 50),
            ),
          ],
        ],
      ),
    );
    final totals = _totalsPanel(invoice: invoice, loc: loc);
    final children = loc.isArabic
        ? <pw.Widget>[
            pw.SizedBox(width: 220, child: totals),
            pw.SizedBox(width: 10),
            pw.Expanded(child: supportingBlock),
          ]
        : <pw.Widget>[
            pw.Expanded(child: supportingBlock),
            pw.SizedBox(width: 10),
            pw.SizedBox(width: 220, child: totals),
          ];

    return pw.Directionality(
      textDirection: loc.textDirection,
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: children,
      ),
    );
  }

  static pw.Widget _totalsPanel({
    required InvoiceModel invoice,
    required AppPdfLocalization loc,
  }) {
    final rows = [
      _LabelValue('subtotal', loc.money(invoice.subtotal), forceLtr: true),
      _LabelValue(
        'total_discount',
        loc.money(invoice.totalDiscount),
        forceLtr: true,
      ),
      _LabelValue('total_tax', loc.money(invoice.totalTax), forceLtr: true),
      _LabelValue(
        'grand_total',
        loc.money(invoice.grandTotal),
        strong: true,
        forceLtr: true,
      ),
      _LabelValue('paid_amount', loc.money(invoice.paidAmount), forceLtr: true),
      _LabelValue(
        'remaining_amount',
        loc.money(invoice.remainingAmount),
        strong: true,
        forceLtr: true,
      ),
    ];
    return pw.Container(
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: _line, width: .6),
        borderRadius: pw.BorderRadius.circular(4),
      ),
      child: pw.Column(
        children: [
          for (var index = 0; index < rows.length; index++)
            _totalRow(
              row: rows[index],
              loc: loc,
              highlight: index == 3 || index == rows.length - 1,
              drawBorder: index != rows.length - 1,
            ),
        ],
      ),
    );
  }

  static pw.Widget _totalRow({
    required _LabelValue row,
    required AppPdfLocalization loc,
    required bool highlight,
    required bool drawBorder,
  }) {
    final label = _localizedLabel(
      key: row.labelKey,
      loc: loc,
      color: highlight ? _ink : _muted,
      fontSize: 6.8,
      fontWeight: row.strong ? pw.FontWeight.bold : pw.FontWeight.normal,
    );
    final value = _ltrText(
      row.value,
      style: pw.TextStyle(
        color: highlight ? _accent : _ink,
        fontSize: highlight ? 8.5 : 7.4,
        fontWeight: row.strong ? pw.FontWeight.bold : pw.FontWeight.normal,
      ),
    );
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4.2),
      decoration: pw.BoxDecoration(
        color: highlight ? _softAccent : null,
        border: drawBorder
            ? pw.Border(bottom: pw.BorderSide(color: _line, width: .35))
            : null,
      ),
      child: pw.Row(
        children: loc.isArabic
            ? [value, pw.Spacer(), label]
            : [label, pw.Spacer(), value],
      ),
    );
  }

  static pw.Widget _compactValue({
    required String labelKey,
    required String value,
    required AppPdfLocalization loc,
  }) {
    final label = _localizedLabel(
      key: labelKey,
      loc: loc,
      color: _muted,
      fontSize: 6.7,
    );
    final valueWidget = _mixedText(
      value,
      loc: loc,
      style: pw.TextStyle(color: _ink, fontSize: 7.5),
    );
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 3),
      child: pw.Row(
        children: loc.isArabic
            ? [valueWidget, pw.Spacer(), label]
            : [label, pw.Spacer(), valueWidget],
      ),
    );
  }

  static pw.Widget _notesSection({
    required String notes,
    required AppPdfLocalization loc,
  }) {
    return pw.Directionality(
      textDirection: loc.textDirection,
      child: pw.Container(
        width: double.infinity,
        padding: const pw.EdgeInsets.all(8),
        decoration: pw.BoxDecoration(
          color: PdfColors.grey100,
          border: pw.Border.all(color: _line, width: .45),
          borderRadius: pw.BorderRadius.circular(4),
        ),
        child: pw.Column(
          crossAxisAlignment: loc.startCrossAxis,
          children: [
            _localizedLabel(
              key: 'notes',
              loc: loc,
              color: _accent,
              fontSize: 8,
              fontWeight: pw.FontWeight.bold,
            ),
            pw.SizedBox(height: 3),
            _mixedText(
              notes,
              loc: loc,
              style: pw.TextStyle(color: _ink, fontSize: 7.2),
            ),
          ],
        ),
      ),
    );
  }

  static pw.Widget _pageFooter({
    required pw.Context context,
    required BusinessPdfConfiguration configuration,
  }) {
    final loc = configuration.localization;
    final footerText = configuration.pdfSettings.invoiceFooterText.trim();
    final pageNumberText = '${context.pageNumber} / ${context.pagesCount}';
    final footer = footerText.isEmpty
        ? pw.SizedBox.shrink()
        : pw.Expanded(
            child: _mixedText(
              footerText,
              loc: loc,
              style: pw.TextStyle(color: _muted, fontSize: 6.8),
            ),
          );
    final page = pw.Directionality(
      textDirection: pw.TextDirection.ltr,
      child: pw.Row(
        mainAxisSize: pw.MainAxisSize.min,
        children: loc.isArabic
            ? [
                _ltrText(
                  pageNumberText,
                  style: pw.TextStyle(color: _muted, fontSize: 6.8),
                ),
                pw.SizedBox(width: 4),
                _localizedLabel(
                  key: 'page',
                  loc: loc,
                  color: _muted,
                  fontSize: 6.4,
                ),
              ]
            : [
                _localizedLabel(
                  key: 'page',
                  loc: loc,
                  color: _muted,
                  fontSize: 6.4,
                ),
                pw.SizedBox(width: 4),
                _ltrText(
                  pageNumberText,
                  style: pw.TextStyle(color: _muted, fontSize: 6.8),
                ),
              ],
      ),
    );
    final children = loc.isArabic
        ? <pw.Widget>[
            page,
            if (footerText.isNotEmpty) ...[pw.SizedBox(width: 12), footer],
          ]
        : <pw.Widget>[
            if (footerText.isNotEmpty) ...[footer, pw.SizedBox(width: 12)],
            page,
          ];
    return pw.Directionality(
      textDirection: loc.textDirection,
      child: pw.Container(
        padding: const pw.EdgeInsets.only(top: 5),
        margin: const pw.EdgeInsets.only(top: 7),
        decoration: pw.BoxDecoration(
          border: pw.Border(top: pw.BorderSide(color: _line, width: .4)),
        ),
        child: pw.Row(children: children),
      ),
    );
  }

  static pw.TextDirection _directionForText(
    String value,
    AppPdfLocalization loc,
  ) {
    for (final rune in value.runes) {
      if (_isArabicRune(rune)) return pw.TextDirection.rtl;
      if (_isLtrRune(rune)) return pw.TextDirection.ltr;
    }
    return loc.textDirection;
  }

  static pw.Widget _ltrText(String value, {required pw.TextStyle style}) {
    return pw.Text(
      value.trim(),
      textDirection: pw.TextDirection.ltr,
      textAlign: pw.TextAlign.right,
      style: style,
    );
  }

  static pw.Widget _mixedText(
    String value, {
    required AppPdfLocalization loc,
    required pw.TextStyle style,
    pw.TextDirection? forceDirection,
  }) {
    final text = value.trim();
    if (text.isEmpty) {
      return pw.Text('', style: style);
    }
    if (forceDirection != null) {
      return pw.Text(
        text,
        textDirection: forceDirection,
        textAlign: forceDirection == pw.TextDirection.rtl
            ? pw.TextAlign.right
            : pw.TextAlign.left,
        style: style,
      );
    }

    final lines = text.split('\n');
    if (lines.length == 1) {
      return _mixedLine(lines.single, loc: loc, style: style);
    }
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        for (var index = 0; index < lines.length; index++) ...[
          _mixedLine(lines[index], loc: loc, style: style),
          if (index != lines.length - 1) pw.SizedBox(height: 2),
        ],
      ],
    );
  }

  static pw.Widget _mixedLine(
    String value, {
    required AppPdfLocalization loc,
    required pw.TextStyle style,
  }) {
    final baseDirection = _directionForText(value, loc);
    final runs = _directionalRuns(value, baseDirection);
    if (runs.length <= 1) {
      return pw.Text(
        value.trim(),
        textDirection: runs.isEmpty ? baseDirection : runs.single.direction,
        textAlign: baseDirection == pw.TextDirection.rtl
            ? pw.TextAlign.right
            : pw.TextAlign.left,
        style: style,
      );
    }
    return pw.Directionality(
      textDirection: baseDirection,
      child: pw.Wrap(
        alignment: pw.WrapAlignment.start,
        crossAxisAlignment: pw.WrapCrossAlignment.center,
        spacing: 1.4,
        runSpacing: .4,
        children: [
          for (final run in runs)
            pw.Text(
              run.text.trim(),
              textDirection: run.direction,
              style: style,
            ),
        ],
      ),
    );
  }

  static List<_DirectionalRun> _directionalRuns(
    String value,
    pw.TextDirection fallback,
  ) {
    final runs = <_DirectionalRun>[];
    final buffer = StringBuffer();
    pw.TextDirection? currentDirection;

    void flush() {
      final text = buffer.toString().trim();
      if (text.isNotEmpty) {
        runs.add(_DirectionalRun(text, currentDirection ?? fallback));
      }
      buffer.clear();
    }

    for (final token in RegExp(
      r'\S+',
    ).allMatches(value).map((m) => m.group(0)!)) {
      final direction = _directionForToken(token, fallback);
      if (currentDirection != null && direction != currentDirection) flush();
      if (buffer.isNotEmpty) buffer.write(' ');
      buffer.write(token);
      currentDirection = direction;
    }
    flush();
    return runs;
  }

  static pw.TextDirection _directionForToken(
    String value,
    pw.TextDirection fallback,
  ) {
    for (final rune in value.runes) {
      if (_isArabicRune(rune)) return pw.TextDirection.rtl;
      if (_isLtrRune(rune)) return pw.TextDirection.ltr;
    }
    return fallback;
  }

  static bool _isArabicRune(int rune) {
    return (rune >= 0x0600 && rune <= 0x06ff) ||
        (rune >= 0x0750 && rune <= 0x077f) ||
        (rune >= 0x08a0 && rune <= 0x08ff) ||
        (rune >= 0xfb50 && rune <= 0xfdff) ||
        (rune >= 0xfe70 && rune <= 0xfeff);
  }

  static bool _isLtrRune(int rune) {
    return (rune >= 0x0030 && rune <= 0x0039) ||
        (rune >= 0x0041 && rune <= 0x005a) ||
        (rune >= 0x0061 && rune <= 0x007a);
  }

  static pw.Widget _localizedLabel({
    required String key,
    required AppPdfLocalization loc,
    required PdfColor color,
    required double fontSize,
    pw.FontWeight fontWeight = pw.FontWeight.normal,
    pw.CrossAxisAlignment? crossAxisAlignment,
  }) {
    return pw.Column(
      mainAxisSize: pw.MainAxisSize.min,
      crossAxisAlignment:
          crossAxisAlignment ??
          (loc.isArabic
              ? pw.CrossAxisAlignment.end
              : pw.CrossAxisAlignment.start),
      children: [
        pw.Text(
          loc.t(key),
          textDirection: loc.textDirection,
          style: pw.TextStyle(
            color: color,
            fontSize: fontSize,
            fontWeight: fontWeight,
          ),
        ),
      ],
    );
  }

  static pw.Widget _signatures(AppPdfLocalization loc) {
    return pw.Row(
      children: [
        pw.Expanded(child: _signatureLine('prepared_by', loc)),
        pw.SizedBox(width: 18),
        pw.Expanded(child: _signatureLine('signature', loc)),
      ],
    );
  }

  static pw.Widget _signatureLine(String labelKey, AppPdfLocalization loc) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.SizedBox(height: 22),
        pw.Container(height: .7, color: PdfColors.grey500),
        pw.SizedBox(height: 3),
        _localizedLabel(key: labelKey, loc: loc, color: _muted, fontSize: 6.5),
      ],
    );
  }
}

class _LabelValue {
  const _LabelValue(
    this.labelKey,
    this.value, {
    this.strong = false,
    this.forceLtr = false,
  });

  final String labelKey;
  final String value;
  final bool strong;
  final bool forceLtr;
}

class _DirectionalRun {
  const _DirectionalRun(this.text, this.direction);

  final String text;
  final pw.TextDirection direction;
}
