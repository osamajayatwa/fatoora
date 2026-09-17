import 'dart:ui' as ui;

import 'package:fatoora/core/constants/color.dart';
import 'package:fatoora/core/motion/fatoora_motion_widgets.dart';
import 'package:fatoora/features/admin_dashboard/view/widgets/dashboard_card.dart';
import 'package:fatoora/features/expenses/controllers/expense_form_controller.dart';
import 'package:fatoora/features/expenses/data/models/expense_model.dart';
import 'package:fatoora/features/shared/business/business_shell.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

class ExpenseFormScreen extends StatelessWidget {
  const ExpenseFormScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return GetBuilder<ExpenseFormController>(
      builder: (controller) => BusinessShell(
        title: 'expense_new'.tr,
        showBackButton: true,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final padding = constraints.maxWidth < 600 ? 14.0 : 24.0;
            return SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(padding, padding, padding, 96),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 760),
                  child: DashboardCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _FormHeader(controller: controller),
                        const SizedBox(height: 20),
                        TextField(
                          controller: controller.amountController,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: InputDecoration(
                            labelText: 'expense_amount'.tr,
                            prefixIcon: const Icon(Icons.payments_outlined),
                            border: const OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 16),
                        DropdownButtonFormField<ExpenseCategory>(
                          value: controller.category,
                          decoration: InputDecoration(
                            labelText: 'expense_category'.tr,
                            prefixIcon: const Icon(Icons.category_outlined),
                            border: const OutlineInputBorder(),
                          ),
                          items: [
                            for (final category in ExpenseCategory.values)
                              DropdownMenuItem(
                                value: category,
                                child: Text(category.labelKey.tr),
                              ),
                          ],
                          onChanged: controller.setCategory,
                        ),
                        if (controller.category == ExpenseCategory.other) ...[
                          const SizedBox(height: 16),
                          TextField(
                            controller: controller.customCategoryController,
                            decoration: InputDecoration(
                              labelText: 'expense_custom_category'.tr,
                              prefixIcon: const Icon(Icons.edit_outlined),
                              border: const OutlineInputBorder(),
                            ),
                          ),
                        ],
                        const SizedBox(height: 16),
                        _FundingSourceSelector(controller: controller),
                        const SizedBox(height: 16),
                        _ExpenseDateField(controller: controller),
                        const SizedBox(height: 16),
                        TextField(
                          controller: controller.descriptionController,
                          maxLines: 3,
                          decoration: InputDecoration(
                            labelText: 'expense_description'.tr,
                            alignLabelWithHint: true,
                            border: const OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 22),
                        FilledButton.icon(
                          onPressed: controller.isSaving
                              ? null
                              : controller.saveExpense,
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColor.primaryColor,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 18,
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
                            controller.isAdmin
                                ? 'expense_post'.tr
                                : 'expense_submit_for_approval'.tr,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _FormHeader extends StatelessWidget {
  const _FormHeader({required this.controller});

  final ExpenseFormController controller;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton.filledTonal(
          tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          onPressed: Get.back<void>,
          icon: Icon(
            Directionality.of(context) == ui.TextDirection.rtl
                ? Icons.arrow_forward_rounded
                : Icons.arrow_back_rounded,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'expense_new'.tr,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: AppColor.secondaryColor,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                controller.isAdmin
                    ? 'expense_admin_form_hint'.tr
                    : 'expense_rep_form_hint'.tr,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: AppColor.grey),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _FundingSourceSelector extends StatelessWidget {
  const _FundingSourceSelector({required this.controller});

  final ExpenseFormController controller;

  @override
  Widget build(BuildContext context) {
    return InputDecorator(
      decoration: InputDecoration(
        labelText: 'expense_funding_source'.tr,
        border: const OutlineInputBorder(),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final source in controller.availableFundingSources)
            ChoiceChip(
              selected: controller.fundingSource == source,
              onSelected: (_) => controller.setFundingSource(source),
              label: Text(source.labelKey.tr),
            ),
        ],
      ),
    );
  }
}

class _ExpenseDateField extends StatelessWidget {
  const _ExpenseDateField({required this.controller});

  final ExpenseFormController controller;

  @override
  Widget build(BuildContext context) {
    final formatter = DateFormat.yMd();
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          firstDate: DateTime(2020),
          lastDate: DateTime.now().add(const Duration(days: 365)),
          initialDate: controller.expenseDate,
        );
        if (picked != null) controller.setExpenseDate(picked);
      },
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: 'expense_date'.tr,
          prefixIcon: const Icon(Icons.event_outlined),
          border: const OutlineInputBorder(),
        ),
        child: Text(
          formatter.format(controller.expenseDate),
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: AppColor.secondaryColor,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
