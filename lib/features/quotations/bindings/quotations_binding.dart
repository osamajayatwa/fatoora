import 'package:fatoora/core/services/services.dart';
import 'package:fatoora/core/settings/business_permission_resolver.dart';
import 'package:fatoora/features/invoices/bindings/invoices_list_binding.dart';
import 'package:fatoora/features/invoices/data/services/invoice_totals_service.dart';
import 'package:fatoora/features/quotations/controllers/quotation_details_controller.dart';
import 'package:fatoora/features/quotations/controllers/quotation_form_controller.dart';
import 'package:fatoora/features/quotations/controllers/quotations_list_controller.dart';
import 'package:fatoora/features/quotations/data/repositories/quotation_repository.dart';
import 'package:get/get.dart';

void registerQuotationDependencies() {
  registerInvoiceCoreDependencies();
  if (!Get.isRegistered<QuotationRepository>()) {
    Get.lazyPut<QuotationRepository>(QuotationRepository.new, fenix: true);
  }
}

class QuotationsBinding extends Bindings {
  @override
  void dependencies() {
    registerQuotationDependencies();
    Get.lazyPut<QuotationsListController>(
      () => QuotationsListController(
        repository: Get.find<QuotationRepository>(),
        myServices: Get.find<MyServices>(),
        permissionResolver: Get.find<BusinessPermissionResolver>(),
      ),
    );
  }
}

class QuotationFormBinding extends Bindings {
  @override
  void dependencies() {
    registerQuotationDependencies();
    Get.lazyPut<QuotationFormController>(
      () => QuotationFormController(
        repository: Get.find<QuotationRepository>(),
        totalsService: Get.find<InvoiceTotalsService>(),
        myServices: Get.find<MyServices>(),
        permissionResolver: Get.find<BusinessPermissionResolver>(),
      ),
    );
  }
}

class QuotationDetailsBinding extends Bindings {
  @override
  void dependencies() {
    registerQuotationDependencies();
    Get.lazyPut<QuotationDetailsController>(
      () => QuotationDetailsController(
        repository: Get.find<QuotationRepository>(),
        myServices: Get.find<MyServices>(),
      ),
    );
  }
}
