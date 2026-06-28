import 'package:fatoora/core/class/handilingdataview.dart';
import 'package:fatoora/core/constants/color.dart';
import 'package:fatoora/features/settings/controllers/settings_controller.dart';
import 'package:fatoora/features/settings/view/models/settings_menu_section.dart';
import 'package:fatoora/features/settings/view/widgets/settings_section_card.dart';
import 'package:fatoora/features/shared/business/business_shell.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final settingsController = Get.find<SettingsController>();
    return BusinessShell(
      title: 'settings'.tr,
      showBackButton: !settingsController.isAdmin,
      onBack: settingsController.goBack,
      child: GetBuilder<SettingsController>(
        builder: (controller) => HandilingDataView(
          statusrequest: controller.statusRequest,
          errorMessage: controller.loadErrorMessageKey.tr,
          retryLabel: 'settings_retry'.tr,
          onRetry: controller.loadSettings,
          widget: _SettingsMenu(controller: controller),
        ),
      ),
    );
  }
}

class _SettingsMenu extends StatelessWidget {
  const _SettingsMenu({required this.controller});

  final SettingsController controller;

  @override
  Widget build(BuildContext context) {
    final sections = settingsMenuSections(isAdmin: controller.isAdmin);
    final compact = MediaQuery.sizeOf(context).width < 600;

    return SingleChildScrollView(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 14 : 24,
        vertical: compact ? 16 : 24,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1120),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'settings'.tr,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: AppColor.secondaryColor,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                'settings_main_subtitle'.tr,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: AppColor.grey),
              ),
              const SizedBox(height: 20),
              LayoutBuilder(
                builder: (context, constraints) {
                  const spacing = 16.0;
                  final columns = constraints.maxWidth >= 820 ? 2 : 1;
                  final width =
                      (constraints.maxWidth - spacing * (columns - 1)) /
                      columns;
                  return Wrap(
                    spacing: spacing,
                    runSpacing: spacing,
                    children: [
                      for (final section in sections)
                        SizedBox(
                          width: width,
                          child: _SettingsMenuCard(section: section),
                        ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 28),
            ],
          ),
        ),
      ),
    );
  }
}

class _SettingsMenuCard extends StatelessWidget {
  const _SettingsMenuCard({required this.section});

  final SettingsMenuSection section;

  @override
  Widget build(BuildContext context) {
    final rtl = Directionality.of(context) == TextDirection.rtl;
    return Semantics(
      button: true,
      label: '${section.titleKey.tr}. ${section.subtitleKey.tr}',
      child: SettingsSectionCard(
        title: section.titleKey.tr,
        subtitle: section.subtitleKey.tr,
        icon: section.icon,
        onTap: () => Get.toNamed<void>(section.route),
        trailing: Tooltip(
          message: 'settings_open_section'.tr,
          child: Icon(
            rtl ? Icons.chevron_left_rounded : Icons.chevron_right_rounded,
            color: AppColor.grey,
          ),
        ),
      ),
    );
  }
}
