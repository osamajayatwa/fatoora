import 'package:fatoora/core/services/services.dart';
import 'package:fatoora/data/repositories/admin_auth_repository.dart';
import 'package:fatoora/modules/admin_dashboard/controller/admin_dashboard_controller.dart';
import 'package:get/get.dart';

class AdminDashboardBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<AdminAuthRepository>(AdminAuthRepository.new, fenix: true);
    Get.lazyPut<AdminDashboardController>(
      () => AdminDashboardController(
        repository: Get.find<AdminAuthRepository>(),
        myServices: Get.find<MyServices>(),
      ),
      fenix: true,
    );
  }
}
