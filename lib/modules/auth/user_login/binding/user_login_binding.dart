import 'package:fatoora/core/services/services.dart';
import 'package:fatoora/data/repositories/user_auth_repository.dart';
import 'package:fatoora/modules/auth/user_login/controller/user_login_controller.dart';
import 'package:get/get.dart';

class UserLoginBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<UserAuthRepository>(UserAuthRepository.new);
    Get.lazyPut<UserLoginControllerImp>(
      () => UserLoginControllerImp(
        repository: Get.find<UserAuthRepository>(),
        myServices: Get.find<MyServices>(),
      ),
    );
  }
}
