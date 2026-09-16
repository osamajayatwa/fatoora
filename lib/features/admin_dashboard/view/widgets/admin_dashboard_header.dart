import 'package:fatoora/core/constants/color.dart';
import 'package:fatoora/core/localization/changelocal.dart';
import 'package:fatoora/features/admin_dashboard/controller/admin_dashboard_controller.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class AdminDashboardHeader extends StatelessWidget {
  const AdminDashboardHeader({
    super.key,
    required this.compact,
    this.sidebarVisible = false,
    this.onMenuPressed,
  });

  final bool compact;
  final bool sidebarVisible;
  final VoidCallback? onMenuPressed;

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<AdminDashboardController>();
    final localeController = Get.find<LocaleController>();
    final scheme = Theme.of(context).colorScheme;
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    return Container(
      height: 82 + ((textScale - 1).clamp(0, 1).toDouble() * 28),
      padding: EdgeInsets.symmetric(horizontal: compact ? 12 : 24),
      decoration: BoxDecoration(
        color: context.appSurface,
        border: Border(bottom: BorderSide(color: context.appBorder)),
      ),
      child: Row(
        children: [
          if (compact || !sidebarVisible)
            Builder(
              builder: (context) => IconButton(
                tooltip: MaterialLocalizations.of(context).openAppDrawerTooltip,
                onPressed: compact
                    ? () => Scaffold.of(context).openDrawer()
                    : onMenuPressed,
                icon: const Icon(Icons.menu_rounded),
                color: context.appText,
              ),
            ),
          if (compact || !sidebarVisible) const SizedBox(width: 4),
          if (compact)
            Expanded(
              child: Text(
                'fatoora'.tr,
                textAlign: TextAlign.start,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: context.appText,
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
                    fillColor: context.appSurfaceMuted,
                    contentPadding: const EdgeInsets.symmetric(vertical: 12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(color: context.appBorder),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(color: context.appBorder),
                    ),
                  ),
                ),
              ),
            ),
          if (!compact) const SizedBox(width: 18),
          Obx(() {
            if (compact) {
              return IconButton(
                tooltip: localeController.isRtl ? 'English' : 'العربية',
                onPressed: controller.toggleLanguage,
                icon: const Icon(Icons.language_rounded),
              );
            }
            return TextButton.icon(
              onPressed: controller.toggleLanguage,
              icon: const Icon(Icons.language_rounded, size: 19),
              label: Text(localeController.isRtl ? 'English' : 'العربية'),
              style: TextButton.styleFrom(
                foregroundColor: context.appText,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: context.appBorder),
                ),
              ),
            );
          }),
          const SizedBox(width: 8),
          IconButton(
            tooltip: Theme.of(context).brightness == Brightness.dark
                ? 'settings_theme_light'.tr
                : 'settings_theme_dark'.tr,
            onPressed: () => localeController.changeThemeMode(
              Theme.of(context).brightness == Brightness.dark
                  ? 'light'
                  : 'dark',
            ),
            icon: Icon(
              Theme.of(context).brightness == Brightness.dark
                  ? Icons.light_mode_outlined
                  : Icons.dark_mode_outlined,
            ),
          ),
          Stack(
            clipBehavior: Clip.none,
            children: [
              IconButton(
                tooltip: 'dashboard_notifications'.tr,
                onPressed: controller.showNotifications,
                icon: const Icon(Icons.notifications_none_rounded),
                color: context.appText,
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
            Container(width: 1, height: 34, color: context.appBorder),
            const SizedBox(width: 14),
            CircleAvatar(
              radius: 20,
              backgroundColor: scheme.primary.withValues(alpha: .13),
              child: Text(
                _initials(controller.adminName),
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: scheme.primary,
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
                      color: context.appText,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    'dashboard_admin'.tr,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: context.appMutedText,
                    ),
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
