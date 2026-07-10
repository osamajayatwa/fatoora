import 'dart:ui' as ui;

import 'package:fatoora/core/class/handilingdataview.dart';
import 'package:fatoora/core/constants/color.dart';
import 'package:fatoora/features/admin_dashboard/view/widgets/dashboard_card.dart';
import 'package:fatoora/features/expenses/controllers/expense_details_controller.dart';
import 'package:fatoora/features/expenses/data/models/expense_model.dart';
import 'package:fatoora/features/shared/business/business_shell.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

class ExpenseDetailsScreen extends StatelessWidget {
  const ExpenseDetailsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return GetBuilder<ExpenseDetailsController>(
      builder: (controller) => BusinessShell(
        title: 'expense_details'.tr,
        showBackButton: true,
        child: HandilingDataView(
          statusrequest: controller.statusRequest,
          errorMessage: controller.loadErrorMessageKey.tr,
          retryLabel: 'items_retry'.tr,
          onRetry: controller.loadExpense,
          widget: LayoutBuilder(
            builder: (context, constraints) {
              final padding = constraints.maxWidth < 600 ? 14.0 : 24.0;
              final expense = controller.expense;
              if (expense == null) {
                return Center(child: Text('expense_not_found'.tr));
              }
              return SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(padding, padding, padding, 96),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 900),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _DetailsHeader(expense: expense),
                        const SizedBox(height: 16),
                        _ExpenseInfo(expense: expense),
                        if (controller.canDecide) ...[
                          const SizedBox(height: 16),
                          _DecisionCard(controller: controller),
                        ],
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _DetailsHeader extends StatelessWidget {
  const _DetailsHeader({required this.expense});

  final ExpenseModel expense;

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(symbol: 'JOD ', decimalDigits: 3);
    final statusColor = _statusColor(expense.status);
    return DashboardCard(
      child: Row(
        children: [
          IconButton.filledTonal(
            tooltip: MaterialLocalizations.of(context).backButtonTooltip,
            onPressed: () => Get.back(result: true),
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
                  _categoryLabel(expense).tr,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: AppColor.secondaryColor,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  expense.status.labelKey.tr,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: statusColor,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            currency.format(expense.amount),
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: AppColor.error,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _ExpenseInfo extends StatelessWidget {
  const _ExpenseInfo({required this.expense});

  final ExpenseModel expense;

  @override
  Widget build(BuildContext context) {
    final formatter = DateFormat.yMd();
    return DashboardCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _InfoRow('expense_date', formatter.format(expense.expenseDate)),
          _InfoRow('expense_category', _categoryLabel(expense).tr),
          _InfoRow('expense_funding_source', expense.fundingSource.labelKey.tr),
          _InfoRow(
            'expense_reimbursement_status',
            expense.reimbursementStatus.labelKey.tr,
          ),
          _InfoRow('expense_paid_by', expense.paidByName),
          if (expense.salesRepName.isNotEmpty)
            _InfoRow('sales_rep', expense.salesRepName),
          if (expense.description.isNotEmpty)
            _InfoRow('expense_description', expense.description),
          if (expense.cashMovementId.isNotEmpty)
            _InfoRow('cash_movements', expense.cashMovementId),
          if (expense.approvedByName.isNotEmpty)
            _InfoRow('expense_approved_by', expense.approvedByName),
          if (expense.rejectedByName.isNotEmpty)
            _InfoRow('expense_rejected_by', expense.rejectedByName),
          if (expense.rejectionReason.isNotEmpty)
            _InfoRow('expense_rejection_reason', expense.rejectionReason),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow(this.labelKey, this.value);

  final String labelKey;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 210,
            child: Text(
              labelKey.tr,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: AppColor.grey),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: AppColor.secondaryColor,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DecisionCard extends StatelessWidget {
  const _DecisionCard({required this.controller});

  final ExpenseDetailsController controller;

  @override
  Widget build(BuildContext context) {
    return DashboardCard(
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        alignment: WrapAlignment.end,
        children: [
          OutlinedButton.icon(
            onPressed: controller.isSavingDecision
                ? null
                : () => _showRejectDialog(context, controller),
            icon: const Icon(Icons.close_rounded),
            label: Text('expense_reject'.tr),
          ),
          FilledButton.icon(
            onPressed: controller.isSavingDecision
                ? null
                : controller.approveExpense,
            style: FilledButton.styleFrom(
              backgroundColor: AppColor.primaryColor,
            ),
            icon: controller.isSavingDecision
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColor.surface,
                    ),
                  )
                : const Icon(Icons.check_rounded),
            label: Text('expense_approve'.tr),
          ),
        ],
      ),
    );
  }
}

Future<void> _showRejectDialog(
  BuildContext context,
  ExpenseDetailsController controller,
) async {
  final reasonController = TextEditingController();
  final result = await Get.dialog<String>(
    AlertDialog(
      title: Text('expense_reject'.tr),
      content: TextField(
        controller: reasonController,
        maxLines: 3,
        decoration: InputDecoration(
          labelText: 'expense_rejection_reason'.tr,
          border: const OutlineInputBorder(),
        ),
      ),
      actions: [
        TextButton(onPressed: Get.back<void>, child: Text('No'.tr)),
        FilledButton(
          onPressed: () => Get.back(result: reasonController.text),
          child: Text('Yes'.tr),
        ),
      ],
    ),
  );
  reasonController.dispose();
  if (result != null) {
    await controller.rejectExpense(result);
  }
}

Color _statusColor(ExpenseStatus status) {
  return switch (status) {
    ExpenseStatus.posted || ExpenseStatus.approved => AppColor.success,
    ExpenseStatus.pending => const Color(0xFFFF9838),
    ExpenseStatus.rejected || ExpenseStatus.cancelled => AppColor.error,
  };
}

String _categoryLabel(ExpenseModel expense) {
  if (expense.category == ExpenseCategory.other &&
      expense.customCategoryName.isNotEmpty) {
    return expense.customCategoryName;
  }
  return expense.category.labelKey;
}
