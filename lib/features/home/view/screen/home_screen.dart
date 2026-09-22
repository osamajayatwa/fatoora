import 'package:fatoora/core/services/services.dart';
import 'package:fatoora/features/auth/utils/auth_session.dart';
import 'package:fatoora/features/financial/controllers/sales_rep_dashboard_controller.dart';
import 'package:fatoora/features/home/view/widgets/sales_rep_dashboard_content.dart';
import 'package:fatoora/features/shared/navigation/adaptive_business_shell.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final services = Get.find<MyServices>();
    final name = AuthSession.cachedDisplayName(services);
    return GetBuilder<SalesRepDashboardController>(
      builder: (controller) => AdaptiveBusinessShell(
        title: 'fatoora'.tr,
        child: SalesRepDashboardBody(name: name, controller: controller),
      ),
    );
  }
}
