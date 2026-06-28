import 'package:fatoora/features/settings/data/models/app_settings_model.dart';
import 'package:fatoora/features/settings/data/models/user_preferences_model.dart';
import 'package:fatoora/features/settings/data/repositories/settings_repository.dart';

class BusinessSettingsResolver {
  BusinessSettingsResolver({required SettingsRepository repository})
    : _repository = repository;

  final SettingsRepository _repository;

  Future<AppSettingsModel> loadAppSettings(String companyId) async {
    try {
      return await _repository
          .getAppSettings(companyId)
          .timeout(const Duration(seconds: 5));
    } catch (_) {
      return AppSettingsModel.defaults;
    }
  }

  Future<UserPreferencesModel> loadUserPreferences(String uid) async {
    if (uid.trim().isEmpty) return UserPreferencesModel.defaults;
    try {
      return await _repository
          .getUserPreferences(uid)
          .timeout(const Duration(seconds: 5));
    } catch (_) {
      return UserPreferencesModel.defaults;
    }
  }
}
