import 'package:fatoora/core/settings/business_settings_resolver.dart';
import 'package:fatoora/features/settings/data/repositories/settings_repository.dart';
import 'package:get/get.dart';

void registerSettingsDependencies() {
  if (!Get.isRegistered<SettingsRepository>()) {
    Get.lazyPut<SettingsRepository>(SettingsRepository.new, fenix: true);
  }
  if (!Get.isRegistered<BusinessSettingsResolver>()) {
    Get.lazyPut<BusinessSettingsResolver>(
      () =>
          BusinessSettingsResolver(repository: Get.find<SettingsRepository>()),
      fenix: true,
    );
  }
}
