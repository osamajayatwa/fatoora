import 'package:fatoora/core/network/api_service.dart';
import 'package:get/get.dart';

class InitialBindings extends Bindings {
  @override
  void dependencies() {
    Get.put(ApiService());
  }
}
