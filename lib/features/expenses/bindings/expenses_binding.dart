import 'package:fatoora/core/services/services.dart';
import 'package:fatoora/features/expenses/controllers/expense_details_controller.dart';
import 'package:fatoora/features/expenses/controllers/expense_form_controller.dart';
import 'package:fatoora/features/expenses/controllers/expenses_list_controller.dart';
import 'package:fatoora/features/expenses/data/repositories/expense_repository.dart';
import 'package:get/get.dart';

void registerExpenseDependencies() {
  if (!Get.isRegistered<ExpenseRepository>()) {
    Get.lazyPut<ExpenseRepository>(ExpenseRepository.new, fenix: true);
  }
}

class ExpensesBinding extends Bindings {
  @override
  void dependencies() {
    registerExpenseDependencies();
    Get.lazyPut<ExpensesListController>(
      () => ExpensesListController(
        repository: Get.find<ExpenseRepository>(),
        myServices: Get.find<MyServices>(),
      ),
    );
  }
}

class ExpenseFormBinding extends Bindings {
  @override
  void dependencies() {
    registerExpenseDependencies();
    Get.lazyPut<ExpenseFormController>(
      () => ExpenseFormController(
        repository: Get.find<ExpenseRepository>(),
        myServices: Get.find<MyServices>(),
      ),
    );
  }
}

class ExpenseDetailsBinding extends Bindings {
  @override
  void dependencies() {
    registerExpenseDependencies();
    Get.lazyPut<ExpenseDetailsController>(
      () => ExpenseDetailsController(
        repository: Get.find<ExpenseRepository>(),
        myServices: Get.find<MyServices>(),
      ),
    );
  }
}
