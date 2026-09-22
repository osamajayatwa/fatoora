import 'dart:ui' show SemanticsFlag;

import 'package:fatoora/app/routes/app_routes.dart';
import 'package:fatoora/core/services/services.dart';
import 'package:fatoora/core/settings/business_permission_resolver.dart';
import 'package:fatoora/features/admin_dashboard/controller/admin_dashboard_controller.dart';
import 'package:fatoora/features/admin_dashboard/view/widgets/admin_dashboard_shell.dart';
import 'package:fatoora/features/auth/data/repositories/auth_repository.dart';
import 'package:fatoora/features/shared/navigation/adaptive_business_shell.dart';
import 'package:fatoora/features/shared/navigation/business_navigation_destination.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() async {
    await Get.delete<MyServices>(force: true);
    Get.reset();
  });

  test('More destinations are scoped to effective role permissions', () {
    const admin = BusinessNavigationAccess(
      role: AuthRepository.adminRole,
      permissions: EffectiveBusinessPermissions(
        isAdmin: true,
        isSalesRep: false,
        createCustomers: true,
        createReceipts: true,
        createReturns: true,
        createQuotations: true,
        editCatalogPrice: true,
        applyDiscount: true,
      ),
    );
    const salesRep = BusinessNavigationAccess(
      role: AuthRepository.salesRepRole,
      permissions: EffectiveBusinessPermissions(
        isAdmin: false,
        isSalesRep: true,
        createCustomers: false,
        createReceipts: false,
        createReturns: false,
        createQuotations: false,
        editCatalogPrice: false,
        applyDiscount: false,
      ),
    );

    final adminRoutes = BusinessNavigationCatalog.more(
      admin,
    ).map((item) => item.route);
    final repRoutes = BusinessNavigationCatalog.more(
      salesRep,
    ).map((item) => item.route);

    expect(adminRoutes, contains(AppRoute.adminUsers));
    expect(adminRoutes, contains(AppRoute.financialLedger));
    expect(adminRoutes, contains(AppRoute.adminAuditLog));
    expect(repRoutes, isNot(contains(AppRoute.adminUsers)));
    expect(repRoutes, isNot(contains(AppRoute.financialLedger)));
    expect(repRoutes, isNot(contains(AppRoute.adminAuditLog)));
    expect(repRoutes, contains(AppRoute.repInventory));
  });

  testWidgets('admin mobile shell exposes persistent primary navigation', (
    tester,
  ) async {
    await _registerServices(role: AuthRepository.adminRole);
    await _setSurfaceSize(tester, const Size(390, 800));

    await tester.pumpWidget(
      _app(
        access: const BusinessNavigationAccess(role: AuthRepository.adminRole),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('adaptive-shell-mobile')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('business-bottom-navigation')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('business-nav-home')), findsOneWidget);
    expect(find.byKey(const ValueKey('business-nav-invoices')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('business-nav-customers')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('business-nav-more')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('business-create-invoice-fab')),
      findsOneWidget,
    );
  });

  testWidgets('sales rep More sheet excludes admin-only modules', (
    tester,
  ) async {
    await _registerServices(role: AuthRepository.salesRepRole);
    await _setSurfaceSize(tester, const Size(390, 800));

    await tester.pumpWidget(
      _app(
        access: const BusinessNavigationAccess(
          role: AuthRepository.salesRepRole,
        ),
        initialRoute: AppRoute.home,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('business-nav-more')));
    await tester.pumpAndSettle();

    expect(find.text('dashboard_quotations'), findsOneWidget);
    expect(find.text('admin_users'), findsNothing);
    expect(find.text('financial_ledger'), findsNothing);
    expect(find.text('audit_log_title'), findsNothing);
  });

  testWidgets('central FAB reuses invoice form route and arguments', (
    tester,
  ) async {
    await _registerServices(role: AuthRepository.adminRole);
    await _setSurfaceSize(tester, const Size(390, 800));
    Map<dynamic, dynamic>? receivedArguments;

    await tester.pumpWidget(
      _app(
        access: const BusinessNavigationAccess(role: AuthRepository.adminRole),
        invoiceFormBuilder: () {
          receivedArguments = Get.arguments as Map<dynamic, dynamic>?;
          return const Scaffold(body: Text('invoice-form'));
        },
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('business-create-invoice-fab')));
    await tester.pumpAndSettle();

    expect(Get.currentRoute, AppRoute.invoiceForm);
    expect(receivedArguments?['mode'], 'create');
    expect(receivedArguments?['companyId'], 'default_company');
    expect(receivedArguments?['invoiceType'], 'regular');
  });

  testWidgets('selected tab follows route and repeated tap does not stack', (
    tester,
  ) async {
    await _registerServices(role: AuthRepository.adminRole);
    await _setSurfaceSize(tester, const Size(390, 800));
    final observer = _RecordingNavigatorObserver();
    const access = BusinessNavigationAccess(role: AuthRepository.adminRole);

    await tester.pumpWidget(_app(access: access, observer: observer));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.receipt_long_outlined).last);
    await tester.pumpAndSettle();

    expect(Get.currentRoute, AppRoute.invoices);
    final semantics = tester.getSemantics(
      find.byKey(const ValueKey('business-nav-invoices')),
    );
    expect(semantics.hasFlag(SemanticsFlag.isSelected), isTrue);
    final invoicePushes = observer.pushedNames
        .where((name) => name == AppRoute.invoices)
        .length;

    await tester.tap(find.byIcon(Icons.receipt_long_rounded).last);
    await tester.pumpAndSettle();

    expect(
      observer.pushedNames.where((name) => name == AppRoute.invoices).length,
      invoicePushes,
    );
    expect(Get.key.currentState?.canPop(), isFalse);
  });

  testWidgets('adaptive shell selects mobile tablet and desktop layouts', (
    tester,
  ) async {
    await _registerServices(role: AuthRepository.adminRole);
    const access = BusinessNavigationAccess(role: AuthRepository.adminRole);

    await _setSurfaceSize(tester, const Size(390, 800));
    await tester.pumpWidget(_app(access: access));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('adaptive-shell-mobile')), findsOneWidget);

    await tester.binding.setSurfaceSize(const Size(800, 900));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('adaptive-shell-tablet')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('business-navigation-rail')),
      findsOneWidget,
    );

    await tester.binding.setSurfaceSize(const Size(1366, 900));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('adaptive-shell-desktop')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('business-desktop-sidebar')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'admin compatibility shell does not require dashboard controller',
    (tester) async {
      await _registerServices(role: AuthRepository.adminRole);
      await _setSurfaceSize(tester, const Size(390, 800));

      expect(Get.isRegistered<AdminDashboardController>(), isFalse);
      await tester.pumpWidget(
        const GetMaterialApp(
          home: AdminDashboardShell(child: SizedBox.shrink()),
        ),
      );
      await tester.pumpAndSettle();

      expect(Get.isRegistered<AdminDashboardController>(), isFalse);
      expect(
        find.byKey(const ValueKey('adaptive-shell-mobile')),
        findsOneWidget,
      );
    },
  );
}

Future<void> _registerServices({required String role}) async {
  SharedPreferences.setMockInitialValues({
    'companyId': 'default_company',
    'role': role,
    'uid': role == AuthRepository.adminRole ? 'admin-1' : 'rep-1',
    'name': role == AuthRepository.adminRole ? 'Admin' : 'Sales Rep',
    'approvalStatus': 'approved',
    'active': true,
  });
  Get.reset();
  final services = await MyServices().init();
  Get.put<MyServices>(services);
}

Future<void> _setSurfaceSize(WidgetTester tester, Size size) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
}

Widget _app({
  required BusinessNavigationAccess access,
  String initialRoute = AppRoute.adminHome,
  NavigatorObserver? observer,
  Widget Function()? invoiceFormBuilder,
}) {
  Widget shell(String title) => AdaptiveBusinessShell(
    title: title,
    navigationAccess: access,
    child: Center(child: Text(title)),
  );

  return GetMaterialApp(
    initialRoute: initialRoute,
    navigatorObservers: observer == null ? const [] : [observer],
    getPages: [
      GetPage(name: AppRoute.adminHome, page: () => shell('admin-home')),
      GetPage(name: AppRoute.home, page: () => shell('home')),
      GetPage(name: AppRoute.invoices, page: () => shell('invoices')),
      GetPage(name: AppRoute.customers, page: () => shell('customers')),
      GetPage(
        name: AppRoute.invoiceForm,
        page:
            invoiceFormBuilder ??
            () => const Scaffold(body: Text('invoice-form')),
      ),
    ],
  );
}

class _RecordingNavigatorObserver extends NavigatorObserver {
  final List<String?> pushedNames = [];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushedNames.add(route.settings.name);
    super.didPush(route, previousRoute);
  }
}
