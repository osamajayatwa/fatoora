import 'package:fatoora/core/constant/routes.dart';
import 'package:fatoora/core/services/services.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class MyMiddleware extends GetMiddleware {
  @override
  int? get priority => 1;
  MyServices myServices = Get.find();

  @override
  RouteSettings? redirect(String? route) {
    final step = myServices.sharedPreferences.getString("step");
    final role = myServices.sharedPreferences.getString("role");
    if (step == "3" && role == "admin") {
      return const RouteSettings(name: AppRoute.adminHome);
    }
    if (step == "2") {
      return const RouteSettings(name: AppRoute.home);
    }
    return null;
  }
}

class AdminMiddleware extends GetMiddleware {
  @override
  int? get priority => 1;

  final MyServices myServices = Get.find<MyServices>();

  @override
  RouteSettings? redirect(String? route) {
    final preferences = myServices.sharedPreferences;
    final isAdmin =
        preferences.getString('step') == '3' &&
        preferences.getString('role') == 'admin';
    if (!isAdmin) {
      return const RouteSettings(name: AppRoute.adminLogin);
    }
    return null;
  }
}
