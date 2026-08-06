import 'package:fatoora/app/app.dart';
import 'package:fatoora/core/startup/startup_error_app.dart';
import 'package:get/get.dart';
import 'package:flutter/material.dart';
import 'package:fatoora/core/localization/changelocal.dart';
import 'package:fatoora/core/services/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:fatoora/firebase_options.dart';
import 'package:intl/date_symbol_data_local.dart';
export 'package:fatoora/app/app.dart' show MyApp;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await initializeDateFormatting();
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    await initialServices();
    final localeController = Get.put(LocaleController());
    await localeController.init();
    runApp(const MyApp());
  } catch (error, stackTrace) {
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stackTrace,
        library: 'application bootstrap',
      ),
    );
    runApp(StartupErrorApp(onRetry: main));
  }
}
