import 'package:fatoora/core/constants/color.dart';
import 'package:fatoora/features/admin_dashboard/view/widgets/admin_dashboard_shell.dart';
import 'package:fatoora/features/admin_dashboard/view/widgets/dashboard_card.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class AdminSectionScreen extends StatelessWidget {
  const AdminSectionScreen({
    super.key,
    required this.titleKey,
    required this.icon,
    this.descriptionKey = 'dashboard_module_coming_soon',
  });

  final String titleKey;
  final IconData icon;
  final String descriptionKey;

  @override
  Widget build(BuildContext context) {
    return AdminDashboardShell(
      child: SingleChildScrollView(
        padding: EdgeInsets.all(
          MediaQuery.sizeOf(context).width < 600 ? 14 : 24,
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1100),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  titleKey.tr,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: context.appText,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 22),
                DashboardCard(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 70),
                    child: Column(
                      children: [
                        Container(
                          width: 82,
                          height: 82,
                          decoration: BoxDecoration(
                            color: Theme.of(
                              context,
                            ).colorScheme.primary.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(24),
                          ),
                          child: Icon(
                            icon,
                            size: 40,
                            color: AppColor.primaryColor,
                          ),
                        ),
                        const SizedBox(height: 22),
                        Text(
                          titleKey.tr,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(
                                color: context.appText,
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          descriptionKey.tr,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(color: context.appMutedText),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
