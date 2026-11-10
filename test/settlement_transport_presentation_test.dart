import 'dart:io';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:fatoora/features/financial/data/services/cash_report_pdf_service.dart';
import 'package:fatoora/features/financial/data/services/settlement_details_formatter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import 'settlement_transport_test.dart' show SettlementWireHarness;
import 'settlement_details_widget_test.dart' as preview;
import 'support/pdf_font_assertions.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    for (final font in ['Regular', 'Bold']) {
      await (FontLoader(
        'Cairo',
      )..addFont(rootBundle.load('assets/fonts/Cairo/Cairo-$font.ttf'))).load();
    }
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  tearDown(Get.reset);
  for (final lang in ['en', 'ar']) {
    for (final dimensions in [(320.0, 2.0), (768.0, 1.0), (1366.0, 1.0)]) {
      testWidgets(
        'authenticated $lang ${dimensions.$1}px ${dimensions.$2}x details and revocation remain responsive',
        (tester) async {
          final h = SettlementWireHarness()..batchSize = 2;
          final source = h.source(),
              fmt = SettlementDetailsFormatter(arabic: lang == 'ar');
          await preview.pumpPreview(
            tester,
            Size(dimensions.$1, 1000),
            lang,
            dimensions.$2,
            source,
          );
          final load = find.byKey(const ValueKey('settlement-load-all'));
          await tester.ensureVisible(load);
          await tester.tap(load);
          await tester.pumpAndSettle();
          expect(find.text(fmt.t('authenticated')), findsOneWidget);
          expect(find.text(fmt.t('fixture')), findsNothing);
          expect(find.text(fmt.t('verified')), findsOneWidget);
          expect(
            tester
                .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, '1'))
                .selected,
            isTrue,
          );
          final expected = fmt.money(
            h.report().certifiedTotals!['remainingUnits'],
            'JOD',
          );
          expect(find.text(expected), findsWidgets);
          expect(tester.takeException(), isNull);
          await Scrollable.ensureVisible(
            tester.element(find.text(fmt.t('title'))),
            alignment: .04,
          );
          await tester.pumpAndSettle();
          await _capture(
            tester,
            'authenticated-$lang-${dimensions.$1.toInt()}-${dimensions.$2.toInt()}',
          );
          h.denied = true;
          await expectLater(source.authorizePdf(h.report()), throwsA(anything));
          await tester.pumpAndSettle();
          expect(find.text(expected), findsNothing);
          expect(find.text(fmt.t('denied')), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
      );
    }
    for (final status in ['verified', 'blocked']) {
      test(
        'authenticated $status $lang PDF retains exact report and provenance',
        () async {
          final h = SettlementWireHarness();
          if (status == 'blocked') {
            h.data
              ..clear()
              ..addAll(
                jsonDecode(
                      File(
                        'test/fixtures/settlement_transport_blocked_emulator.json',
                      ).readAsStringSync(),
                    )
                    as Map<String, dynamic>,
              );
          }
          final source = h.source(), a = h.assembly();
          for (var i = 0; i < (h.data['pages'] as List).length; i++) {
            a.add(await source.read(i));
          }
          final report = a.finish();
          expect(report.verified, status == 'verified');
          await source.authorizePdf(report);
          final bytes = await CashReportPdfService.buildSettlementDetails(
            details: report,
            configuration: CashReportPdfService.settlementFixtureConfiguration(
              lang,
            ),
            representativeLabel: source.representativeLabel,
            settlementLabel: source.settlementLabel,
          );
          source.requirePdfPermission(report);
          expectPdfFontMetrics(
            bytes,
            await loadPdfSourceFonts(),
            context: 'authenticated-$status-$lang',
          );
          final dir = Platform.environment['SETTLEMENT_AUTH_PDF_DIR'];
          if (dir != null) {
            await Directory(dir).create(recursive: true);
            await File(
              '$dir/settlement-authenticated-$status-$lang.pdf',
            ).writeAsBytes(bytes);
          }
        },
      );
    }
  }
}

Future<void> _capture(WidgetTester tester, String name) async {
  final dir = Platform.environment['SETTLEMENT_TRANSPORT_WIDGET_DIR'];
  if (dir == null) return;
  await tester.runAsync(() async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const ValueKey('settlement-visual')),
    );
    final image = await boundary.toImage(pixelRatio: 1),
        bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await Directory(dir).create(recursive: true);
    await File('$dir/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}
