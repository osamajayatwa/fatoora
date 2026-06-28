import 'package:fatoora/core/services/services.dart';
import 'package:fatoora/features/auth/data/repositories/auth_repository.dart';
import 'package:fatoora/features/settings/controllers/admin_settings_controller.dart';
import 'package:fatoora/features/settings/controllers/settings_controller.dart';
import 'package:fatoora/features/settings/controllers/user_preferences_controller.dart';
import 'package:fatoora/features/settings/bindings/settings_dependencies.dart';
import 'package:fatoora/features/settings/data/repositories/settings_repository.dart';
import 'package:get/get.dart';

class SettingsBinding extends Bindings {
  @override
  void dependencies() {
    registerSettingsDependencies();
    if (!Get.isRegistered<AuthRepository>()) {
      Get.lazyPut<AuthRepository>(AuthRepository.new, fenix: true);
    }
    Get.lazyPut<AdminSettingsController>(
      () => AdminSettingsController(repository: Get.find<SettingsRepository>()),
    );
    Get.lazyPut<UserPreferencesController>(
      () => UserPreferencesController(
        repository: Get.find<SettingsRepository>(),
        myServices: Get.find<MyServices>(),
      ),
    );
    Get.lazyPut<SettingsController>(
      () => SettingsController(
        repository: Get.find<SettingsRepository>(),
        authRepository: Get.find<AuthRepository>(),
        myServices: Get.find<MyServices>(),
      ),
    );
  }
}
