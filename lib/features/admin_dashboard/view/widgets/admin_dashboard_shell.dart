import 'package:fatoora/core/constants/color.dart';
import 'package:fatoora/features/admin_dashboard/view/widgets/admin_dashboard_header.dart';
import 'package:fatoora/features/admin_dashboard/view/widgets/admin_sidebar.dart';
import 'package:flutter/material.dart';

class AdminDashboardShell extends StatelessWidget {
  const AdminDashboardShell({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 1080;
        return Scaffold(
          backgroundColor: context.appBackground,
          drawer: compact
              ? const Drawer(
                  width: 286,
                  shape: RoundedRectangleBorder(),
                  child: AdminSidebar(),
                )
              : null,
          body: Row(
            children: [
              if (!compact) const SizedBox(width: 272, child: AdminSidebar()),
              Expanded(
                child: SafeArea(
                  left: compact,
                  child: Column(
                    children: [
                      AdminDashboardHeader(compact: compact),
                      Expanded(child: child),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
