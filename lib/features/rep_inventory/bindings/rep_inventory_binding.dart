import 'package:fatoora/core/services/services.dart';
import 'package:fatoora/features/admin_dashboard/binding/admin_dashboard_binding.dart';
import 'package:fatoora/features/rep_inventory/controllers/rep_inventory_controllers.dart';
import 'package:fatoora/features/rep_inventory/data/repositories/rep_inventory_repository.dart';
import 'package:get/get.dart';

void registerRepInventoryCore() {
  registerAdminDashboardDependencies();
  if (!Get.isRegistered<RepInventoryRepository>()) {
    Get.lazyPut<RepInventoryRepository>(
      RepInventoryRepository.new,
      fenix: true,
    );
  }
}

class RepInventoryBinding extends Bindings {
  @override
  void dependencies() {
    registerRepInventoryCore();
    Get.lazyPut(
      () => RepInventoryController(
        repository: Get.find(),
        myServices: Get.find<MyServices>(),
      ),
    );
  }
}

class InventoryTransfersBinding extends Bindings {
  @override
  void dependencies() {
    registerRepInventoryCore();
    Get.lazyPut(
      () => InventoryTransfersController(
        repository: Get.find(),
        myServices: Get.find<MyServices>(),
      ),
    );
  }
}

class InventoryTransferFormBinding extends Bindings {
  @override
  void dependencies() {
    registerRepInventoryCore();
    Get.lazyPut(
      () => InventoryTransferFormController(
        repository: Get.find(),
        myServices: Get.find<MyServices>(),
      ),
    );
  }
}

class InventoryTransferDetailsBinding extends Bindings {
  @override
  void dependencies() {
    registerRepInventoryCore();
    Get.lazyPut(
      () => InventoryTransferDetailsController(
        repository: Get.find(),
        myServices: Get.find<MyServices>(),
      ),
    );
  }
}
