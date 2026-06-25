import 'package:fatoora/core/services/services.dart';
import 'package:fatoora/features/auth/data/repositories/admin_auth_repository.dart';
import 'package:fatoora/features/customers/bindings/customers_binding.dart';
import 'package:fatoora/features/invoices/controllers/invoices_list_controller.dart';
import 'package:fatoora/features/invoices/data/repositories/invoice_repository.dart';
import 'package:fatoora/features/invoices/data/services/invoice_number_service.dart';
import 'package:fatoora/features/invoices/data/services/invoice_totals_service.dart';
import 'package:fatoora/features/invoices/data/services/jofotara_placeholder_service.dart';
import 'package:fatoora/features/admin_dashboard/controller/admin_dashboard_controller.dart';
import 'package:fatoora/features/items/binding/items_binding.dart';
import 'package:fatoora/features/financial/bindings/financial_binding.dart';
import 'package:fatoora/features/financial/data/repositories/financial_repository.dart';
import 'package:get/get.dart';

void registerInvoiceCoreDependencies() {
  registerCustomerDependencies();
  registerItemsCoreDependencies();
  registerFinancialDependencies();
  if (!Get.isRegistered<AdminAuthRepository>()) {
    Get.lazyPut<AdminAuthRepository>(AdminAuthRepository.new, fenix: true);
  }
  if (!Get.isRegistered<AdminDashboardController>()) {
    Get.lazyPut<AdminDashboardController>(
      () => AdminDashboardController(
        repository: Get.find<AdminAuthRepository>(),
        financialRepository: Get.find<FinancialRepository>(),
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
      () => InvoiceRepository(
        jofotaraService: Get.find<JofotaraPlaceholderService>(),
      ),
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
