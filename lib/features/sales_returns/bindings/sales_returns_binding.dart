import 'package:fatoora/core/services/services.dart';
import 'package:fatoora/core/settings/business_permission_resolver.dart';
import 'package:fatoora/features/invoices/bindings/invoices_list_binding.dart';
import 'package:fatoora/features/invoices/data/repositories/invoice_repository.dart';
import 'package:fatoora/features/sales_returns/controllers/sales_return_details_controller.dart';
import 'package:fatoora/features/sales_returns/controllers/sales_return_form_controller.dart';
import 'package:fatoora/features/sales_returns/controllers/sales_returns_list_controller.dart';
import 'package:fatoora/features/sales_returns/data/repositories/sales_return_repository.dart';
import 'package:get/get.dart';

void registerSalesReturnDependencies() {
  registerInvoiceCoreDependencies();
  if (!Get.isRegistered<SalesReturnRepository>()) {
    Get.lazyPut<SalesReturnRepository>(SalesReturnRepository.new, fenix: true);
  }
}

class SalesReturnsBinding extends Bindings {
  @override
  void dependencies() {
    registerSalesReturnDependencies();
    Get.lazyPut<SalesReturnsListController>(
      () => SalesReturnsListController(
        repository: Get.find<SalesReturnRepository>(),
        myServices: Get.find<MyServices>(),
      ),
    );
  }
}

class SalesReturnFormBinding extends Bindings {
  @override
  void dependencies() {
    registerSalesReturnDependencies();
    Get.lazyPut<SalesReturnFormController>(
      () => SalesReturnFormController(
        repository: Get.find<SalesReturnRepository>(),
        invoiceRepository: Get.find<InvoiceRepository>(),
        myServices: Get.find<MyServices>(),
        permissionResolver: Get.find<BusinessPermissionResolver>(),
      ),
    );
  }
}

class SalesReturnDetailsBinding extends Bindings {
  @override
  void dependencies() {
    registerSalesReturnDependencies();
    Get.lazyPut<SalesReturnDetailsController>(
      () => SalesReturnDetailsController(
        repository: Get.find<SalesReturnRepository>(),
        myServices: Get.find<MyServices>(),
      ),
    );
  }
}
