import 'package:fatoora/features/settings/controllers/admin_settings_controller.dart';
import 'package:fatoora/features/settings/view/widgets/settings_switch_tile.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class CompanySettingsForm extends StatelessWidget {
  const CompanySettingsForm({super.key, required this.controller});

  final AdminSettingsController controller;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _field(
          controller: controller.companyNameController,
          label: 'settings_company_name'.tr,
          required: true,
        ),
        _field(
          controller: controller.countryController,
          label: 'settings_country'.tr,
          required: true,
        ),
        _field(
          controller: controller.emailController,
          label: 'settings_email'.tr,
          keyboardType: TextInputType.emailAddress,
          validator: (value) {
            final text = value?.trim() ?? '';
            if (text.isEmpty) return 'settings_field_required'.tr;
            if (!text.contains('@')) return 'settings_invalid_email'.tr;
            return null;
          },
        ),
        _field(
          controller: controller.websiteController,
          label: 'settings_website'.tr,
        ),
        _field(
          controller: controller.phoneController,
          label: 'settings_phone'.tr,
          keyboardType: TextInputType.phone,
        ),
        _field(
          controller: controller.addressController,
          label: 'settings_address'.tr,
          maxLines: 2,
        ),
        SettingsSwitchTile(
          title: 'settings_logo_enabled'.tr,
          subtitle: 'settings_logo_reference_todo'.tr,
          value: controller.logoEnabled,
          onChanged: controller.setLogoEnabled,
        ),
      ],
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    bool required = false,
    int maxLines = 1,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: controller,
        maxLines: maxLines,
        keyboardType: keyboardType,
        decoration: InputDecoration(labelText: label),
        validator:
            validator ??
            (value) {
              if (required && (value?.trim().isEmpty ?? true)) {
                return 'settings_field_required'.tr;
              }
              return null;
            },
      ),
    );
  }
}
