import 'package:fatoora/core/services/services.dart';
import 'package:fatoora/data/repositories/admin_auth_repository.dart';
import 'package:fatoora/data/repositories/item_repository.dart';
import 'package:fatoora/modules/admin_dashboard/controller/admin_dashboard_controller.dart';
import 'package:fatoora/modules/admin_dashboard/items/controller/items_controller.dart';
import 'package:get/get.dart';

void registerItemsCoreDependencies() {
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
