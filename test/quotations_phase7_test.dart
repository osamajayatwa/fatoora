import 'dart:io';

import 'package:fatoora/app/routes/app_routes.dart';
import 'package:fatoora/core/class/statusrequest.dart';
import 'package:fatoora/core/data/firestore_query_pager.dart';
import 'package:fatoora/core/localization/translation.dart';
import 'package:fatoora/core/pdf/business_pdf_configuration.dart';
import 'package:fatoora/core/services/services.dart';
import 'package:fatoora/core/settings/business_permission_resolver.dart';
import 'package:fatoora/features/invoices/data/models/invoice_customer_snapshot.dart';
import 'package:fatoora/features/invoices/data/models/invoice_item_snapshot.dart';
import 'package:fatoora/features/invoices/data/services/invoice_totals_service.dart';
import 'package:fatoora/features/quotations/controllers/quotation_details_controller.dart';
import 'package:fatoora/features/quotations/controllers/quotation_form_controller.dart';
import 'package:fatoora/features/quotations/controllers/quotations_list_controller.dart';
import 'package:fatoora/features/quotations/data/models/quotation_item_model.dart';
import 'package:fatoora/features/quotations/data/models/quotation_model.dart';
import 'package:fatoora/features/quotations/data/models/quotation_status.dart';
import 'package:fatoora/features/quotations/data/repositories/quotation_repository.dart';
import 'package:fatoora/features/quotations/data/services/quotation_pdf_service.dart';
import 'package:fatoora/features/quotations/view/screens/quotation_details_screen.dart';
import 'package:fatoora/features/quotations/view/screens/quotation_form_screen.dart';
import 'package:fatoora/features/quotations/view/screens/quotations_list_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(() async {
    await Get.delete<QuotationsListController>(force: true);
    await Get.delete<QuotationDetailsController>(force: true);
    await Get.delete<QuotationFormController>(force: true);
    await Get.delete<MyServices>(force: true);
    Get.reset();
  });

  testWidgets('Admin mobile shows compact quotation cards and rep metadata', (
    tester,
  ) async {
    await _pumpList(tester, const Size(390, 800), role: 'admin');
    expect(find.byType(QuotationListCard), findsOneWidget);
    expect(find.text('Representative One'), findsOneWidget);
    expect(find.byType(DataTable), findsNothing);
    expect(
      find.byKey(const ValueKey('quotation-filter-button')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Sales Rep mobile hides redundant rep metadata at 320px and 2x text',
    (tester) async {
      await _pumpList(tester, const Size(320, 640), textScale: 2);
      expect(find.byType(QuotationListCard), findsOneWidget);
      expect(find.text('Representative One'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'tablet uses cards; desktop table hides Sales Rep column for rep',
    (tester) async {
      await _pumpList(tester, const Size(800, 900));
      expect(find.byType(QuotationListCard), findsOneWidget);
      expect(find.byType(DataTable), findsNothing);
      await tester.binding.setSurfaceSize(const Size(1200, 900));
      await tester.pumpAndSettle();
      expect(find.byType(DataTable), findsOneWidget);
      expect(find.text('Representative One'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Admin desktop table shows Sales Rep and opens details from row',
    (tester) async {
      await _pumpList(
        tester,
        const Size(1200, 900),
        role: 'admin',
        includeDetailsRoute: true,
      );
      expect(find.byType(DataTable), findsOneWidget);
      expect(find.text('Representative One'), findsOneWidget);
      await tester.tap(find.text('QUO-2026-001').last);
      await tester.pumpAndSettle();
      expect(find.text('quotation-details-test-page'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('status sheet keeps every real status and removable chip', (
    tester,
  ) async {
    final controller = await _pumpList(tester, const Size(390, 800));
    await tester.tap(find.byKey(const ValueKey('quotation-filter-button')));
    await tester.pumpAndSettle();
    for (final status in QuotationStatus.values) {
      expect(
        find.byKey(ValueKey('quotation-filter-${status.value}')),
        findsOneWidget,
      );
    }
    await tester.tap(find.byKey(const ValueKey('quotation-filter-sent')));
    await tester.pumpAndSettle();
    expect(controller.statusFilter, QuotationStatus.sent);
    expect(find.byKey(const ValueKey('quotation-status-chip')), findsOneWidget);
    tester
        .widget<InputChip>(find.byKey(const ValueKey('quotation-status-chip')))
        .onDeleted!();
    await tester.pumpAndSettle();
    expect(controller.statusFilter, isNull);
  });

  testWidgets(
    'search keeps minimum length, Enter, and mounted controls during reload',
    (tester) async {
      final repository = _QuotationRepositoryFake();
      final controller = await _pumpList(
        tester,
        const Size(390, 800),
        repository: repository,
      );
      controller.onSearchChanged('x');
      expect(controller.searchIsTooShort, isTrue);
      expect(controller.hasAppliedFilters, isFalse);
      await tester.pump(const Duration(milliseconds: 500));
      expect(repository.searches, hasLength(1));
      controller.onSearchChanged('pump');
      await tester.pump(const Duration(milliseconds: 449));
      expect(repository.searches, hasLength(1));
      controller.submitSearch();
      await tester.pumpAndSettle();
      expect(repository.searches.last, 'pump');
      controller.statusRequest = StatusRequest.loading;
      controller.update();
      await tester.pump();
      expect(find.byKey(const ValueKey('quotation-search')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('quotation-results-loading')),
        findsOneWidget,
      );
    },
  );

  testWidgets('empty and retryable error keep filters available', (
    tester,
  ) async {
    final controller = await _pumpList(tester, const Size(390, 800));
    controller.quotations = const [];
    controller.update();
    await tester.pump();
    expect(
      find.byKey(const ValueKey('quotation-results-empty')),
      findsOneWidget,
    );
    controller.statusRequest = StatusRequest.failure;
    controller.update();
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('quotation-results-error')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('quotation-search')), findsOneWidget);
  });

  testWidgets('Arabic RTL cards remain within 320px viewport', (tester) async {
    await _pumpList(tester, const Size(320, 640), locale: const Locale('ar'));
    expect(find.byType(QuotationListCard), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('details shows line description, PDF and conversion action', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    SharedPreferences.setMockInitialValues({
      'companyId': 'default_company',
      'role': 'sales_rep',
    });
    Get.reset();
    final services = await MyServices().init();
    Get.put<MyServices>(services);
    Get.put<QuotationDetailsController>(
      QuotationDetailsController(
        repository: _QuotationRepositoryFake(),
        myServices: services,
      ),
    );
    await tester.pumpWidget(
      GetMaterialApp(
        translations: MyTranslation(),
        locale: const Locale('en'),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        initialRoute: AppRoute.quotationDetailsPath('quotation-1'),
        getPages: [
          GetPage(
            name: AppRoute.quotationDetails,
            page: () => const QuotationDetailsScreen(),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Pump'), findsOneWidget);
    expect(find.text('Pump description'), findsOneWidget);
    expect(find.text('convert_to_invoice'.tr), findsOneWidget);
    expect(find.text('export_pdf'.tr), findsOneWidget);
    expect(find.text('Representative One'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('details desktop line table stays scroll-safe', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    SharedPreferences.setMockInitialValues({
      'companyId': 'default_company',
      'role': 'admin',
    });
    Get.reset();
    final services = await MyServices().init();
    Get.put<MyServices>(services);
    Get.put<QuotationDetailsController>(
      QuotationDetailsController(
        repository: _QuotationRepositoryFake(),
        myServices: services,
      ),
    );
    await tester.pumpWidget(
      GetMaterialApp(
        locale: const Locale('en'),
        translations: MyTranslation(),
        initialRoute: AppRoute.quotationDetailsPath('quotation-1'),
        getPages: [
          GetPage(
            name: AppRoute.quotationDetails,
            page: () => const QuotationDetailsScreen(),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(DataTable), findsOneWidget);
    expect(find.text('Representative One'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('create form retains catalog and custom actions', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    SharedPreferences.setMockInitialValues({
      'companyId': 'default_company',
      'role': 'admin',
    });
    Get.reset();
    final services = await MyServices().init();
    Get.put<MyServices>(services);
    Get.put<QuotationFormController>(
      QuotationFormController(
        repository: _QuotationRepositoryFake(),
        totalsService: const InvoiceTotalsService(),
        myServices: services,
        permissionResolver: const _PermissionResolverFake(true),
      ),
    );
    await tester.pumpWidget(
      GetMaterialApp(
        translations: MyTranslation(),
        locale: const Locale('en'),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: const QuotationFormScreen(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('select_item'.tr), findsOneWidget);
    expect(find.text('custom_line'.tr), findsOneWidget);
    expect(find.text('quotation_line_help'.tr), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test(
    'catalog and custom descriptions and line identities survive quotation-to-invoice mapping',
    () {
      final quotation = _quotation(
        items: [
          _line(
            'Catalog pump',
            'Catalog quotation description',
            'catalog-1',
            InvoiceLineType.catalog,
          ),
          _line(
            'Installation',
            'Custom quotation description',
            null,
            InvoiceLineType.custom,
          ),
        ],
      );
      final restored = QuotationModel.fromMap(quotation.toMap());
      expect(restored.items.map((item) => item.description), [
        'Catalog quotation description',
        'Custom quotation description',
      ]);
      expect(restored.items.map((item) => item.lineId), [
        'line-catalog-1',
        'line-custom',
      ]);
      expect(restored.items.map((item) => item.lineType), [
        InvoiceLineType.catalog,
        InvoiceLineType.custom,
      ]);
      expect(restored.items.last.itemId, isNull);
      final invoiceLines = restored.items
          .map((item) => item.toInvoiceItem())
          .toList();
      expect(invoiceLines.last.lineType, InvoiceLineType.custom);
      expect(invoiceLines.last.description, 'Custom quotation description');
      expect(invoiceLines.first.itemId, 'catalog-1');
    },
  );

  test(
    'quotation PDF builds with catalog and custom names and descriptions',
    () async {
      await initializeDateFormatting('en');
      final quotation = _quotation(
        items: [
          _line(
            'Catalog pump',
            'Catalog quotation description',
            'catalog-1',
            InvoiceLineType.catalog,
          ),
          _line(
            'Installation',
            'Custom quotation description',
            null,
            InvoiceLineType.custom,
          ),
        ],
      );
      final bytes = await QuotationPdfService.build(
        quotation,
        configuration: BusinessPdfConfiguration.defaults(),
      );
      expect(bytes.length, greaterThan(1000));
      expect(String.fromCharCodes(bytes.take(4)), '%PDF');
      final output = Platform.environment['FATOORA_PDF_QA_OUTPUT'];
      if (output != null && output.isNotEmpty) {
        await File(output).parent.create(recursive: true);
        await File(output).writeAsBytes(bytes);
      }
    },
  );
}

Future<QuotationsListController> _pumpList(
  WidgetTester tester,
  Size size, {
  String role = 'sales_rep',
  Locale locale = const Locale('en'),
  double textScale = 1,
  bool includeDetailsRoute = false,
  _QuotationRepositoryFake? repository,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  SharedPreferences.setMockInitialValues({
    'companyId': 'default_company',
    'role': role,
  });
  Get.reset();
  final services = await MyServices().init();
  Get.put<MyServices>(services);
  final controller = QuotationsListController(
    repository: repository ?? _QuotationRepositoryFake(),
    myServices: services,
    permissionResolver: _PermissionResolverFake(role == 'admin'),
  );
  Get.put<QuotationsListController>(controller);
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
      home: const QuotationsListScreen(),
      getPages: includeDetailsRoute
          ? [
              GetPage(
                name: AppRoute.quotationDetails,
                page: () =>
                    const Scaffold(body: Text('quotation-details-test-page')),
              ),
            ]
          : const [],
    ),
  );
  await tester.pumpAndSettle();
  return controller;
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
        createReceipts: false,
        createReturns: false,
        createQuotations: isAdmin,
        editCatalogPrice: isAdmin,
        applyDiscount: isAdmin,
      );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _QuotationRepositoryFake implements QuotationRepository {
  final searches = <String?>[];

  @override
  Future<QuotationModel?> getQuotationById({
    required String companyId,
    required String quotationId,
  }) async => _quotation();

  @override
  Future<FirestorePage<QuotationModel>> fetchQuotationsPage({
    required String companyId,
    QuotationStatus? status,
    String? searchText,
    FirestorePageCursor? after,
    int pageSize = 50,
  }) async {
    searches.add(searchText);
    return FirestorePage(
      items: status == null || status == QuotationStatus.sent
          ? [_quotation()]
          : [],
      cursor: null,
      hasMore: false,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

QuotationModel _quotation({List<QuotationItemModel>? items}) {
  final date = DateTime(2026, 9, 23);
  return QuotationModel.empty(
    companyId: 'default_company',
    createdByUid: 'rep-1',
    createdByName: 'Representative One',
    createdByRole: 'sales_rep',
  ).copyWith(
    id: 'quotation-1',
    quotationNumber: 'QUO-2026-001',
    quotationDate: date,
    validUntil: date.add(const Duration(days: 14)),
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
    items:
        items ??
        [
          _line(
            'Pump',
            'Pump description',
            'catalog-1',
            InvoiceLineType.catalog,
          ),
        ],
    subtotal: 20,
    grandTotal: 20,
    status: QuotationStatus.sent,
  );
}

QuotationItemModel _line(
  String name,
  String description,
  String? itemId,
  InvoiceLineType type,
) => QuotationItemModel(
  lineId: itemId == null ? 'line-custom' : 'line-$itemId',
  lineType: type,
  itemId: itemId,
  itemName: name,
  description: description,
  itemCode: itemId ?? '',
  unit: 'PCS',
  quantity: 1,
  unitPrice: 20,
  discount: 0,
  taxPercent: 0,
  subtotal: 20,
  taxAmount: 0,
  total: 20,
);
