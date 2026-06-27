import 'package:fatoora/app/routes/app_routes.dart';
import 'package:fatoora/core/class/statusrequest.dart';
import 'package:fatoora/core/constants/color.dart';
import 'package:fatoora/core/localization/changelocal.dart';
import 'package:fatoora/core/services/services.dart';
import 'package:fatoora/features/auth/data/models/app_user_model.dart';
import 'package:fatoora/features/auth/data/repositories/auth_repository.dart';
import 'package:fatoora/features/auth/utils/auth_session.dart';
import 'package:fatoora/features/settings/controllers/admin_settings_controller.dart';
import 'package:fatoora/features/settings/controllers/user_preferences_controller.dart';
import 'package:fatoora/features/settings/data/models/app_settings_model.dart';
import 'package:fatoora/features/settings/data/models/user_preferences_model.dart';
import 'package:fatoora/features/settings/data/repositories/settings_repository.dart';
import 'package:get/get.dart';

class SettingsController extends GetxController {
  SettingsController({
    required SettingsRepository repository,
    required AuthRepository authRepository,
    required MyServices myServices,
  }) : _repository = repository,
       _authRepository = authRepository,
       _myServices = myServices;

  final SettingsRepository _repository;
  final AuthRepository _authRepository;
  final MyServices _myServices;

  StatusRequest statusRequest = StatusRequest.loading;
  String loadErrorMessageKey = 'settings_load_failed';
  AppUserModel? profile;
  AppSettingsModel appSettings = AppSettingsModel.defaults;
  UserPreferencesModel preferences = UserPreferencesModel.defaults;
  bool isLoggingOut = false;

  String get role =>
      profile?.role ?? _myServices.sharedPreferences.getString('role') ?? '';
  String get companyId =>
      profile?.companyId ??
      _myServices.sharedPreferences.getString('companyId') ??
      AuthRepository.defaultCompanyId;
  String get uid =>
      profile?.uid ?? _myServices.sharedPreferences.getString('uid') ?? '';
  bool get isAdmin => role == AuthRepository.adminRole;
  bool get isSalesRep => role == AuthRepository.salesRepRole;
  String get appVersion => '1.0.0+1';

  @override
  void onReady() {
    super.onReady();
    loadSettings();
  }

  Future<void> loadSettings() async {
    statusRequest = StatusRequest.loading;
    update();
    try {
      final loadedProfile = await _repository.getCurrentUserProfile();
      final loadedPreferences = await _repository.getUserPreferences(
        loadedProfile.uid,
      );
      final loadedAppSettings = loadedProfile.isAdmin
          ? await _repository.getAppSettings(loadedProfile.companyId)
          : AppSettingsModel.defaults;

      profile = loadedProfile;
      preferences = loadedPreferences;
      appSettings = loadedAppSettings;
      Get.find<UserPreferencesController>().hydrate(
        profile: loadedProfile,
        preferences: loadedPreferences,
      );
      if (loadedProfile.isAdmin) {
        Get.find<AdminSettingsController>().hydrate(loadedAppSettings);
      }
      statusRequest = StatusRequest.success;
    } catch (error) {
      statusRequest = _statusFor(error);
      loadErrorMessageKey = _messageFor(error, 'settings_load_failed');
    }
    if (!isClosed) update();
  }

  Future<void> goBack() async {
    if (Get.key.currentState?.canPop() ?? false) {
      Get.back<void>();
      return;
    }
    await Get.offNamed(isAdmin ? AppRoute.adminHome : AppRoute.home);
  }

  Future<void> logout() async {
    if (isLoggingOut) return;
    isLoggingOut = true;
    update();
    final target = isAdmin ? AppRoute.adminLogin : AppRoute.userLogin;
    try {
      await _authRepository.signOut();
      await AuthSession.clear(_myServices);
      if (Get.isRegistered<LocaleController>()) {
        await Get.find<LocaleController>().resetToDefault();
      }
      await Get.offAllNamed(target);
    } catch (_) {
      Get.snackbar(
        'settings'.tr,
        'settings_logout_failed'.tr,
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: AppColor.error,
        colorText: AppColor.surface,
      );
    } finally {
      isLoggingOut = false;
      if (!isClosed) update();
    }
  }

  StatusRequest _statusFor(Object error) {
    if (error is! SettingsRepositoryException) {
      return StatusRequest.serverfailure;
    }
    return switch (error.error) {
      SettingsRepositoryError.unauthenticated ||
      SettingsRepositoryError.permissionDenied => StatusRequest.unauthorized,
      SettingsRepositoryError.timeout => StatusRequest.timeout,
      SettingsRepositoryError.unavailable => StatusRequest.offlinefailure,
      SettingsRepositoryError.profileMissing ||
      SettingsRepositoryError.invalidData => StatusRequest.failure,
      SettingsRepositoryError.unknown => StatusRequest.serverfailure,
    };
  }

  String _messageFor(Object error, String fallback) {
    if (error is! SettingsRepositoryException) return fallback;
    return switch (error.error) {
      SettingsRepositoryError.permissionDenied ||
      SettingsRepositoryError.unauthenticated => 'settings_permission_denied',
      SettingsRepositoryError.profileMissing => 'settings_profile_missing',
      SettingsRepositoryError.invalidData => 'settings_invalid_data',
      SettingsRepositoryError.timeout => 'settings_timeout',
      SettingsRepositoryError.unavailable => 'settings_offline',
      SettingsRepositoryError.unknown => fallback,
    };
  }
}
