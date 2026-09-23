import 'package:fatoora/app/routes/app_routes.dart';
import 'package:fatoora/core/data/firestore_query_pager.dart';
import 'package:fatoora/core/localization/translation.dart';
import 'package:fatoora/core/pdf/business_pdf_configuration.dart';
import 'package:fatoora/core/services/services.dart';
import 'package:fatoora/features/customers/controllers/customer_statement_controller.dart';
import 'package:fatoora/features/customers/data/models/customer_model.dart';
import 'package:fatoora/features/customers/data/models/customer_transaction_model.dart';
import 'package:fatoora/features/customers/data/repositories/customer_repository.dart';
import 'package:fatoora/features/customers/data/services/customer_statement_pdf_service.dart';
import 'package:fatoora/features/customers/view/screens/customer_statement_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(Get.reset);

  testWidgets('320px 2x statement uses transaction cards and balance label', (
    tester,
  ) async {
    await _pumpStatement(tester, const Size(320, 640), textScale: 2);
    expect(find.byType(StatementTransactionCard), findsOneWidget);
    expect(find.byType(DataTable), findsNothing);
    expect(find.text('Acme Pumps'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Arabic RTL statement remains overflow-free', (tester) async {
    await _pumpStatement(
      tester,
      const Size(320, 640),
      textScale: 2,
      locale: const Locale('ar'),
    );
    expect(find.byType(StatementTransactionCard), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop statement keeps dense table and PDF action', (
    tester,
  ) async {
    await _pumpStatement(tester, const Size(1366, 900));
    expect(find.byType(DataTable), findsOneWidget);
    expect(find.byIcon(Icons.picture_as_pdf_outlined), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('date range and Load More retry preserve server paging', (
    tester,
  ) async {
    final repo = _StatementRepoFake(paged: true);
    final controller = await _pumpStatement(
      tester,
      const Size(390, 800),
      repo: repo,
    );
    controller.setDateRange(DateTime(2026, 9, 1), DateTime(2026, 9, 30));
    await tester.pumpAndSettle();
    expect(repo.lastFromDate, DateTime(2026, 9, 1));
    expect(find.byType(InputChip), findsOneWidget);
    repo.failNextPage = true;
    await controller.loadMore();
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('statement-load-more-error')),
      findsOneWidget,
    );
    repo.failNextPage = false;
    await controller.loadMore();
    await tester.pumpAndSettle();
    expect(controller.transactions, hasLength(2));
  });

  test('statement PDF still generates from current statement data', () async {
    await initializeDateFormatting('en');
    final bytes = await CustomerStatementPdfService.build(
      customer: _customer(),
      transactions: [_transaction()],
      fromDate: null,
      toDate: null,
      openingBalance: 0,
      totalDebit: 20,
      totalCredit: 0,
      finalBalance: 20,
      configuration: BusinessPdfConfiguration.defaults(),
    );
    expect(bytes.length, greaterThan(1000));
    expect(String.fromCharCodes(bytes.take(4)), '%PDF');
  });
}

Future<CustomerStatementController> _pumpStatement(
  WidgetTester tester,
  Size size, {
  Locale locale = const Locale('en'),
  double textScale = 1,
  _StatementRepoFake? repo,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  SharedPreferences.setMockInitialValues({
    'companyId': 'default_company',
    'role': 'sales_rep',
    'uid': 'rep-1',
  });
  Get.reset();
  final services = await MyServices().init();
  Get.put<MyServices>(services);
  final controller = CustomerStatementController(
    repository: repo ?? _StatementRepoFake(),
    myServices: services,
  );
  Get.put<CustomerStatementController>(controller);
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
      initialRoute: AppRoute.customerStatementPath('customer-1'),
      getPages: [
        GetPage(
          name: AppRoute.customerStatement,
          page: () => const CustomerStatementScreen(),
        ),
      ],
    ),
  );
  await tester.pumpAndSettle();
  return controller;
}

class _FakeCursor implements FirestorePageCursor {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _StatementRepoFake implements CustomerRepository {
  _StatementRepoFake({this.paged = false});
  final bool paged;
  DateTime? lastFromDate;
  bool failNextPage = false;

  @override
  Future<CustomerModel> getCustomer({
    String companyId = 'default_company',
    required String customerId,
  }) async => _customer();

  @override
  Future<CustomerStatementPage> fetchStatementPage({
    String companyId = 'default_company',
    required String customerId,
    DateTime? fromDate,
    DateTime? toDate,
    FirestorePageCursor? after,
    int pageSize = 50,
  }) async {
    lastFromDate = fromDate;
    if (after != null && failNextPage) throw StateError('Page unavailable');
    return CustomerStatementPage(
      transactions: [_transaction(id: after == null ? 'tx-1' : 'tx-2')],
      cursor: paged && after == null ? _FakeCursor() : null,
      hasMore: paged && after == null,
      openingBalance: 0,
      totalDebit: 20,
      totalCredit: 0,
      closingBalance: 20,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

CustomerModel _customer() => CustomerModel.fromMap({
  'companyId': 'default_company',
  'name': 'Acme Pumps',
  'currentBalance': 20,
}, id: 'customer-1');

CustomerTransactionModel _transaction({String id = 'tx-1'}) {
  final now = DateTime(2026, 9, 23);
  return CustomerTransactionModel(
    id: id,
    companyId: 'default_company',
    customerId: 'customer-1',
    customerName: 'Acme Pumps',
    transactionType: 'invoice',
    sourceCollection: 'invoices',
    sourceId: 'invoice-1',
    sourceNumber: 'INV-001',
    transactionDate: now,
    debitAmount: 20,
    creditAmount: 0,
    balanceAfter: 20,
    notes: 'Invoice for parts',
    createdByUid: 'rep-1',
    createdByName: 'Representative One',
    createdByRole: 'sales_rep',
    salesRepId: 'rep-1',
    salesRepName: 'Representative One',
    createdAt: now,
  );
}
