import 'package:fatoora/data/repositories/item_repository.dart';
import 'package:fatoora/modules/admin_dashboard/items/binding/items_binding.dart';
import 'package:fatoora/modules/admin_dashboard/items/controller/item_details_controller.dart';
import 'package:get/get.dart';

class ItemDetailsBinding extends Bindings {
  @override
  void dependencies() {
    registerItemsCoreDependencies();
    Get.lazyPut<ItemDetailsController>(
      () => ItemDetailsController(repository: Get.find<ItemRepository>()),
    );
  }
}
