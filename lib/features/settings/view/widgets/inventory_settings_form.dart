import 'package:fatoora/features/settings/controllers/admin_settings_controller.dart';
import 'package:fatoora/features/settings/view/widgets/settings_switch_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

class InventorySettingsForm extends StatelessWidget {
  const InventorySettingsForm({super.key, required this.controller});

  final AdminSettingsController controller;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: TextFormField(
            controller: controller.defaultWarehouseController,
            decoration: InputDecoration(
              labelText: 'settings_default_warehouse'.tr,
            ),
            validator: (value) => value == null || value.trim().isEmpty
                ? 'settings_field_required'.tr
                : null,
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: TextFormField(
            controller: controller.defaultMinStockController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
            ],
            decoration: InputDecoration(
              labelText: 'settings_default_min_stock'.tr,
            ),
            validator: (value) {
              final number = double.tryParse(value?.trim() ?? '');
              return number == null || number < 0
                  ? 'settings_invalid_number'.tr
                  : null;
            },
          ),
        ),
        SettingsSwitchTile(
          title: 'settings_allow_negative_stock'.tr,
          subtitle: 'settings_stage_two_not_enforced'.tr,
          value: controller.allowNegativeStock,
          onChanged: controller.setAllowNegativeStock,
        ),
        SettingsSwitchTile(
          title: 'settings_low_stock_alerts'.tr,
          value: controller.lowStockAlertsEnabled,
          onChanged: controller.setLowStockAlertsEnabled,
        ),
        SettingsSwitchTile(
          title: 'settings_track_stock_by_default'.tr,
          value: controller.trackStockByDefault,
          onChanged: controller.setTrackStockByDefault,
        ),
      ],
    );
  }
}
