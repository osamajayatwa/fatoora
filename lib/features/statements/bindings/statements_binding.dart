import 'package:fatoora/core/services/services.dart';
import 'package:fatoora/features/customers/bindings/customers_binding.dart';
import 'package:fatoora/features/customers/data/repositories/customer_repository.dart';
import 'package:fatoora/features/statements/controllers/statements_controller.dart';
import 'package:get/get.dart';

class StatementsBinding extends Bindings {
  @override
  void dependencies() {
    registerCustomerDependencies();
    Get.lazyPut<StatementsController>(
      () => StatementsController(
        repository: Get.find<CustomerRepository>(),
        myServices: Get.find<MyServices>(),
      ),
    );
  }
}
