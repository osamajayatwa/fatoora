import 'package:fatoora/core/localization/translation.dart';
import 'package:fatoora/core/services/services.dart';
import 'package:fatoora/features/financial_ledger/controllers/financial_ledger_controller.dart';
import 'package:fatoora/features/financial_ledger/data/models/financial_ledger_entry.dart';
import 'package:fatoora/features/financial_ledger/data/models/financial_ledger_filters.dart';
import 'package:fatoora/features/financial_ledger/data/models/financial_ledger_summary.dart';
import 'package:fatoora/features/financial_ledger/data/repositories/financial_ledger_repository.dart';
import 'package:fatoora/features/financial_ledger/data/services/financial_ledger_excel_service.dart';
import 'package:fatoora/features/financial_ledger/view/screens/financial_ledger_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(Get.reset);

  testWidgets('320px 2x ledger keeps compact filters and entry card', (
    tester,
  ) async {
    await _pumpLedger(tester, const Size(320, 640), textScale: 2);
    expect(find.byKey(const ValueKey('ledger-search')), findsOneWidget);
    expect(find.byKey(const ValueKey('ledger-filter-button')), findsOneWidget);
    expect(find.byType(DataTable), findsNothing);
    expect(find.textContaining('JOD 25.000'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Arabic RTL compact ledger does not overflow', (tester) async {
    await _pumpLedger(
      tester,
      const Size(320, 640),
      textScale: 2,
      locale: const Locale('ar'),
    );
    expect(find.byKey(const ValueKey('ledger-filter-button')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('filter sheet preserves server filter set and applies once', (
    tester,
  ) async {
    final repo = _LedgerRepoFake();
    final controller = await _pumpLedger(
      tester,
      const Size(390, 800),
      repo: repo,
    );
    await tester.tap(find.byKey(const ValueKey('ledger-filter-button')));
    await tester.pumpAndSettle();
    expect(find.text('Sales representative'), findsWidgets);
    await tester.ensureVisible(find.text('Apply filters'));
    await tester.tap(find.text('Apply filters'));
    await tester.pumpAndSettle();
    expect(repo.pageCalls, 2);
    controller.setType('receipt');
    await tester.pumpAndSettle();
    expect(repo.lastFilters?.type, 'receipt');
    expect(controller.filters.indexedQueryKey, startsWith('v3:'));
  });

  testWidgets('desktop table retains all ledger columns', (tester) async {
    await _pumpLedger(tester, const Size(1600, 900));
    expect(find.byType(DataTable, skipOffstage: false), findsOneWidget);
    expect(find.text('Representative One'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Load More failure is inline and retry appends', (tester) async {
    final repo = _LedgerRepoFake(paged: true);
    final controller = await _pumpLedger(
      tester,
      const Size(390, 800),
      repo: repo,
    );
    repo.failNextPage = true;
    await controller.loadMore();
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('ledger-load-more-error')),
      findsOneWidget,
    );
    repo.failNextPage = false;
    await controller.loadMore();
    await tester.pumpAndSettle();
    expect(controller.entries, hasLength(2));
  });
}

Future<FinancialLedgerController> _pumpLedger(
  WidgetTester tester,
  Size size, {
  Locale locale = const Locale('en'),
  double textScale = 1,
  _LedgerRepoFake? repo,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  SharedPreferences.setMockInitialValues({
    'companyId': 'default_company',
    'role': 'admin',
    'uid': 'admin-1',
  });
  Get.reset();
  final services = await MyServices().init();
  Get.put<MyServices>(services);
  final controller = FinancialLedgerController(
    repository: repo ?? _LedgerRepoFake(),
    excelService: _ExcelFake(),
    myServices: services,
  );
  Get.put<FinancialLedgerController>(controller);
  await tester.pumpWidget(
    GetMaterialApp(
      locale: locale,
      translations: MyTranslation(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: const FinancialLedgerScreen(),
    ),
  );
  await tester.pumpAndSettle();
  return controller;
}

class _LedgerRepoFake implements FinancialLedgerRepository {
  _LedgerRepoFake({this.paged = false});
  final bool paged;
  int pageCalls = 0;
  bool failNextPage = false;
  FinancialLedgerFilters? lastFilters;

  @override
  Future<FinancialLedgerPage> fetchPage({
    required String companyId,
    required FinancialLedgerFilters filters,
    FinancialLedgerCursor? after,
    int pageSize = 40,
  }) async {
    pageCalls++;
    lastFilters = filters;
    if (after != null && failNextPage) throw StateError('Page unavailable');
    return FinancialLedgerPage(
      entries: [_entry(after == null ? 'entry-1' : 'entry-2')],
      cursor: paged && after == null
          ? FinancialLedgerCursor(
              occurredAt: DateTime(2026, 9, 23),
              id: 'entry-1',
            )
          : null,
      hasMore: paged && after == null,
    );
  }

  @override
  Future<FinancialLedgerSummary> fetchSummary({
    required String companyId,
    required FinancialLedgerFilters filters,
  }) async => const FinancialLedgerSummary(entryCount: 1, sales: 25);

  @override
  Future<FinancialLedgerLookups> fetchLookups(String companyId) async =>
      const FinancialLedgerLookups(representatives: [], customers: []);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ExcelFake implements FinancialLedgerExcelService {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

FinancialLedgerEntry _entry(String id) => FinancialLedgerEntry.fromMap({
  'id': id,
  'occurredAt': DateTime(2026, 9, 23),
  'type': 'receipt',
  'description': 'Receipt payment',
  'amount': 25,
  'debitAccountKey': 'company_cash',
  'creditAccountKey': 'customer:1',
  'customerName': 'Acme Pumps',
  'salesRepName': 'Representative One',
  'referenceType': 'receipt',
  'referenceId': 'receipt-1',
  'referenceNumber': 'REC-001',
});
