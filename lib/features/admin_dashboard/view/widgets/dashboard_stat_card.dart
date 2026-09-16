import 'package:fatoora/core/constants/color.dart';
import 'package:fatoora/features/admin_dashboard/model/admin_dashboard_models.dart';
import 'package:fatoora/features/admin_dashboard/view/widgets/dashboard_card.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class DashboardStatCard extends StatelessWidget {
  const DashboardStatCard({super.key, required this.stat});

  final DashboardStat stat;

  @override
  Widget build(BuildContext context) {
    return DashboardCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  stat.titleKey.tr,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: context.appText,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: stat.color,
                  borderRadius: BorderRadius.circular(15),
                  boxShadow: [
                    BoxShadow(
                      color: stat.color.withValues(alpha: 0.25),
                      blurRadius: 14,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Icon(stat.icon, color: Colors.white, size: 25),
              ),
            ],
          ),
          const Spacer(),
          Text(
            stat.value,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              color: context.appText,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            stat.captionKey.tr,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: context.appMutedText),
          ),
          const Spacer(),
          Row(
            children: [
              const Icon(
                Icons.arrow_upward_rounded,
                size: 16,
                color: AppColor.success,
              ),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  stat.change,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: AppColor.success,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  'dashboard_from_yesterday'.tr,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: context.appMutedText),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
