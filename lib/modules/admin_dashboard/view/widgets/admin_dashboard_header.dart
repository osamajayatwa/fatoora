import 'package:fatoora/core/constant/color.dart';
import 'package:fatoora/core/localization/changelocal.dart';
import 'package:fatoora/modules/admin_dashboard/controller/admin_dashboard_controller.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class AdminDashboardHeader extends StatelessWidget {
  const AdminDashboardHeader({super.key, required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<AdminDashboardController>();
    final localeController = Get.find<LocaleController>();
    return Container(
      height: 82,
      padding: EdgeInsets.symmetric(horizontal: compact ? 12 : 24),
      decoration: const BoxDecoration(
        color: AppColor.surface,
        border: Border(bottom: BorderSide(color: Color(0xFFE8EBF1))),
      ),
      child: Row(
        children: [
          if (compact)
            Builder(
              builder: (context) => IconButton(
                tooltip: MaterialLocalizations.of(context).openAppDrawerTooltip,
                onPressed: () => Scaffold.of(context).openDrawer(),
                icon: const Icon(Icons.menu_rounded),
                color: AppColor.secondaryColor,
              ),
            ),
          if (compact) const SizedBox(width: 4),
          if (compact)
            Expanded(
              child: Text(
                'fatoora'.tr,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: AppColor.secondaryColor,
                  fontWeight: FontWeight.w800,
                ),
              ),
            )
          else
            Expanded(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: TextField(
                  controller: controller.searchController,
                  onChanged: controller.onSearchChanged,
                  decoration: InputDecoration(
                    hintText: 'dashboard_search_hint'.tr,
                    prefixIcon: const Icon(Icons.search_rounded),
                    filled: true,
                    fillColor: const Color(0xFFFAFBFD),
                    contentPadding: const EdgeInsets.symmetric(vertical: 12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: Color(0xFFE1E5ED)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: Color(0xFFE1E5ED)),
                    ),
                  ),
                ),
              ),
            ),
          if (!compact) const SizedBox(width: 18),
          Obx(
            () => TextButton.icon(
              onPressed: controller.toggleLanguage,
              icon: const Icon(Icons.language_rounded, size: 19),
              label: Text(localeController.isRtl ? 'English' : 'العربية'),
              style: TextButton.styleFrom(
                foregroundColor: AppColor.secondaryColor,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: const BorderSide(color: Color(0xFFE1E5ED)),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Stack(
            clipBehavior: Clip.none,
            children: [
              IconButton(
                tooltip: 'dashboard_notifications'.tr,
                onPressed: controller.showNotifications,
                icon: const Icon(Icons.notifications_none_rounded),
                color: AppColor.secondaryColor,
              ),
              PositionedDirectional(
                top: 6,
                end: 6,
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: AppColor.error,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ],
          ),
          if (!compact) ...[
            const SizedBox(width: 10),
            Container(width: 1, height: 34, color: const Color(0xFFE4E7ED)),
            const SizedBox(width: 14),
            CircleAvatar(
              radius: 20,
              backgroundColor: AppColor.primaryLight,
              child: Text(
                _initials(controller.adminName),
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: AppColor.primaryDark,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(width: 10),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 150),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    controller.adminName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColor.secondaryColor,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    'dashboard_admin'.tr,
                    style: Theme.of(
                      context,
                    ).textTheme.labelSmall?.copyWith(color: AppColor.grey),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return 'A';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }
}
