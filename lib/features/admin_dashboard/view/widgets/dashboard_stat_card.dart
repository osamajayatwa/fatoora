import 'package:fatoora/core/constants/color.dart';
import 'package:fatoora/features/admin_dashboard/model/admin_dashboard_models.dart';
import 'package:fatoora/features/admin_dashboard/view/widgets/dashboard_card.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class DashboardStatCard extends StatelessWidget {
  const DashboardStatCard({super.key, required this.stat, required this.onTap});

  final DashboardStat stat;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return DashboardCard(
      onTap: onTap,
      semanticLabel: stat.titleKey.tr,
      padding: const EdgeInsets.all(15),
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
              const SizedBox(width: 8),
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: stat.color,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: stat.color.withValues(alpha: 0.25),
                      blurRadius: 14,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Icon(stat.icon, color: Colors.white, size: 21),
              ),
            ],
          ),
          const SizedBox(height: 13),
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
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: Icon(
              Directionality.of(context) == TextDirection.rtl
                  ? Icons.arrow_back_rounded
                  : Icons.arrow_forward_rounded,
              size: 17,
              color: stat.color,
            ),
          ),
        ],
      ),
    );
  }
}
