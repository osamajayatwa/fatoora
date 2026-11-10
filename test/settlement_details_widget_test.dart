import 'dart:io';
import 'dart:ui' as ui;

import 'package:fatoora/core/constants/app.dart';
import 'package:fatoora/core/localization/translation.dart';
import 'package:fatoora/core/services/services.dart';
import 'package:fatoora/features/admin_dashboard/view/widgets/dashboard_card.dart';
import 'package:fatoora/features/financial/controllers/cash_movements_controller.dart';
import 'package:fatoora/features/financial/data/models/cash_movement_model.dart';
import 'package:fatoora/features/financial/data/models/financial_dashboard_snapshot.dart';
import 'package:fatoora/features/financial/data/models/settlement_details.dart';
import 'package:fatoora/features/financial/data/repositories/financial_repository.dart';
import 'package:fatoora/features/financial/data/services/settlement_details_fixtures.dart';
import 'package:fatoora/features/financial/data/services/settlement_details_formatter.dart';
import 'package:fatoora/features/financial/view/screens/cash_movements_screen.dart';
import 'package:fatoora/features/financial/view/widgets/settlement_details_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'settlement_details_test.dart' as fixtures;

Future<void> screenshot(WidgetTester tester, String name) async {
  final path = Platform.environment['SETTLEMENT_WIDGET_DIR'];
  if (path == null) return;
  await tester.runAsync(() async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const ValueKey('settlement-visual')),
    );
    final image = await boundary.toImage(pixelRatio: 1),
        bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await Directory(path).create(recursive: true);
    await File('$path/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

Future<void> pumpPreview(
  WidgetTester tester,
  Size size,
  String language,
  double scale,
  SettlementDetailsSource source,
) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    RepaintBoundary(
      key: const ValueKey('settlement-visual'),
      child: GetMaterialApp(
        debugShowCheckedModeBanner: false,
        locale: Locale(language),
        theme: AppTheme.light(fontFamily: 'Cairo'),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(12),
            child: DashboardCard(
              child: SettlementDetailsPanel(
                fixtures: source,
                arabic: language == 'ar',
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> tapLoad(WidgetTester tester) async {
  final button = find.byKey(const ValueKey('settlement-load-page'));
  await tester.ensureVisible(button);
  await tester.tap(button);
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    for (final weight in ['Regular', 'Bold']) {
      await (FontLoader('Cairo')
            ..addFont(rootBundle.load('assets/fonts/Cairo/Cairo-$weight.ttf')))
          .load();
    }
  });
  tearDown(Get.reset);
  for (final language in ['en', 'ar']) {
    testWidgets('existing design system $language settlement visual evidence', (
      tester,
    ) async {
      final fmt = SettlementDetailsFormatter(arabic: language == 'ar');
      await pumpPreview(
        tester,
        Size(language == 'ar' ? 768 : 1366, 1100),
        language,
        1,
        SettlementDetailsFixtures.fromJson(
          fixtures.settlementFixture('verified'),
        ),
      );
      await tapLoad(tester);
      await tapLoad(tester);
      await tester.ensureVisible(find.text(fmt.t('title')));
      await tester.pumpAndSettle();
      await screenshot(tester, 'showcase-$language');
      expect(tester.takeException(), isNull);
    });
  }
  for (final language in ['en', 'ar']) {
    for (final width in [320.0, 768.0, 1366.0]) {
      for (final scale in [1.0, 2.0]) {
        testWidgets(
          '$language ${width.toInt()}px scale $scale retains exact details without overflow',
          (tester) async {
            final raw = fixtures.settlementFixture('verified');
            raw['representativeLabel'] =
                '${raw['representativeLabel']} ${'اسم طويل / Long name ' * 8}';
            final source = SettlementDetailsFixtures.fromJson(raw),
                fmt = SettlementDetailsFormatter(arabic: language == 'ar');
            await pumpPreview(
              tester,
              Size(width, 900),
              language,
              scale,
              source,
            );
            await tapLoad(tester);
            expect(find.text('JOD 99.940'), findsNothing);
            expect(find.text(fmt.t('incomplete')), findsOneWidget);
            await tapLoad(tester);
            expect(find.text('JOD 99.940'), findsWidgets);
            expect(find.text(fmt.t('verified')), findsOneWidget);
            await tester.ensureVisible(find.text(fmt.t('title')));
            await tester.pumpAndSettle();
            await screenshot(
              tester,
              '$language-${width.toInt()}-${scale.toInt()}-summary',
            );
            await tester.ensureVisible(find.text(fmt.t('remainingUnits')));
            await tester.pumpAndSettle();
            await screenshot(
              tester,
              '$language-${width.toInt()}-${scale.toInt()}-totals',
            );
            final current = find.byKey(
              const ValueKey('settlement-row-current_rep_out'),
            );
            await tester.ensureVisible(current);
            await tester.tap(current);
            await tester.pumpAndSettle();
            expect(
              find.textContaining(
                'companies/synthetic-phase2b11/settlements/current',
              ),
              findsWidgets,
            );
            expect(tester.takeException(), isNull);
            await screenshot(
              tester,
              '$language-${width.toInt()}-${scale.toInt()}-row',
            );
          },
        );
      }
    }
  }
  testWidgets(
    'loading and retryable page errors retain evidence without exposing certified totals',
    (tester) async {
      final source = SettlementDetailsFixtures.fromJson(
        fixtures.settlementFixture('verified'),
        latency: const Duration(milliseconds: 300),
        failFirstReads: {1},
      );
      await pumpPreview(tester, const Size(390, 840), 'en', 1, source);
      final button = find.byKey(const ValueKey('settlement-load-page'));
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pump();
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      await tester.pumpAndSettle();
      await tapLoad(tester);
      expect(find.text('Retry page'), findsOneWidget);
      expect(find.text('JOD 99.940'), findsNothing);
      await tapLoad(tester);
      expect(find.text('JOD 99.940'), findsWidgets);
      expect(tester.takeException(), isNull);
    },
  );
  for (final state in ['blocked', 'incomplete']) {
    testWidgets(
      '$state evidence suppresses totals and keeps an explicit warning',
      (tester) async {
        await pumpPreview(
          tester,
          const Size(320, 840),
          'ar',
          2,
          SettlementDetailsFixtures.fromJson(fixtures.settlementFixture(state)),
        );
        await tapLoad(tester);
        if (state == 'blocked') {
          await tapLoad(tester);
        }
        expect(find.text('JOD 99.940'), findsNothing);
        expect(find.textContaining('غير'), findsWidgets);
        expect(tester.takeException(), isNull);
      },
    );
  }
  for (final width in [390.0, 1366.0]) {
    testWidgets(
      'existing cash ${width.toInt()}px settlement details embed the injected preview',
      (tester) async {
        await tester.binding.setSurfaceSize(Size(width, 900));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        SharedPreferences.setMockInitialValues({
          'companyId': 'synthetic-phase2b11',
          'role': 'admin',
          'uid': 'synthetic-administrator',
        });
        final services = await MyServices().init();
        Get.put<MyServices>(services);
        final controller = CashMovementsController(
          repository: _CashFake(),
          myServices: services,
          settlementDetailsFixtures: SettlementDetailsFixtures.fromJson(
            fixtures.settlementFixture('verified'),
          ),
        );
        Get.put(controller);
        await tester.pumpWidget(
          GetMaterialApp(
            debugShowCheckedModeBanner: false,
            locale: const Locale('en'),
            translations: MyTranslation(),
            home: const CashMovementsScreen(),
          ),
        );
        await tester.pumpAndSettle();
        if (width > 900) {
          await tester.tap(find.byKey(const ValueKey('cash-open-rep-out')));
          await tester.pumpAndSettle();
        }
        expect(find.byType(SettlementDetailsPanel), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
  test(
    'preview injection is absent by default, gated by admin/company/settlement, and never bound into production',
    () async {
      final source = SettlementDetailsFixtures.fromJson(
        fixtures.settlementFixture('verified'),
      );
      for (final role in ['admin', 'sales_rep']) {
        SharedPreferences.setMockInitialValues({
          'companyId': source.companyId,
          'role': role,
        });
        final services = await MyServices().init();
        final normal = CashMovementsController(
          repository: _CashFake(),
          myServices: services,
        );
        expect(normal.settlementDetailsFor('current'), isNull);
        final injected = CashMovementsController(
          repository: _CashFake(),
          myServices: services,
          settlementDetailsFixtures: source,
        );
        expect(
          injected.settlementDetailsFor('current'),
          role == 'admin' ? isNotNull : isNull,
        );
        expect(injected.settlementDetailsFor('other'), isNull);
        await services.sharedPreferences.setString(
          'companyId',
          'other-company',
        );
        expect(injected.settlementDetailsFor('current'), isNull);
      }
      expect(
        File(
          'lib/features/financial/controllers/cash_movements_controller.dart',
        ).readAsStringSync(),
        contains('!kReleaseMode'),
      );
      expect(
        File(
          'lib/features/financial/bindings/financial_binding.dart',
        ).readAsStringSync(),
        isNot(contains('settlementDetailsFixtures')),
      );
      expect(
        File('pubspec.yaml').readAsStringSync(),
        isNot(contains('test/fixtures/settlement_details')),
      );
    },
  );
}

class _CashFake implements FinancialRepository {
  @override
  Future<FinancialCashPage> fetchCashPage({
    String companyId = 'default_company',
    DateTime? fromDate,
    DateTime? toDate,
    dynamic after,
    int pageSize = 50,
  }) async => FinancialCashPage(
    snapshot: FinancialCashSnapshot(
      movements: [
        for (final rep in [true, false])
          CashMovementModel(
            id: rep ? 'rep-out' : 'company-in',
            companyId: companyId,
            salesRepId: 'synthetic-representative',
            salesRepName: 'Synthetic representative',
            type: 'settlement_to_admin',
            movementType: 'settlement',
            direction: rep ? 'out' : 'in',
            amount: 10,
            referenceId: 'current',
            referenceNumber: 'SET-2026-011',
            sourceCollection: 'settlements',
            sourceId: 'current',
            sourceNumber: 'SET-2026-011',
            customerId: '',
            customerName: '',
            date: DateTime(2026, 11, 9),
            notes: '',
            cashAccount: rep ? 'rep_cash' : 'company_cash',
            settlementId: 'current',
            createdByUid: 'synthetic-administrator',
            createdByName: 'Synthetic administrator',
            createdByRole: 'admin',
            createdAt: DateTime(2026, 11, 9),
          ),
      ],
      cashInHand: 80,
      totalIn: 10,
      totalOut: 10,
      cashBySalesRep: const [],
    ),
    cursor: null,
    hasMore: false,
  );
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
