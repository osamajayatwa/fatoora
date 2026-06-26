import 'package:fatoora/core/services/services.dart';
import 'package:fatoora/features/admin_dashboard/binding/admin_dashboard_binding.dart';
import 'package:fatoora/features/inventory/controllers/inventory_adjustment_controller.dart';
import 'package:fatoora/features/inventory/controllers/inventory_dashboard_controller.dart';
import 'package:fatoora/features/inventory/controllers/item_stock_details_controller.dart';
import 'package:fatoora/features/inventory/controllers/stock_movements_controller.dart';
import 'package:fatoora/features/inventory/data/repositories/inventory_repository.dart';
import 'package:fatoora/features/items/binding/items_binding.dart';
import 'package:fatoora/features/items/data/repositories/item_repository.dart';
import 'package:get/get.dart';

void registerInventoryDependencies() {
  registerAdminDashboardDependencies();
  registerItemsCoreDependencies();
  if (!Get.isRegistered<InventoryRepository>()) {
    Get.lazyPut<InventoryRepository>(InventoryRepository.new, fenix: true);
  }
}

class InventoryDashboardBinding extends Bindings {
  @override
  void dependencies() {
    registerInventoryDependencies();
    Get.lazyPut<InventoryDashboardController>(
      () => InventoryDashboardController(
        repository: Get.find<InventoryRepository>(),
        myServices: Get.find<MyServices>(),
      ),
    );
  }
}

class StockMovementsBinding extends Bindings {
  @override
  void dependencies() {
    registerInventoryDependencies();
    Get.lazyPut<StockMovementsController>(
      () => StockMovementsController(
        repository: Get.find<InventoryRepository>(),
        myServices: Get.find<MyServices>(),
      ),
    );
  }
}

class InventoryAdjustmentBinding extends Bindings {
  @override
  void dependencies() {
    registerInventoryDependencies();
    Get.lazyPut<InventoryAdjustmentController>(
      () => InventoryAdjustmentController(
        repository: Get.find<InventoryRepository>(),
        myServices: Get.find<MyServices>(),
      ),
    );
  }
}

class ItemStockDetailsBinding extends Bindings {
  @override
  void dependencies() {
    registerInventoryDependencies();
    Get.lazyPut<ItemStockDetailsController>(
      () => ItemStockDetailsController(
        inventoryRepository: Get.find<InventoryRepository>(),
        itemRepository: Get.find<ItemRepository>(),
        myServices: Get.find<MyServices>(),
      ),
    );
  }
}
