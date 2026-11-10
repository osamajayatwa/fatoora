import 'dart:io';

import 'package:fatoora/features/financial/data/models/settlement_details.dart';
import 'package:fatoora/features/financial/data/services/cash_report_pdf_service.dart';
import 'package:flutter_test/flutter_test.dart';

import 'settlement_details_test.dart' as fixtures;
import 'support/pdf_font_assertions.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final state in ['verified', 'blocked']) {
    for (final language in ['en', 'ar']) {
      test(
        'complete $state settlement PDF $language preserves totals status and embedded Arabic fonts',
        () async {
          final a = fixtures.assembly();
          for (final p in fixtures.pages(state)) {
            a.add(p);
          }
          final r = a.finish();
          final bytes = await CashReportPdfService.buildSettlementDetails(
            details: r,
            configuration: CashReportPdfService.settlementFixtureConfiguration(
              language,
            ),
            representativeLabel: 'أحمد عبد الرحمن — Ahmed Abdulrahman',
            settlementLabel: 'SET-2026-011',
          );
          expect(bytes.length, greaterThan(10000));
          expectPdfFontMetrics(
            bytes,
            await loadPdfSourceFonts(),
            context: '$state-$language',
          );
          final dir = Platform.environment['SETTLEMENT_PDF_DIR'];
          if (dir != null) {
            await Directory(dir).create(recursive: true);
            await File(
              '$dir/settlement-$state-$language.pdf',
            ).writeAsBytes(bytes);
          }
        },
      );
    }
  }
  for (final language in ['en', 'ar']) {
    test(
      'long unbroken identifiers and actor names remain printable $language',
      () async {
        final a = fixtures.assembly();
        for (var i = 0; i < 2; i++) {
          final p = fixtures.clonePage(i);
          if (i == 0) {
          p['rows'][1]['sourceNumber'] = (language == 'ar' ? 'م' : 'W') * 1500;
            p['rows'][1]['sourceCreator']['name'] = 'اسم طويل ' * 120;
          }
          fixtures.rehash(p);
          a.add(SettlementDetailPage.fromJson(p));
        }
        final bytes = await CashReportPdfService.buildSettlementDetails(
          details: a.finish(),
          configuration: CashReportPdfService.settlementFixtureConfiguration(
            language,
          ),
          representativeLabel: '${'W' * 600} ${'اسم طويل ' * 100}',
          settlementLabel: 'SET-${'W' * 600}',
        );
        expectPdfFontMetrics(
          bytes,
          await loadPdfSourceFonts(),
          context: 'long-$language',
        );
        final dir = Platform.environment['SETTLEMENT_PDF_STRESS_DIR'];
        if (dir != null) {
          await Directory(dir).create(recursive: true);
          await File('$dir/long-$language.pdf').writeAsBytes(bytes);
        }
      },
    );
  }
}
