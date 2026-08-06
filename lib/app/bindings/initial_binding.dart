import 'package:fatoora/core/network/api_service.dart';
import 'package:fatoora/features/items/data/repositories/item_repository.dart';
import 'package:get/get.dart';

class InitialBindings extends Bindings {
  @override
  void dependencies() {
    Get.put(ApiService());
    if (!Get.isRegistered<ItemRepository>()) {
      Get.lazyPut<ItemRepository>(ItemRepository.new, fenix: true);
    }
  }
}
