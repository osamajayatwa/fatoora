import 'package:fatoora/core/constants/color.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class FatooraAppBar extends StatelessWidget implements PreferredSizeWidget {
  const FatooraAppBar({
    super.key,
    required this.title,
    this.subtitle,
    this.showBackButton = false,
    this.onBack,
    this.leading,
    this.actions = const [],
    this.onSearch,
    this.onNotifications,
    this.onProfile,
    this.profileLabel,
  });

  final String title;
  final String? subtitle;
  final bool showBackButton;
  final VoidCallback? onBack;
  final Widget? leading;
  final List<Widget> actions;
  final VoidCallback? onSearch;
  final VoidCallback? onNotifications;
  final VoidCallback? onProfile;
  final String? profileLabel;

  @override
  Size get preferredSize => Size.fromHeight(subtitle == null ? 68 : 78);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final effectiveLeading =
        leading ??
        (showBackButton
            ? IconButton(
                tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                onPressed: onBack ?? Get.back<void>,
                icon: Icon(
                  Directionality.of(context) == TextDirection.rtl
                      ? Icons.arrow_forward_rounded
                      : Icons.arrow_back_rounded,
                ),
              )
            : null);
    return AppBar(
      toolbarHeight: preferredSize.height,
      automaticallyImplyLeading: false,
      leading: effectiveLeading,
      titleSpacing: effectiveLeading == null ? 20 : 4,
      shape: Border(bottom: BorderSide(color: context.appBorder)),
      title: Row(
        children: [
          if (effectiveLeading == null) ...[
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                gradient: AppColor.mainGradient,
                borderRadius: BorderRadius.circular(11),
              ),
              child: const Icon(
                Icons.receipt_long_rounded,
                color: Colors.white,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: scheme.onSurface,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (subtitle != null && subtitle!.trim().isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
      actions: [
        if (onSearch != null)
          IconButton(
            tooltip: MaterialLocalizations.of(context).searchFieldLabel,
            onPressed: onSearch,
            icon: const Icon(Icons.search_rounded),
          ),
        if (onNotifications != null)
          IconButton(
            tooltip: 'dashboard_notifications'.tr,
            onPressed: onNotifications,
            icon: const Icon(Icons.notifications_none_rounded),
          ),
        ...actions,
        if (onProfile != null)
          Padding(
            padding: const EdgeInsetsDirectional.only(end: 12, start: 4),
            child: Tooltip(
              message: profileLabel ?? '',
              child: InkWell(
                onTap: onProfile,
                borderRadius: BorderRadius.circular(20),
                child: CircleAvatar(
                  radius: 18,
                  backgroundColor: scheme.primary.withValues(alpha: .14),
                  child: Text(
                    _initial(profileLabel),
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: scheme.primary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ),
          ),
        const SizedBox(width: 4),
      ],
    );
  }

  String _initial(String? value) {
    final name = value?.trim() ?? '';
    return name.isEmpty ? 'F' : name.characters.first.toUpperCase();
  }
}
