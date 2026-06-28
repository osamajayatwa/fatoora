import 'package:fatoora/core/services/services.dart';
import 'package:fatoora/core/settings/business_settings_resolver.dart';
import 'package:fatoora/features/items/data/repositories/item_repository.dart';
import 'package:fatoora/features/items/binding/items_binding.dart';
import 'package:fatoora/features/items/controller/add_item_controller.dart';
import 'package:get/get.dart';

class AddItemBinding extends Bindings {
  @override
  void dependencies() {
    registerItemsCoreDependencies();
    Get.lazyPut<AddItemController>(
      () => AddItemController(
        repository: Get.find<ItemRepository>(),
        settingsResolver: Get.find<BusinessSettingsResolver>(),
        myServices: Get.find<MyServices>(),
      ),
    );
  }
}
