import 'package:fatoora/core/constants/color.dart';
import 'package:fatoora/core/services/services.dart';
import 'package:fatoora/features/auth/data/repositories/auth_repository.dart';
import 'package:fatoora/features/admin_dashboard/view/widgets/admin_dashboard_shell.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class BusinessShell extends StatelessWidget {
  const BusinessShell({
    super.key,
    required this.child,
    required this.title,
    this.showBackButton = false,
    this.onBack,
  });

  final Widget child;
  final String title;
  final bool showBackButton;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final services = Get.find<MyServices>();
    final role = services.sharedPreferences.getString('role') ?? '';
    if (role == AuthRepository.adminRole) {
      return AdminDashboardShell(child: child);
    }

    return Scaffold(
      backgroundColor: AppColor.background,
      appBar: AppBar(
        title: Text(title),
        leading: showBackButton
            ? IconButton(
                onPressed: onBack ?? Get.back<void>,
                icon: Icon(
                  Directionality.of(context) == TextDirection.rtl
                      ? Icons.arrow_forward_rounded
                      : Icons.arrow_back_rounded,
                ),
              )
            : null,
      ),
      body: SafeArea(child: child),
    );
  }
}
