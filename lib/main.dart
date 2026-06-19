
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'package:fatoora/core/Binding/intialbinding.dart';
import 'package:fatoora/core/localization/changelocal.dart';
import 'package:fatoora/core/localization/translation.dart';
import 'package:fatoora/core/services/services.dart';
import 'package:fatoora/routes.dart';



Future<void> main() async {

 await initialServices();

  await dotenv.load(fileName: ".env");

  final localeController = Get.put(LocaleController());
  await localeController.init(); 

  runApp(const MyApp());
}

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
        theme: localeController.appTheme,
        initialBinding: InitialBindings(),
      
      getPages: routes,
      );
    });
  }
}
