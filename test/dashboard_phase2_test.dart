import 'package:fatoora/app/routes/app_routes.dart';
import 'package:fatoora/core/class/statusrequest.dart';
import 'package:fatoora/core/services/services.dart';
import 'package:fatoora/core/settings/business_permission_resolver.dart';
import 'package:fatoora/core/motion/fatoora_motion_widgets.dart';
import 'package:fatoora/features/admin_dashboard/controller/admin_dashboard_controller.dart';
import 'package:fatoora/features/admin_dashboard/model/admin_dashboard_models.dart';
import 'package:fatoora/features/admin_dashboard/view/widgets/admin_dashboard_content.dart';
import 'package:fatoora/features/admin_dashboard/view/widgets/dashboard_stat_card.dart';
import 'package:fatoora/features/auth/data/repositories/admin_auth_repository.dart';
import 'package:fatoora/features/customers/data/models/customer_model.dart';
import 'package:fatoora/features/financial/controllers/sales_rep_dashboard_controller.dart';
import 'package:fatoora/features/financial/data/models/financial_dashboard_snapshot.dart';
import 'package:fatoora/features/financial/data/repositories/financial_repository.dart';
import 'package:fatoora/features/home/view/widgets/sales_rep_dashboard_content.dart';
import 'package:fatoora/features/home/view/widgets/sales_rep_overview_metrics.dart';
import 'package:fatoora/features/invoices/data/models/invoice_model.dart';
import 'package:fatoora/features/shared/business/business_user_context.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(Get.reset);

  testWidgets('admin KPI is compact, tappable, and has no fake trend', (
    tester,
  ) async {
    var tapped = false;
    const stat = DashboardStat(
      titleKey: 'dashboard_customers_count',
      value: '12',
      captionKey: 'dashboard_customer',
      route: AppRoute.customers,
      icon: Icons.people_outline,
      color: Colors.orange,
    );
    await tester.pumpWidget(
      GetMaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: Scaffold(
            body: SizedBox(
              width: 300,
              height: 280,
              child: DashboardStatCard(stat: stat, onTap: () => tapped = true),
            ),
          ),
        ),
      ),
    );

    expect(find.text('0%'), findsNothing);
    expect(find.text('dashboard_from_yesterday'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('12'));
    expect(tapped, isTrue);
  });

  testWidgets(
    'admin dashboard keeps sections and opens invoice/customer rows',
    (tester) async {
      final services = await _services();
      final controller = _TestAdminController(services)
        ..statusRequest = StatusRequest.success
        ..snapshot = _snapshot();
      Get.put<AdminDashboardController>(controller);
      await tester.binding.setSurfaceSize(const Size(1100, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        const GetMaterialApp(home: Scaffold(body: AdminDashboardContent())),
      );
      await tester.pumpAndSettle();

      expect(find.text('dashboard_latest_invoices'), findsOneWidget);
      expect(find.text('dashboard_invoice_chart'), findsOneWidget);
      expect(find.text('dashboard_invoice_summary'), findsOneWidget);
      expect(find.text('dashboard_top_customers'), findsOneWidget);
      expect(find.text('dashboard_sales_by_representative'), findsOneWidget);
      expect(find.text('dashboard_alerts'), findsOneWidget);
      expect(find.text('dashboard_no_sales_reps_yet'), findsOneWidget);

      await tester.ensureVisible(find.text('INV-1').first);
      await tester.tap(find.text('INV-1').first);
      expect(controller.routes, contains(AppRoute.invoiceDetailsPath('inv-1')));

      await tester.ensureVisible(find.text('Acme').last);
      await tester.tap(find.text('Acme').last);
      expect(
        controller.routes,
        contains(AppRoute.customerDetailsPath('cust-1')),
      );
      expect(controller.stats.last.route, AppRoute.pendingUsers);
      await tester.pumpAndSettle();
    },
  );

  testWidgets('sales rep keeps all sections and shows dynamic custody totals', (
    tester,
  ) async {
    final controller =
        SalesRepDashboardController(
            repository: _FakeFinancialRepository(),
            myServices: await _services(),
            permissionResolver: _FakePermissionResolver(),
          )
          ..statusRequest = StatusRequest.success
          ..snapshot = _snapshot()
          ..custodyItemCount = 3
          ..custodyTotalQuantity = 12.5;
    await tester.binding.setSurfaceSize(const Size(390, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      GetMaterialApp(
        home: Scaffold(
          body: SalesRepDashboardBody(name: 'Rep', controller: controller),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('sales_rep_home_overview'), findsOneWidget);
    expect(find.text('sales_rep_home_quick_actions'), findsOneWidget);
    expect(find.text('sales_rep_home_more_services'), findsOneWidget);
    expect(find.text('sales_rep_home_needs_attention'), findsOneWidget);
    expect(find.text('sales_rep_home_recent_activity'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(find.text('sales_rep_home_view_inventory'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('custody metric falls back to a truthful CTA when unavailable', (
    tester,
  ) async {
    final controller = SalesRepDashboardController(
      repository: _FakeFinancialRepository(),
      myServices: await _services(),
      permissionResolver: _FakePermissionResolver(),
    );
    await tester.pumpWidget(
      GetMaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: SalesRepOverviewMetrics(controller: controller),
          ),
        ),
      ),
    );
    expect(find.text('sales_rep_home_view_inventory'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'sales rep dashboard exposes consistent loading and error states',
    (tester) async {
      final controller = SalesRepDashboardController(
        repository: _FakeFinancialRepository(),
        myServices: await _services(),
        permissionResolver: _FakePermissionResolver(),
      );
      await tester.pumpWidget(
        GetMaterialApp(
          home: Scaffold(
            body: SalesRepDashboardBody(name: 'Rep', controller: controller),
          ),
        ),
      );
      expect(find.byType(FatooraProgressIndicator), findsNothing);
      expect(find.byKey(const ValueKey('loading')), findsOneWidget);

      controller.statusRequest = StatusRequest.serverfailure;
      await tester.pumpWidget(
        GetMaterialApp(
          home: Scaffold(
            body: SalesRepDashboardBody(name: 'Rep', controller: controller),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('financial_load_error'), findsOneWidget);
      expect(find.byKey(const ValueKey('error')), findsOneWidget);
    },
  );

  test('sales rep refresh reloads the selected current month once', () async {
    final repository = _FakeFinancialRepository();
    final controller = SalesRepDashboardController(
      repository: repository,
      myServices: await _services(),
      permissionResolver: _FakePermissionResolver(),
    );
    await controller.refreshDashboard();

    expect(repository.dashboardCalls, 1);
    expect(controller.statusRequest, StatusRequest.success);
    expect(controller.selectedPeriod.isSameMonth(DateTime.now()), isTrue);
  });
}

Future<MyServices> _services() async {
  SharedPreferences.setMockInitialValues({
    'name': 'Test User',
    'companyId': 'company-1',
  });
  return MyServices().init();
}

FinancialDashboardSnapshot _snapshot() {
  final now = DateTime(2026, 9, 22, 12);
  final invoice = InvoiceModel.fromMap({
    'companyId': 'company-1',
    'invoiceNumber': 'INV-1',
    'invoiceStatus': 'confirmed',
    'paymentStatus': 'paid',
    'invoiceDate': now,
    'customerId': 'cust-1',
    'customerSnapshot': {'id': 'cust-1', 'name': 'Acme'},
    'grandTotal': 20,
  }, id: 'inv-1');
  final customer = CustomerModel.fromMap({
    'companyId': 'company-1',
    'name': 'Acme',
    'createdAt': now,
    'updatedAt': now,
  }, id: 'cust-1');
  return FinancialDashboardSnapshot(
    totalSales: 20,
    cashSales: 20,
    creditSales: 0,
    partialSales: 0,
    totalReceivables: 5,
    cashInHand: 8,
    companyCash: 4,
    repCashOutstanding: 4,
    totalExpenses: 2,
    pendingExpenseCount: 1,
    invoiceCount: 1,
    customerCount: 1,
    receiptCount: 0,
    recentInvoices: [invoice],
    recentReceipts: const [],
    topCustomers: [FinancialCustomerBalance(customer: customer, balance: 5)],
    cashBySalesRep: const [],
    salesByRep: const [],
    salesByRepSummary: const [],
    weeklyInvoiceValues: const [0, 0, 0, 20, 0, 0, 0],
  );
}

class _TestAdminController extends AdminDashboardController {
  _TestAdminController(MyServices services)
    : super(
        repository: _FakeAdminAuthRepository(),
        financialRepository: _FakeFinancialRepository(),
        myServices: services,
        contextReader: _FakeBusinessUserContextReader(),
      );

  final routes = <String>[];

  @override
  void onReady() {}

  @override
  void navigateTo(String route) => routes.add(route);
}

class _FakeAdminAuthRepository implements AdminAuthRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeFinancialRepository implements FinancialRepository {
  int dashboardCalls = 0;

  @override
  Future<FinancialDashboardSnapshot> fetchDashboard({
    String companyId = 'default_company',
    DateTime? fromDate,
    DateTime? toDate,
  }) async {
    dashboardCalls++;
    return _snapshot();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakePermissionResolver implements BusinessPermissionResolver {
  @override
  Future<EffectiveBusinessPermissions> resolve(String companyId) async {
    return const EffectiveBusinessPermissions(
      isAdmin: false,
      isSalesRep: true,
      createCustomers: true,
      createReceipts: true,
      createReturns: true,
      createQuotations: true,
      editCatalogPrice: true,
      applyDiscount: true,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeBusinessUserContextReader implements BusinessUserContextReader {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
