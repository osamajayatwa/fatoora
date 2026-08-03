import 'package:fatoora/app/routes/app_pages.dart';
import 'package:fatoora/app/routes/app_routes.dart';
import 'package:fatoora/core/localization/audit_log_translations.dart';
import 'package:fatoora/core/middleware/middleware.dart';
import 'package:fatoora/core/services/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('audit route is protected by the admin middleware', () async {
    SharedPreferences.setMockInitialValues({});
    Get.put<MyServices>(await MyServices().init());
    final route = routes.singleWhere(
      (page) => page.name == AppRoute.adminAuditLog,
    );
    expect(route.middlewares, isNotEmpty);
    expect(route.middlewares!.whereType<AdminMiddleware>(), hasLength(1));
    Get.reset();
  });

  test('audit UI and emitted action codes are localized in both languages', () {
    const requiredUiKeys = [
      'audit_log_title',
      'audit_log_description',
      'audit_event_details',
      'audit_changes',
      'audit_financial_impact',
      'audit_inventory_impact',
      'audit_related_events',
      'audit_technical_metadata',
    ];
    const actionKeys = [
      'customer.created',
      'customer.opening_balance_created',
      'customer.opening_balance_adjusted',
      'invoice.created',
      'invoice.confirmed',
      'sales_return.confirmed',
      'receipt.created',
      'inventory_transfer.confirmed',
      'expense.approved',
      'expense.rejected',
      'settlement.confirmed',
      'user.role_changed',
      'user.deactivated',
      'document_prefix.changed',
      'numbering_counter.changed',
    ];
    for (final key in [...requiredUiKeys, ...actionKeys]) {
      expect(auditLogEnglishTranslations[key], isNotEmpty, reason: key);
      expect(auditLogArabicTranslations[key], isNotEmpty, reason: key);
    }
  });
}
