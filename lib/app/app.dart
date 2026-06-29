import 'package:fatoora/app/bindings/initial_binding.dart';
import 'package:fatoora/app/routes/app_pages.dart';
import 'package:fatoora/core/localization/changelocal.dart';
import 'package:fatoora/core/localization/translation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final LocaleController localeController = Get.find();

    return Obx(() {
      return GetMaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'fatoora'.tr,
        translations: MyTranslation(),
        locale: localeController.locale,
        theme: localeController.lightTheme,
        darkTheme: localeController.darkTheme,
        themeMode: localeController.themeMode,
        initialBinding: InitialBindings(),
        getPages: routes,
        unknownRoute: unknownRoute,
      );
    });
  }
}
