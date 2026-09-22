import 'package:fatoora/app/routes/app_routes.dart';
import 'package:fatoora/core/services/services.dart';
import 'package:fatoora/features/invoices/controllers/invoice_context.dart';
import 'package:fatoora/features/invoices/data/models/invoice_enums.dart';
import 'package:get/get.dart';

abstract final class BusinessNavigationRouter {
  static bool isCurrentDestination(String route) {
    final currentPath =
        Uri.tryParse(Get.currentRoute)?.path ?? Get.currentRoute;
    final targetPath = Uri.tryParse(route)?.path ?? route;
    return currentPath == targetPath;
  }

  static Future<bool> replaceRoot(String route) async {
    if (isCurrentDestination(route)) return false;
    await Get.offNamed(route);
    return true;
  }

  static Future<bool> openCreateInvoice(MyServices services) async {
    final companyId = InvoiceContext.resolveCompanyId(services, const {});
    final changed = await Get.toNamed(
      AppRoute.invoiceForm,
      arguments: {
        'mode': 'create',
        'companyId': companyId,
        'invoiceType': InvoiceType.regular.value,
      },
    );
    return changed == true;
  }
}
