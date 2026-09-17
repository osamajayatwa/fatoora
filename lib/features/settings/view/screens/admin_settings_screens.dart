import 'package:fatoora/core/constants/color.dart';
import 'package:fatoora/core/motion/fatoora_motion_widgets.dart';
import 'package:fatoora/features/settings/controllers/admin_settings_controller.dart';
import 'package:fatoora/features/settings/controllers/settings_controller.dart';
import 'package:fatoora/features/settings/view/widgets/company_settings_form.dart';
import 'package:fatoora/features/settings/view/widgets/document_settings_form.dart';
import 'package:fatoora/features/settings/view/widgets/inventory_settings_form.dart';
import 'package:fatoora/features/settings/view/widgets/jofotara_status_card.dart';
import 'package:fatoora/features/settings/view/widgets/pdf_settings_form.dart';
import 'package:fatoora/features/settings/view/widgets/settings_section_scaffold.dart';
import 'package:fatoora/features/settings/view/widgets/settings_switch_tile.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class CompanySettingsScreen extends StatelessWidget {
  const CompanySettingsScreen({super.key});

  @override
  Widget build(BuildContext context) => const _AdminEditableSettingsScreen(
    section: _AdminSettingsSection.company,
  );
}

class DocumentSettingsScreen extends StatelessWidget {
  const DocumentSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) => const _AdminEditableSettingsScreen(
    section: _AdminSettingsSection.documents,
  );
}

class InventorySettingsScreen extends StatelessWidget {
  const InventorySettingsScreen({super.key});

  @override
  Widget build(BuildContext context) => const _AdminEditableSettingsScreen(
    section: _AdminSettingsSection.inventory,
  );
}

class PdfSettingsScreen extends StatelessWidget {
  const PdfSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) =>
      const _AdminEditableSettingsScreen(section: _AdminSettingsSection.pdf);
}

class PermissionSettingsScreen extends StatelessWidget {
  const PermissionSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) => const _AdminEditableSettingsScreen(
    section: _AdminSettingsSection.permissions,
  );
}

class JofotaraSettingsScreen extends StatelessWidget {
  const JofotaraSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return SettingsSectionScaffold(
      titleKey: 'settings_jofotara',
      subtitleKey: 'settings_jofotara_subtitle',
      icon: Icons.lock_clock_outlined,
      adminOnly: true,
      child: GetBuilder<SettingsController>(
        builder: (controller) => JofotaraStatusCard(
          settings: controller.appSettings.jofotaraStatusSettings,
        ),
      ),
    );
  }
}

enum _AdminSettingsSection { company, documents, inventory, pdf, permissions }

class _AdminEditableSettingsScreen extends StatelessWidget {
  const _AdminEditableSettingsScreen({required this.section});

  final _AdminSettingsSection section;

  @override
  Widget build(BuildContext context) {
    return SettingsSectionScaffold(
      titleKey: section.titleKey,
      subtitleKey: section.subtitleKey,
      icon: section.icon,
      adminOnly: true,
      child: GetBuilder<AdminSettingsController>(
        builder: (controller) => Form(
          key: controller.formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _sectionForm(controller),
              const SizedBox(height: 18),
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: FilledButton.icon(
                  onPressed: controller.isSaving
                      ? null
                      : _saveAction(controller),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColor.primaryColor,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 22,
                      vertical: 15,
                    ),
                  ),
                  icon: controller.isSaving
                      ? const SizedBox.square(
                          dimension: 18,
                          child: FatooraProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.save_outlined),
                  label: Text('settings_save_section'.tr),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> Function() _saveAction(AdminSettingsController controller) {
    return switch (section) {
      _AdminSettingsSection.company => controller.saveCompanySettings,
      _AdminSettingsSection.documents => controller.saveDocumentSettings,
      _AdminSettingsSection.inventory => controller.saveInventorySettings,
      _AdminSettingsSection.pdf => controller.savePdfSettings,
      _AdminSettingsSection.permissions => controller.savePermissionSettings,
    };
  }

  Widget _sectionForm(AdminSettingsController controller) {
    return switch (section) {
      _AdminSettingsSection.company => CompanySettingsForm(
        controller: controller,
      ),
      _AdminSettingsSection.documents => DocumentSettingsForm(
        controller: controller,
      ),
      _AdminSettingsSection.inventory => InventorySettingsForm(
        controller: controller,
      ),
      _AdminSettingsSection.pdf => PdfSettingsForm(controller: controller),
      _AdminSettingsSection.permissions => _PermissionSettingsForm(
        controller: controller,
      ),
    };
  }
}

extension on _AdminSettingsSection {
  String get titleKey => switch (this) {
    _AdminSettingsSection.company => 'settings_company',
    _AdminSettingsSection.documents => 'settings_documents',
    _AdminSettingsSection.inventory => 'settings_inventory',
    _AdminSettingsSection.pdf => 'settings_pdf',
    _AdminSettingsSection.permissions => 'settings_permissions',
  };

  String get subtitleKey => switch (this) {
    _AdminSettingsSection.company => 'settings_company_subtitle',
    _AdminSettingsSection.documents => 'settings_documents_subtitle',
    _AdminSettingsSection.inventory => 'settings_inventory_subtitle',
    _AdminSettingsSection.pdf => 'settings_pdf_subtitle',
    _AdminSettingsSection.permissions => 'settings_permissions_subtitle',
  };

  IconData get icon => switch (this) {
    _AdminSettingsSection.company => Icons.business_outlined,
    _AdminSettingsSection.documents => Icons.description_outlined,
    _AdminSettingsSection.inventory => Icons.warehouse_outlined,
    _AdminSettingsSection.pdf => Icons.picture_as_pdf_outlined,
    _AdminSettingsSection.permissions => Icons.admin_panel_settings_outlined,
  };
}

class _PermissionSettingsForm extends StatelessWidget {
  const _PermissionSettingsForm({required this.controller});

  final AdminSettingsController controller;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SettingsSwitchTile(
          title: 'settings_allow_sales_rep_create_customers'.tr,
          value: controller.allowSalesRepCreateCustomers,
          onChanged: controller.setAllowSalesRepCreateCustomers,
        ),
        SettingsSwitchTile(
          title: 'settings_allow_sales_rep_create_receipts'.tr,
          value: controller.allowSalesRepCreateReceipts,
          onChanged: controller.setAllowSalesRepCreateReceipts,
        ),
        SettingsSwitchTile(
          title: 'settings_allow_sales_rep_create_returns'.tr,
          value: controller.allowSalesRepCreateReturns,
          onChanged: controller.setAllowSalesRepCreateReturns,
        ),
        SettingsSwitchTile(
          title: 'settings_allow_sales_rep_create_quotations'.tr,
          value: controller.allowSalesRepCreateQuotations,
          onChanged: controller.setAllowSalesRepCreateQuotations,
        ),
        SettingsSwitchTile(
          title: 'settings_allow_sales_rep_price_edit'.tr,
          value: controller.allowSalesRepPermissionPriceEdit,
          onChanged: controller.setAllowSalesRepPermissionPriceEdit,
        ),
        SettingsSwitchTile(
          title: 'settings_allow_sales_rep_discount'.tr,
          value: controller.allowSalesRepDiscount,
          onChanged: controller.setAllowSalesRepDiscount,
        ),
      ],
    );
  }
}
