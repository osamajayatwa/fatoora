import 'package:fatoora/core/class/statusrequest.dart';
import 'package:fatoora/core/constants/color.dart';
import 'package:fatoora/core/motion/fatoora_overlays.dart';
import 'package:fatoora/core/widgets/responsive_data_table_card.dart';
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
        child: RefreshIndicator(
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
                        if (controller.statusRequest ==
                            StatusRequest.success) ...[
                          const SizedBox(height: 14),
                          _ExpenseSummary(controller: controller),
                        ],
                        const SizedBox(height: 14),
                        _ExpenseFilters(controller: controller),
                        const SizedBox(height: 14),
                        _ExpenseResults(controller: controller),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          key: const ValueKey('expense-search'),
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
            filled: true,
            fillColor: AppColor.surface,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
          ),
        ),
        if (controller.searchIsTooShort) ...[
          const SizedBox(height: 5),
          Text(
            'expenses_search_minimum'.tr,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
        const SizedBox(height: 10),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: OutlinedButton.icon(
            key: const ValueKey('expense-filter-button'),
            onPressed: () => _showFilters(context),
            icon: const Icon(Icons.tune_rounded),
            label: Text('expenses_filter'.tr),
          ),
        ),
        if (controller.hasFilters) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              if (controller.searchText.trim().isNotEmpty)
                InputChip(
                  label: Text(controller.searchText.trim()),
                  onDeleted: controller.clearSearch,
                ),
              if (controller.statusFilter != null)
                InputChip(
                  label: Text(controller.statusFilter!.labelKey.tr),
                  onDeleted: () => controller.setStatusFilter(null),
                ),
              if (controller.categoryFilter != null)
                InputChip(
                  label: Text(controller.categoryFilter!.labelKey.tr),
                  onDeleted: () => controller.setCategoryFilter(null),
                ),
              if (controller.fromDate != null && controller.toDate != null)
                InputChip(
                  label: Text(
                    '${DateFormat.yMd().format(controller.fromDate!)} - '
                    '${DateFormat.yMd().format(controller.toDate!)}',
                  ),
                  onDeleted: () => controller.setDateRange(null),
                ),
              TextButton(
                onPressed: controller.clearFilters,
                child: Text('clear_filters'.tr),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Future<void> _showFilters(BuildContext context) async {
    var status = controller.statusFilter;
    var category = controller.categoryFilter;
    DateTimeRange? range =
        controller.fromDate != null && controller.toDate != null
        ? DateTimeRange(start: controller.fromDate!, end: controller.toDate!)
        : null;
    final apply = await showFatooraModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'expenses_filter'.tr,
                    style: Theme.of(sheetContext).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<ExpenseStatus?>(
                    value: status,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: 'expense_status'.tr,
                      border: const OutlineInputBorder(),
                    ),
                    items: [
                      DropdownMenuItem<ExpenseStatus?>(
                        value: null,
                        child: Text('all'.tr),
                      ),
                      for (final value in ExpenseStatus.values)
                        DropdownMenuItem(
                          value: value,
                          child: Text(value.labelKey.tr),
                        ),
                    ],
                    onChanged: (value) => setSheetState(() => status = value),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<ExpenseCategory?>(
                    value: category,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: 'expense_category'.tr,
                      border: const OutlineInputBorder(),
                    ),
                    items: [
                      DropdownMenuItem<ExpenseCategory?>(
                        value: null,
                        child: Text('all'.tr),
                      ),
                      for (final value in ExpenseCategory.values)
                        DropdownMenuItem(
                          value: value,
                          child: Text(value.labelKey.tr),
                        ),
                    ],
                    onChanged: (value) => setSheetState(() => category = value),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final picked = await showDateRangePicker(
                        context: sheetContext,
                        firstDate: DateTime(2020),
                        lastDate: DateTime.now().add(const Duration(days: 365)),
                        initialDateRange: range,
                      );
                      if (picked != null) setSheetState(() => range = picked);
                    },
                    icon: const Icon(Icons.date_range_outlined),
                    label: Text(
                      range == null
                          ? 'financial_filter_dates'.tr
                          : '${DateFormat.yMd().format(range!.start)} - '
                                '${DateFormat.yMd().format(range!.end)}',
                    ),
                  ),
                  if (range != null)
                    TextButton(
                      onPressed: () => setSheetState(() => range = null),
                      child: Text('financial_clear_dates'.tr),
                    ),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: () => Navigator.of(sheetContext).pop(true),
                    child: Text('apply_filters'.tr),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    if (apply == true) {
      controller.applyFilters(status: status, category: category, range: range);
    }
  }
}

class _ExpenseResults extends StatelessWidget {
  const _ExpenseResults({required this.controller});
  final ExpensesListController controller;

  @override
  Widget build(BuildContext context) {
    if (controller.statusRequest == StatusRequest.loading) {
      return const Center(
        key: ValueKey('expense-results-loading'),
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 48),
          child: CircularProgressIndicator(),
        ),
      );
    }
    if (controller.statusRequest != StatusRequest.success) {
      return BusinessEmptyState(
        key: const ValueKey('expense-results-error'),
        icon: Icons.error_outline_rounded,
        title: controller.loadErrorMessageKey.tr,
        action: OutlinedButton.icon(
          onPressed: controller.loadExpenses,
          icon: const Icon(Icons.refresh_rounded),
          label: Text('items_retry'.tr),
        ),
      );
    }
    if (controller.expenses.isEmpty) {
      return _EmptyExpenses(hasFilters: controller.hasAppliedFilters);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ExpenseList(controller: controller),
        if (controller.loadMoreErrorMessageKey != null) ...[
          const SizedBox(height: 12),
          BusinessEmptyState(
            key: const ValueKey('expense-load-more-error'),
            icon: Icons.error_outline_rounded,
            title: controller.loadMoreErrorMessageKey!.tr,
            action: OutlinedButton.icon(
              onPressed: controller.loadMoreExpenses,
              icon: const Icon(Icons.refresh_rounded),
              label: Text('items_retry'.tr),
            ),
          ),
        ],
        if (controller.hasMore &&
            controller.loadMoreErrorMessageKey == null) ...[
          const SizedBox(height: 14),
          BusinessLoadMoreButton(
            loading: controller.isLoadingMore,
            onPressed: controller.loadMoreExpenses,
          ),
        ],
      ],
    );
  }
}

class _ExpenseList extends StatelessWidget {
  const _ExpenseList({required this.controller});

  final ExpensesListController controller;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final largeText = MediaQuery.textScalerOf(context).scale(1) > 1.3;
        if (constraints.maxWidth >= 900 && !largeText) {
          return _ExpenseTable(controller: controller);
        }
        final twoColumns = constraints.maxWidth >= 650 && !largeText;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final expense in controller.expenses)
              SizedBox(
                width: twoColumns
                    ? (constraints.maxWidth - 12) / 2
                    : constraints.maxWidth,
                child: ExpenseListCard(
                  expense: expense,
                  showSalesRepresentative: controller.isAdmin,
                  onTap: () => controller.openDetails(expense),
                ),
              ),
          ],
        );
      },
    );
  }
}

class ExpenseListCard extends StatelessWidget {
  const ExpenseListCard({
    super.key,
    required this.expense,
    required this.showSalesRepresentative,
    required this.onTap,
  });

  final ExpenseModel expense;
  final bool showSalesRepresentative;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(symbol: 'JOD ', decimalDigits: 3);
    final date = DateFormat.yMd();
    final statusColor = _expenseStatusColor(expense.status);
    return DashboardCard(
      padding: EdgeInsets.zero,
      child: InkWell(
        key: ValueKey('expense-card-${expense.id}'),
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _categoryLabel(expense).tr,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: AppColor.secondaryColor,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    expense.status.labelKey.tr,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: statusColor,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                currency.format(expense.amount),
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: AppColor.error,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 10,
                runSpacing: 6,
                children: [
                  Text(date.format(expense.expenseDate)),
                  Text(
                    expense.fundingSource.labelKey.tr,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  if (showSalesRepresentative &&
                      expense.salesRepName.isNotEmpty)
                    Text(expense.salesRepName),
                ],
              ),
              if (expense.description.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  expense.description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
              const SizedBox(height: 4),
              Text(
                '${'expenses_reference'.tr}: ${expense.id}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _categoryLabel(ExpenseModel expense) =>
    expense.category == ExpenseCategory.other &&
        expense.customCategoryName.isNotEmpty
    ? expense.customCategoryName
    : expense.category.labelKey;

class _ExpenseTable extends StatelessWidget {
  const _ExpenseTable({required this.controller});
  final ExpensesListController controller;

  @override
  Widget build(BuildContext context) {
    final money = NumberFormat.currency(symbol: 'JOD ', decimalDigits: 3);
    return ResponsiveDataTableCard(
      minWidth: controller.isAdmin ? 1050 : 900,
      child: DataTable(
        columnSpacing: 14,
        horizontalMargin: 14,
        columns: [
          _column('expenses_reference', 110),
          _column('expense_category', 140),
          _column('expense_amount', 120, numeric: true),
          _column('expense_date', 100),
          _column('expense_status', 90),
          _column('expense_funding_source', 145),
          if (controller.isAdmin) _column('sales_rep', 125),
          _column('actions', 60),
        ],
        rows: [
          for (final expense in controller.expenses)
            DataRow(
              onSelectChanged: (_) => controller.openDetails(expense),
              cells: [
                DataCell(
                  BoundedTableText(expense.id, width: 110, forceLtr: true),
                ),
                DataCell(
                  BoundedTableText(_categoryLabel(expense).tr, width: 140),
                ),
                DataCell(
                  BoundedTableText(
                    money.format(expense.amount),
                    width: 120,
                    forceLtr: true,
                  ),
                ),
                DataCell(
                  BoundedTableText(
                    DateFormat.yMd().format(expense.expenseDate),
                    width: 100,
                    forceLtr: true,
                  ),
                ),
                DataCell(
                  BoundedTableText(expense.status.labelKey.tr, width: 90),
                ),
                DataCell(
                  BoundedTableText(
                    expense.fundingSource.labelKey.tr,
                    width: 145,
                  ),
                ),
                if (controller.isAdmin)
                  DataCell(BoundedTableText(expense.salesRepName, width: 125)),
                DataCell(
                  IconButton.filledTonal(
                    tooltip: 'expense_details'.tr,
                    onPressed: () => controller.openDetails(expense),
                    icon: const Icon(Icons.visibility_outlined),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  DataColumn _column(String labelKey, double width, {bool numeric = false}) =>
      DataColumn(
        numeric: numeric,
        label: SizedBox(
          width: width,
          child: Text(
            labelKey.tr,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      );
}

Color _expenseStatusColor(ExpenseStatus status) => switch (status) {
  ExpenseStatus.posted || ExpenseStatus.approved => AppColor.success,
  ExpenseStatus.pending => const Color(0xFFFF9838),
  ExpenseStatus.rejected || ExpenseStatus.cancelled => AppColor.error,
};

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
