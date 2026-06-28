import 'package:fatoora/app/routes/app_routes.dart';
import 'package:fatoora/features/settings/view/models/settings_menu_section.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('admin Settings menu exposes admin and shared sections', () {
    final routes = settingsMenuSections(
      isAdmin: true,
    ).map((section) => section.route).toSet();

    expect(routes, hasLength(9));
    expect(
      routes,
      containsAll({
        AppRoute.companySettings,
        AppRoute.documentSettings,
        AppRoute.inventorySettings,
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
}
