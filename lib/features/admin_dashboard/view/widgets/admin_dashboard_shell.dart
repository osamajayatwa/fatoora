import 'package:fatoora/features/shared/navigation/adaptive_business_shell.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class AdminDashboardShell extends StatelessWidget {
  const AdminDashboardShell({
    super.key,
    required this.child,
    this.title,
    this.showBackButton = false,
    this.onBack,
  });

  final Widget child;
  final String? title;
  final bool showBackButton;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    return AdaptiveBusinessShell(
      title: title ?? 'fatoora'.tr,
      showBackButton: showBackButton,
      onBack: onBack,
      child: child,
    );
  }
}
