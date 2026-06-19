import 'package:fatoora/core/constant/app.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class LocaleController extends GetxController {
  // final MyServices myServices = Get.find();

  final RxString activeLang = 'en'.obs;
  final Rx<Locale> _locale = Locale('en').obs;
  final Rx<ThemeData> _theme = themeEnglish.obs;

  Locale get locale => _locale.value;
  ThemeData get appTheme => _theme.value;
  bool get isRtl => activeLang.value == 'ar';

  Future<void> init() async {
    try {
      // await _loadLanguagePreference();

      try {
        //   NotificationService.instance.init();
      } catch (_) {}

      Get.updateLocale(locale);
      Get.changeTheme(appTheme);
    } catch (e) {
      debugPrint("LocaleController.init error: $e");
    }
  }

  // Future<void> _loadLanguagePreference() async {
  //   try {
  //     // final sp = myServices.sharedPreferences;
  //     // final saved = sp.getString('lang');
  //     // String langCode = saved ??
  //     //     (Get.deviceLocale?.languageCode ?? 'en');

  //     if (!(langCode == 'en' || langCode == 'ar')) langCode = 'en';
  //     _applyLanguage(langCode, saveToPrefs: false);
  //   } catch (e) {
  //     debugPrint("Error loading language pref: $e");
  //     _applyLanguage('en', saveToPrefs: false);
  //   }
  // }

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
        // myServices.sharedPreferences.setString('lang', langCode);
      } catch (e) {
        debugPrint("Failed to save lang pref: $e");
      }
    }

    Get.updateLocale(_locale.value);
    Get.changeTheme(_theme.value);

    update();
  }

  Future<void> resetToDefault() async {
    // await myServices.sharedPreferences.remove('lang');
    _applyLanguage('en', saveToPrefs: false);
  }

  @override
  void onInit() {
    init();
    super.onInit();
  }
}
