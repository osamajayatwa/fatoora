import 'package:fatoora/core/class/handilingdataview.dart';
import 'package:fatoora/core/constants/color.dart';
import 'package:fatoora/features/customers/controllers/customer_form_controller.dart';
import 'package:fatoora/features/admin_dashboard/view/widgets/dashboard_card.dart';
import 'package:fatoora/features/shared/business/business_shell.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class CustomerFormScreen extends StatelessWidget {
  const CustomerFormScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return GetBuilder<CustomerFormController>(
      builder: (controller) => BusinessShell(
        title: controller.isEditMode ? 'customers_edit'.tr : 'customers_add'.tr,
        showBackButton: true,
        onBack: controller.requestBack,
        child: HandilingDataView(
          statusrequest: controller.statusRequest,
          errorMessage: controller.loadErrorMessageKey.tr,
          retryLabel: 'items_retry'.tr,
          onRetry: controller.initialize,
          widget: SingleChildScrollView(
            padding: EdgeInsets.all(
              MediaQuery.sizeOf(context).width < 600 ? 14 : 24,
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 860),
                child: Form(
                  key: controller.formKey,
                  child: DashboardCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          controller.isEditMode
                              ? 'customers_edit'.tr
                              : 'customers_add'.tr,
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(
                                color: AppColor.secondaryColor,
                                fontWeight: FontWeight.w900,
                              ),
                        ),
                        const SizedBox(height: 18),
                        _Field(
                          controller: controller.nameController,
                          label: 'customer_name'.tr,
                          icon: Icons.person_outline,
                          validator: controller.validateName,
                        ),
                        const SizedBox(height: 14),
                        _Field(
                          controller: controller.phoneController,
                          label: 'Phone'.tr,
                          icon: Icons.phone_outlined,
                          keyboardType: TextInputType.phone,
                        ),
                        const SizedBox(height: 14),
                        _Field(
                          controller: controller.addressController,
                          label: 'address'.tr,
                          icon: Icons.location_on_outlined,
                          maxLines: 2,
                        ),
                        const SizedBox(height: 14),
                        Wrap(
                          spacing: 14,
                          runSpacing: 14,
                          children: [
                            SizedBox(
                              width: 260,
                              child: _Field(
                                controller: controller.cityController,
                                label: 'city'.tr,
                                icon: Icons.location_city_outlined,
                              ),
                            ),
                            SizedBox(
                              width: 260,
                              child: _Field(
                                controller: controller.areaController,
                                label: 'customers_area'.tr,
                                icon: Icons.place_outlined,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        _Field(
                          controller: controller.notesController,
                          label: 'notes'.tr,
                          icon: Icons.notes_outlined,
                          maxLines: 3,
                        ),
                        if (controller.isEditMode) ...[
                          const SizedBox(height: 10),
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            value: controller.active,
                            onChanged: controller.setActive,
                            title: Text('items_active'.tr),
                          ),
                        ],
                        const SizedBox(height: 22),
                        FilledButton.icon(
                          onPressed: controller.isSaving
                              ? null
                              : controller.saveCustomer,
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColor.primaryColor,
                            padding: const EdgeInsets.symmetric(vertical: 15),
                          ),
                          icon: controller.isSaving
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: AppColor.surface,
                                  ),
                                )
                              : const Icon(Icons.save_outlined),
                          label: Text('save'.tr),
                        ),
                      ],
                    ),
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

class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    required this.label,
    required this.icon,
    this.validator,
    this.keyboardType,
    this.maxLines = 1,
  });

  final TextEditingController controller;
  final String label;
  final IconData icon;
  final String? Function(String?)? validator;
  final TextInputType? keyboardType;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      validator: validator,
      keyboardType: keyboardType,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }
}
