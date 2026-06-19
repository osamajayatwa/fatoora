import 'package:fatoora/core/class/api_services.dart';
import 'package:get/get.dart';
class InitialBindings extends Bindings {
  @override
  void dependencies() {
    Get.put(ApiService());
  }
}
