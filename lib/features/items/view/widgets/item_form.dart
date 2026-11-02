import 'package:fatoora/core/constants/color.dart';
import 'package:fatoora/core/motion/fatoora_motion_widgets.dart';
import 'package:fatoora/features/admin_dashboard/view/widgets/dashboard_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

class ItemForm extends StatelessWidget {
  const ItemForm({
    super.key,
    required this.formKey,
    required this.nameController,
    required this.codeController,
    required this.descriptionController,
    required this.unitController,
    required this.priceController,
    required this.taxRateController,
    required this.currentStockController,
    required this.openingStockController,
    required this.minStockController,
    required this.costPriceController,
    required this.barcodeController,
    required this.categoryController,
    required this.warehouseController,
    required this.active,
    required this.trackStock,
    required this.onActiveChanged,
    required this.onTrackStockChanged,
    required this.onSubmit,
    required this.submitLabel,
    required this.loading,
    this.showCurrentStock = true,
    this.inventoryLocked = false,
  });

  final GlobalKey<FormState> formKey;
  final TextEditingController nameController;
  final TextEditingController codeController;
  final TextEditingController descriptionController;
  final TextEditingController unitController;
  final TextEditingController priceController;
  final TextEditingController taxRateController;
  final TextEditingController currentStockController;
  final TextEditingController openingStockController;
  final TextEditingController minStockController;
  final TextEditingController costPriceController;
  final TextEditingController barcodeController;
  final TextEditingController categoryController;
  final TextEditingController warehouseController;
  final bool active;
  final bool trackStock;
  final ValueChanged<bool> onActiveChanged;
  final ValueChanged<bool> onTrackStockChanged;
  final VoidCallback onSubmit;
  final String submitLabel;
  final bool loading;
  final bool showCurrentStock;
  final bool inventoryLocked;

  @override
  Widget build(BuildContext context) => Form(
    key: formKey,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _section(context, 'items_basic_information'.tr, [
          _textField(
            'item-name-field',
            nameController,
            'items_name'.tr,
            Icons.inventory_2_outlined,
          ),
          _textField(
            'item-code-field',
            codeController,
            'items_code'.tr,
            Icons.qr_code_2_rounded,
          ),
          _textField(
            'item-description-field',
            descriptionController,
            'items_description'.tr,
            Icons.notes_rounded,
            maxLines: 4,
            wide: true,
          ),
          _textField(
            'item-unit-field',
            unitController,
            'items_unit'.tr,
            Icons.straighten_rounded,
          ),
          _textField(
            'item-barcode-field',
            barcodeController,
            'barcode'.tr,
            Icons.qr_code_scanner_rounded,
            required: false,
          ),
          _textField(
            'item-category-field',
            categoryController,
            'category'.tr,
            Icons.category_outlined,
            required: false,
          ),
          _switchTile(
            context,
            'items_active'.tr,
            Icons.toggle_on_outlined,
            active,
            onActiveChanged,
            key: 'item-active-switch',
          ),
        ]),
        const SizedBox(height: 14),
        _section(context, 'items_pricing'.tr, [
          _numberField(
            'item-price-field',
            priceController,
            'items_price'.tr,
            Icons.payments_outlined,
            _validatePrice,
            'items_jod'.tr,
          ),
          _numberField(
            'item-tax-field',
            taxRateController,
            'items_tax_rate'.tr,
            Icons.percent_rounded,
            _validateTax,
            '%',
          ),
          _numberField(
            'item-cost-field',
            costPriceController,
            'cost_price'.tr,
            Icons.price_change_outlined,
            _validateNonNegative,
            'items_jod'.tr,
          ),
        ]),
        const SizedBox(height: 14),
        _section(context, 'items_inventory'.tr, [
          if (inventoryLocked)
            _FormFieldSpec(
              wide: true,
              child: Text('items_inventory_locked'.tr),
            ),
          _switchTile(
            context,
            'track_stock'.tr,
            Icons.inventory_outlined,
            trackStock,
            onTrackStockChanged,
            key: 'item-track-switch',
            locked: inventoryLocked,
          ),
          if (trackStock) ...[
            if (showCurrentStock)
              _numberField(
                'item-current-stock-field',
                currentStockController,
                'current_stock'.tr,
                Icons.inventory_2_outlined,
                _validateNonNegative,
                'quantity'.tr,
              ),
            _numberField(
              'item-opening-stock-field',
              openingStockController,
              'opening_stock'.tr,
              Icons.input_rounded,
              _validateNonNegative,
              'quantity'.tr,
            ),
            _numberField(
              'item-min-stock-field',
              minStockController,
              'min_stock'.tr,
              Icons.warning_amber_rounded,
              _validateNonNegative,
              'quantity'.tr,
            ),
          ] else
            _FormFieldSpec(
              wide: true,
              child: Text(
                'track_stock_disabled'.tr,
                key: const ValueKey('item-tracking-disabled'),
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: context.appMutedText),
              ),
            ),
          _textField(
            'item-warehouse-field',
            warehouseController,
            'warehouse'.tr,
            Icons.warehouse_outlined,
          ),
        ]),
        const SizedBox(height: 18),
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: FilledButton.icon(
            key: const ValueKey('item-save-button'),
            onPressed: loading ? null : onSubmit,
            style: FilledButton.styleFrom(
              backgroundColor: AppColor.primaryColor,
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 15),
            ),
            icon: loading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: FatooraProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.check_rounded),
            label: Text(loading ? 'items_saving'.tr : submitLabel),
          ),
        ),
      ],
    ),
  );

  Widget _section(
    BuildContext context,
    String title,
    List<_FormFieldSpec> specs,
  ) => DashboardCard(
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: context.appText,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 14),
        LayoutBuilder(
          builder: (context, constraints) {
            final twoColumns =
                constraints.maxWidth >= 620 &&
                MediaQuery.textScalerOf(context).scale(1) <= 1.3;
            final width = twoColumns
                ? (constraints.maxWidth - 12) / 2
                : constraints.maxWidth;
            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final spec in specs)
                  SizedBox(
                    width: spec.wide ? constraints.maxWidth : width,
                    child: spec.child,
                  ),
              ],
            );
          },
        ),
      ],
    ),
  );

  _FormFieldSpec _textField(
    String key,
    TextEditingController controller,
    String label,
    IconData icon, {
    int maxLines = 1,
    bool required = true,
    bool wide = false,
  }) => _FormFieldSpec(
    wide: wide,
    child: TextFormField(
      key: ValueKey(key),
      controller: controller,
      enabled: !loading,
      maxLines: maxLines,
      readOnly: inventoryLocked && key == 'item-warehouse-field',
      textInputAction: maxLines > 1
          ? TextInputAction.newline
          : TextInputAction.next,
      validator: required ? _validateRequired : null,
      decoration: _decoration('$label${required ? ' *' : ''}', icon),
    ),
  );

  _FormFieldSpec _numberField(
    String key,
    TextEditingController controller,
    String label,
    IconData icon,
    String? Function(String?) validator,
    String suffix,
  ) => _FormFieldSpec(
    child: TextFormField(
      key: ValueKey(key),
      controller: controller,
      enabled: !loading,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      readOnly:
          inventoryLocked &&
          (key == 'item-current-stock-field' ||
              key == 'item-opening-stock-field'),
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
      ],
      textInputAction: TextInputAction.next,
      validator: validator,
      decoration: _decoration('$label *', icon).copyWith(suffixText: suffix),
    ),
  );

  _FormFieldSpec _switchTile(
    BuildContext context,
    String label,
    IconData icon,
    bool value,
    ValueChanged<bool> onChanged, {
    required String key,
    bool locked = false,
  }) => _FormFieldSpec(
    child: Container(
      key: ValueKey(key),
      constraints: const BoxConstraints(minHeight: 58),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: context.appSurfaceMuted,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: context.appBorder),
      ),
      child: Row(
        children: [
          Icon(icon, color: context.appMutedText),
          const SizedBox(width: 8),
          Expanded(
            child: Text(label, style: Theme.of(context).textTheme.bodyMedium),
          ),
          Switch(
            value: value,
            onChanged: loading || locked ? null : onChanged,
            activeTrackColor: AppColor.success,
          ),
        ],
      ),
    ),
  );

  InputDecoration _decoration(String label, IconData icon) => InputDecoration(
    labelText: label,
    prefixIcon: Icon(icon),
    alignLabelWithHint: true,
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(13)),
  );

  String? _validateRequired(String? value) =>
      value == null || value.trim().isEmpty ? 'items_required'.tr : null;

  String? _validatePrice(String? value) {
    if (value == null || value.trim().isEmpty) return 'items_required'.tr;
    final number = double.tryParse(value.trim());
    if (number == null) return 'items_invalid_number'.tr;
    if (number < 0) return 'items_price_validation'.tr;
    return null;
  }

  String? _validateTax(String? value) {
    if (value == null || value.trim().isEmpty) return 'items_required'.tr;
    final number = double.tryParse(value.trim());
    if (number == null) return 'items_invalid_number'.tr;
    if (number < 0 || number > 100) return 'items_tax_validation'.tr;
    return null;
  }

  String? _validateNonNegative(String? value) {
    if (value == null || value.trim().isEmpty) return 'items_required'.tr;
    final number = double.tryParse(value.trim());
    if (number == null) return 'items_invalid_number'.tr;
    if (number < 0) return 'inventory_number_non_negative'.tr;
    return null;
  }
}

class _FormFieldSpec {
  const _FormFieldSpec({required this.child, this.wide = false});
  final Widget child;
  final bool wide;
}
