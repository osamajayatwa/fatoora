import 'package:fatoora/core/constants/color.dart';
import 'package:fatoora/features/financial/controllers/sales_rep_dashboard_controller.dart';
import 'package:fatoora/features/home/view/widgets/sales_rep_dashboard_primitives.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

class SalesRepDashboardHeader extends StatelessWidget {
  const SalesRepDashboardHeader({
    super.key,
    required this.name,
    required this.controller,
  });

  final String name;
  final SalesRepDashboardController controller;

  @override
  Widget build(BuildContext context) {
    final locale = Get.locale?.toLanguageTag();
    final date = DateFormat.yMMMMEEEEd(locale).format(DateTime.now());
    return SalesRepDashboardSurface(
      padding: const EdgeInsetsDirectional.fromSTEB(14, 14, 10, 14),
      child: Row(
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: AppColor.primaryColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(15),
            ),
            alignment: Alignment.center,
            child: Text(
              _initials(name),
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: AppColor.primaryColor,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Container(
            width: 3,
            height: 38,
            decoration: BoxDecoration(
              color: AppColor.primaryColor,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'home_welcome_admin'.trParams({'name': name}),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: context.appText,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  date,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: context.appMutedText),
                ),
                const SizedBox(height: 2),
                InkWell(
                  onTap: () => controller.selectMonth(context),
                  borderRadius: BorderRadius.circular(6),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.calendar_month_outlined,
                        size: 14,
                        color: context.appMutedText,
                      ),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          controller.selectedMonthLabel(context),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(
                                color: AppColor.primaryColor,
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            decoration: BoxDecoration(
              color: context.appSurfaceMuted,
              borderRadius: BorderRadius.circular(13),
              border: Border.all(color: context.appBorder),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: 'sales_rep_home_settings'.tr,
                  visualDensity: VisualDensity.compact,
                  constraints: const BoxConstraints.tightFor(
                    width: 36,
                    height: 36,
                  ),
                  padding: const EdgeInsets.all(7),
                  onPressed: controller.openSettings,
                  icon: const Icon(Icons.tune_rounded, size: 20),
                  color: context.appMutedText,
                ),
                SizedBox(
                  height: 24,
                  child: VerticalDivider(width: 1, color: context.appBorder),
                ),
                IconButton(
                  tooltip: 'dashboard_refresh'.tr,
                  visualDensity: VisualDensity.compact,
                  constraints: const BoxConstraints.tightFor(
                    width: 36,
                    height: 36,
                  ),
                  padding: const EdgeInsets.all(7),
                  onPressed: controller.refreshDashboard,
                  icon: const Icon(Icons.refresh_rounded, size: 20),
                  color: AppColor.primaryColor,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String _initials(String name) {
  final words = name
      .trim()
      .split(RegExp(r'\s+'))
      .where((word) => word.isNotEmpty)
      .take(2)
      .toList();
  if (words.isEmpty) return 'F';
  return words.map((word) => word.characters.first.toUpperCase()).join();
}
