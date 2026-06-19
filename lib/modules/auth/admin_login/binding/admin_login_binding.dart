import 'package:fatoora/core/services/services.dart';
import 'package:fatoora/data/repositories/admin_auth_repository.dart';
import 'package:fatoora/modules/auth/admin_login/controller/admin_login_controller.dart';
import 'package:get/get.dart';

class AdminLoginBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<AdminAuthRepository>(AdminAuthRepository.new);
    Get.lazyPut<AdminLoginControllerImp>(
      () => AdminLoginControllerImp(
        repository: Get.find<AdminAuthRepository>(),
        myServices: Get.find<MyServices>(),
      ),
    );
  }
}
