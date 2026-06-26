import 'package:fatoora/core/class/handilingdataview.dart';
import 'package:fatoora/core/constants/color.dart';
import 'package:fatoora/features/items/controller/add_item_controller.dart';
import 'package:fatoora/features/items/view/widgets/item_form.dart';
import 'package:fatoora/features/admin_dashboard/view/widgets/admin_dashboard_shell.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class AddItemScreen extends StatelessWidget {
  const AddItemScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return GetBuilder<AddItemController>(
      builder: (controller) => PopScope(
        canPop: controller.allowPop,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) controller.requestBack();
        },
        child: AdminDashboardShell(
          child: _ItemFormPage(
            title: 'items_add'.tr,
            onBack: controller.requestBack,
            child: HandilingDataRequest(
              statusrequest: controller.statusRequest,
              widget: ItemForm(
                formKey: controller.formKey,
                nameController: controller.nameController,
                codeController: controller.codeController,
                descriptionController: controller.descriptionController,
                unitController: controller.unitController,
                priceController: controller.priceController,
                taxRateController: controller.taxRateController,
                currentStockController: controller.currentStockController,
                openingStockController: controller.openingStockController,
                minStockController: controller.minStockController,
                costPriceController: controller.costPriceController,
                barcodeController: controller.barcodeController,
                categoryController: controller.categoryController,
                warehouseController: controller.warehouseController,
                active: controller.active,
                trackStock: controller.trackStock,
                onActiveChanged: controller.setActive,
                onTrackStockChanged: controller.setTrackStock,
                onSubmit: controller.submit,
                submitLabel: 'items_save'.tr,
                loading: controller.isLoading,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ItemFormPage extends StatelessWidget {
  const _ItemFormPage({
    required this.title,
    required this.onBack,
    required this.child,
  });

  final String title;
  final VoidCallback onBack;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: EdgeInsets.all(MediaQuery.sizeOf(context).width < 600 ? 14 : 24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1000),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  IconButton(
                    onPressed: onBack,
                    icon: Icon(
                      Directionality.of(context) == TextDirection.rtl
                          ? Icons.arrow_forward_rounded
                          : Icons.arrow_back_rounded,
                    ),
                    color: AppColor.secondaryColor,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    title,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: AppColor.secondaryColor,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Card(
                margin: EdgeInsets.zero,
                elevation: 0,
                color: AppColor.surface,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                  side: const BorderSide(color: Color(0xFFE4E8EF)),
                ),
                child: Padding(
                  padding: EdgeInsets.all(
                    MediaQuery.sizeOf(context).width < 600 ? 16 : 26,
                  ),
                  child: child,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
