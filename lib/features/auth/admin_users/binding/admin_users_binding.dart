import 'package:fatoora/core/services/services.dart';
import 'package:fatoora/features/admin_dashboard/binding/admin_dashboard_binding.dart';
import 'package:fatoora/features/auth/admin_users/controller/admin_users_controller.dart';
import 'package:fatoora/features/auth/data/repositories/admin_auth_repository.dart';
import 'package:get/get.dart';

class AdminUsersBinding extends Bindings {
  @override
  void dependencies() {
    registerAdminDashboardDependencies();
    Get.lazyPut<AdminUsersController>(
      () => AdminUsersController(
        repository: Get.find<AdminAuthRepository>(),
        myServices: Get.find<MyServices>(),
      ),
    );
  }
}
