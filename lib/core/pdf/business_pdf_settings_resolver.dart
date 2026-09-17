import 'package:fatoora/core/pdf/app_pdf_localization.dart';
import 'package:fatoora/core/pdf/business_pdf_configuration.dart';
import 'package:fatoora/core/settings/business_settings_resolver.dart';
import 'package:fatoora/features/settings/data/models/app_settings_model.dart';
import 'package:fatoora/features/settings/data/models/user_preferences_model.dart';
import 'package:fatoora/features/settings/data/repositories/settings_repository.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:get/get.dart';

class BusinessPdfSettingsResolver {
  const BusinessPdfSettingsResolver._();

  static Future<BusinessPdfConfiguration> resolve({
    required String companyId,
    bool includeUserPreferences = false,
  }) async {
    late SettingsRepository repository;
    try {
      repository = Get.isRegistered<SettingsRepository>()
          ? Get.find<SettingsRepository>()
          : SettingsRepository();
    } catch (_) {
      return BusinessPdfConfiguration.defaults(
        languageCode: _currentAppLanguage(UserPreferencesModel.defaults),
      );
    }
    final values = await Future.wait<Object>([
      _loadAppSettings(repository, companyId),
      includeUserPreferences
          ? _loadUserPreferences(repository)
          : Future.value(UserPreferencesModel.defaults),
    ]);
    final appSettings = values[0] as AppSettingsModel;
    final preferences = values[1] as UserPreferencesModel;
    final languageCode = _resolveLanguageCode(
      appSettings.pdfSettings.pdfLanguageMode,
      preferences,
    );
    return BusinessPdfConfiguration(
      companySettings: appSettings.companySettings,
      pdfSettings: appSettings.pdfSettings,
      userPreferences: preferences,
      localization: AppPdfLocalization.forLanguage(languageCode),
    );
  }

  static Future<AppSettingsModel> _loadAppSettings(
    SettingsRepository repository,
    String companyId,
  ) async {
    try {
      return await BusinessSettingsResolver(
        repository: repository,
      ).loadAppSettings(companyId);
    } catch (_) {
      return AppSettingsModel.defaults;
    }
  }

  static Future<UserPreferencesModel> _loadUserPreferences(
    SettingsRepository repository,
  ) async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
      if (uid.isEmpty) return UserPreferencesModel.defaults;
      return await BusinessSettingsResolver(
        repository: repository,
      ).loadUserPreferences(uid);
    } catch (_) {
      return UserPreferencesModel.defaults;
    }
  }

  static String _resolveLanguageCode(
    String mode,
    UserPreferencesModel preferences,
  ) {
    return switch (mode.trim().toLowerCase()) {
      'ar' || 'arabic' => 'ar',
      'en' || 'english' => 'en',
      _ => _currentAppLanguage(preferences),
    };
  }

  static String _currentAppLanguage(UserPreferencesModel preferences) {
    final current = Get.locale?.languageCode.toLowerCase();
    if (current == 'ar' || current == 'en') return current!;
    return preferences.language == 'ar' ? 'ar' : 'en';
  }
}
