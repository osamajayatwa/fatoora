import 'package:fatoora/core/utils/alertexitapp.dart';
import 'package:fatoora/features/admin_dashboard/view/widgets/admin_dashboard_content.dart';
import 'package:fatoora/features/admin_dashboard/view/widgets/admin_dashboard_shell.dart';
import 'package:flutter/material.dart';

class AdminHomeScreen extends StatelessWidget {
  const AdminHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) alertExitApp();
      },
      child: const AdminDashboardShell(child: AdminDashboardContent()),
    );
  }
}
