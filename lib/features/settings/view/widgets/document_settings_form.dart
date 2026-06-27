import 'package:fatoora/features/settings/controllers/admin_settings_controller.dart';
import 'package:fatoora/features/settings/view/widgets/settings_switch_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

class DocumentSettingsForm extends StatelessWidget {
  const DocumentSettingsForm({super.key, required this.controller});

  final AdminSettingsController controller;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _prefix(controller.invoicePrefixController, 'settings_invoice_prefix'),
        _prefix(controller.receiptPrefixController, 'settings_receipt_prefix'),
        _prefix(
          controller.quotationPrefixController,
          'settings_quotation_prefix',
        ),
        _prefix(
          controller.salesReturnPrefixController,
          'settings_sales_return_prefix',
        ),
        _number(
          controller.defaultDueDaysController,
          'settings_default_due_days',
          decimal: false,
        ),
        _number(
          controller.defaultTaxPercentController,
          'settings_default_tax_percent',
          max: 100,
        ),
        SettingsSwitchTile(
          title: 'settings_allow_discount'.tr,
          value: controller.allowDiscount,
          onChanged: controller.setAllowDiscount,
        ),
        SettingsSwitchTile(
          title: 'settings_allow_sales_rep_price_edit'.tr,
          value: controller.allowSalesRepPriceEdit,
          onChanged: controller.setAllowSalesRepPriceEdit,
        ),
      ],
    );
  }

  Widget _prefix(TextEditingController textController, String key) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: textController,
        textCapitalization: TextCapitalization.characters,
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp('[A-Za-z0-9]')),
          LengthLimitingTextInputFormatter(10),
        ],
        decoration: InputDecoration(labelText: key.tr),
        validator: (value) => value == null || value.trim().isEmpty
            ? 'settings_field_required'.tr
            : null,
      ),
    );
  }

  Widget _number(
    TextEditingController textController,
    String key, {
    bool decimal = true,
    double? max,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: textController,
        keyboardType: TextInputType.numberWithOptions(decimal: decimal),
        inputFormatters: [
          FilteringTextInputFormatter.allow(
            decimal ? RegExp(r'[0-9.]') : RegExp(r'[0-9]'),
          ),
        ],
        decoration: InputDecoration(labelText: key.tr),
        validator: (value) {
          final number = double.tryParse(value?.trim() ?? '');
          if (number == null || number < 0) return 'settings_invalid_number'.tr;
          if (max != null && number > max) {
            return 'settings_number_too_large'.trParams({
              'max': max.toStringAsFixed(0),
            });
          }
          return null;
        },
      ),
    );
  }
}
