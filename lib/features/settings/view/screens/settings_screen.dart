import 'package:fatoora/core/class/handilingdataview.dart';
import 'package:fatoora/core/constants/color.dart';
import 'package:fatoora/features/settings/controllers/admin_settings_controller.dart';
import 'package:fatoora/features/settings/controllers/settings_controller.dart';
import 'package:fatoora/features/settings/controllers/user_preferences_controller.dart';
import 'package:fatoora/features/settings/view/widgets/app_preferences_form.dart';
import 'package:fatoora/features/settings/view/widgets/company_settings_form.dart';
import 'package:fatoora/features/settings/view/widgets/document_settings_form.dart';
import 'package:fatoora/features/settings/view/widgets/inventory_settings_form.dart';
import 'package:fatoora/features/settings/view/widgets/jofotara_status_card.dart';
import 'package:fatoora/features/settings/view/widgets/pdf_settings_form.dart';
import 'package:fatoora/features/settings/view/widgets/profile_settings_form.dart';
import 'package:fatoora/features/settings/view/widgets/settings_section_card.dart';
import 'package:fatoora/features/settings/view/widgets/settings_switch_tile.dart';
import 'package:fatoora/features/shared/business/business_shell.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final settingsController = Get.find<SettingsController>();
    return BusinessShell(
      title: 'settings'.tr,
      showBackButton: !settingsController.isAdmin,
      onBack: settingsController.goBack,
      child: GetBuilder<SettingsController>(
        builder: (controller) => HandilingDataView(
          statusrequest: controller.statusRequest,
          errorMessage: controller.loadErrorMessageKey.tr,
          retryLabel: 'settings_retry'.tr,
          onRetry: controller.loadSettings,
          widget: _SettingsContent(controller: controller),
        ),
      ),
    );
  }
}

class _SettingsContent extends StatelessWidget {
  const _SettingsContent({required this.controller});

  final SettingsController controller;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: EdgeInsets.all(MediaQuery.sizeOf(context).width < 600 ? 14 : 24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1180),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'settings'.tr,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: AppColor.secondaryColor,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                controller.isAdmin
                    ? 'settings_admin_description'.tr
                    : 'settings_sales_rep_description'.tr,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: AppColor.grey),
              ),
              const SizedBox(height: 20),
              if (controller.isAdmin) const _AdminSettings(),
              if (controller.isAdmin) const SizedBox(height: 18),
              const _PersonalSettings(),
              const SizedBox(height: 18),
              _AccountSettings(controller: controller),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }
}

class _AdminSettings extends StatelessWidget {
  const _AdminSettings();

  @override
  Widget build(BuildContext context) {
    return GetBuilder<AdminSettingsController>(
      builder: (controller) => Form(
        key: controller.formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _ResponsiveSettingsGrid(
              children: [
                SettingsSectionCard(
                  title: 'settings_company'.tr,
                  subtitle: 'settings_company_description'.tr,
                  icon: Icons.business_outlined,
                  child: CompanySettingsForm(controller: controller),
                ),
                SettingsSectionCard(
                  title: 'settings_documents'.tr,
                  subtitle: 'settings_documents_description'.tr,
                  icon: Icons.description_outlined,
                  child: DocumentSettingsForm(controller: controller),
                ),
                SettingsSectionCard(
                  title: 'settings_inventory'.tr,
                  subtitle: 'settings_inventory_description'.tr,
                  icon: Icons.warehouse_outlined,
                  child: InventorySettingsForm(controller: controller),
                ),
                SettingsSectionCard(
                  title: 'settings_pdf'.tr,
                  subtitle: 'settings_pdf_description'.tr,
                  icon: Icons.picture_as_pdf_outlined,
                  child: PdfSettingsForm(controller: controller),
                ),
                SettingsSectionCard(
                  title: 'settings_permissions'.tr,
                  subtitle: 'settings_permissions_stage_one'.tr,
                  icon: Icons.admin_panel_settings_outlined,
                  child: _PermissionSettings(controller: controller),
                ),
                SettingsSectionCard(
                  title: 'settings_jofotara'.tr,
                  icon: Icons.lock_clock_outlined,
                  child: JofotaraStatusCard(
                    settings: controller.settings.jofotaraStatusSettings,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: FilledButton.icon(
                onPressed: controller.isSaving ? null : controller.save,
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
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColor.surface,
                        ),
                      )
                    : const Icon(Icons.save_outlined),
                label: Text('settings_save_company_settings'.tr),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PermissionSettings extends StatelessWidget {
  const _PermissionSettings({required this.controller});

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

class _PersonalSettings extends StatelessWidget {
  const _PersonalSettings();

  @override
  Widget build(BuildContext context) {
    return GetBuilder<UserPreferencesController>(
      builder: (controller) => _ResponsiveSettingsGrid(
        children: [
          SettingsSectionCard(
            title: 'settings_profile'.tr,
            subtitle: 'settings_profile_safe_fields'.tr,
            icon: Icons.person_outline_rounded,
            child: ProfileSettingsForm(controller: controller),
          ),
          SettingsSectionCard(
            title: 'settings_preferences'.tr,
            subtitle: 'settings_preferences_description'.tr,
            icon: Icons.tune_rounded,
            child: AppPreferencesForm(controller: controller),
          ),
        ],
      ),
    );
  }
}

class _AccountSettings extends StatelessWidget {
  const _AccountSettings({required this.controller});

  final SettingsController controller;

  @override
  Widget build(BuildContext context) {
    final profile = controller.profile;
    return SettingsSectionCard(
      title: 'settings_account'.tr,
      subtitle: 'settings_about'.tr,
      icon: Icons.info_outline_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _InfoRow(label: 'settings_role'.tr, value: profile?.role.tr ?? ''),
          _InfoRow(
            label: 'settings_account_status'.tr,
            value: profile?.approvalStatus.tr ?? '',
          ),
          _InfoRow(
            label: 'settings_app_version'.tr,
            value: controller.appVersion,
          ),
          const SizedBox(height: 14),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: OutlinedButton.icon(
              onPressed: controller.isLoggingOut
                  ? null
                  : () => _confirmLogout(context),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColor.error,
                side: const BorderSide(color: AppColor.error),
              ),
              icon: controller.isLoggingOut
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.logout_rounded),
              label: Text('settings_logout'.tr),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmLogout(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('settings_logout'.tr),
        content: Text('settings_logout_confirmation'.tr),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('settings_cancel'.tr),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text('settings_logout'.tr),
          ),
        ],
      ),
    );
    if (confirmed == true) await controller.logout();
  }
}

class _ResponsiveSettingsGrid extends StatelessWidget {
  const _ResponsiveSettingsGrid({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const spacing = 16.0;
        final columns = constraints.maxWidth >= 920 ? 2 : 1;
        final width =
            (constraints.maxWidth - spacing * (columns - 1)) / columns;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          crossAxisAlignment: WrapCrossAlignment.start,
          children: [
            for (final child in children) SizedBox(width: width, child: child),
          ],
        );
      },
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: AppColor.grey),
            ),
          ),
          const SizedBox(width: 16),
          Text(
            value,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: AppColor.secondaryColor,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}
