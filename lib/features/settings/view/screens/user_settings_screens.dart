import 'package:fatoora/core/constants/color.dart';
import 'package:fatoora/core/motion/fatoora_overlays.dart';
import 'package:fatoora/core/motion/fatoora_motion_widgets.dart';
import 'package:fatoora/features/settings/controllers/settings_controller.dart';
import 'package:fatoora/features/settings/controllers/user_preferences_controller.dart';
import 'package:fatoora/features/settings/view/widgets/app_preferences_form.dart';
import 'package:fatoora/features/settings/view/widgets/profile_settings_form.dart';
import 'package:fatoora/features/settings/view/widgets/settings_section_scaffold.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class ProfileSettingsScreen extends StatelessWidget {
  const ProfileSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return SettingsSectionScaffold(
      titleKey: 'settings_profile',
      subtitleKey: 'settings_profile_subtitle',
      icon: Icons.person_outline_rounded,
      child: GetBuilder<UserPreferencesController>(
        builder: (controller) => ProfileSettingsForm(controller: controller),
      ),
    );
  }
}

class AppPreferencesSettingsScreen extends StatelessWidget {
  const AppPreferencesSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return SettingsSectionScaffold(
      titleKey: 'settings_preferences',
      subtitleKey: 'settings_preferences_subtitle',
      icon: Icons.tune_rounded,
      child: GetBuilder<UserPreferencesController>(
        builder: (controller) => AppPreferencesForm(controller: controller),
      ),
    );
  }
}

class AccountSettingsScreen extends StatelessWidget {
  const AccountSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return SettingsSectionScaffold(
      titleKey: 'settings_account',
      subtitleKey: 'settings_account_subtitle',
      icon: Icons.info_outline_rounded,
      child: GetBuilder<SettingsController>(
        builder: (controller) => _AccountContent(controller: controller),
      ),
    );
  }
}

class _AccountContent extends StatelessWidget {
  const _AccountContent({required this.controller});

  final SettingsController controller;

  @override
  Widget build(BuildContext context) {
    final profile = controller.profile;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _InfoRow(label: 'settings_role'.tr, value: profile?.role.tr ?? ''),
        _InfoRow(
          label: 'settings_account_status'.tr,
          value: profile?.approvalStatus.tr ?? '',
        ),
        _InfoRow(
          label: 'settings_app_version'.tr,
          value: controller.appVersion,
        ),
        const SizedBox(height: 18),
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: OutlinedButton.icon(
            onPressed: controller.isLoggingOut
                ? null
                : () => _confirmLogout(context),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColor.error,
              side: const BorderSide(color: AppColor.error),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            ),
            icon: controller.isLoggingOut
                ? const SizedBox.square(
                    dimension: 18,
                    child: FatooraProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.logout_rounded),
            label: Text('settings_logout'.tr),
          ),
        ),
      ],
    );
  }

  Future<void> _confirmLogout(BuildContext context) async {
    final confirmed = await showFatooraDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('settings_logout'.tr),
        content: Text('settings_logout_confirmation'.tr),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text('settings_cancel'.tr),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text('settings_logout'.tr),
          ),
        ],
      ),
    );
    if (confirmed == true) await controller.logout();
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: context.appMutedText),
            ),
          ),
          const SizedBox(width: 16),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: context.appText,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
