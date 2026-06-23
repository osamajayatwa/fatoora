import 'package:fatoora/data/repositories/item_repository.dart';
import 'package:fatoora/modules/admin_dashboard/items/binding/items_binding.dart';
import 'package:fatoora/modules/admin_dashboard/items/controller/edit_item_controller.dart';
import 'package:get/get.dart';

class EditItemBinding extends Bindings {
  @override
  void dependencies() {
    registerItemsCoreDependencies();
    Get.lazyPut<EditItemController>(
      () => EditItemController(repository: Get.find<ItemRepository>()),
    );
  }
}
