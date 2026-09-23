import 'dart:async';

import 'package:fatoora/app/routes/app_routes.dart';
import 'package:fatoora/core/class/statusrequest.dart';
import 'package:fatoora/core/data/firestore_query_pager.dart';
import 'package:fatoora/core/localization/translation.dart';
import 'package:fatoora/core/pdf/business_pdf_configuration.dart';
import 'package:fatoora/core/services/services.dart';
import 'package:fatoora/core/settings/business_permission_resolver.dart';
import 'package:fatoora/core/settings/business_settings_resolver.dart';
import 'package:fatoora/features/customers/data/models/customer_model.dart';
import 'package:fatoora/features/customers/data/repositories/customer_repository.dart';
import 'package:fatoora/features/customers/view/widgets/customer_list_components.dart';
import 'package:fatoora/features/invoices/data/models/invoice_customer_snapshot.dart';
import 'package:fatoora/features/receipts/controllers/receipt_details_controller.dart';
import 'package:fatoora/features/receipts/controllers/receipt_error_mapper.dart';
import 'package:fatoora/features/receipts/controllers/receipt_form_controller.dart';
import 'package:fatoora/features/receipts/controllers/receipts_list_controller.dart';
import 'package:fatoora/features/receipts/data/models/receipt_model.dart';
import 'package:fatoora/features/receipts/data/repositories/receipt_repository.dart';
import 'package:fatoora/features/receipts/data/services/receipt_pdf_service.dart';
import 'package:fatoora/features/receipts/view/screens/receipt_details_screen.dart';
import 'package:fatoora/features/receipts/view/screens/receipt_form_screen.dart';
import 'package:fatoora/features/receipts/view/screens/receipts_list_screen.dart';
import 'package:fatoora/features/receipts/view/widgets/receipt_presentation.dart';
import 'package:fatoora/features/settings/data/models/app_settings_model.dart';
import 'package:fatoora/features/settings/data/models/user_preferences_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:get/get.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(Get.reset);

  testWidgets('Admin mobile cards show amount, allocations and rep metadata', (
    tester,
  ) async {
    await _pumpList(tester, const Size(390, 800), role: 'admin');
    expect(find.byType(ReceiptListCard), findsOneWidget);
    expect(find.text('Representative One'), findsOneWidget);
    expect(find.textContaining('JOD 35.000'), findsOneWidget);
    expect(find.byType(DataTable), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Sales Rep 320px large text hides redundant rep metadata', (
    tester,
  ) async {
    await _pumpList(tester, const Size(320, 640), textScale: 2);
    expect(find.byType(ReceiptListCard), findsOneWidget);
    expect(find.text('Representative One'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tablet cards and desktop table preserve role-specific columns', (
    tester,
  ) async {
    await _pumpList(tester, const Size(800, 900));
    expect(find.byType(ReceiptListCard), findsOneWidget);
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    await tester.pumpAndSettle();
    expect(find.byType(DataTable), findsOneWidget);
    expect(find.text('Representative One'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Admin desktop table opens receipt details from row', (
    tester,
  ) async {
    await _pumpList(
      tester,
      const Size(1200, 900),
      role: 'admin',
      includeDetailsRoute: true,
    );
    expect(find.byType(DataTable), findsOneWidget);
    expect(find.text('Representative One'), findsOneWidget);
    await tester.tap(find.text('REC-2026-001').last);
    await tester.pumpAndSettle();
    expect(find.text('receipt-details-test-page'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('date filter is compact and removable', (tester) async {
    final repo = _ReceiptRepositoryFake();
    final controller = await _pumpList(
      tester,
      const Size(390, 800),
      repository: repo,
    );
    await tester.tap(find.byKey(const ValueKey('receipt-filter-button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('receipt-date-choose')), findsOneWidget);
    Get.back<void>();
    await tester.pumpAndSettle();
    controller.setDateRange(
      DateTimeRange(start: DateTime(2026, 9, 1), end: DateTime(2026, 9, 30)),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('receipt-date-chip')), findsOneWidget);
    expect(repo.lastFromDate, DateTime(2026, 9, 1));
    expect(repo.lastToDate, DateTime(2026, 9, 30));
    expect(repo.lastPageSize, 50);
    tester
        .widget<InputChip>(find.byKey(const ValueKey('receipt-date-chip')))
        .onDeleted!();
    await tester.pumpAndSettle();
    expect(controller.fromDate, isNull);
    expect(repo.lastFromDate, isNull);
    expect(repo.lastToDate, isNull);
  });

  testWidgets(
    'search keeps server minimum, debounce, Enter and mounted controls',
    (tester) async {
      final repo = _ReceiptRepositoryFake();
      final controller = await _pumpList(
        tester,
        const Size(390, 800),
        repository: repo,
      );
      controller.onSearchChanged('x');
      expect(controller.searchIsTooShort, isTrue);
      expect(controller.hasAppliedFilters, isFalse);
      await tester.pump(const Duration(milliseconds: 500));
      expect(repo.searches, hasLength(1));
      controller.onSearchChanged('pump');
      await tester.pump(const Duration(milliseconds: 449));
      expect(repo.searches, hasLength(1));
      controller.submitSearch();
      await tester.pumpAndSettle();
      expect(repo.searches.last, 'pump');
      controller.statusRequest = StatusRequest.loading;
      controller.update();
      await tester.pump();
      expect(find.byKey(const ValueKey('receipt-search')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('receipt-results-loading')),
        findsOneWidget,
      );
    },
  );

  testWidgets('Load More appends; failure has inline retry', (tester) async {
    final repo = _ReceiptRepositoryFake(paged: true);
    final controller = await _pumpList(
      tester,
      const Size(390, 800),
      repository: repo,
    );
    expect(controller.hasMore, isTrue);
    repo.failNextPage = true;
    await controller.loadMoreReceipts();
    await tester.pumpAndSettle();
    expect(controller.receipts, hasLength(1));
    expect(
      find.byKey(const ValueKey('receipt-load-more-error')),
      findsOneWidget,
    );
    repo.failNextPage = false;
    await controller.loadMoreReceipts();
    await tester.pumpAndSettle();
    expect(controller.receipts, hasLength(2));
    expect(repo.afterCalls, 2);
    expect(controller.loadMoreErrorMessageKey, isNull);
  });

  testWidgets('empty and retryable error keep search controls visible', (
    tester,
  ) async {
    final controller = await _pumpList(tester, const Size(390, 800));
    controller.receipts = const [];
    controller.update();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('receipt-results-empty')), findsOneWidget);
    controller.statusRequest = StatusRequest.failure;
    controller.update();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('receipt-results-error')), findsOneWidget);
    expect(find.byKey(const ValueKey('receipt-search')), findsOneWidget);
  });

  testWidgets('Arabic RTL list stays inside 320px viewport', (tester) async {
    await _pumpList(tester, const Size(320, 640), locale: const Locale('ar'));
    expect(find.byType(ReceiptListCard), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test(
    'presentation uses stored allocations and only recorded cash destination',
    () {
      final receipt = _receipt();
      expect(receiptAllocationRows(receipt).single.invoiceNumber, 'INV-1');
      expect(receiptCashDestinationKey(receipt), 'ledger_rep_cash');
      expect(receiptCashDestinationKey(_receipt(method: 'bank')), isNull);
      expect(receiptCashDestinationKey(_receipt(cashMovementIds: [])), isNull);
      expect(
        receiptCashDestinationKey(_receipt(role: 'admin')),
        'financial_company_cash',
      );
      final legacy = _receipt(
        allocations: const [],
        allocationMap: const {'invoice-id': 5},
      );
      expect(receiptAllocationRows(legacy).single.invoiceId, 'invoice-id');
    },
  );

  test('trusted receipt preconditions surface a clear retry message', () {
    final error = ReceiptRepositoryException(
      ReceiptRepositoryError.unknown,
      FirebaseException(plugin: 'cloud_functions', code: 'failed-precondition'),
    );
    expect(
      ReceiptErrorMapper.messageKey(error),
      'receipts_server_validation_error',
    );
  });

  testWidgets('Admin form shows system-derived company cash destination', (
    tester,
  ) async {
    await _pumpForm(tester, const Size(390, 800), role: 'admin');
    expect(find.textContaining('Company cash'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'details show stored allocation, balance, cash destination and PDF',
    (tester) async {
      await _pumpDetails(tester, const Size(320, 640), textScale: 2);
      expect(find.text('INV-1'), findsOneWidget);
      expect(find.textContaining('JOD 35.000'), findsWidgets);
      expect(find.byType(CustomerBalanceBadge), findsOneWidget);
      expect(find.textContaining('Representative cash'), findsOneWidget);
      expect(find.text('export_pdf'.tr), findsOneWidget);
      expect(find.text('Representative One'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Admin details show creator and credit state without recalculation',
    (tester) async {
      await _pumpDetails(
        tester,
        const Size(1200, 900),
        role: 'admin',
        receipt: _receipt(role: 'admin', resultingBalance: -3),
      );
      expect(find.text('Admin Creator'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('customer-balance-credit')),
        findsOneWidget,
      );
      expect(find.text('Company cash'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'form keeps customer picker, payment methods, cash label and save guard',
    (tester) async {
      final repo = _ReceiptRepositoryFake();
      final controller = await _pumpForm(
        tester,
        const Size(320, 640),
        role: 'sales_rep',
        repository: repo,
        textScale: 2,
      );
      expect(find.textContaining('Representative cash'), findsOneWidget);
      expect(find.byType(ChoiceChip), findsNWidgets(4));
      expect(find.text('receipts_allocation_auto'.tr), findsOneWidget);
      expect(tester.takeException(), isNull);
      controller.customer = _customer();
      controller.amountController.text = '35.000';
      controller.update();
      await tester.pumpAndSettle();
      repo.createCompleter = Completer<ReceiptModel>();
      final first = controller.saveReceipt();
      final second = controller.saveReceipt();
      await tester.pump();
      expect(repo.createCalls, 1);
      expect(controller.isSaving, isTrue);
      repo.createCompleter!.completeError(
        const ReceiptRepositoryException(ReceiptRepositoryError.unavailable),
      );
      await Future.wait([first, second]);
      await tester.pumpAndSettle();
      expect(controller.isSaving, isFalse);
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'existing customer picker returns selected customer without a second query',
    (tester) async {
      final customerRepo = _CustomerRepositoryFake();
      final controller = await _pumpForm(
        tester,
        const Size(390, 800),
        customerRepository: customerRepo,
      );
      await tester.tap(find.text('receipts_customer_required'.tr));
      await tester.pumpAndSettle();
      expect(Get.isBottomSheetOpen, isTrue);
      expect(find.text('Acme Pumps'), findsOneWidget);
      await tester.tap(find.text('Acme Pumps'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 500));
      expect(Get.isBottomSheetOpen, isFalse);
      expect(controller.customer?.id, 'customer-1');
      expect(customerRepo.calls, 1);
    },
  );

  test('receipt PDF still generates with stored allocation data', () async {
    await initializeDateFormatting('en');
    final bytes = await ReceiptPdfService.build(
      _receipt(),
      configuration: BusinessPdfConfiguration.defaults(),
    );
    expect(bytes.length, greaterThan(1000));
    expect(String.fromCharCodes(bytes.take(4)), '%PDF');
  });
}

Future<ReceiptsListController> _pumpList(
  WidgetTester tester,
  Size size, {
  String role = 'sales_rep',
  Locale locale = const Locale('en'),
  double textScale = 1,
  bool includeDetailsRoute = false,
  _ReceiptRepositoryFake? repository,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final services = await _services(role);
  final controller = ReceiptsListController(
    repository: repository ?? _ReceiptRepositoryFake(),
    myServices: services,
    permissionResolver: _PermissionResolverFake(role == 'admin'),
  );
  Get.put<ReceiptsListController>(controller);
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
      home: const ReceiptsListScreen(),
      getPages: includeDetailsRoute
          ? [
              GetPage(
                name: AppRoute.receiptDetails,
                page: () =>
                    const Scaffold(body: Text('receipt-details-test-page')),
              ),
            ]
          : const [],
    ),
  );
  await tester.pumpAndSettle();
  return controller;
}

Future<ReceiptDetailsController> _pumpDetails(
  WidgetTester tester,
  Size size, {
  String role = 'sales_rep',
  double textScale = 1,
  ReceiptModel? receipt,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final services = await _services(role);
  final controller = ReceiptDetailsController(
    repository: _ReceiptRepositoryFake(receipt: receipt ?? _receipt()),
    myServices: services,
  );
  Get.put<ReceiptDetailsController>(controller);
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
      initialRoute: AppRoute.receiptDetailsPath('receipt-1'),
      getPages: [
        GetPage(
          name: AppRoute.receiptDetails,
          page: () => const ReceiptDetailsScreen(),
        ),
      ],
    ),
  );
  await tester.pumpAndSettle();
  return controller;
}

Future<ReceiptFormController> _pumpForm(
  WidgetTester tester,
  Size size, {
  String role = 'admin',
  double textScale = 1,
  _ReceiptRepositoryFake? repository,
  _CustomerRepositoryFake? customerRepository,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final services = await _services(role);
  final permissions = _PermissionResolverFake(role == 'admin');
  Get.put<BusinessPermissionResolver>(permissions);
  Get.put<CustomerRepository>(customerRepository ?? _CustomerRepositoryFake());
  final controller = ReceiptFormController(
    repository: repository ?? _ReceiptRepositoryFake(),
    myServices: services,
    settingsResolver: BusinessSettingsResolver.withLoaders(
      appSettingsLoader: (_) async => AppSettingsModel.defaults,
      userPreferencesLoader: (_) async => UserPreferencesModel.defaults,
    ),
    permissionResolver: permissions,
  );
  Get.put<ReceiptFormController>(controller);
  await tester.pumpWidget(
    GetMaterialApp(
      locale: const Locale('en'),
      translations: MyTranslation(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(size: size, textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: const ReceiptFormScreen(),
    ),
  );
  await tester.pumpAndSettle();
  return controller;
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

class _PermissionResolverFake implements BusinessPermissionResolver {
  const _PermissionResolverFake(this.isAdmin);
  final bool isAdmin;
  @override
  Future<EffectiveBusinessPermissions> resolve(String companyId) async =>
      EffectiveBusinessPermissions(
        isAdmin: isAdmin,
        isSalesRep: !isAdmin,
        createCustomers: false,
        createReceipts: true,
        createReturns: false,
        createQuotations: false,
        editCatalogPrice: false,
        applyDiscount: false,
      );
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeCursor implements FirestorePageCursor {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ReceiptRepositoryFake implements ReceiptRepository {
  _ReceiptRepositoryFake({this.paged = false, ReceiptModel? receipt})
    : receipt = receipt ?? _receipt();
  final bool paged;
  final ReceiptModel receipt;
  final searches = <String>[];
  DateTime? lastFromDate;
  DateTime? lastToDate;
  int? lastPageSize;
  int afterCalls = 0;
  bool failNextPage = false;
  int createCalls = 0;
  Completer<ReceiptModel>? createCompleter;

  @override
  Future<FirestorePage<ReceiptModel>> fetchReceiptsPage({
    String companyId = 'default_company',
    DateTime? fromDate,
    DateTime? toDate,
    String searchText = '',
    FirestorePageCursor? after,
    int pageSize = 50,
  }) async {
    searches.add(searchText);
    lastFromDate = fromDate;
    lastToDate = toDate;
    lastPageSize = pageSize;
    if (after != null) {
      afterCalls++;
      if (failNextPage) throw StateError('Page unavailable');
    }
    return FirestorePage(
      items: [after == null ? receipt : _receipt(id: 'receipt-2')],
      cursor: paged && after == null ? _FakeCursor() : null,
      hasMore: paged && after == null,
    );
  }

  @override
  Future<ReceiptModel?> getReceiptById({
    String companyId = 'default_company',
    required String receiptId,
  }) async => receipt;

  @override
  Future<ReceiptModel> createReceipt({
    String companyId = 'default_company',
    required String customerId,
    required double amount,
    required String paymentMethod,
    required DateTime receiptDate,
    String notes = '',
    bool payFullBalance = false,
  }) {
    createCalls++;
    return createCompleter?.future ?? Future.value(receipt);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _CustomerRepositoryFake implements CustomerRepository {
  int calls = 0;
  @override
  Future<FirestorePage<CustomerModel>> fetchCustomersPage({
    String companyId = 'default_company',
    String searchText = '',
    bool activeOnly = true,
    FirestorePageCursor? after,
    int pageSize = 50,
  }) async {
    calls++;
    return FirestorePage(items: [_customer()], cursor: null, hasMore: false);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

ReceiptModel _receipt({
  String id = 'receipt-1',
  String role = 'sales_rep',
  String method = 'cash',
  List<String>? cashMovementIds,
  List<ReceiptInvoiceAllocation>? allocations,
  Map<String, double>? allocationMap,
  double? resultingBalance = 65,
}) {
  final date = DateTime(2026, 9, 23);
  return ReceiptModel(
    id: id,
    companyId: 'default_company',
    receiptNumber: 'REC-2026-001',
    receiptDate: date,
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
    amount: 35,
    paymentMethod: method,
    notes: 'Reference ABC',
    salesRepId: 'rep-1',
    salesRepName: 'Representative One',
    createdByUid: role == 'admin' ? 'admin-1' : 'rep-1',
    createdByName: role == 'admin' ? 'Admin Creator' : 'Representative One',
    createdByRole: role,
    customerTransactionIds: const ['transaction-1'],
    cashMovementIds: cashMovementIds ?? const ['cash-1'],
    invoiceAllocationDetails:
        allocations ??
        const [
          ReceiptInvoiceAllocation(
            invoiceId: 'invoice-1',
            invoiceNumber: 'INV-1',
            amount: 35,
          ),
        ],
    invoiceAllocations: allocationMap ?? const {'invoice-1': 35},
    resultingCustomerBalance: resultingBalance,
    createdAt: date,
    updatedAt: date,
  );
}

CustomerModel _customer() => CustomerModel.empty(
  companyId: 'default_company',
  createdByUid: 'rep-1',
  createdByName: 'Representative One',
  createdByRole: 'sales_rep',
).copyWith(id: 'customer-1', name: 'Acme Pumps', currentBalance: 100);
