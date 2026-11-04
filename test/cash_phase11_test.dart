import 'dart:async';

import 'package:fatoora/core/data/firestore_query_pager.dart';
import 'package:fatoora/core/localization/translation.dart';
import 'package:fatoora/core/services/services.dart';
import 'package:fatoora/features/financial/controllers/cash_movements_controller.dart';
import 'package:fatoora/features/financial/data/models/cash_movement_model.dart';
import 'package:fatoora/features/financial/data/models/financial_dashboard_snapshot.dart';
import 'package:fatoora/features/financial/data/repositories/financial_repository.dart';
import 'package:fatoora/features/financial/view/screens/cash_movements_screen.dart';
import 'package:fatoora/features/financial/view/widgets/cash_movement_presentation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(Get.reset);

  test('only verified settlement sides are paired', () {
    final repOut = _movement(
      'rep-out',
      direction: 'out',
      account: CashMovementModel.repCashAccount,
    );
    final companyIn = _movement(
      'company-in',
      direction: 'in',
      account: CashMovementModel.companyCashAccount,
    );
    final groups = cashMovementPresentationGroups([repOut, companyIn]);
    expect(groups, hasLength(1));
    expect(groups.single.map((item) => item.id), ['rep-out', 'company-in']);
    expect(cashMovementPresentationGroups([repOut]), hasLength(1));
    expect(cashMovementPresentationGroups([repOut]).single, hasLength(1));
    expect(cashAccountLabelKey(repOut), 'ledger_rep_cash');
    expect(cashAccountLabelKey(companyIn), 'financial_company_cash');
  });

  testWidgets('Admin 320px sees both settlement sides and separate balances', (
    tester,
  ) async {
    await _pumpCash(tester, const Size(320, 640), role: 'admin', textScale: 2);
    expect(find.text('Company cash'), findsWidgets);
    expect(find.textContaining('Representative cash (rep-1)'), findsWidgets);
    expect(find.textContaining('-JOD 50.000'), findsOneWidget);
    expect(find.textContaining('+JOD 50.000'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Rep 320px only sees own cash view and textual OUT', (
    tester,
  ) async {
    await _pumpCash(
      tester,
      const Size(320, 640),
      role: 'sales_rep',
      textScale: 2,
      oneSided: true,
    );
    expect(find.text('Representative cash'), findsWidgets);
    expect(find.text('Company cash'), findsNothing);
    expect(find.text('OUT'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Admin desktop table keeps direction, account and reference', (
    tester,
  ) async {
    await _pumpCash(tester, const Size(1366, 900), role: 'admin');
    expect(find.byType(DataTable), findsOneWidget);
    expect(find.text('OUT'), findsOneWidget);
    expect(find.text('IN'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Load More failure remains retryable inline', (tester) async {
    final repo = _CashRepoFake(paged: true);
    final controller = await _pumpCash(
      tester,
      const Size(390, 800),
      repo: repo,
    );
    repo.failPage = true;
    await controller.loadMore();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('cash-load-more-error')), findsOneWidget);
    repo.failPage = false;
    await controller.loadMore();
    await tester.pumpAndSettle();
    expect(controller.snapshot.movements, hasLength(3));
  });

  testWidgets('paging retries deduplicate IDs and retain full-scope balances', (
    tester,
  ) async {
    final repo = _CashRepoFake(paged: true, duplicatePage: true);
    final controller = await _pumpCash(
      tester,
      const Size(390, 800),
      repo: repo,
    );
    final reported = {
      'closingBalance': BigInt.from(123456),
      'openingBalance': null,
    };
    repo.reported = reported;
    await controller.loadCash();
    await controller.loadMore();
    await controller.loadMore();
    expect(
      controller.snapshot.movements.map((m) => m.id).toSet(),
      hasLength(3),
    );
    expect(controller.snapshot.movements, hasLength(3));
    expect(controller.snapshot.units('closingBalance'), BigInt.from(123456));
    expect(controller.snapshot.units('openingBalance'), isNull);
    expect(controller.snapshot.totalIn, 50);
  });

  testWidgets('date changes reset paging and discard an older in-flight page', (
    tester,
  ) async {
    final repo = _CashRepoFake(paged: true);
    final controller = await _pumpCash(
      tester,
      const Size(390, 800),
      repo: repo,
    );
    repo.delayedPage = Completer<void>();
    final oldPage = controller.loadMore();
    controller.setDateRange(DateTime(2026, 11, 1), DateTime(2026, 11, 4));
    await tester.pump();
    expect(repo.lastFrom, DateTime(2026, 11, 1));
    expect(repo.lastTo, DateTime(2026, 11, 4));
    repo.delayedPage!.complete();
    await oldPage;
    expect(controller.snapshot.movements, hasLength(2));
    controller.clearDateRange();
    await tester.pumpAndSettle();
    expect(repo.lastFrom, isNull);
    expect(repo.lastTo, isNull);
    expect(controller.hasMore, isTrue);
    expect(tester.takeException(), isNull);
  });
}

Future<CashMovementsController> _pumpCash(
  WidgetTester tester,
  Size size, {
  String role = 'sales_rep',
  double textScale = 1,
  bool oneSided = false,
  _CashRepoFake? repo,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  SharedPreferences.setMockInitialValues({
    'companyId': 'default_company',
    'role': role,
    'uid': 'rep-1',
  });
  Get.reset();
  final services = await MyServices().init();
  Get.put<MyServices>(services);
  final controller = CashMovementsController(
    repository: repo ?? _CashRepoFake(oneSided: oneSided),
    myServices: services,
  );
  Get.put<CashMovementsController>(controller);
  await tester.pumpWidget(
    GetMaterialApp(
      locale: const Locale('en'),
      translations: MyTranslation(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: const CashMovementsScreen(),
    ),
  );
  await tester.pumpAndSettle();
  return controller;
}

class _FakeCursor implements FirestorePageCursor {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _CashRepoFake implements FinancialRepository {
  _CashRepoFake({
    this.paged = false,
    this.oneSided = false,
    this.duplicatePage = false,
  });
  final bool paged;
  final bool oneSided;
  final bool duplicatePage;
  Map<String, BigInt?>? reported;
  Completer<void>? delayedPage;
  DateTime? lastFrom, lastTo;
  bool failPage = false;

  @override
  Future<FinancialCashPage> fetchCashPage({
    String companyId = 'default_company',
    DateTime? fromDate,
    DateTime? toDate,
    FirestorePageCursor? after,
    int pageSize = 50,
  }) async {
    lastFrom = fromDate;
    lastTo = toDate;
    return FinancialCashPage(
      snapshot: FinancialCashSnapshot(
        reportedValues: reported,
        movements: [
          _movement(
            'rep-out',
            direction: 'out',
            account: CashMovementModel.repCashAccount,
          ),
          if (!oneSided)
            _movement(
              'company-in',
              direction: 'in',
              account: CashMovementModel.companyCashAccount,
            ),
        ],
        openingBalance: 100,
        closingBalance: 50,
        cashInHand: 50,
        companyCash: 50,
        repCashOutstanding: 50,
        totalIn: 50,
        totalOut: 50,
        cashBySalesRep: const [],
        repCashOutstandingBySalesRep: const [],
      ),
      cursor: paged ? _FakeCursor() : null,
      hasMore: paged,
    );
  }

  @override
  Future<FirestorePage<CashMovementModel>> fetchCashMovementDetailsPage({
    String companyId = 'default_company',
    DateTime? fromDate,
    DateTime? toDate,
    FirestorePageCursor? after,
    int pageSize = 50,
  }) async {
    await delayedPage?.future;
    if (failPage) throw StateError('Page unavailable');
    return FirestorePage(
      items: [
        if (duplicatePage)
          _movement(
            'rep-out',
            direction: 'out',
            account: CashMovementModel.repCashAccount,
          ),
        _movement(
          'another',
          direction: 'in',
          account: CashMovementModel.repCashAccount,
          settlementId: '',
        ),
      ],
      cursor: duplicatePage ? _FakeCursor() : null,
      hasMore: duplicatePage,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

CashMovementModel _movement(
  String id, {
  required String direction,
  required String account,
  String settlementId = 'settlement-1',
}) {
  final now = DateTime(2026, 9, 23);
  return CashMovementModel(
    id: id,
    companyId: 'default_company',
    salesRepId: 'rep-1',
    salesRepName: 'Representative One',
    type: 'settlement_to_admin',
    movementType: 'settlement',
    direction: direction,
    amount: 50,
    referenceId: settlementId,
    referenceNumber: 'SET-001',
    sourceCollection: 'settlements',
    sourceId: settlementId,
    sourceNumber: 'SET-001',
    customerId: '',
    customerName: '',
    date: now,
    notes: '',
    cashAccount: account,
    settlementId: settlementId,
    createdByUid: 'admin-1',
    createdByName: 'Admin',
    createdByRole: 'admin',
    createdAt: now,
  );
}
