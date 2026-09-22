import 'package:fatoora/core/class/statusrequest.dart';
import 'package:fatoora/app/routes/app_routes.dart';
import 'package:fatoora/core/data/firestore_query_pager.dart';
import 'package:fatoora/core/services/services.dart';
import 'package:fatoora/features/invoices/controllers/invoices_list_controller.dart';
import 'package:fatoora/features/invoices/data/models/invoice_customer_snapshot.dart';
import 'package:fatoora/features/invoices/data/models/invoice_enums.dart';
import 'package:fatoora/features/invoices/data/models/invoice_list_query.dart';
import 'package:fatoora/features/invoices/data/models/invoice_model.dart';
import 'package:fatoora/features/invoices/data/repositories/invoice_repository.dart';
import 'package:fatoora/features/invoices/view/screens/invoices_list_screen.dart';
import 'package:fatoora/features/invoices/view/widgets/invoice_actions_menu.dart';
import 'package:fatoora/features/invoices/view/widgets/invoice_card.dart';
import 'package:fatoora/features/invoices/view/widgets/invoice_filter_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() async {
    await Get.delete<InvoicesListController>(force: true);
    await Get.delete<MyServices>(force: true);
    Get.reset();
  });

  testWidgets('invoice list uses cards at narrow mobile width', (tester) async {
    await _pumpInvoiceList(tester, const Size(390, 800));

    expect(find.byType(InvoiceCard), findsNWidgets(_invoices.length));
    expect(find.byType(DataTable), findsNothing);
    expect(find.byType(InvoiceActionsMenu), findsNWidgets(_invoices.length));
    expect(tester.takeException(), isNull);
  });

  testWidgets('invoice cards support Arabic at 320px with 2x text', (
    tester,
  ) async {
    await _pumpInvoiceList(
      tester,
      const Size(320, 640),
      locale: const Locale('ar'),
      textScale: 2,
    );

    expect(find.byType(InvoiceCard), findsNWidgets(_invoices.length));
    expect(find.byType(DataTable), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('invoice list uses compact action menus at 1024 web width', (
    tester,
  ) async {
    await _pumpInvoiceList(tester, const Size(1024, 800));

    expect(find.byType(DataTable), findsOneWidget);
    expect(find.byType(InvoiceCard), findsNothing);
    expect(find.byType(InvoiceActionsMenu), findsNWidgets(_invoices.length));
    _expectFinderInsideViewport(
      tester,
      find.byType(InvoiceActionsMenu).first,
      viewportWidth: 1024,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('invoice list uses full table columns at wide web width', (
    tester,
  ) async {
    await _pumpInvoiceList(tester, const Size(1536, 900), role: 'admin');

    expect(find.byType(DataTable), findsOneWidget);
    expect(find.text('return_status'), findsWidgets);
    expect(find.text('sales_rep'), findsWidgets);
    expect(find.byType(InvoiceActionsMenu), findsNWidgets(_invoices.length));
    _expectFinderInsideViewport(
      tester,
      find.byType(InvoiceActionsMenu).last,
      viewportWidth: 1536,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('invoice list keeps actions visible at 1366 web width', (
    tester,
  ) async {
    await _pumpInvoiceList(tester, const Size(1366, 850));

    expect(find.byType(DataTable), findsOneWidget);
    expect(find.byType(InvoiceActionsMenu), findsNWidgets(_invoices.length));
    _expectFinderInsideViewport(
      tester,
      find.byType(InvoiceActionsMenu).last,
      viewportWidth: 1366,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('invoice table supports Arabic customer names without overflow', (
    tester,
  ) async {
    await _pumpInvoiceList(
      tester,
      const Size(1024, 800),
      locale: const Locale('ar'),
    );

    expect(find.byType(DataTable), findsOneWidget);
    expect(find.text('شركة مضخات المياه المتقدمة'), findsOneWidget);
    expect(find.byType(InvoiceActionsMenu), findsNWidgets(_invoices.length));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'mobile uses compact controls and exposes every relevant filter',
    (tester) async {
      await _pumpInvoiceList(tester, const Size(390, 800));

      expect(
        find.byKey(const ValueKey('invoice-filter-button')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('invoice-sort-button')), findsOneWidget);
      expect(find.byType(InvoiceFilterBar), findsNothing);

      await tester.tap(find.byKey(const ValueKey('invoice-filter-button')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('invoice-filter-sales-rep')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('invoice-filter-customer')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('invoice-filter-status')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('invoice-filter-payment-status')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('invoice-filter-type')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('invoice-filter-return-status')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('invoice-filter-date-range')),
        findsOneWidget,
      );
    },
  );

  testWidgets('admin sees sales representative filters and card metadata', (
    tester,
  ) async {
    await _pumpInvoiceList(tester, const Size(390, 800), role: 'admin');

    expect(
      find.descendant(
        of: find.byType(InvoiceCard).first,
        matching: find.text('Sales Rep'),
      ),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('invoice-filter-button')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('invoice-filter-sales-rep')),
      findsOneWidget,
    );
  });

  testWidgets('sales representative card omits redundant self metadata', (
    tester,
  ) async {
    await _pumpInvoiceList(tester, const Size(390, 800));

    expect(
      find.descendant(
        of: find.byType(InvoiceCard).first,
        matching: find.text('Sales Rep'),
      ),
      findsNothing,
    );
  });

  testWidgets(
    'active filters can be removed individually or cleared together',
    (tester) async {
      final controller = await _pumpInvoiceList(tester, const Size(390, 800));
      controller.statusFilter = InvoiceStatus.confirmed;
      controller.paymentStatusFilter = PaymentStatus.paid;
      controller.update();
      await tester.pump();

      expect(find.byType(InputChip), findsNWidgets(2));
      tester.widget<InputChip>(find.byType(InputChip).first).onDeleted!();
      await tester.pumpAndSettle();
      expect(controller.activeFilterCount, 1);

      controller.statusFilter = InvoiceStatus.confirmed;
      controller.paymentStatusFilter = PaymentStatus.paid;
      controller.update();
      await tester.pump();
      await tester.drag(
        find.byKey(const ValueKey('invoice-active-filter-chips')),
        const Offset(-700, 0),
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('invoice-clear-all-filters')));
      await tester.pumpAndSettle();
      expect(controller.hasActiveFilters, isFalse);
    },
  );

  testWidgets(
    'sort sheet exposes all fields and reflects forced date sorting',
    (tester) async {
      final controller = await _pumpInvoiceList(tester, const Size(390, 800));
      controller.fromDate = DateTime(2026, 9, 1);
      controller.toDate = DateTime(2026, 9, 30);
      controller.sortField = InvoiceSortField.invoiceDate;
      controller.update();
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey('invoice-sort-button')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('invoice-sort-date-notice')),
        findsOneWidget,
      );
      for (final field in InvoiceSortField.values) {
        expect(
          find.byKey(ValueKey('invoice-sort-${field.name}')),
          findsOneWidget,
        );
      }
      final customerSort = tester.widget<RadioListTile<InvoiceSortField>>(
        find.byKey(const ValueKey('invoice-sort-customerName')),
      );
      expect(customerSort.onChanged, isNull);
    },
  );

  testWidgets(
    'filter sheet reset applies through authoritative controller state',
    (tester) async {
      final controller = await _pumpInvoiceList(tester, const Size(390, 800));
      controller
        ..statusFilter = InvoiceStatus.confirmed
        ..paymentStatusFilter = PaymentStatus.paid
        ..update();
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey('invoice-filter-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('invoice-filter-reset')));
      await tester.tap(find.byKey(const ValueKey('invoice-filter-apply')));
      await tester.pumpAndSettle();

      expect(controller.statusFilter, isNull);
      expect(controller.paymentStatusFilter, isNull);
    },
  );

  testWidgets('existing Load More affordance remains available', (
    tester,
  ) async {
    final controller = await _pumpInvoiceList(tester, const Size(390, 800));
    controller
      ..hasMore = true
      ..update();
    await tester.pump();
    expect(find.text('load_more_records'), findsOneWidget);
  });

  testWidgets('result loading and error states keep controls visible', (
    tester,
  ) async {
    final controller = await _pumpInvoiceList(tester, const Size(390, 800));
    controller
      ..invoices = const []
      ..statusRequest = StatusRequest.loading
      ..update();
    await tester.pump();
    expect(find.byKey(const ValueKey('invoice-search-field')), findsOneWidget);
    expect(find.byKey(const ValueKey('invoice-filter-button')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('invoice-results-loader')),
      findsOneWidget,
    );

    controller
      ..statusRequest = StatusRequest.serverfailure
      ..loadErrorMessageKey = 'invoice_load_error'
      ..update();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('invoice-search-field')), findsOneWidget);
    expect(find.byKey(const ValueKey('invoice-retry-button')), findsOneWidget);
  });

  testWidgets('normal and filtered empty states remain distinct', (
    tester,
  ) async {
    final controller = await _pumpInvoiceList(tester, const Size(390, 800));
    controller
      ..invoices = const []
      ..statusRequest = StatusRequest.success
      ..update();
    await tester.pumpAndSettle();
    expect(find.text('no_invoices_found'), findsOneWidget);

    controller.statusFilter = InvoiceStatus.confirmed;
    controller.update();
    await tester.pumpAndSettle();
    expect(find.text('no_search_results'), findsOneWidget);
  });

  testWidgets('one-character search shows guidance without applied filtering', (
    tester,
  ) async {
    final controller = await _pumpInvoiceList(tester, const Size(390, 800));
    await tester.enterText(
      find.byKey(const ValueKey('invoice-search-field')),
      'a',
    );
    await tester.pump(const Duration(milliseconds: 500));

    expect(controller.searchIsTooShort, isTrue);
    expect(controller.hasFilters, isFalse);
    expect(
      find.byKey(const ValueKey('invoice-search-minimum-hint')),
      findsOneWidget,
    );
  });

  testWidgets('tablet keeps the compact card workflow without overflow', (
    tester,
  ) async {
    await _pumpInvoiceList(tester, const Size(800, 1024));
    expect(find.byType(InvoiceCard), findsNWidgets(_invoices.length));
    expect(find.byKey(const ValueKey('invoice-filter-button')), findsOneWidget);
    expect(find.byType(DataTable), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('mobile card and desktop row open existing invoice details', (
    tester,
  ) async {
    await _pumpInvoiceList(
      tester,
      const Size(390, 800),
      includeDetailsRoute: true,
    );
    await tester.tap(find.byType(InvoiceCard).first);
    await tester.pumpAndSettle();
    expect(Get.currentRoute, '/invoices/invoice-1');

    Get.back();
    await tester.pumpAndSettle();
    await tester.binding.setSurfaceSize(const Size(1024, 800));
    await tester.pumpAndSettle();
    await tester.tap(find.text('INV-2026-000001').first);
    await tester.pumpAndSettle();
    expect(Get.currentRoute, '/invoices/invoice-1');
  });
}

Future<InvoicesListController> _pumpInvoiceList(
  WidgetTester tester,
  Size size, {
  Locale locale = const Locale('en'),
  double textScale = 1,
  String role = 'sales_rep',
  bool includeDetailsRoute = false,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));

  SharedPreferences.setMockInitialValues({
    'companyId': 'default_company',
    'role': role,
    'uid': 'rep-1',
    'name': 'Sales Rep',
    'approvalStatus': 'approved',
    'active': true,
  });
  Get.reset();
  final services = await MyServices().init();
  Get.put<MyServices>(services);
  final controller = InvoicesListController(
    repository: _FakeInvoiceRepository(_invoices),
    myServices: services,
  );
  controller.statusRequest = StatusRequest.success;
  controller.invoices = _invoices;
  Get.put<InvoicesListController>(controller);

  await tester.pumpWidget(
    GetMaterialApp(
      locale: locale,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: const InvoicesListScreen(),
      getPages: includeDetailsRoute
          ? [
              GetPage(
                name: AppRoute.invoiceDetails,
                page: () => const Scaffold(body: Text('invoice-details-page')),
              ),
            ]
          : const [],
    ),
  );
  await tester.pumpAndSettle();
  return controller;
}

void _expectFinderInsideViewport(
  WidgetTester tester,
  Finder finder, {
  required double viewportWidth,
}) {
  final topRight = tester.getTopRight(finder);
  final bottomRight = tester.getBottomRight(finder);

  expect(topRight.dx, lessThanOrEqualTo(viewportWidth));
  expect(bottomRight.dx, lessThanOrEqualTo(viewportWidth));
}

class _FakeInvoiceRepository implements InvoiceRepository {
  const _FakeInvoiceRepository(this.invoices);

  final List<InvoiceModel> invoices;

  @override
  Future<List<InvoiceModel>> getInvoices({
    required String companyId,
    InvoiceType? type,
    InvoiceStatus? status,
    PaymentStatus? paymentStatus,
    InvoiceReturnStatus? returnStatus,
    String? salesRepId,
    String? customerId,
    DateTime? fromDate,
    DateTime? toDate,
    String? searchText,
    InvoiceSortField sortField = InvoiceSortField.invoiceDate,
    InvoiceSortDirection sortDirection = InvoiceSortDirection.descending,
  }) async {
    return invoices
        .where((invoice) => type == null || invoice.invoiceType == type)
        .where((invoice) => status == null || invoice.invoiceStatus == status)
        .toList(growable: false);
  }

  @override
  Future<FirestorePage<InvoiceModel>> getInvoicesPage({
    required String companyId,
    InvoiceType? type,
    InvoiceStatus? status,
    PaymentStatus? paymentStatus,
    InvoiceReturnStatus? returnStatus,
    String? salesRepId,
    String? customerId,
    DateTime? fromDate,
    DateTime? toDate,
    String? searchText,
    InvoiceSortField sortField = InvoiceSortField.invoiceDate,
    InvoiceSortDirection sortDirection = InvoiceSortDirection.descending,
    FirestorePageCursor? after,
    int pageSize = 50,
  }) async {
    return FirestorePage(
      items: await getInvoices(
        companyId: companyId,
        type: type,
        status: status,
        paymentStatus: paymentStatus,
        returnStatus: returnStatus,
        salesRepId: salesRepId,
        customerId: customerId,
        fromDate: fromDate,
        toDate: toDate,
        searchText: searchText,
        sortField: sortField,
        sortDirection: sortDirection,
      ),
      cursor: null,
      hasMore: false,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final _invoices = [
  _invoice(
    id: 'invoice-1',
    number: 'INV-2026-000001',
    customerName: 'شركة مضخات المياه المتقدمة',
    status: InvoiceStatus.draft,
    paymentStatus: PaymentStatus.unpaid,
    amount: 145.75,
  ),
  _invoice(
    id: 'invoice-2',
    number: 'INV-2026-000002',
    customerName:
        'International Pumping Solutions With A Very Long Customer Name',
    status: InvoiceStatus.confirmed,
    paymentStatus: PaymentStatus.partiallyPaid,
    amount: 2040.125,
  ),
  _invoice(
    id: 'invoice-3',
    number: 'INV-2026-000003',
    customerName: 'Fujika Model FDSS 4SP-10 Customer',
    status: InvoiceStatus.accepted,
    paymentStatus: PaymentStatus.paid,
    amount: 99.5,
  ),
];

InvoiceModel _invoice({
  required String id,
  required String number,
  required String customerName,
  required InvoiceStatus status,
  required PaymentStatus paymentStatus,
  required double amount,
}) {
  final now = DateTime(2026, 7, 12);
  return InvoiceModel(
    id: id,
    companyId: 'default_company',
    invoiceNumber: number,
    invoiceType: InvoiceType.regular,
    invoiceStatus: status,
    paymentType: paymentStatus == PaymentStatus.paid
        ? PaymentType.cash
        : PaymentType.credit,
    paymentStatus: paymentStatus,
    hasReceivedPayment: paymentStatus != PaymentStatus.unpaid,
    invoiceDate: now,
    dueDate: now.add(const Duration(days: 14)),
    createdAt: now,
    updatedAt: now,
    createdByUid: 'rep-1',
    createdByName: 'Sales Representative With Long Name',
    createdByRole: 'sales_rep',
    salesRepId: 'rep-1',
    salesRepName: 'Sales Rep',
    customerId: 'customer-$id',
    customerSnapshot: InvoiceCustomerSnapshot(
      id: 'customer-$id',
      name: customerName,
      phone: '+962 79 123 4567',
      address: 'Amman',
      taxNumber: '',
      nationalNumber: '',
      city: 'Amman',
    ),
    items: const [],
    subtotal: amount,
    totalDiscount: 0,
    totalTax: 0,
    grandTotal: amount,
    paidAmount: paymentStatus == PaymentStatus.paid ? amount : 0,
    remainingAmount: paymentStatus == PaymentStatus.paid ? 0 : amount,
    notes: '',
    paymentMethod: paymentStatus.value,
    isLocked: status != InvoiceStatus.draft,
    financialPosted: status != InvoiceStatus.draft,
    financialPostedByUid: '',
    financialPostedByName: '',
    customerTransactionIds: const [],
    cashMovementIds: const [],
    inventoryPosted: false,
    inventoryPostedByUid: '',
    inventoryPostedByName: '',
    inventoryMovementIds: const [],
    searchKeywords: const [],
    customerNameLower: customerName.toLowerCase(),
    itemNamesLower: const [],
    invoiceNumberLower: number.toLowerCase(),
    dateString: '2026-07-12',
  );
}
