import 'package:fatoora/core/services/services.dart';
import 'package:fatoora/features/customers/controllers/customer_details_controller.dart';
import 'package:fatoora/features/customers/controllers/customer_form_controller.dart';
import 'package:fatoora/features/customers/controllers/customer_statement_controller.dart';
import 'package:fatoora/features/customers/controllers/customers_controller.dart';
import 'package:fatoora/features/customers/data/repositories/customer_repository.dart';
import 'package:get/get.dart';

void registerCustomerDependencies() {
  if (!Get.isRegistered<CustomerRepository>()) {
    Get.lazyPut<CustomerRepository>(CustomerRepository.new, fenix: true);
  }
}

class CustomersBinding extends Bindings {
  @override
  void dependencies() {
    registerCustomerDependencies();
    Get.lazyPut<CustomersController>(
      () => CustomersController(
        repository: Get.find<CustomerRepository>(),
        myServices: Get.find<MyServices>(),
      ),
    );
  }
}

class CustomerFormBinding extends Bindings {
  @override
  void dependencies() {
    registerCustomerDependencies();
    Get.lazyPut<CustomerFormController>(
      () => CustomerFormController(
        repository: Get.find<CustomerRepository>(),
        myServices: Get.find<MyServices>(),
      ),
    );
  }
}

class CustomerDetailsBinding extends Bindings {
  @override
  void dependencies() {
    registerCustomerDependencies();
    Get.lazyPut<CustomerDetailsController>(
      () => CustomerDetailsController(
        repository: Get.find<CustomerRepository>(),
        myServices: Get.find<MyServices>(),
      ),
    );
  }
}

class CustomerStatementBinding extends Bindings {
  @override
  void dependencies() {
    registerCustomerDependencies();
    Get.lazyPut<CustomerStatementController>(
      () => CustomerStatementController(
        repository: Get.find<CustomerRepository>(),
        myServices: Get.find<MyServices>(),
      ),
    );
  }
}
