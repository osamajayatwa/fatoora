import 'package:fatoora/core/constants/color.dart';
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

  @override
  Widget build(BuildContext context) {
    return Form(
      key: formKey,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final twoColumns = constraints.maxWidth >= 720;
          final fieldWidth = twoColumns
              ? (constraints.maxWidth - 18) / 2
              : constraints.maxWidth;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: 18,
                runSpacing: 17,
                children: [
                  SizedBox(
                    width: fieldWidth,
                    child: _textField(
                      controller: nameController,
                      label: 'items_name'.tr,
                      icon: Icons.inventory_2_outlined,
                    ),
                  ),
                  SizedBox(
                    width: fieldWidth,
                    child: _textField(
                      controller: codeController,
                      label: 'items_code'.tr,
                      icon: Icons.qr_code_2_rounded,
                    ),
                  ),
                  SizedBox(
                    width: fieldWidth,
                    child: _textField(
                      controller: unitController,
                      label: 'items_unit'.tr,
                      icon: Icons.straighten_rounded,
                    ),
                  ),
                  SizedBox(
                    width: fieldWidth,
                    child: _numberField(
                      controller: priceController,
                      label: 'items_price'.tr,
                      icon: Icons.payments_outlined,
                      validator: _validatePrice,
                      suffix: 'items_jod'.tr,
                    ),
                  ),
                  SizedBox(
                    width: fieldWidth,
                    child: _numberField(
                      controller: taxRateController,
                      label: 'items_tax_rate'.tr,
                      icon: Icons.percent_rounded,
                      validator: _validateTax,
                      suffix: '%',
                    ),
                  ),
                  SizedBox(
                    width: fieldWidth,
                    child: _switchTile(
                      context: context,
                      label: 'items_active'.tr,
                      icon: Icons.toggle_on_outlined,
                      value: active,
                      onChanged: onActiveChanged,
                    ),
                  ),
                  SizedBox(
                    width: fieldWidth,
                    child: _switchTile(
                      context: context,
                      label: 'track_stock'.tr,
                      icon: Icons.inventory_outlined,
                      value: trackStock,
                      onChanged: onTrackStockChanged,
                    ),
                  ),
                  if (showCurrentStock)
                    SizedBox(
                      width: fieldWidth,
                      child: _numberField(
                        controller: currentStockController,
                        label: 'current_stock'.tr,
                        icon: Icons.inventory_2_outlined,
                        validator: _validateNonNegative,
                        suffix: 'quantity'.tr,
                        enabled: trackStock,
                      ),
                    ),
                  SizedBox(
                    width: fieldWidth,
                    child: _numberField(
                      controller: openingStockController,
                      label: 'opening_stock'.tr,
                      icon: Icons.input_rounded,
                      validator: _validateNonNegative,
                      suffix: 'quantity'.tr,
                      enabled: trackStock,
                    ),
                  ),
                  SizedBox(
                    width: fieldWidth,
                    child: _numberField(
                      controller: minStockController,
                      label: 'min_stock'.tr,
                      icon: Icons.warning_amber_rounded,
                      validator: _validateNonNegative,
                      suffix: 'quantity'.tr,
                      enabled: trackStock,
                    ),
                  ),
                  SizedBox(
                    width: fieldWidth,
                    child: _numberField(
                      controller: costPriceController,
                      label: 'cost_price'.tr,
                      icon: Icons.price_change_outlined,
                      validator: _validateNonNegative,
                      suffix: 'items_jod'.tr,
                    ),
                  ),
                  SizedBox(
                    width: fieldWidth,
                    child: _textField(
                      controller: barcodeController,
                      label: 'barcode'.tr,
                      icon: Icons.qr_code_scanner_rounded,
                      required: false,
                    ),
                  ),
                  SizedBox(
                    width: fieldWidth,
                    child: _textField(
                      controller: categoryController,
                      label: 'category'.tr,
                      icon: Icons.category_outlined,
                      required: false,
                    ),
                  ),
                  SizedBox(
                    width: fieldWidth,
                    child: _textField(
                      controller: warehouseController,
                      label: 'warehouse'.tr,
                      icon: Icons.warehouse_outlined,
                    ),
                  ),
                  SizedBox(
                    width: constraints.maxWidth,
                    child: _textField(
                      controller: descriptionController,
                      label: 'items_description'.tr,
                      icon: Icons.notes_rounded,
                      maxLines: 4,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 26),
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: SizedBox(
                  width: twoColumns ? 190 : double.infinity,
                  child: FilledButton.icon(
                    onPressed: loading ? null : onSubmit,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColor.primaryColor,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(13),
                      ),
                    ),
                    icon: loading
                        ? const SizedBox(
                            width: 19,
                            height: 19,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.check_rounded),
                    label: Text(submitLabel),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _textField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    int maxLines = 1,
    bool required = true,
    bool enabled = true,
  }) {
    return TextFormField(
      controller: controller,
      enabled: enabled && !loading,
      maxLines: maxLines,
      textInputAction: maxLines > 1
          ? TextInputAction.newline
          : TextInputAction.next,
      validator: required ? _validateRequired : null,
      decoration: _decoration(label: label, icon: icon),
    );
  }

  Widget _numberField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    required String? Function(String?) validator,
    required String suffix,
    bool enabled = true,
  }) {
    return TextFormField(
      controller: controller,
      enabled: enabled && !loading,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
      ],
      textInputAction: TextInputAction.next,
      validator: validator,
      decoration: _decoration(
        label: label,
        icon: icon,
      ).copyWith(suffixText: suffix),
    );
  }

  Widget _switchTile({
    required BuildContext context,
    required String label,
    required IconData icon,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Container(
      constraints: const BoxConstraints(minHeight: 58),
      padding: const EdgeInsets.symmetric(horizontal: 15),
      decoration: BoxDecoration(
        color: const Color(0xFFFAFBFD),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: const Color(0xFFE1E5ED)),
      ),
      child: Row(
        children: [
          Icon(icon, color: AppColor.grey),
          const SizedBox(width: 12),
          Expanded(
            child: Text(label, style: Theme.of(context).textTheme.bodyLarge),
          ),
          Switch(
            value: value,
            onChanged: loading ? null : onChanged,
            activeTrackColor: AppColor.success,
          ),
        ],
      ),
    );
  }

  InputDecoration _decoration({required String label, required IconData icon}) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon),
      filled: true,
      fillColor: const Color(0xFFFAFBFD),
      alignLabelWithHint: true,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(13),
        borderSide: const BorderSide(color: Color(0xFFE1E5ED)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(13),
        borderSide: const BorderSide(color: Color(0xFFE1E5ED)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(13),
        borderSide: const BorderSide(color: AppColor.primaryColor, width: 1.4),
      ),
    );
  }

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
