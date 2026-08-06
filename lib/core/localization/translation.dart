import 'package:fatoora/core/localization/admin_dashboard_translations.dart';
import 'package:fatoora/core/localization/admin_login_translations.dart';
import 'package:fatoora/core/localization/admin_users_translations.dart';
import 'package:fatoora/core/localization/audit_log_translations.dart';
import 'package:fatoora/core/localization/common_translations.dart';
import 'package:fatoora/core/localization/customers_translations.dart';
import 'package:fatoora/core/localization/expenses_translations.dart';
import 'package:fatoora/core/localization/financial_translations.dart';
import 'package:fatoora/core/localization/inventory_translations.dart';
import 'package:fatoora/core/localization/invoices_translations.dart';
import 'package:fatoora/core/localization/items_translations.dart';
import 'package:fatoora/core/localization/pdf_translations.dart';
import 'package:fatoora/core/localization/permissions_translations.dart';
import 'package:fatoora/core/localization/quotations_translations.dart';
import 'package:fatoora/core/localization/receipts_translations.dart';
import 'package:fatoora/core/localization/rep_inventory_translations.dart';
import 'package:fatoora/core/localization/sales_rep_home_translations.dart';
import 'package:fatoora/core/localization/sales_return_translations.dart';
import 'package:fatoora/core/localization/settings_translations.dart';
import 'package:fatoora/core/localization/user_auth_translations.dart';
import 'package:get/get.dart';

class MyTranslation extends Translations {
  @override
  Map<String, Map<String, String>> get keys => {
    'ar': {
      ...adminLoginArabicTranslations,
      ...userAuthArabicTranslations,
      ...adminDashboardArabicTranslations,
      ...adminUsersArabicTranslations,
      ...itemsArabicTranslations,
      ...invoicesArabicTranslations,
      ...customersArabicTranslations,
      ...financialArabicTranslations,
      ...expensesArabicTranslations,
      ...receiptsArabicTranslations,
      ...salesReturnArabicTranslations,
      ...pdfArabicTranslations,
      ...quotationsArabicTranslations,
      ...commonArabicTranslations,
      ...inventoryArabicTranslations,
      ...settingsArabicTranslations,
      ...permissionsArabicTranslations,
      ...repInventoryArabicTranslations,
      ...salesRepHomeArabicTranslations,
      ...auditLogArabicTranslations,
    },
    'en': {
      ...adminLoginEnglishTranslations,
      ...userAuthEnglishTranslations,
      ...adminDashboardEnglishTranslations,
      ...adminUsersEnglishTranslations,
      ...itemsEnglishTranslations,
      ...invoicesEnglishTranslations,
      ...customersEnglishTranslations,
      ...financialEnglishTranslations,
      ...expensesEnglishTranslations,
      ...receiptsEnglishTranslations,
      ...salesReturnEnglishTranslations,
      ...pdfEnglishTranslations,
      ...quotationsEnglishTranslations,
      ...commonEnglishTranslations,
      ...inventoryEnglishTranslations,
      ...settingsEnglishTranslations,
      ...permissionsEnglishTranslations,
      ...repInventoryEnglishTranslations,
      ...salesRepHomeEnglishTranslations,
      ...auditLogEnglishTranslations,
    },
  };
}
