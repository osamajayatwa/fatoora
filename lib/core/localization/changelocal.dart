import 'dart:async';

import 'package:fatoora/core/constants/app.dart';
import 'package:fatoora/core/services/services.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class LocaleController extends GetxController {
  final RxString activeLang = 'en'.obs;
  final Rx<Locale> _locale = Locale('en').obs;
  final Rx<ThemeData> _theme = themeEnglish.obs;

  Locale get locale => _locale.value;
  ThemeData get appTheme => _theme.value;
  bool get isRtl => activeLang.value == 'ar';

  Future<void> init() async {
    try {
      _loadLanguagePreference();

      try {
        //   NotificationService.instance.init();
      } catch (_) {}

      Get.updateLocale(locale);
      Get.changeTheme(appTheme);
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
      _theme.value = langCode == 'ar' ? themeArabic : themeEnglish;
    } catch (error) {
      debugPrint('Error loading language preference: $error');
      activeLang.value = 'en';
      _locale.value = const Locale('en');
      _theme.value = themeEnglish;
    }
  }

  void changeLang(String langCode, {bool save = true}) {
    if (langCode == activeLang.value) return;
    _applyLanguage(langCode, saveToPrefs: save);
  }

  void _applyLanguage(String langCode, {bool saveToPrefs = true}) {
    activeLang.value = langCode;
    _locale.value = Locale(langCode);
    _theme.value = langCode == 'ar' ? themeArabic : themeEnglish;

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
    Get.changeTheme(_theme.value);

    update();
  }

  Future<void> resetToDefault() async {
    if (Get.isRegistered<MyServices>()) {
      await Get.find<MyServices>().sharedPreferences.remove('lang');
    }
    _applyLanguage('en', saveToPrefs: false);
  }

  @override
  void onInit() {
    init();
    super.onInit();
  }
}
