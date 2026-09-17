import 'package:fatoora/core/class/handilingdataview.dart';
import 'package:fatoora/core/constants/color.dart';
import 'package:fatoora/features/admin_dashboard/view/widgets/dashboard_card.dart';
import 'package:fatoora/features/expenses/controllers/expenses_list_controller.dart';
import 'package:fatoora/features/expenses/data/models/expense_model.dart';
import 'package:fatoora/features/shared/business/business_page_widgets.dart';
import 'package:fatoora/features/shared/business/business_shell.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

class ExpensesListScreen extends StatelessWidget {
  const ExpensesListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return GetBuilder<ExpensesListController>(
      builder: (controller) => BusinessShell(
        title: 'expenses'.tr,
        child: HandilingDataView(
          statusrequest: controller.statusRequest,
          errorMessage: controller.loadErrorMessageKey.tr,
          retryLabel: 'items_retry'.tr,
          onRetry: controller.loadExpenses,
          widget: RefreshIndicator(
            color: AppColor.primaryColor,
            onRefresh: controller.refreshExpenses,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final padding = constraints.maxWidth < 600 ? 14.0 : 24.0;
                return SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: EdgeInsets.fromLTRB(padding, padding, padding, 96),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1220),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _ExpensesHeader(controller: controller),
                          const SizedBox(height: 16),
                          _ExpenseSummary(controller: controller),
                          const SizedBox(height: 16),
                          _ExpenseFilters(controller: controller),
                          const SizedBox(height: 16),
                          if (controller.expenses.isEmpty)
                            _EmptyExpenses(hasFilters: controller.hasFilters)
                          else
                            _ExpenseList(controller: controller),
                          if (controller.hasMore || controller.isLoadingMore)
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Center(
                                child: controller.isLoadingMore
                                    ? const CircularProgressIndicator()
                                    : OutlinedButton.icon(
                                        onPressed: controller.loadMoreExpenses,
                                        icon: const Icon(
                                          Icons.expand_more_rounded,
                                        ),
                                        label: Text('load_more_records'.tr),
                                      ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _ExpensesHeader extends StatelessWidget {
  const _ExpensesHeader({required this.controller});

  final ExpensesListController controller;

  @override
  Widget build(BuildContext context) {
    return BusinessPageHeader(
      title: controller.isAdmin ? 'expenses'.tr : 'my_expenses'.tr,
      subtitle: controller.isAdmin
          ? 'expenses_admin_subtitle'.tr
          : 'expenses_rep_subtitle'.tr,
      trailing: BusinessPrimaryActionButton(
        onPressed: controller.openCreateExpense,
        icon: Icons.add_rounded,
        label: 'expense_new'.tr,
      ),
    );
  }
}

class _ExpenseSummary extends StatelessWidget {
  const _ExpenseSummary({required this.controller});

  final ExpensesListController controller;

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(symbol: 'JOD ', decimalDigits: 3);
    final tiles = [
      _SummaryTileData(
        labelKey: 'expenses_total_posted',
        value: currency.format(controller.postedExpenseTotal),
        icon: Icons.trending_down_rounded,
        color: AppColor.error,
      ),
      _SummaryTileData(
        labelKey: 'expenses_pending',
        value: controller.pendingExpenseCount.toString(),
        icon: Icons.pending_actions_outlined,
        color: const Color(0xFFFF9838),
      ),
      _SummaryTileData(
        labelKey: 'expenses_reimbursements_payable',
        value: currency.format(controller.payableReimbursements),
        icon: Icons.request_page_outlined,
        color: AppColor.primaryColor,
      ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 760 ? 3 : 1;
        const spacing = 12.0;
        final width =
            (constraints.maxWidth - (columns - 1) * spacing) / columns;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final tile in tiles) _SummaryTile(width: width, data: tile),
          ],
        );
      },
    );
  }
}

class _SummaryTileData {
  const _SummaryTileData({
    required this.labelKey,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String labelKey;
  final String value;
  final IconData icon;
  final Color color;
}

class _SummaryTile extends StatelessWidget {
  const _SummaryTile({required this.width, required this.data});

  final double width;
  final _SummaryTileData data;

  @override
  Widget build(BuildContext context) {
    return DashboardCard(
      padding: const EdgeInsets.all(16),
      child: SizedBox(
        width: width - 34,
        child: Row(
          children: [
            Icon(data.icon, color: data.color),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    data.labelKey.tr,
                    style: Theme.of(
                      context,
                    ).textTheme.labelMedium?.copyWith(color: AppColor.grey),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    data.value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: data.color,
                      fontWeight: FontWeight.w900,
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

class _ExpenseFilters extends StatelessWidget {
  const _ExpenseFilters({required this.controller});

  final ExpensesListController controller;

  @override
  Widget build(BuildContext context) {
    return DashboardCard(
      padding: const EdgeInsets.all(14),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final stacked =
              constraints.maxWidth < 620 ||
              MediaQuery.textScalerOf(context).scale(1) > 1.3;
          double width(double preferred) =>
              stacked ? constraints.maxWidth : preferred;
          return Wrap(
            spacing: 10,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: width(300),
                child: TextField(
                  controller: controller.searchController,
                  onChanged: controller.onSearchChanged,
                  onSubmitted: (_) => controller.submitSearch(),
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: 'expenses_search_hint'.tr,
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: controller.searchText.isEmpty
                        ? null
                        : IconButton(
                            onPressed: controller.clearSearch,
                            icon: const Icon(Icons.close_rounded),
                          ),
                    border: const OutlineInputBorder(),
                  ),
                ),
              ),
              SizedBox(
                width: width(220),
                child: DropdownButtonFormField<ExpenseStatus?>(
                  value: controller.statusFilter,
                  decoration: InputDecoration(
                    labelText: 'expense_status'.tr,
                    border: const OutlineInputBorder(),
                  ),
                  items: [
                    DropdownMenuItem<ExpenseStatus?>(
                      value: null,
                      child: Text('all'.tr),
                    ),
                    for (final status in ExpenseStatus.values)
                      DropdownMenuItem<ExpenseStatus?>(
                        value: status,
                        child: Text(status.labelKey.tr),
                      ),
                  ],
                  onChanged: controller.setStatusFilter,
                ),
              ),
              SizedBox(
                width: width(230),
                child: DropdownButtonFormField<ExpenseCategory?>(
                  value: controller.categoryFilter,
                  decoration: InputDecoration(
                    labelText: 'expense_category'.tr,
                    border: const OutlineInputBorder(),
                  ),
                  items: [
                    DropdownMenuItem<ExpenseCategory?>(
                      value: null,
                      child: Text('all'.tr),
                    ),
                    for (final category in ExpenseCategory.values)
                      DropdownMenuItem<ExpenseCategory?>(
                        value: category,
                        child: Text(category.labelKey.tr),
                      ),
                  ],
                  onChanged: controller.setCategoryFilter,
                ),
              ),
              OutlinedButton.icon(
                onPressed: () async {
                  final range = await showDateRangePicker(
                    context: context,
                    firstDate: DateTime(2020),
                    lastDate: DateTime.now().add(const Duration(days: 365)),
                    initialDateRange:
                        controller.fromDate != null && controller.toDate != null
                        ? DateTimeRange(
                            start: controller.fromDate!,
                            end: controller.toDate!,
                          )
                        : null,
                  );
                  controller.setDateRange(range);
                },
                icon: const Icon(Icons.date_range_outlined),
                label: Text('financial_filter_dates'.tr),
              ),
              if (controller.hasFilters)
                TextButton.icon(
                  onPressed: controller.clearFilters,
                  icon: const Icon(Icons.close_rounded),
                  label: Text('financial_clear_dates'.tr),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _ExpenseList extends StatelessWidget {
  const _ExpenseList({required this.controller});

  final ExpensesListController controller;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final expense in controller.expenses) ...[
          _ExpenseCard(
            expense: expense,
            onTap: () => controller.openDetails(expense),
          ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}

class _ExpenseCard extends StatelessWidget {
  const _ExpenseCard({required this.expense, required this.onTap});

  final ExpenseModel expense;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(symbol: 'JOD ', decimalDigits: 3);
    final date = DateFormat.yMd();
    final statusColor = switch (expense.status) {
      ExpenseStatus.posted || ExpenseStatus.approved => AppColor.success,
      ExpenseStatus.pending => const Color(0xFFFF9838),
      ExpenseStatus.rejected || ExpenseStatus.cancelled => AppColor.error,
    };
    return DashboardCard(
      padding: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.receipt_long_outlined, color: statusColor),
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
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: AppColor.secondaryColor,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      [
                        expense.fundingSource.labelKey.tr,
                        expense.paidByName,
                        date.format(expense.expenseDate),
                        if (expense.description.isNotEmpty) expense.description,
                      ].where((item) => item.trim().isNotEmpty).join('  |  '),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(color: AppColor.grey),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    currency.format(expense.amount),
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: AppColor.error,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    expense.status.labelKey.tr,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: statusColor,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _categoryLabel(ExpenseModel expense) {
    if (expense.category == ExpenseCategory.other &&
        expense.customCategoryName.isNotEmpty) {
      return expense.customCategoryName;
    }
    return expense.category.labelKey;
  }
}

class _EmptyExpenses extends StatelessWidget {
  const _EmptyExpenses({required this.hasFilters});

  final bool hasFilters;

  @override
  Widget build(BuildContext context) {
    return BusinessEmptyState(
      icon: Icons.receipt_long_outlined,
      title: hasFilters ? 'expenses_empty_filtered'.tr : 'expenses_empty'.tr,
    );
  }
}
