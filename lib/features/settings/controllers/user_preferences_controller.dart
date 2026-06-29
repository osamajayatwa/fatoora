import 'package:fatoora/core/constants/color.dart';
import 'package:fatoora/core/localization/changelocal.dart';
import 'package:fatoora/core/services/services.dart';
import 'package:fatoora/features/auth/data/models/app_user_model.dart';
import 'package:fatoora/features/settings/data/models/user_preferences_model.dart';
import 'package:fatoora/features/settings/data/repositories/settings_repository.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class UserPreferencesController extends GetxController {
  UserPreferencesController({
    required SettingsRepository repository,
    required MyServices myServices,
  }) : _repository = repository,
       _myServices = myServices;

  final SettingsRepository _repository;
  final MyServices _myServices;
  final GlobalKey<FormState> profileFormKey = GlobalKey<FormState>();
  final GlobalKey<FormState> preferencesFormKey = GlobalKey<FormState>();

  final nameController = TextEditingController();
  final phoneController = TextEditingController();
  final photoUrlController = TextEditingController();
  final defaultInvoiceNoteController = TextEditingController();
  final defaultReceiptNoteController = TextEditingController();

  AppUserModel? profile;
  UserPreferencesModel preferences = UserPreferencesModel.defaults;
  String language = 'en';
  String themeMode = 'system';
  bool isSavingProfile = false;
  bool isSavingPreferences = false;

  String get email => profile?.email ?? '';
  String get role => profile?.role ?? '';
  String get approvalStatus => profile?.approvalStatus ?? '';
  bool get active => profile?.active ?? false;

  void hydrate({
    required AppUserModel profile,
    required UserPreferencesModel preferences,
  }) {
    this.profile = profile;
    this.preferences = preferences;
    nameController.text = profile.name;
    phoneController.text = profile.phone;
    photoUrlController.text = profile.photoUrl;
    defaultInvoiceNoteController.text = preferences.defaultInvoiceNote;
    defaultReceiptNoteController.text = preferences.defaultReceiptNote;
    final localLanguage = _myServices.sharedPreferences.getString('lang');
    language =
        preferences.updatedAt.millisecondsSinceEpoch == 0 &&
            UserPreferencesModel.supportedLanguages.contains(localLanguage)
        ? localLanguage!
        : preferences.language;
    themeMode = preferences.themeMode;
    if (Get.isRegistered<LocaleController>()) {
      final localeController = Get.find<LocaleController>();
      localeController.changeLang(language, save: false);
      localeController.changeThemeMode(themeMode, save: false);
    }
    if (!isClosed) update();
  }

  void setLanguage(String? value) {
    if (value == null ||
        !UserPreferencesModel.supportedLanguages.contains(value)) {
      return;
    }
    language = value;
    update();
  }

  void setThemeMode(String? value) {
    if (value == null ||
        !UserPreferencesModel.supportedThemeModes.contains(value)) {
      return;
    }
    themeMode = value;
    update();
  }

  Future<void> saveProfile() async {
    final current = profile;
    if (current == null ||
        isSavingProfile ||
        !(profileFormKey.currentState?.validate() ?? false)) {
      return;
    }
    isSavingProfile = true;
    update();
    try {
      await _repository.updateSafeUserProfileFields(
        uid: current.uid,
        name: nameController.text,
        phone: phoneController.text,
        photoUrl: photoUrlController.text,
      );
      final safeName = nameController.text.trim();
      profile = current.copyWith(
        name: safeName,
        phone: phoneController.text.trim(),
        photoUrl: photoUrlController.text.trim(),
        updatedAt: DateTime.now(),
      );
      await _myServices.sharedPreferences.setString('name', safeName);
      await _myServices.sharedPreferences.setString(
        'phone',
        phoneController.text.trim(),
      );
      await _myServices.sharedPreferences.setString(
        'photoUrl',
        photoUrlController.text.trim(),
      );
      _show('settings_profile_updated', AppColor.success);
    } catch (error) {
      _show(_errorKey(error), AppColor.error);
    } finally {
      isSavingProfile = false;
      if (!isClosed) update();
    }
  }

  Future<void> savePreferences() async {
    final current = profile;
    if (current == null ||
        isSavingPreferences ||
        !(preferencesFormKey.currentState?.validate() ?? false)) {
      return;
    }
    isSavingPreferences = true;
    update();
    try {
      final next = preferences.copyWith(
        language: language,
        themeMode: themeMode,
        defaultInvoiceNote: defaultInvoiceNoteController.text.trim(),
        defaultReceiptNote: defaultReceiptNoteController.text.trim(),
        updatedAt: DateTime.now(),
      );
      await _repository.updateUserPreferences(current.uid, next);
      preferences = next;
      await _myServices.sharedPreferences.setString('lang', language);
      await _myServices.sharedPreferences.setString('themeMode', themeMode);
      if (Get.isRegistered<LocaleController>()) {
        final localeController = Get.find<LocaleController>();
        localeController.changeLang(language, save: false);
        localeController.changeThemeMode(themeMode, save: false);
      }
      _show('settings_preferences_updated', AppColor.success);
    } catch (error) {
      _show(_errorKey(error), AppColor.error);
    } finally {
      isSavingPreferences = false;
      if (!isClosed) update();
    }
  }

  String _errorKey(Object error) {
    if (error is SettingsRepositoryException) {
      if (error.error == SettingsRepositoryError.permissionDenied ||
          error.error == SettingsRepositoryError.unauthenticated) {
        return 'settings_permission_denied';
      }
      if (error.error == SettingsRepositoryError.invalidData) {
        return 'settings_invalid_data';
      }
    }
    return 'settings_save_failed';
  }

  void _show(String key, Color color) {
    Get.snackbar(
      'settings'.tr,
      key.tr,
      snackPosition: SnackPosition.BOTTOM,
      backgroundColor: color,
      colorText: AppColor.surface,
    );
  }

  @override
  void onClose() {
    nameController.dispose();
    phoneController.dispose();
    photoUrlController.dispose();
    defaultInvoiceNoteController.dispose();
    defaultReceiptNoteController.dispose();
    super.onClose();
  }
}
