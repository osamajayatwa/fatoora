import 'package:fatoora/core/pdf/app_pdf_assets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'support/arabic_pdf_cases.dart';
import 'support/pdf_font_assertions.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Map<String, TtfParser> sourceFonts;
  setUpAll(() async {
    sourceFonts = await loadPdfSourceFonts();
  });

  for (final bold in [false, true]) {
    test('all Cairo Arabic glyph forms have correct widths ($bold)', () async {
      final assets = await AppPdfAssets.load(loadLogo: false);
      final data = await rootBundle.load(
        'assets/fonts/Cairo/Cairo-${bold ? 'Bold' : 'Regular'}.ttf',
      );
      final source = TtfParser(data);
      final document = pw.Document();
      final font = (bold ? assets.boldFont : assets.regularFont).getFont(
        pw.Context(document: document.document),
      );
      for (final letter in arabicLetterForms.entries) {
        for (final form in letter.value.entries) {
          final expectedGlyph =
              source.charToGlyphIndexMap[form.key == 'isolated'
                  ? letter.key
                  : form.value];
          final expected = source.glyphInfoMap[expectedGlyph]!;
          final actual = font.glyphMetrics(form.value);
          final reason = 'U+${letter.key.toRadixString(16)} ${form.key}';
          expect(font.isRuneSupported(form.value), isTrue, reason: reason);
          expect(actual.advanceWidth, greaterThan(0), reason: reason);
          expect(actual.advanceWidth, expected.advanceWidth, reason: reason);
          expect(actual.top, expected.top, reason: reason);
          expect(actual.bottom, expected.bottom, reason: reason);
        }
      }
    });

    test('Cairo shapes every Arabic letter in context ($bold)', () async {
      final assets = await AppPdfAssets.load(loadLogo: false);
      for (final letter in arabicLetterForms.entries) {
        final character = String.fromCharCode(letter.key);
        for (final form in letter.value.entries) {
          final sample = switch (form.key) {
            'initial' => '$characterب',
            'medial' => 'ب$characterب',
            'final' => 'ب$character',
            _ => character,
          };
          final document = pw.Document(theme: assets.theme);
          final font =
              (bold ? assets.boldFont : assets.regularFont).getFont(
                    pw.Context(document: document.document),
                  )
                  as PdfTtfFont;
          document.addPage(
            pw.Page(
              build: (_) => pw.Text(
                sample,
                textDirection: pw.TextDirection.rtl,
                style: pw.TextStyle(
                  font: bold ? assets.boldFont : assets.regularFont,
                ),
              ),
            ),
          );
          final bytes = await document.save();
          expectPdfFontMetrics(bytes, sourceFonts);
          expect(
            font.unicodeCMap.cmap,
            contains(form.value),
            reason: 'U+${letter.key.toRadixString(16)} ${form.key}',
          );
        }
      }
    });

    test(
      'Cairo embeds aliases and lam-alef ligatures correctly ($bold)',
      () async {
        final assets = await AppPdfAssets.load(loadLogo: false);
        final style = pw.TextStyle(
          font: bold ? assets.boldFont : assets.regularFont,
        );
        final alphabet = arabicLetterForms.keys
            .map(String.fromCharCode)
            .join(' ');
        final document = pw.Document(theme: assets.theme);
        final font =
            style.font!.getFont(pw.Context(document: document.document))
                as PdfTtfFont;
        document.addPage(
          pw.Page(
            build: (_) => pw.Column(
              children: [
                pw.Text(
                  alphabet,
                  textDirection: pw.TextDirection.ltr,
                  style: style,
                ),
                pw.Text(
                  alphabet,
                  textDirection: pw.TextDirection.rtl,
                  style: style,
                ),
                pw.Text(
                  'لآ لآ بلآ لأ بلأ لإ بلإ لا بلا',
                  textDirection: pw.TextDirection.rtl,
                  style: style,
                ),
              ],
            ),
          ),
        );
        expectPdfFontMetrics(await document.save(), sourceFonts);
        for (var form = 0xfef5; form <= 0xfefc; form++) {
          expect(font.unicodeCMap.cmap, contains(form));
          expect(font.glyphMetrics(form).advanceWidth, greaterThan(0));
        }
      },
    );

    test(
      'Cairo ${bold ? 'bold' : 'regular'} preserves isolated yeh width',
      () async {
        final assets = await AppPdfAssets.load(loadLogo: false);
        final document = pw.Document();
        final context = pw.Context(document: document.document);
        final font = (bold ? assets.boldFont : assets.regularFont).getFont(
          context,
        );

        // The last yeh in "رامي الجعيدي" is isolated after the dal. The PDF
        // shaper emits U+FEF1; it must occupy the same width as U+064A.
        final isolatedYeh = font.glyphMetrics(0xfef1);
        final yeh = font.glyphMetrics(0x064a);
        expect(font.isRuneSupported(0xfef1), isTrue);
        expect(isolatedYeh.advanceWidth, greaterThan(0));
        expect(isolatedYeh.advanceWidth, closeTo(yeh.advanceWidth, .00001));

        // U+FEEF is alef maksura, not yeh: it must keep the dotless glyph.
        final isolatedAlefMaksura = font.glyphMetrics(0xfeef);
        final alefMaksura = font.glyphMetrics(0x0649);
        expect(isolatedAlefMaksura.advanceWidth, alefMaksura.advanceWidth);
        expect(isolatedAlefMaksura.top, alefMaksura.top);

        // Diacritics remain zero-width; fixing yeh must not space out marks.
        expect(font.glyphMetrics(0x064e).advanceWidth, 0);
        expect(font.glyphMetrics(0x0650).advanceWidth, 0);
      },
    );
  }
}
