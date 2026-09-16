import 'package:fatoora/app/routes/app_routes.dart';
import 'package:fatoora/core/constants/app.dart';
import 'package:fatoora/core/localization/changelocal.dart';
import 'package:fatoora/core/localization/translation.dart';
import 'package:fatoora/core/services/services.dart';
import 'package:fatoora/features/splash/view/screens/language.dart';
import 'package:fatoora/features/splash/view/screens/splash.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() async {
    await Get.delete<LocaleController>(force: true);
    await Get.delete<MyServices>(force: true);
    Get.reset();
  });

  testWidgets('language screen is scroll-safe at 320px with 2x Arabic text', (
    tester,
  ) async {
    await _pumpOnboardingScreen(
      tester,
      screen: const Language(),
      size: const Size(320, 568),
      languageCode: 'ar',
      textScale: 2,
    );

    expect(find.byKey(const Key('language_compact_layout')), findsOneWidget);
    expect(find.byKey(const Key('language_option_en')), findsOneWidget);
    expect(find.byKey(const Key('language_option_ar')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('splash screen is scroll-safe at 320px with 2x Arabic text', (
    tester,
  ) async {
    await _pumpOnboardingScreen(
      tester,
      screen: const SplashScreen(),
      size: const Size(320, 568),
      languageCode: 'ar',
      textScale: 2,
    );

    expect(find.byKey(const Key('splash_compact_layout')), findsOneWidget);
    expect(find.byKey(const Key('admin_portal_option')), findsOneWidget);
    expect(find.byKey(const Key('user_portal_option')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('language screen uses its balanced desktop composition', (
    tester,
  ) async {
    await _pumpOnboardingScreen(
      tester,
      screen: const Language(),
      size: const Size(1440, 900),
    );

    expect(find.byKey(const Key('language_wide_layout')), findsOneWidget);
    expect(find.byKey(const Key('language_selection_panel')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'splash screen uses its balanced tablet and desktop composition',
    (tester) async {
      await _pumpOnboardingScreen(
        tester,
        screen: const SplashScreen(),
        size: const Size(1024, 768),
      );

      expect(find.byKey(const Key('splash_wide_layout')), findsOneWidget);
      expect(find.byKey(const Key('splash_access_panel')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('language screen stays horizontal on a wide portrait display', (
    tester,
  ) async {
    await _pumpOnboardingScreen(
      tester,
      screen: const Language(),
      size: const Size(1024, 1366),
    );

    expect(find.byKey(const Key('language_wide_layout')), findsOneWidget);
    expect(find.byKey(const Key('language_compact_layout')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('splash screen stays horizontal on a wide portrait display', (
    tester,
  ) async {
    await _pumpOnboardingScreen(
      tester,
      screen: const SplashScreen(),
      size: const Size(1024, 1366),
    );

    expect(find.byKey(const Key('splash_wide_layout')), findsOneWidget);
    expect(find.byKey(const Key('splash_compact_layout')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('selected language and continue navigation remain unchanged', (
    tester,
  ) async {
    final localeController = await _pumpOnboardingScreen(
      tester,
      screen: const Language(),
      size: const Size(1024, 768),
      languageCode: 'ar',
      routes: [
        GetPage(
          name: AppRoute.splash,
          page: () => const Scaffold(body: Text('splash-destination')),
        ),
      ],
    );

    expect(localeController.activeLang.value, 'ar');

    await tester.tap(find.byKey(const Key('language_continue_button')));
    await tester.pumpAndSettle();

    expect(Get.find<MyServices>().sharedPreferences.getString('lang'), 'ar');
    expect(find.text('splash-destination'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('splash role cards preserve their existing destinations', (
    tester,
  ) async {
    await _pumpOnboardingScreen(
      tester,
      screen: const SplashScreen(),
      size: const Size(1024, 768),
      routes: [
        GetPage(
          name: AppRoute.adminLogin,
          page: () => const Scaffold(body: Text('admin-destination')),
        ),
        GetPage(
          name: AppRoute.userLogin,
          page: () => const Scaffold(body: Text('user-destination')),
        ),
      ],
    );

    await tester.tap(find.byKey(const Key('admin_portal_option')));
    await tester.pumpAndSettle();

    expect(find.text('admin-destination'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Future<LocaleController> _pumpOnboardingScreen(
  WidgetTester tester, {
  required Widget screen,
  required Size size,
  String languageCode = 'en',
  double textScale = 1,
  List<GetPage<dynamic>> routes = const [],
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));

  SharedPreferences.setMockInitialValues({'lang': languageCode});
  Get.reset();
  final services = await MyServices().init();
  Get.put<MyServices>(services);
  final localeController = Get.put<LocaleController>(
    _TestLocaleController(languageCode),
  );

  await tester.pumpWidget(
    GetMaterialApp(
      translations: MyTranslation(),
      locale: Locale(languageCode),
      theme: languageCode == 'ar'
          ? AppTheme.light(fontFamily: 'Cairo')
          : AppTheme.light(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      getPages: routes,
      home: screen,
    ),
  );
  await tester.pumpAndSettle();
  return localeController;
}

class _TestLocaleController extends LocaleController {
  _TestLocaleController(String languageCode) {
    activeLang.value = languageCode;
  }

  @override
  Future<void> init() async {
    // App bootstrap owns preference initialization. Tests set the locale
    // explicitly so no locale reassemble races the first widget frame.
  }
}
