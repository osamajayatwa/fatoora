import 'package:fatoora/core/services/services.dart';
import 'package:fatoora/features/auth/data/repositories/admin_auth_repository.dart';
import 'package:fatoora/features/admin_dashboard/controller/admin_dashboard_controller.dart';
import 'package:fatoora/features/financial/bindings/financial_binding.dart';
import 'package:fatoora/features/financial/data/repositories/financial_repository.dart';
import 'package:get/get.dart';

void registerAdminDashboardDependencies() {
  if (!Get.isRegistered<AdminAuthRepository>()) {
    Get.lazyPut<AdminAuthRepository>(AdminAuthRepository.new, fenix: true);
  }
  registerFinancialDependencies();
  if (!Get.isRegistered<AdminDashboardController>()) {
    Get.lazyPut<AdminDashboardController>(
      () => AdminDashboardController(
        repository: Get.find<AdminAuthRepository>(),
        financialRepository: Get.find<FinancialRepository>(),
        myServices: Get.find<MyServices>(),
      ),
      fenix: true,
    );
  }
}

class AdminDashboardBinding extends Bindings {
  @override
  void dependencies() {
    registerAdminDashboardDependencies();
  }
}
