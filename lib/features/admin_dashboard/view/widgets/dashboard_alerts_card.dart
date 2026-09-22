import 'package:fatoora/core/constants/color.dart';
import 'package:fatoora/features/admin_dashboard/controller/admin_dashboard_controller.dart';
import 'package:fatoora/features/admin_dashboard/view/widgets/dashboard_card.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class DashboardAlertsCard extends StatelessWidget {
  const DashboardAlertsCard({super.key});

  @override
  Widget build(BuildContext context) {
    final alerts = Get.find<AdminDashboardController>().alerts;
    return DashboardCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const DashboardSectionTitle(titleKey: 'dashboard_alerts'),
          const SizedBox(height: 10),
          if (alerts.isEmpty)
            const DashboardEmptyState(
              icon: Icons.check_circle_outline_rounded,
              messageKey: 'sales_rep_home_all_good_detail',
            ),
          for (var index = 0; index < alerts.length; index++) ...[
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => Get.find<AdminDashboardController>().navigateTo(
                  alerts[index].route,
                ),
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 12,
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: alerts[index].color.withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          alerts[index].icon,
                          size: 19,
                          color: alerts[index].color,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          alerts[index].messageKey.tr,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                color: context.appText,
                                fontWeight: FontWeight.w500,
                              ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        alerts[index].date,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: context.appMutedText,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (index != alerts.length - 1)
              Divider(height: 1, color: context.appBorder),
          ],
        ],
      ),
    );
  }
}
