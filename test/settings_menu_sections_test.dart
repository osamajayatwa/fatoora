import 'package:fatoora/app/routes/app_pages.dart';
import 'package:fatoora/app/routes/app_routes.dart';
import 'package:fatoora/core/middleware/middleware.dart';
import 'package:fatoora/core/services/services.dart';
import 'package:fatoora/features/settings/view/screens/financial_settings_screens.dart';
import 'package:fatoora/features/settings/view/models/settings_menu_section.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('admin Settings menu exposes admin and shared sections', () {
    final routes = settingsMenuSections(
      isAdmin: true,
    ).map((section) => section.route).toSet();

    expect(routes, hasLength(10));
    expect(
      routes,
      containsAll({
        AppRoute.companySettings,
        AppRoute.documentSettings,
        AppRoute.inventorySettings,
        AppRoute.financialSettings,
        AppRoute.pdfSettings,
        AppRoute.permissionSettings,
        AppRoute.jofotaraSettings,
        AppRoute.profileSettings,
        AppRoute.appPreferencesSettings,
        AppRoute.accountSettings,
      }),
    );
  });

  test('sales rep Settings menu exposes only shared sections', () {
    final routes = settingsMenuSections(
      isAdmin: false,
    ).map((section) => section.route).toSet();

    expect(routes, {
      AppRoute.profileSettings,
      AppRoute.appPreferencesSettings,
      AppRoute.accountSettings,
    });
  });

  test('financial and opening balance routes are admin protected', () async {
    SharedPreferences.setMockInitialValues({});
    Get.put<MyServices>(await MyServices().init());
    final financialRoute = routes.singleWhere(
      (page) => page.name == AppRoute.financialSettings,
    );
    final openingRoute = routes.singleWhere(
      (page) => page.name == AppRoute.openingBalances,
    );

    expect(financialRoute.page(), isA<FinancialSettingsScreen>());
    expect(openingRoute.page(), isA<OpeningBalancesScreen>());
    expect(
      financialRoute.middlewares?.whereType<AdminSettingsMiddleware>(),
      hasLength(1),
    );
    expect(
      openingRoute.middlewares?.whereType<AdminSettingsMiddleware>(),
      hasLength(1),
    );
    Get.reset();
  });
}
