import 'package:fatoora/core/class/handilingdataview.dart';
import 'package:fatoora/core/constants/color.dart';
import 'package:fatoora/core/motion/fatoora_motion_widgets.dart';
import 'package:fatoora/features/customers/controllers/customer_form_controller.dart';
import 'package:fatoora/features/admin_dashboard/view/widgets/dashboard_card.dart';
import 'package:fatoora/features/shared/business/business_page_widgets.dart';
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
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: EdgeInsets.fromLTRB(
              MediaQuery.sizeOf(context).width < 600 ? 14 : 24,
              MediaQuery.sizeOf(context).width < 600 ? 14 : 24,
              MediaQuery.sizeOf(context).width < 600 ? 14 : 24,
              24 + MediaQuery.viewInsetsOf(context).bottom,
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 860),
                child: Form(
                  key: controller.formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      BusinessPageHeader(
                        title: controller.isEditMode
                            ? 'customers_edit'.tr
                            : 'customers_add'.tr,
                        subtitle: 'customers_identity'.tr,
                      ),
                      const SizedBox(height: 14),
                      DashboardCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _Field(
                              fieldKey: const ValueKey('customer-name-field'),
                              controller: controller.nameController,
                              label: '${'customer_name'.tr} *',
                              icon: Icons.person_outline,
                              validator: controller.validateName,
                              enabled: !controller.isSaving,
                              autofillHints: const [AutofillHints.name],
                              textInputAction: TextInputAction.next,
                            ),
                            const SizedBox(height: 14),
                            _Field(
                              fieldKey: const ValueKey('customer-phone-field'),
                              controller: controller.phoneController,
                              label: 'Phone'.tr,
                              icon: Icons.phone_outlined,
                              keyboardType: TextInputType.phone,
                              enabled: !controller.isSaving,
                              autofillHints: const [
                                AutofillHints.telephoneNumber,
                              ],
                              textInputAction: TextInputAction.next,
                            ),
                            const SizedBox(height: 14),
                            _Field(
                              fieldKey: const ValueKey(
                                'customer-address-field',
                              ),
                              controller: controller.addressController,
                              label: 'address'.tr,
                              icon: Icons.location_on_outlined,
                              maxLines: 2,
                              enabled: !controller.isSaving,
                              autofillHints: const [
                                AutofillHints.streetAddressLine1,
                              ],
                            ),
                            const SizedBox(height: 14),
                            LayoutBuilder(
                              builder: (context, constraints) {
                                final stacked = constraints.maxWidth < 580;
                                final fieldWidth = stacked
                                    ? constraints.maxWidth
                                    : (constraints.maxWidth - 14) / 2;
                                return Wrap(
                                  spacing: 14,
                                  runSpacing: 14,
                                  children: [
                                    SizedBox(
                                      width: fieldWidth,
                                      child: _Field(
                                        fieldKey: const ValueKey(
                                          'customer-city-field',
                                        ),
                                        controller: controller.cityController,
                                        label: 'city'.tr,
                                        icon: Icons.location_city_outlined,
                                        enabled: !controller.isSaving,
                                        textInputAction: TextInputAction.next,
                                      ),
                                    ),
                                    SizedBox(
                                      width: fieldWidth,
                                      child: _Field(
                                        fieldKey: const ValueKey(
                                          'customer-area-field',
                                        ),
                                        controller: controller.areaController,
                                        label: 'customers_area'.tr,
                                        icon: Icons.place_outlined,
                                        enabled: !controller.isSaving,
                                        textInputAction: TextInputAction.next,
                                      ),
                                    ),
                                  ],
                                );
                              },
                            ),
                            const SizedBox(height: 14),
                            _Field(
                              fieldKey: const ValueKey('customer-notes-field'),
                              controller: controller.notesController,
                              label: 'notes'.tr,
                              icon: Icons.notes_outlined,
                              maxLines: 3,
                              enabled: !controller.isSaving,
                              textInputAction: TextInputAction.newline,
                            ),
                            if (controller.isEditMode) ...[
                              const SizedBox(height: 10),
                              SwitchListTile(
                                contentPadding: EdgeInsets.zero,
                                value: controller.active,
                                onChanged: controller.isSaving
                                    ? null
                                    : controller.setActive,
                                title: Text('items_active'.tr),
                              ),
                            ],
                            const SizedBox(height: 22),
                            FilledButton.icon(
                              key: const ValueKey('customer-save-button'),
                              onPressed: controller.isSaving
                                  ? null
                                  : controller.saveCustomer,
                              style: FilledButton.styleFrom(
                                backgroundColor: AppColor.primaryColor,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 15,
                                ),
                              ),
                              icon: controller.isSaving
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: FatooraProgressIndicator(
                                        strokeWidth: 2,
                                        color: AppColor.surface,
                                      ),
                                    )
                                  : const Icon(Icons.save_outlined),
                              label: Text(
                                controller.isSaving
                                    ? 'customers_saving'.tr
                                    : 'save'.tr,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
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
    required this.fieldKey,
    required this.controller,
    required this.label,
    required this.icon,
    this.validator,
    this.keyboardType,
    this.maxLines = 1,
    this.enabled = true,
    this.autofillHints,
    this.textInputAction,
  });

  final Key fieldKey;
  final TextEditingController controller;
  final String label;
  final IconData icon;
  final String? Function(String?)? validator;
  final TextInputType? keyboardType;
  final int maxLines;
  final bool enabled;
  final Iterable<String>? autofillHints;
  final TextInputAction? textInputAction;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      key: fieldKey,
      controller: controller,
      enabled: enabled,
      validator: validator,
      keyboardType: keyboardType,
      maxLines: maxLines,
      autofillHints: autofillHints,
      textInputAction: textInputAction,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }
}
