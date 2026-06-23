import 'package:fatoora/core/services/services.dart';
import 'package:fatoora/data/repositories/admin_auth_repository.dart';
import 'package:fatoora/features/invoices/controllers/invoices_list_controller.dart';
import 'package:fatoora/features/invoices/data/repositories/invoice_repository.dart';
import 'package:fatoora/features/invoices/data/services/invoice_number_service.dart';
import 'package:fatoora/features/invoices/data/services/invoice_totals_service.dart';
import 'package:fatoora/features/invoices/data/services/jofotara_placeholder_service.dart';
import 'package:fatoora/modules/admin_dashboard/controller/admin_dashboard_controller.dart';
import 'package:get/get.dart';

void registerInvoiceCoreDependencies() {
  if (!Get.isRegistered<AdminAuthRepository>()) {
    Get.lazyPut<AdminAuthRepository>(AdminAuthRepository.new, fenix: true);
  }
  if (!Get.isRegistered<AdminDashboardController>()) {
    Get.lazyPut<AdminDashboardController>(
      () => AdminDashboardController(
        repository: Get.find<AdminAuthRepository>(),
        myServices: Get.find<MyServices>(),
      ),
      fenix: true,
    );
  }
  if (!Get.isRegistered<InvoiceTotalsService>()) {
    Get.lazyPut<InvoiceTotalsService>(
      () => const InvoiceTotalsService(),
      fenix: true,
    );
  }
  if (!Get.isRegistered<InvoiceNumberService>()) {
    Get.lazyPut<InvoiceNumberService>(
      () => const InvoiceNumberService(),
      fenix: true,
    );
  }
  if (!Get.isRegistered<JofotaraPlaceholderService>()) {
    Get.lazyPut<JofotaraPlaceholderService>(
      JofotaraPlaceholderService.new,
      fenix: true,
    );
  }
  if (!Get.isRegistered<InvoiceRepository>()) {
    Get.lazyPut<InvoiceRepository>(
      () => InvoiceRepository(jofotaraService: Get.find()),
      fenix: true,
    );
  }
}

class InvoicesListBinding extends Bindings {
  @override
  void dependencies() {
    registerInvoiceCoreDependencies();
    Get.lazyPut<InvoicesListController>(
      () => InvoicesListController(
        repository: Get.find<InvoiceRepository>(),
        myServices: Get.find<MyServices>(),
      ),
    );
  }
}
