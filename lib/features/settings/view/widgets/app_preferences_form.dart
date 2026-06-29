import 'package:fatoora/core/constants/color.dart';
import 'package:fatoora/features/settings/controllers/user_preferences_controller.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class AppPreferencesForm extends StatelessWidget {
  const AppPreferencesForm({super.key, required this.controller});

  final UserPreferencesController controller;

  @override
  Widget build(BuildContext context) {
    return Form(
      key: controller.preferencesFormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DropdownButtonFormField<String>(
            value: controller.language,
            decoration: InputDecoration(labelText: 'settings_language'.tr),
            items: [
              DropdownMenuItem(value: 'en', child: Text('settings_english'.tr)),
              DropdownMenuItem(value: 'ar', child: Text('settings_arabic'.tr)),
            ],
            onChanged: controller.setLanguage,
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: controller.themeMode,
            decoration: InputDecoration(labelText: 'settings_theme'.tr),
            items: [
              DropdownMenuItem(
                value: 'system',
                child: Text('settings_theme_system'.tr),
              ),
              DropdownMenuItem(
                value: 'light',
                child: Text('settings_theme_light'.tr),
              ),
              DropdownMenuItem(
                value: 'dark',
                child: Text('settings_theme_dark'.tr),
              ),
            ],
            onChanged: controller.setThemeMode,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: controller.defaultInvoiceNoteController,
            maxLines: 2,
            decoration: InputDecoration(
              labelText: 'settings_default_invoice_note'.tr,
            ),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: controller.defaultReceiptNoteController,
            maxLines: 2,
            decoration: InputDecoration(
              labelText: 'settings_default_receipt_note'.tr,
            ),
          ),
          const SizedBox(height: 14),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: FilledButton.icon(
              onPressed: controller.isSavingPreferences
                  ? null
                  : controller.savePreferences,
              style: FilledButton.styleFrom(
                backgroundColor: AppColor.primaryColor,
              ),
              icon: controller.isSavingPreferences
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.tune_rounded),
              label: Text('settings_save_preferences'.tr),
            ),
          ),
        ],
      ),
    );
  }
}
