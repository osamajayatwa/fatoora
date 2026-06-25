import 'package:fatoora/core/services/services.dart';
import 'package:fatoora/features/auth/data/repositories/admin_auth_repository.dart';
import 'package:fatoora/features/items/data/repositories/item_repository.dart';
import 'package:fatoora/features/admin_dashboard/controller/admin_dashboard_controller.dart';
import 'package:fatoora/features/items/controller/items_controller.dart';
import 'package:fatoora/features/financial/bindings/financial_binding.dart';
import 'package:fatoora/features/financial/data/repositories/financial_repository.dart';
import 'package:get/get.dart';

void registerItemsCoreDependencies() {
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
  if (!Get.isRegistered<ItemRepository>()) {
    Get.lazyPut<ItemRepository>(ItemRepository.new, fenix: true);
  }
}

class ItemsBinding extends Bindings {
  @override
  void dependencies() {
    registerItemsCoreDependencies();
    Get.lazyPut<ItemsController>(
      () => ItemsController(repository: Get.find<ItemRepository>()),
    );
  }
}
