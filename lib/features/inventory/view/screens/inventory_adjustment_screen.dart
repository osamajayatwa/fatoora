import 'package:fatoora/core/class/handilingdataview.dart';
import 'package:fatoora/core/constants/color.dart';
import 'package:fatoora/features/admin_dashboard/view/widgets/admin_dashboard_shell.dart';
import 'package:fatoora/features/inventory/controllers/inventory_adjustment_controller.dart';
import 'package:fatoora/features/invoices/view/widgets/item_picker_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

class InventoryAdjustmentScreen extends StatelessWidget {
  const InventoryAdjustmentScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return GetBuilder<InventoryAdjustmentController>(
      builder: (controller) => AdminDashboardShell(
        child: SingleChildScrollView(
          padding: EdgeInsets.all(
            MediaQuery.sizeOf(context).width < 600 ? 14 : 24,
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 860),
              child: Card(
                elevation: 0,
                color: AppColor.surface,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: const BorderSide(color: Color(0xFFE4E8EF)),
                ),
                child: Padding(
                  padding: EdgeInsets.all(
                    MediaQuery.sizeOf(context).width < 600 ? 16 : 24,
                  ),
                  child: HandilingDataRequest(
                    statusrequest: controller.statusRequest,
                    widget: _AdjustmentForm(controller: controller),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AdjustmentForm extends StatelessWidget {
  const _AdjustmentForm({required this.controller});

  final InventoryAdjustmentController controller;

  @override
  Widget build(BuildContext context) {
    final item = controller.selectedItem;
    return Form(
      key: controller.formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'inventory_adjustment'.tr,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              color: AppColor.secondaryColor,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 18),
          OutlinedButton.icon(
            onPressed: controller.isLoading
                ? null
                : () async {
                    final picked = await showInvoiceItemPicker(context);
                    controller.selectItem(picked);
                  },
            icon: const Icon(Icons.inventory_2_outlined),
            label: Align(
              alignment: AlignmentDirectional.centerStart,
              child: Text(item == null ? 'select_item'.tr : item.name),
            ),
          ),
          if (item != null) ...[
            const SizedBox(height: 10),
            Text(
              '${'current_stock'.tr}: ${NumberFormat('#,##0.###').format(item.currentStock)}',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: AppColor.grey),
            ),
          ],
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            value: controller.adjustmentType,
            items:
                const [
                      'manual_adjustment_in',
                      'manual_adjustment_out',
                      'damage',
                      'correction',
                    ]
                    .map(
                      (type) =>
                          DropdownMenuItem(value: type, child: Text(type.tr)),
                    )
                    .toList(),
            onChanged: controller.isLoading
                ? null
                : (value) => controller.setAdjustmentType(
                    value ?? 'manual_adjustment_in',
                  ),
            decoration: InputDecoration(
              labelText: 'inventory_adjustment'.tr,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: controller.quantityController,
            enabled: !controller.isLoading,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
            ],
            validator: (value) {
              final number = double.tryParse(value?.trim() ?? '');
              if (number == null) return 'items_invalid_number'.tr;
              if (number <= 0) return 'quantity_must_be_positive'.tr;
              return null;
            },
            decoration: InputDecoration(
              labelText: 'quantity'.tr,
              prefixIcon: const Icon(Icons.numbers_rounded),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: controller.notesController,
            enabled: !controller.isLoading,
            maxLines: 3,
            decoration: InputDecoration(
              labelText: 'notes'.tr,
              prefixIcon: const Icon(Icons.notes_rounded),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
          const SizedBox(height: 22),
          FilledButton.icon(
            onPressed: controller.isLoading ? null : controller.submit,
            icon: controller.isLoading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColor.surface,
                    ),
                  )
                : const Icon(Icons.save_rounded),
            label: Text('save'.tr),
            style: FilledButton.styleFrom(
              backgroundColor: AppColor.primaryColor,
              padding: const EdgeInsets.symmetric(vertical: 15),
            ),
          ),
        ],
      ),
    );
  }
}
