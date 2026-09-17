import 'package:fatoora/app/routes/app_routes.dart';
import 'package:fatoora/core/class/handilingdataview.dart';
import 'package:fatoora/core/constants/color.dart';
import 'package:fatoora/core/motion/fatoora_overlays.dart';
import 'package:fatoora/core/motion/fatoora_motion_widgets.dart';
import 'package:fatoora/features/financial/controllers/company_cash_opening_balance_controller.dart';
import 'package:fatoora/features/financial/data/models/company_cash_opening_balance_model.dart';
import 'package:fatoora/features/settings/view/widgets/settings_section_card.dart';
import 'package:fatoora/features/settings/view/widgets/settings_section_scaffold.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart' as intl;

class FinancialSettingsScreen extends StatelessWidget {
  const FinancialSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return SettingsSectionScaffold(
      titleKey: 'settings_financial',
      subtitleKey: 'settings_financial_subtitle',
      icon: Icons.account_balance_wallet_outlined,
      adminOnly: true,
      child: SettingsSectionCard(
        title: 'settings_opening_balances'.tr,
        subtitle: 'settings_opening_balances_subtitle'.tr,
        icon: Icons.price_check_outlined,
        onTap: () => Get.toNamed<void>(AppRoute.openingBalances),
        trailing: Icon(
          Directionality.of(context) == TextDirection.rtl
              ? Icons.chevron_left_rounded
              : Icons.chevron_right_rounded,
          color: context.appMutedText,
        ),
      ),
    );
  }
}

class OpeningBalancesScreen extends StatelessWidget {
  const OpeningBalancesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return SettingsSectionScaffold(
      titleKey: 'settings_opening_balances',
      subtitleKey: 'settings_opening_balances_subtitle',
      icon: Icons.price_check_outlined,
      adminOnly: true,
      child: GetBuilder<CompanyCashOpeningBalanceController>(
        builder: (controller) => HandilingDataView(
          statusrequest: controller.statusRequest,
          errorMessage: controller.loadErrorMessageKey.tr,
          retryLabel: 'settings_retry'.tr,
          onRetry: controller.loadOpeningBalance,
          widget: controller.openingBalance == null
              ? _OpeningBalanceCreation(controller: controller)
              : _OpeningBalanceReadOnly(
                  openingBalance: controller.openingBalance!,
                ),
        ),
      ),
    );
  }
}

class _OpeningBalanceCreation extends StatelessWidget {
  const _OpeningBalanceCreation({required this.controller});

  final CompanyCashOpeningBalanceController controller;

  @override
  Widget build(BuildContext context) {
    if (!controller.canCreate) {
      return _Notice(
        icon: Icons.lock_outline_rounded,
        color: AppColor.error,
        title: 'financial_company_cash_opening_balance_not_created'.tr,
        message: 'financial_company_cash_opening_balance_restricted'.tr,
      );
    }

    return Form(
      key: controller.formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Notice(
            icon: Icons.info_outline_rounded,
            color: AppColor.primaryColor,
            title: 'financial_company_cash_opening_balance_migration'.tr,
            message:
                'financial_company_cash_opening_balance_migration_notice'.tr,
          ),
          const SizedBox(height: 20),
          _ReadOnlyField(
            label: 'financial_company_cash_opening_balance_date'.tr,
            value: '30/07/2026',
            icon: Icons.event_outlined,
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: controller.amountController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
            ],
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(
              labelText: 'financial_company_cash_opening_balance_amount'.tr,
              prefixIcon: const Icon(Icons.payments_outlined),
              suffixText: 'JOD',
            ),
            validator: controller.validateAmount,
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: controller.noteController,
            maxLength: 500,
            minLines: 2,
            maxLines: 4,
            decoration: InputDecoration(
              labelText: 'financial_company_cash_opening_balance_note'.tr,
              hintText: 'financial_company_cash_opening_balance_note_hint'.tr,
              prefixIcon: const Icon(Icons.notes_rounded),
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: FilledButton.icon(
              onPressed: controller.isSaving
                  ? null
                  : () => _confirmCreation(context, controller),
              icon: controller.isSaving
                  ? const SizedBox.square(
                      dimension: 18,
                      child: FatooraProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.add_card_rounded),
              label: Text(
                controller.isSaving
                    ? 'financial_company_cash_opening_balance_saving'.tr
                    : 'financial_company_cash_opening_balance_create'.tr,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmCreation(
    BuildContext context,
    CompanyCashOpeningBalanceController controller,
  ) async {
    if (!(controller.formKey.currentState?.validate() ?? false)) return;
    final confirmed = await showFatooraDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('financial_company_cash_opening_balance_confirm_title'.tr),
        content: Text(
          'financial_company_cash_opening_balance_confirm_message'.tr,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text('settings_cancel'.tr),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text('financial_company_cash_opening_balance_confirm'.tr),
          ),
        ],
      ),
    );
    if (confirmed == true) await controller.createOpeningBalance();
  }
}

class _OpeningBalanceReadOnly extends StatelessWidget {
  const _OpeningBalanceReadOnly({required this.openingBalance});

  final CompanyCashOpeningBalanceModel openingBalance;

  @override
  Widget build(BuildContext context) {
    final currency = intl.NumberFormat.currency(
      symbol: 'JOD ',
      decimalDigits: 3,
    );
    final createdAt = intl.DateFormat(
      'dd/MM/yyyy HH:mm',
    ).format(openingBalance.createdAt.toLocal());
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Notice(
          icon: Icons.lock_rounded,
          color: AppColor.success,
          title: 'financial_company_cash_opening_balance_recorded'.tr,
          message: 'financial_company_cash_opening_balance_read_only'.tr,
        ),
        const SizedBox(height: 20),
        Wrap(
          spacing: 14,
          runSpacing: 14,
          children: [
            _SummaryField(
              label: 'financial_company_cash_opening_balance_amount'.tr,
              value: currency.format(openingBalance.amount),
            ),
            _SummaryField(
              label: 'financial_company_cash_opening_balance_date'.tr,
              value: '30/07/2026',
            ),
            _SummaryField(
              label: 'financial_company_cash_balance_before'.tr,
              value: currency.format(openingBalance.balanceBefore),
            ),
            _SummaryField(
              label: 'financial_company_cash_balance_after'.tr,
              value: currency.format(openingBalance.balanceAfter),
            ),
            _SummaryField(
              label: 'financial_company_cash_opening_balance_created_by'.tr,
              value: openingBalance.createdByName,
            ),
            _SummaryField(
              label: 'financial_company_cash_opening_balance_created_at'.tr,
              value: createdAt,
            ),
          ],
        ),
        if (openingBalance.note.isNotEmpty) ...[
          const SizedBox(height: 16),
          _ReadOnlyField(
            label: 'financial_company_cash_opening_balance_note'.tr,
            value: openingBalance.note,
            icon: Icons.notes_rounded,
          ),
        ],
      ],
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({
    required this.icon,
    required this.color,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: context.appText,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    message,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: context.appMutedText,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReadOnlyField extends StatelessWidget {
  const _ReadOnlyField({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return InputDecorator(
      decoration: InputDecoration(labelText: label, prefixIcon: Icon(icon)),
      child: Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
    );
  }
}

class _SummaryField extends StatelessWidget {
  const _SummaryField({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: MediaQuery.sizeOf(context).width < 600 ? double.infinity : 350,
      child: _ReadOnlyField(
        label: label,
        value: value,
        icon: Icons.check_circle_outline_rounded,
      ),
    );
  }
}
