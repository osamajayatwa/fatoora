import 'package:fatoora/core/services/services.dart';
import 'package:fatoora/features/invoices/bindings/invoices_list_binding.dart';
import 'package:fatoora/features/invoices/controllers/invoice_form_controller.dart';
import 'package:fatoora/features/invoices/data/repositories/invoice_repository.dart';
import 'package:fatoora/features/invoices/data/services/invoice_number_service.dart';
import 'package:fatoora/features/invoices/data/services/invoice_totals_service.dart';
import 'package:get/get.dart';

class InvoiceFormBinding extends Bindings {
  @override
  void dependencies() {
    registerInvoiceCoreDependencies();
    Get.lazyPut<InvoiceFormController>(
      () => InvoiceFormController(
        repository: Get.find<InvoiceRepository>(),
        numberService: Get.find<InvoiceNumberService>(),
        totalsService: Get.find<InvoiceTotalsService>(),
        myServices: Get.find<MyServices>(),
      ),
    );
  }
}
