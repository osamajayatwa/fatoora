import 'package:fatoora/core/class/handilingdataview.dart';
import 'package:fatoora/core/constant/color.dart';
import 'package:fatoora/modules/admin_dashboard/items/controller/edit_item_controller.dart';
import 'package:fatoora/modules/admin_dashboard/items/view/widgets/item_form.dart';
import 'package:fatoora/modules/admin_dashboard/view/widgets/admin_dashboard_shell.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class EditItemScreen extends StatelessWidget {
  const EditItemScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return GetBuilder<EditItemController>(
      builder: (controller) => PopScope(
        canPop: controller.allowPop,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) controller.requestBack();
        },
        child: AdminDashboardShell(
          child: SingleChildScrollView(
            padding: EdgeInsets.all(
              MediaQuery.sizeOf(context).width < 600 ? 14 : 24,
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1000),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        IconButton(
                          onPressed: controller.requestBack,
                          icon: Icon(
                            Directionality.of(context) == TextDirection.rtl
                                ? Icons.arrow_forward_rounded
                                : Icons.arrow_back_rounded,
                          ),
                          color: AppColor.secondaryColor,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'items_edit'.tr,
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(
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
                        child: controller.item == null
                            ? HandilingDataView(
                                statusrequest: controller.statusRequest,
                                errorMessage: 'items_not_found_error'.tr,
                                retryLabel: 'items_retry'.tr,
                                widget: const SizedBox.shrink(),
                              )
                            : HandilingDataRequest(
                                statusrequest: controller.statusRequest,
                                widget: ItemForm(
                                  formKey: controller.formKey,
                                  nameController: controller.nameController,
                                  codeController: controller.codeController,
                                  descriptionController:
                                      controller.descriptionController,
                                  unitController: controller.unitController,
                                  priceController: controller.priceController,
                                  taxRateController:
                                      controller.taxRateController,
                                  active: controller.active,
                                  onActiveChanged: controller.setActive,
                                  onSubmit: controller.submit,
                                  submitLabel: 'items_update'.tr,
                                  loading: controller.isLoading,
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
