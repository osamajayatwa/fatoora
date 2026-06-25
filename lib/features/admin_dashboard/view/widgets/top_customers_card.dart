import 'package:fatoora/core/constants/color.dart';
import 'package:fatoora/app/routes/app_routes.dart';
import 'package:fatoora/features/admin_dashboard/controller/admin_dashboard_controller.dart';
import 'package:fatoora/features/admin_dashboard/view/widgets/dashboard_card.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class TopCustomersCard extends StatelessWidget {
  const TopCustomersCard({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<AdminDashboardController>();
    final customers = controller.topCustomers;
    const medalColors = [
      Color(0xFFFFB000),
      Color(0xFFA7AFBC),
      Color(0xFFC76B36),
    ];
    return DashboardCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DashboardSectionTitle(
            titleKey: 'dashboard_top_customers',
            trailing: TextButton(
              onPressed: () => controller.navigateTo(AppRoute.customers),
              child: Text('dashboard_view_all'.tr),
            ),
          ),
          const SizedBox(height: 10),
          for (var index = 0; index < customers.length; index++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: medalColors[index].withValues(alpha: 0.14),
                      border: Border.all(color: medalColors[index], width: 1.5),
                    ),
                    child: Text(
                      '${index + 1}',
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: medalColors[index],
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      customers[index].name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppColor.secondaryColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        customers[index].amount,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppColor.secondaryColor,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        'dashboard_jod'.tr,
                        style: Theme.of(
                          context,
                        ).textTheme.labelSmall?.copyWith(color: AppColor.grey),
                      ),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
