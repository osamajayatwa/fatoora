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
        color: AppColor.background,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.lock_outline_rounded, color: AppColor.grey),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'settings_jofotara_disabled'.tr,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: AppColor.secondaryColor,
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
            ).textTheme.bodySmall?.copyWith(color: AppColor.grey),
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
