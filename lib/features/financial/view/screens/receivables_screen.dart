import 'dart:math' as math;

import 'package:fatoora/core/class/handilingdataview.dart';
import 'package:fatoora/core/constants/color.dart';
import 'package:fatoora/core/widgets/responsive_data_table_card.dart';
import 'package:fatoora/features/admin_dashboard/view/widgets/dashboard_card.dart';
import 'package:fatoora/features/financial/controllers/receivables_controller.dart';
import 'package:fatoora/features/financial/data/models/financial_dashboard_snapshot.dart';
import 'package:fatoora/features/shared/business/business_page_widgets.dart';
import 'package:fatoora/features/shared/business/business_shell.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

class ReceivablesScreen extends StatelessWidget {
  const ReceivablesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return GetBuilder<ReceivablesController>(
      builder: (controller) => BusinessShell(
        title: 'financial_receivables'.tr,
        child: HandilingDataView(
          statusrequest: controller.statusRequest,
          errorMessage: controller.loadErrorMessageKey.tr,
          retryLabel: 'items_retry'.tr,
          onRetry: controller.loadReceivables,
          widget: RefreshIndicator(
            onRefresh: controller.refreshReceivables,
            color: AppColor.primaryColor,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 900;
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
                          _ReceivablesHeader(controller: controller),
                          const SizedBox(height: 16),
                          if (controller.snapshot.customers.isEmpty)
                            const _EmptyReceivables()
                          else if (compact)
                            _ReceivableCards(controller: controller)
                          else
                            _ReceivablesTable(controller: controller),
                          if (controller.hasMore) ...[
                            const SizedBox(height: 12),
                            Center(
                              child: OutlinedButton.icon(
                                onPressed: controller.isLoadingMore
                                    ? null
                                    : controller.loadMore,
                                icon: controller.isLoadingMore
                                    ? const SizedBox.square(
                                        dimension: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(Icons.expand_more_rounded),
                                label: Text('load_more_records'.tr),
                              ),
                            ),
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
      ),
    );
  }
}

class _ReceivablesHeader extends StatelessWidget {
  const _ReceivablesHeader({required this.controller});

  final ReceivablesController controller;

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(symbol: 'JOD ', decimalDigits: 3);
    final controls = Wrap(
      spacing: 8,
      runSpacing: 8,
      alignment: WrapAlignment.end,
      children: [
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
            if (range != null) {
              controller.setDateRange(range.start, range.end);
            }
          },
          icon: const Icon(Icons.date_range_outlined),
          label: Text('financial_filter_dates'.tr),
        ),
        if (controller.fromDate != null || controller.toDate != null)
          IconButton.outlined(
            tooltip: 'financial_clear_dates'.tr,
            onPressed: controller.clearDateRange,
            icon: const Icon(Icons.close_rounded),
          ),
      ],
    );

    return DashboardCard(
      child: BusinessPageHeader(
        title: 'financial_receivables'.tr,
        subtitle: 'financial_receivables_subtitle'.tr,
        stretchTrailingOnCompact: false,
        trailing: Wrap(
          spacing: 16,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _TotalReceivable(
              value: currency.format(controller.snapshot.totalReceivables),
            ),
            controls,
          ],
        ),
      ),
    );
  }
}

class _TotalReceivable extends StatelessWidget {
  const _TotalReceivable({required this.value});

  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          'financial_total_receivables'.tr,
          style: Theme.of(
            context,
          ).textTheme.labelMedium?.copyWith(color: AppColor.grey),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            color: AppColor.error,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }
}

class _ReceivableCards extends StatelessWidget {
  const _ReceivableCards({required this.controller});

  final ReceivablesController controller;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final item in controller.snapshot.customers) ...[
          _ReceivableCard(
            item: item,
            onStatement: () => controller.openStatement(item),
          ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}

class _ReceivableCard extends StatelessWidget {
  const _ReceivableCard({required this.item, required this.onStatement});

  final FinancialCustomerBalance item;
  final VoidCallback onStatement;

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(symbol: 'JOD ', decimalDigits: 3);
    final date = DateFormat.yMd();
    return DashboardCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  item.customer.name,
                  softWrap: true,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: AppColor.secondaryColor,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Text(
                currency.format(item.balance),
                textAlign: TextAlign.end,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: AppColor.error,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (item.customer.phone.isNotEmpty)
                _InfoPill(
                  icon: Icons.phone_outlined,
                  label: item.customer.phone,
                ),
              if (item.customer.createdByName.isNotEmpty)
                _InfoPill(
                  icon: Icons.badge_outlined,
                  label: item.customer.createdByName,
                ),
              if (item.lastTransactionDate != null)
                _InfoPill(
                  icon: Icons.event_outlined,
                  label: date.format(item.lastTransactionDate!),
                ),
            ],
          ),
          const SizedBox(height: 14),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: TextButton.icon(
              onPressed: onStatement,
              icon: const Icon(Icons.article_outlined),
              label: Text('customers_statement'.tr),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReceivablesTable extends StatelessWidget {
  const _ReceivablesTable({required this.controller});

  final ReceivablesController controller;

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(symbol: 'JOD ', decimalDigits: 3);
    final date = DateFormat.yMd();
    return ResponsiveDataTableCard(
      minWidth: 840,
      child: DataTable(
        columnSpacing: 14,
        horizontalMargin: 14,
        columns: [
          _column('customer_name', width: 220),
          _column('Phone', width: 128),
          _column('sales_rep', width: 150),
          _column('financial_last_transaction', width: 112),
          _column('customers_balance', width: 126, numeric: true),
          _column('actions', width: 64),
        ],
        rows: controller.snapshot.customers
            .map(
              (item) => DataRow(
                cells: [
                  DataCell(BoundedTableText(item.customer.name, width: 220)),
                  DataCell(
                    BoundedTableText(
                      item.customer.phone,
                      width: 128,
                      forceLtr: true,
                    ),
                  ),
                  DataCell(
                    BoundedTableText(item.customer.createdByName, width: 150),
                  ),
                  DataCell(
                    BoundedTableText(
                      item.lastTransactionDate == null
                          ? '-'
                          : date.format(item.lastTransactionDate!),
                      width: 112,
                      forceLtr: true,
                    ),
                  ),
                  DataCell(
                    BoundedTableText(
                      currency.format(item.balance),
                      width: 126,
                      textAlign: TextAlign.end,
                      forceLtr: true,
                    ),
                  ),
                  DataCell(
                    SizedBox(
                      width: 64,
                      child: IconButton(
                        tooltip: 'customers_statement'.tr,
                        onPressed: () => controller.openStatement(item),
                        icon: const Icon(Icons.article_outlined),
                      ),
                    ),
                  ),
                ],
              ),
            )
            .toList(),
      ),
    );
  }

  DataColumn _column(
    String labelKey, {
    required double width,
    bool numeric = false,
  }) {
    return DataColumn(
      numeric: numeric,
      label: SizedBox(
        width: width,
        child: Text(labelKey.tr, maxLines: 2, overflow: TextOverflow.ellipsis),
      ),
    );
  }
}

class _EmptyReceivables extends StatelessWidget {
  const _EmptyReceivables();

  @override
  Widget build(BuildContext context) {
    return BusinessEmptyState(
      icon: Icons.account_balance_wallet_outlined,
      title: 'financial_no_receivables'.tr,
    );
  }
}

class _InfoPill extends StatelessWidget {
  const _InfoPill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxWidth: math.max(180.0, MediaQuery.sizeOf(context).width - 72),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFF4F6FA),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppColor.grey),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ),
        ],
      ),
    );
  }
}
