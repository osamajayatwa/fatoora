import 'package:fatoora/core/constant/color.dart';
import 'package:fatoora/core/services/services.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final services = Get.find<MyServices>();
    final name = services.sharedPreferences.getString('name') ?? '';

    return Scaffold(
      backgroundColor: AppColor.background,
      appBar: AppBar(title: Text('home_title'.tr)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'home_welcome_admin'.trParams({'name': name}),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              color: AppColor.primaryColor,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}
