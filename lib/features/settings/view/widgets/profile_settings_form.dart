import 'package:fatoora/core/constants/color.dart';
import 'package:fatoora/features/settings/controllers/user_preferences_controller.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class ProfileSettingsForm extends StatelessWidget {
  const ProfileSettingsForm({super.key, required this.controller});

  final UserPreferencesController controller;

  @override
  Widget build(BuildContext context) {
    return Form(
      key: controller.profileFormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextFormField(
            controller: controller.nameController,
            decoration: InputDecoration(labelText: 'settings_profile_name'.tr),
            validator: (value) {
              final name = value?.trim() ?? '';
              return name.length < 2 || name.toLowerCase() == 'undefined'
                  ? 'settings_invalid_name'.tr
                  : null;
            },
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: controller.phoneController,
            keyboardType: TextInputType.phone,
            decoration: InputDecoration(labelText: 'settings_phone'.tr),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: controller.photoUrlController,
            keyboardType: TextInputType.url,
            decoration: InputDecoration(
              labelText: 'settings_photo_url'.tr,
              helperText: 'settings_photo_upload_todo'.tr,
            ),
          ),
          const SizedBox(height: 12),
          TextFormField(
            initialValue: controller.email,
            readOnly: true,
            decoration: InputDecoration(
              labelText: 'settings_email'.tr,
              suffixIcon: const Icon(Icons.lock_outline_rounded),
            ),
          ),
          const SizedBox(height: 14),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: FilledButton.icon(
              onPressed: controller.isSavingProfile
                  ? null
                  : controller.saveProfile,
              style: FilledButton.styleFrom(
                backgroundColor: AppColor.primaryColor,
              ),
              icon: controller.isSavingProfile
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.person_outline_rounded),
              label: Text('settings_save_profile'.tr),
            ),
          ),
        ],
      ),
    );
  }
}
