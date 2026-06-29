import 'package:fatoora/core/pdf/app_pdf_assets.dart';
import 'package:fatoora/core/pdf/app_pdf_localization.dart';
import 'package:fatoora/core/pdf/business_pdf_configuration.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

class BusinessPdfWidgets {
  const BusinessPdfWidgets._();

  static pw.PageTheme pageTheme(AppPdfAssets assets) {
    return pw.PageTheme(
      margin: const pw.EdgeInsets.all(28),
      theme: assets.theme,
    );
  }

  static pw.Widget shell({
    required AppPdfAssets assets,
    required BusinessPdfConfiguration configuration,
    required String title,
    String? subtitle,
    required List<pw.Widget> children,
  }) {
    final loc = configuration.localization;
    return pw.Directionality(
      textDirection: loc.textDirection,
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          header(
            assets: assets,
            configuration: configuration,
            title: title,
            subtitle: subtitle,
          ),
          pw.SizedBox(height: 20),
          ...children,
        ],
      ),
    );
  }

  static pw.Widget header({
    required AppPdfAssets assets,
    required BusinessPdfConfiguration configuration,
    required String title,
    String? subtitle,
  }) {
    final loc = configuration.localization;
    final companySettings = configuration.companySettings;
    final company = configuration.showCompanyInfo
        ? pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: loc.startCrossAxis,
              children: [
                if (companySettings.name.trim().isNotEmpty)
                  pw.Text(
                    companySettings.name.trim(),
                    style: pw.TextStyle(
                      fontSize: 15,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                for (final value in [
                  companySettings.country,
                  companySettings.email,
                  companySettings.website,
                  companySettings.phone,
                  companySettings.address,
                ])
                  if (value.trim().isNotEmpty) pw.Text(value.trim()),
              ],
            ),
          )
        : null;
    final documentTitle = pw.Column(
      crossAxisAlignment: loc.isArabic
          ? pw.CrossAxisAlignment.start
          : pw.CrossAxisAlignment.end,
      children: [
        pw.Text(
          title,
          style: pw.TextStyle(fontSize: 19, fontWeight: pw.FontWeight.bold),
        ),
        if (subtitle != null && subtitle.trim().isNotEmpty)
          pw.Text(subtitle.trim(), style: const pw.TextStyle(fontSize: 10)),
      ],
    );
    final logo = configuration.showLogo && assets.logo != null
        ? pw.Image(assets.logo!, width: 62, height: 62, fit: pw.BoxFit.contain)
        : null;

    final rowChildren = loc.isArabic
        ? <pw.Widget>[
            documentTitle,
            if (company == null) pw.Spacer(),
            if (company != null) ...[pw.SizedBox(width: 16), company],
            if (logo != null) ...[pw.SizedBox(width: 12), logo],
          ]
        : <pw.Widget>[
            if (logo != null) ...[logo, pw.SizedBox(width: 12)],
            if (company != null) company,
            if (company == null) pw.Spacer(),
            if (company != null) pw.SizedBox(width: 16),
            documentTitle,
          ];

    return pw.Container(
      padding: const pw.EdgeInsets.only(bottom: 14),
      decoration: const pw.BoxDecoration(
        border: pw.Border(
          bottom: pw.BorderSide(color: PdfColors.grey400, width: 0.6),
        ),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: rowChildren,
      ),
    );
  }

  static pw.Widget sectionTitle(String title) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 8, top: 4),
      child: pw.Text(
        title,
        style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
      ),
    );
  }

  static pw.Widget infoGrid({
    required AppPdfLocalization loc,
    required List<PdfInfoItem> items,
  }) {
    return pw.Wrap(
      spacing: 10,
      runSpacing: 8,
      children: [
        for (final item in items)
          pw.Container(
            width: 246,
            padding: const pw.EdgeInsets.all(9),
            decoration: pw.BoxDecoration(
              color: PdfColors.grey100,
              borderRadius: pw.BorderRadius.circular(6),
              border: pw.Border.all(color: PdfColors.grey300, width: 0.5),
            ),
            child: pw.Column(
              crossAxisAlignment: loc.startCrossAxis,
              children: [
                pw.Text(
                  item.label,
                  style: const pw.TextStyle(
                    fontSize: 8,
                    color: PdfColors.grey700,
                  ),
                ),
                pw.SizedBox(height: 2),
                pw.Text(
                  item.value.trim().isEmpty ? '-' : item.value.trim(),
                  style: pw.TextStyle(
                    fontSize: 10,
                    fontWeight: item.bold
                        ? pw.FontWeight.bold
                        : pw.FontWeight.normal,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  static pw.Widget table({
    required AppPdfLocalization loc,
    required List<String> headers,
    required List<List<String>> data,
    double fontSize = 8,
  }) {
    final displayHeaders = loc.isArabic
        ? headers.reversed.toList(growable: false)
        : headers;
    final displayData = loc.isArabic
        ? data
              .map((row) => row.reversed.toList(growable: false))
              .toList(growable: false)
        : data;
    final alignment = loc.isArabic
        ? pw.Alignment.centerRight
        : pw.Alignment.centerLeft;

    return pw.TableHelper.fromTextArray(
      headers: displayHeaders,
      data: displayData,
      border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.35),
      headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
      headerStyle: pw.TextStyle(
        fontSize: fontSize,
        fontWeight: pw.FontWeight.bold,
      ),
      cellStyle: pw.TextStyle(fontSize: fontSize),
      headerAlignment: alignment,
      cellAlignment: alignment,
      cellPadding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 4),
    );
  }

  static pw.Widget totals({
    required AppPdfLocalization loc,
    required List<PdfInfoItem> rows,
  }) {
    return pw.Align(
      alignment: loc.isArabic
          ? pw.Alignment.centerLeft
          : pw.Alignment.centerRight,
      child: pw.Container(
        width: 245,
        padding: const pw.EdgeInsets.all(10),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: PdfColors.grey300, width: 0.5),
          borderRadius: pw.BorderRadius.circular(6),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            for (final row in rows)
              pw.Padding(
                padding: const pw.EdgeInsets.symmetric(vertical: 2),
                child: pw.Row(
                  children: loc.isArabic
                      ? [
                          pw.Text(
                            row.value,
                            style: pw.TextStyle(
                              fontWeight: row.bold
                                  ? pw.FontWeight.bold
                                  : pw.FontWeight.normal,
                            ),
                          ),
                          pw.Spacer(),
                          pw.Text(row.label),
                        ]
                      : [
                          pw.Text(row.label),
                          pw.Spacer(),
                          pw.Text(
                            row.value,
                            style: pw.TextStyle(
                              fontWeight: row.bold
                                  ? pw.FontWeight.bold
                                  : pw.FontWeight.normal,
                            ),
                          ),
                        ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  static pw.Widget notes({
    required AppPdfLocalization loc,
    required String title,
    required String text,
  }) {
    if (text.trim().isEmpty) return pw.SizedBox.shrink();
    return pw.Column(
      crossAxisAlignment: loc.startCrossAxis,
      children: [
        sectionTitle(title),
        pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.all(10),
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: PdfColors.grey300, width: 0.5),
            borderRadius: pw.BorderRadius.circular(6),
          ),
          child: pw.Text(
            text.trim(),
            textAlign: loc.isArabic ? pw.TextAlign.right : pw.TextAlign.left,
          ),
        ),
      ],
    );
  }

  static pw.Widget footer({
    required AppPdfLocalization loc,
    required String text,
  }) {
    if (text.trim().isEmpty) return pw.SizedBox.shrink();
    return pw.Container(
      width: double.infinity,
      margin: const pw.EdgeInsets.only(top: 14),
      padding: const pw.EdgeInsets.only(top: 8),
      decoration: const pw.BoxDecoration(
        border: pw.Border(
          top: pw.BorderSide(color: PdfColors.grey400, width: 0.5),
        ),
      ),
      child: pw.Align(
        alignment: loc.startAlignment,
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              loc.t('pdf_footer'),
              style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 3),
            pw.Text(
              text.trim(),
              textAlign: loc.isArabic ? pw.TextAlign.right : pw.TextAlign.left,
              style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
            ),
          ],
        ),
      ),
    );
  }

  static pw.Widget qrCode(String data) {
    return pw.BarcodeWidget(
      barcode: pw.Barcode.qrCode(),
      data: data,
      width: 92,
      height: 92,
      drawText: false,
    );
  }

  static pw.Widget signatures(AppPdfLocalization loc) {
    return pw.Row(
      children: [
        pw.Expanded(child: signatureLine(loc.t('prepared_by'))),
        pw.SizedBox(width: 18),
        pw.Expanded(child: signatureLine(loc.t('signature'))),
      ],
    );
  }

  static pw.Widget signatureLine(String label) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.SizedBox(height: 26),
        pw.Container(height: 0.7, color: PdfColors.grey500),
        pw.SizedBox(height: 4),
        pw.Text(label, style: const pw.TextStyle(fontSize: 9)),
      ],
    );
  }
}

class PdfInfoItem {
  const PdfInfoItem(this.label, this.value, {this.bold = false});

  final String label;
  final String value;
  final bool bold;
}
