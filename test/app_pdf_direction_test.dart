import 'package:fatoora/core/pdf/app_pdf_direction.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;

void main() {
  group('AppPdfDirection', () {
    test('detects Arabic and Latin content independently', () {
      expect(AppPdfDirection.hasArabic('شركة حلول المياه'), isTrue);
      expect(AppPdfDirection.hasArabic('FDSS 4SP-10'), isFalse);
      expect(AppPdfDirection.hasLatinOrDigit('FDSS 4SP-10'), isTrue);
      expect(AppPdfDirection.hasLatinOrDigit('شركة'), isFalse);
    });

    test('uses RTL direction for mixed Arabic text with model codes', () {
      const value = 'مضخة غاطسة FDSS 4SP-10 / 50FCL16-75';

      expect(AppPdfDirection.directionOf(value), pw.TextDirection.rtl);
    });

    test('keeps English-only model codes LTR', () {
      const value = 'FDSS 4SP-10 / 50FCL16-75';

      expect(AppPdfDirection.directionOf(value), pw.TextDirection.ltr);
    });
  });
}
