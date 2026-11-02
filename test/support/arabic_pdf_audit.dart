import 'dart:io';

import 'package:fatoora/core/pdf/app_pdf_assets.dart';
import 'package:fatoora/core/pdf/app_pdf_direction.dart';
import 'package:pdf/widgets.dart' as pw;

import 'arabic_pdf_cases.dart';

Future<void> writeArabicGlyphAtlas(String path) async {
  final assets = await AppPdfAssets.load(loadLogo: false);
  final document = pw.Document(theme: assets.theme);
  for (final bold in [false, true]) {
    final style = pw.TextStyle(
      fontSize: 15,
      fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
    );
    document.addPage(
      pw.MultiPage(
        build: (_) => [
          pw.Text(
            'Arabic contextual forms - Cairo ${bold ? 'Bold' : 'Regular'}',
          ),
          pw.SizedBox(height: 12),
          pw.Table(
            children: [
              pw.TableRow(
                children: [
                  for (final label in [
                    'Base',
                    'Isolated',
                    'Final',
                    'Initial',
                    'Medial',
                  ])
                    pw.Text(label),
                ],
              ),
              for (final letter in arabicLetterForms.entries)
                pw.TableRow(
                  children: [
                    pw.Text('U+${letter.key.toRadixString(16).toUpperCase()}'),
                    for (final form in [
                      'isolated',
                      'final',
                      'initial',
                      'medial',
                    ])
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(3),
                        child: pw.Text(
                          !letter.value.containsKey(form)
                              ? '-'
                              : switch (form) {
                                  'final' =>
                                    'ب${String.fromCharCode(letter.key)}',
                                  'initial' =>
                                    '${String.fromCharCode(letter.key)}ب',
                                  'medial' =>
                                    'ب${String.fromCharCode(letter.key)}ب',
                                  _ => String.fromCharCode(letter.key),
                                },
                          textDirection: pw.TextDirection.rtl,
                          style: style,
                        ),
                      ),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }
  document.addPage(
    pw.MultiPage(
      build: (_) => [
        pw.Text('Customer-name samples - unchanged Cairo fonts'),
        AppPdfDirection.text(
          'لآ بلآ لأ بلأ لإ بلإ لا بلا',
          style: const pw.TextStyle(fontSize: 13),
        ),
        AppPdfDirection.text(
          'لآ بلآ لأ بلأ لإ بلإ لا بلا',
          style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
        ),
        for (var index = 0; index < arabicCustomerNames.length; index++)
          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(vertical: 5),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.stretch,
              children: [
                pw.Text('Case $index', style: const pw.TextStyle(fontSize: 7)),
                AppPdfDirection.text(
                  arabicCustomerNames[index],
                  style: pw.TextStyle(
                    fontSize: 13,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
      ],
    ),
  );
  await File(path).writeAsBytes(await document.save());
}
