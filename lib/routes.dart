import 'package:fatoora/core/constant/routes.dart';
import 'package:fatoora/core/mymiddleware/middleware.dart';
import 'package:fatoora/modules/auth/admin_login/binding/admin_login_binding.dart';
import 'package:fatoora/modules/auth/admin_login/view/screen/admin_login_screen.dart';
import 'package:fatoora/modules/home/view/screen/home_screen.dart';
import 'package:fatoora/splashscreens/language.dart';
import 'package:fatoora/splashscreens/splash.dart';
import 'package:get/get_navigation/src/routes/get_route.dart';

List<GetPage<dynamic>> routes = [
  GetPage(
    name: '/',
    page: () => const Language(),
    middlewares: [MyMiddleware()],
  ),
  GetPage(name: AppRoute.language, page: () => const Language()),
  GetPage(name: AppRoute.splash, page: () => const SplashScreen()),
  GetPage(
    name: AppRoute.adminLogin,
    page: () => const AdminLoginScreen(),
    binding: AdminLoginBinding(),
  ),
  GetPage(name: AppRoute.home, page: () => const HomeScreen()),
];
