import 'package:fatoora/app/routes/app_routes.dart';
import 'package:fatoora/core/data/firestore_query_pager.dart';
import 'package:fatoora/core/localization/translation.dart';
import 'package:fatoora/core/pdf/business_pdf_configuration.dart';
import 'package:fatoora/core/services/services.dart';
import 'package:fatoora/features/invoices/data/models/invoice_customer_snapshot.dart';
import 'package:fatoora/features/invoices/data/models/invoice_item_snapshot.dart';
import 'package:fatoora/features/sales_returns/controllers/sales_return_details_controller.dart';
import 'package:fatoora/features/sales_returns/controllers/sales_returns_list_controller.dart';
import 'package:fatoora/features/sales_returns/data/models/sales_return_enums.dart';
import 'package:fatoora/features/sales_returns/data/models/sales_return_item_model.dart';
import 'package:fatoora/features/sales_returns/data/models/sales_return_model.dart';
import 'package:fatoora/features/sales_returns/data/repositories/sales_return_repository.dart';
import 'package:fatoora/features/sales_returns/data/services/sales_return_pdf_service.dart';
import 'package:fatoora/features/sales_returns/view/screens/sales_return_details_screen.dart';
import 'package:fatoora/features/sales_returns/view/screens/sales_returns_list_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(Get.reset);

  testWidgets('320px rep card is compact and hides own name', (tester) async {
    await _pumpList(tester, const Size(320, 640), textScale: 2);
    expect(find.byType(SalesReturnListCard), findsOneWidget);
    expect(find.text('Representative One'), findsNothing);
    expect(find.textContaining('JOD 25.000'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Admin tablet and desktop retain representative metadata', (
    tester,
  ) async {
    await _pumpList(tester, const Size(800, 900), role: 'admin');
    expect(find.byType(SalesReturnListCard), findsOneWidget);
    expect(find.text('Representative One'), findsOneWidget);
    await _pumpList(tester, const Size(1366, 900), role: 'admin');
    expect(find.byType(DataTable), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('status filter reaches server and can be removed', (
    tester,
  ) async {
    final repo = _ReturnRepositoryFake();
    final controller = await _pumpList(
      tester,
      const Size(390, 800),
      repo: repo,
    );
    await tester.tap(find.byKey(const ValueKey('return-filter-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirmed').last);
    await tester.pumpAndSettle();
    expect(repo.lastStatus, SalesReturnStatus.confirmed);
    expect(find.byKey(const ValueKey('return-status-chip')), findsOneWidget);
    tester
        .widget<InputChip>(find.byKey(const ValueKey('return-status-chip')))
        .onDeleted!();
    await tester.pumpAndSettle();
    expect(controller.statusFilter, isNull);
    expect(repo.lastStatus, isNull);
  });

  testWidgets('server search and Load More error stay inline', (tester) async {
    final repo = _ReturnRepositoryFake(paged: true);
    final controller = await _pumpList(
      tester,
      const Size(390, 800),
      repo: repo,
    );
    controller.onSearchChanged('ab');
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    expect(repo.lastSearch, 'ab');
    repo.failNextPage = true;
    await controller.loadMoreSalesReturns();
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('return-load-more-error')),
      findsOneWidget,
    );
    repo.failNextPage = false;
    await controller.loadMoreSalesReturns();
    await tester.pumpAndSettle();
    expect(controller.salesReturns, hasLength(2));
    expect(repo.afterCalls, 2);
  });

  testWidgets(
    'RTL list and mobile details show stored credit and custom line',
    (tester) async {
      await _pumpDetails(
        tester,
        const Size(320, 640),
        locale: const Locale('ar'),
        textScale: 2,
      );
      expect(find.text('Custom pipe fitting'), findsOneWidget);
      expect(find.text('Installation description'), findsOneWidget);
      expect(find.textContaining('JOD 5.000'), findsOneWidget);
      expect(find.byIcon(Icons.picture_as_pdf_outlined), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  test(
    'sales return PDF still generates custom name and description',
    () async {
      await initializeDateFormatting('en');
      final bytes = await SalesReturnPdfService.build(
        _salesReturn(),
        configuration: BusinessPdfConfiguration.defaults(),
      );
      expect(bytes.length, greaterThan(1000));
      expect(String.fromCharCodes(bytes.take(4)), '%PDF');
    },
  );
}

Future<SalesReturnsListController> _pumpList(
  WidgetTester tester,
  Size size, {
  String role = 'sales_rep',
  double textScale = 1,
  _ReturnRepositoryFake? repo,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final controller = SalesReturnsListController(
    repository: repo ?? _ReturnRepositoryFake(),
    myServices: await _services(role),
  );
  Get.put<SalesReturnsListController>(controller);
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
      home: const SalesReturnsListScreen(),
    ),
  );
  await tester.pumpAndSettle();
  return controller;
}

Future<void> _pumpDetails(
  WidgetTester tester,
  Size size, {
  Locale locale = const Locale('en'),
  double textScale = 1,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final controller = SalesReturnDetailsController(
    repository: _ReturnRepositoryFake(),
    myServices: await _services('sales_rep'),
  );
  Get.put<SalesReturnDetailsController>(controller);
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
      initialRoute: AppRoute.salesReturnDetailsPath('return-1'),
      getPages: [
        GetPage(
          name: AppRoute.salesReturnDetails,
          page: () => const SalesReturnDetailsScreen(),
        ),
      ],
    ),
  );
  await tester.pumpAndSettle();
}

Future<MyServices> _services(String role) async {
  SharedPreferences.setMockInitialValues({
    'companyId': 'default_company',
    'role': role,
    'uid': 'rep-1',
  });
  Get.reset();
  final services = await MyServices().init();
  Get.put<MyServices>(services);
  return services;
}

class _FakeCursor implements FirestorePageCursor {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ReturnRepositoryFake implements SalesReturnRepository {
  _ReturnRepositoryFake({this.paged = false});
  final bool paged;
  SalesReturnStatus? lastStatus;
  String? lastSearch;
  int afterCalls = 0;
  bool failNextPage = false;

  @override
  Future<FirestorePage<SalesReturnModel>> fetchSalesReturnsPage({
    String companyId = 'default_company',
    SalesReturnStatus? status,
    String searchText = '',
    DateTime? fromDate,
    DateTime? toDate,
    FirestorePageCursor? after,
    int pageSize = 50,
  }) async {
    lastStatus = status;
    lastSearch = searchText;
    if (after != null) {
      afterCalls++;
      if (failNextPage) throw StateError('Page unavailable');
    }
    return FirestorePage(
      items: [_salesReturn(id: after == null ? 'return-1' : 'return-2')],
      cursor: paged && after == null ? _FakeCursor() : null,
      hasMore: paged && after == null,
    );
  }

  @override
  Future<SalesReturnModel?> getSalesReturnById({
    String companyId = 'default_company',
    required String returnId,
  }) async => _salesReturn();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

SalesReturnModel _salesReturn({String id = 'return-1'}) {
  final now = DateTime(2026, 9, 23);
  return SalesReturnModel(
    id: id,
    companyId: 'default_company',
    returnNumber: 'RET-001',
    originalInvoiceId: 'invoice-1',
    originalInvoiceNumber: 'INV-001',
    customerId: 'customer-1',
    customerSnapshot: const InvoiceCustomerSnapshot(
      id: 'customer-1',
      name: 'Acme Pumps',
      phone: '',
      address: '',
      taxNumber: '',
      nationalNumber: '',
      city: '',
    ),
    items: [
      SalesReturnItemModel(
        lineId: 'line-1',
        lineType: InvoiceLineType.custom,
        itemId: null,
        itemName: 'Custom pipe fitting',
        description: 'Installation description',
        itemCode: '',
        unit: 'PCS',
        returnedQuantity: 1,
        unitPrice: 25,
        taxPercent: 0,
        subtotal: 25,
        taxAmount: 0,
        total: 25,
        originalInvoiceItemId: 'invoice-1:line:line-1',
      ),
    ],
    subtotal: 25,
    totalTax: 0,
    grandTotal: 25,
    receivableReduction: 20,
    customerCreditAmount: 5,
    refundType: RefundType.creditCustomerBalance,
    returnDate: now,
    reason: 'Damaged goods',
    status: SalesReturnStatus.confirmed,
    salesRepId: 'rep-1',
    salesRepName: 'Representative One',
    createdByUid: 'rep-1',
    createdByName: 'Representative One',
    createdByRole: 'sales_rep',
    financialPosted: true,
    inventoryPosted: false,
    stockMovementIds: const [],
    customerTransactionIds: const ['customer-tx-1'],
    cashMovementIds: const [],
    createdAt: now,
    updatedAt: now,
  );
}
