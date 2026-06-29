import 'package:fatoora/core/constants/color.dart';
import 'package:fatoora/features/settings/data/models/jofotara_status_settings_model.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class JofotaraStatusCard extends StatelessWidget {
  const JofotaraStatusCard({super.key, required this.settings});

  final JofotaraStatusSettingsModel settings;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.appSurfaceMuted,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.lock_outline_rounded, color: context.appMutedText),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'settings_jofotara_disabled'.tr,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: context.appText,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Chip(label: Text(settings.status.tr)),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'settings_jofotara_placeholder'.tr,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: context.appMutedText),
          ),
          const SizedBox(height: 8),
          Text(
            'settings_jofotara_no_secrets'.tr,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: AppColor.error,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
