import 'package:fatoora/core/constants/color.dart';
import 'package:fatoora/core/localization/changelocal.dart';
import 'package:fatoora/features/admin_dashboard/controller/admin_dashboard_controller.dart';
import 'package:fatoora/features/admin_dashboard/view/widgets/admin_dashboard_header.dart';
import 'package:fatoora/features/admin_dashboard/view/widgets/admin_sidebar.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class AdminDashboardShell extends StatelessWidget {
  const AdminDashboardShell({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return GetBuilder<AdminDashboardController>(
      id: 'admin_shell',
      builder: (controller) {
        final localeController = Get.isRegistered<LocaleController>()
            ? Get.find<LocaleController>()
            : null;

        Widget shell(bool isRtl) => LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 1080;
            final showDesktopSidebar = !compact && controller.sidebarVisible;
            final textDirection = isRtl ? TextDirection.rtl : TextDirection.ltr;
            return Directionality(
              textDirection: textDirection,
              child: Scaffold(
                backgroundColor: context.appBackground,
                drawer: compact
                    ? const Drawer(
                        width: 286,
                        shape: RoundedRectangleBorder(),
                        child: AdminSidebar(),
                      )
                    : null,
                body: Row(
                  textDirection: textDirection,
                  children: [
                    if (showDesktopSidebar)
                      const SizedBox(
                        width: 272,
                        child: AdminSidebar(showCollapseButton: true),
                      ),
                    Expanded(
                      child: SafeArea(
                        left: compact || !showDesktopSidebar || isRtl,
                        right: compact || !showDesktopSidebar || !isRtl,
                        child: Column(
                          children: [
                            AdminDashboardHeader(
                              compact: compact,
                              sidebarVisible: showDesktopSidebar,
                              onMenuPressed: compact
                                  ? null
                                  : controller.showSidebar,
                            ),
                            Expanded(child: child),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );

        if (localeController == null) {
          return shell(Directionality.of(context) == TextDirection.rtl);
        }

        return Obx(() => shell(localeController.isRtl));
      },
    );
  }
}
