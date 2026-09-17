import 'dart:async';

import 'package:fatoora/core/constants/app.dart';
import 'package:fatoora/core/services/services.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class LocaleController extends GetxController {
  final RxString activeLang = 'en'.obs;
  final Rx<Locale> _locale = Locale('en').obs;
  final RxString activeThemeMode = 'system'.obs;

  Locale get locale => _locale.value;
  ThemeData get lightTheme => isRtl ? themeArabic : themeEnglish;
  ThemeData get darkTheme => isRtl ? darkThemeArabic : darkThemeEnglish;
  ThemeMode get themeMode => switch (activeThemeMode.value) {
    'light' => ThemeMode.light,
    'dark' => ThemeMode.dark,
    _ => ThemeMode.system,
  };
  bool get isRtl => activeLang.value == 'ar';

  Future<void> init() async {
    try {
      _loadLanguagePreference();

      try {
        //   NotificationService.instance.init();
      } catch (_) {}

      Get.updateLocale(locale);
    } catch (e) {
      debugPrint("LocaleController.init error: $e");
    }
  }

  void _loadLanguagePreference() {
    try {
      if (!Get.isRegistered<MyServices>()) return;
      final saved = Get.find<MyServices>().sharedPreferences.getString('lang');
      var langCode = saved ?? Get.deviceLocale?.languageCode ?? 'en';
      if (langCode != 'en' && langCode != 'ar') langCode = 'en';
      activeLang.value = langCode;
      _locale.value = Locale(langCode);
      final savedTheme = Get.find<MyServices>().sharedPreferences.getString(
        'themeMode',
      );
      activeThemeMode.value = _normalizeThemeMode(savedTheme);
    } catch (error) {
      debugPrint('Error loading language preference: $error');
      activeLang.value = 'en';
      _locale.value = const Locale('en');
      activeThemeMode.value = 'system';
    }
  }

  void changeLang(String langCode, {bool save = true}) {
    if (langCode == activeLang.value) return;
    _applyLanguage(langCode, saveToPrefs: save);
  }

  void _applyLanguage(String langCode, {bool saveToPrefs = true}) {
    activeLang.value = langCode;
    _locale.value = Locale(langCode);

    if (saveToPrefs) {
      try {
        if (Get.isRegistered<MyServices>()) {
          unawaited(
            Get.find<MyServices>().sharedPreferences.setString(
              'lang',
              langCode,
            ),
          );
        }
      } catch (e) {
        debugPrint("Failed to save lang pref: $e");
      }
    }

    Get.updateLocale(_locale.value);
    update();
  }

  void changeThemeMode(String value, {bool save = true}) {
    final normalized = _normalizeThemeMode(value);
    activeThemeMode.value = normalized;
    if (save && Get.isRegistered<MyServices>()) {
      unawaited(
        Get.find<MyServices>().sharedPreferences.setString(
          'themeMode',
          normalized,
        ),
      );
    }
    update();
  }

  String _normalizeThemeMode(String? value) {
    return switch (value?.trim().toLowerCase()) {
      'light' => 'light',
      'dark' => 'dark',
      _ => 'system',
    };
  }

  Future<void> resetToDefault() async {
    if (Get.isRegistered<MyServices>()) {
      await Get.find<MyServices>().sharedPreferences.remove('lang');
      await Get.find<MyServices>().sharedPreferences.remove('themeMode');
    }
    activeThemeMode.value = 'system';
    _applyLanguage('en', saveToPrefs: false);
  }
}
