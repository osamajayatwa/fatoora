import 'package:fatoora/core/services/services.dart';
import 'package:fatoora/features/invoices/bindings/invoices_list_binding.dart';
import 'package:fatoora/features/invoices/controllers/invoice_details_controller.dart';
import 'package:fatoora/features/invoices/data/repositories/invoice_repository.dart';
import 'package:get/get.dart';

class InvoiceDetailsBinding extends Bindings {
  @override
  void dependencies() {
    registerInvoiceCoreDependencies();
    Get.lazyPut<InvoiceDetailsController>(
      () => InvoiceDetailsController(
        repository: Get.find<InvoiceRepository>(),
        myServices: Get.find<MyServices>(),
      ),
    );
  }
}
