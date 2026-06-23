import 'package:fatoora/core/services/services.dart';
import 'package:fatoora/data/repositories/user_auth_repository.dart';
import 'package:fatoora/modules/auth/user_signup/controller/user_signup_controller.dart';
import 'package:get/get.dart';

class UserSignUpBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<UserAuthRepository>(UserAuthRepository.new);
    Get.lazyPut<UserSignUpControllerImp>(
      () => UserSignUpControllerImp(
        repository: Get.find<UserAuthRepository>(),
        myServices: Get.find<MyServices>(),
      ),
    );
  }
}
