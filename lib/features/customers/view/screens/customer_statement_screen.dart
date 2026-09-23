import 'package:fatoora/core/class/statusrequest.dart';
import 'package:fatoora/core/constants/color.dart';
import 'package:fatoora/core/widgets/responsive_data_table_card.dart';
import 'package:fatoora/features/customers/controllers/customer_statement_controller.dart';
import 'package:fatoora/features/customers/data/models/customer_transaction_model.dart';
import 'package:fatoora/features/customers/view/widgets/customer_list_components.dart';
import 'package:fatoora/features/admin_dashboard/view/widgets/dashboard_card.dart';
import 'package:fatoora/features/shared/business/business_page_widgets.dart';
import 'package:fatoora/features/shared/business/business_shell.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

class CustomerStatementScreen extends StatelessWidget {
  const CustomerStatementScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return GetBuilder<CustomerStatementController>(
      builder: (controller) => BusinessShell(
        title: 'customers_statement'.tr,
        showBackButton: true,
        onBack: controller.requestBack,
        child: _StatementBody(controller: controller),
      ),
    );
  }
}

class _StatementBody extends StatelessWidget {
  const _StatementBody({required this.controller});

  final CustomerStatementController controller;

  @override
  Widget build(BuildContext context) {
    final customer = controller.customer;
    return SingleChildScrollView(
      padding: EdgeInsets.all(MediaQuery.sizeOf(context).width < 600 ? 14 : 24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1180),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DashboardCard(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final headerWidth = constraints.maxWidth < 560
                        ? constraints.maxWidth
                        : 420.0;
                    return Wrap(
                      spacing: 14,
                      runSpacing: 14,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        SizedBox(
                          width: headerWidth,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                customer?.name ?? 'customers_statement'.tr,
                                style: Theme.of(context).textTheme.headlineSmall
                                    ?.copyWith(
                                      color: AppColor.secondaryColor,
                                      fontWeight: FontWeight.w900,
                                    ),
                              ),
                              if (controller.statusRequest ==
                                  StatusRequest.success) ...[
                                const SizedBox(height: 6),
                                CustomerBalanceBadge(
                                  balance: controller.finalBalance,
                                ),
                              ],
                            ],
                          ),
                        ),
                        OutlinedButton.icon(
                          onPressed: () async {
                            final range = await showDateRangePicker(
                              context: context,
                              firstDate: DateTime(2020),
                              lastDate: DateTime(DateTime.now().year + 2),
                              initialDateRange:
                                  controller.fromDate != null &&
                                      controller.toDate != null
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
                          label: Text('date_range'.tr),
                        ),
                        if (controller.fromDate != null ||
                            controller.toDate != null)
                          InputChip(
                            label: Text(
                              '${DateFormat.yMd().format(controller.fromDate!)} - '
                              '${DateFormat.yMd().format(controller.toDate!)}',
                            ),
                            onDeleted: controller.clearDateRange,
                          ),
                        OutlinedButton.icon(
                          onPressed: controller.isPrinting || customer == null
                              ? null
                              : controller.printStatement,
                          icon: const Icon(Icons.print_outlined),
                          label: Text('print'.tr),
                        ),
                        FilledButton.icon(
                          onPressed: controller.isPrinting || customer == null
                              ? null
                              : controller.exportStatementPdf,
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColor.primaryColor,
                          ),
                          icon: const Icon(Icons.picture_as_pdf_outlined),
                          label: Text('export_pdf'.tr),
                        ),
                      ],
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),
              if (controller.statusRequest == StatusRequest.success) ...[
                _Totals(controller: controller),
                const SizedBox(height: 12),
              ],
              _TransactionResults(controller: controller),
            ],
          ),
        ),
      ),
    );
  }
}

class _Totals extends StatelessWidget {
  const _Totals({required this.controller});

  final CustomerStatementController controller;

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(symbol: 'JOD ', decimalDigits: 3);
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        _TotalChip(
          label: 'customers_opening_balance'.tr,
          value: currency.format(controller.openingBalance),
        ),
        _TotalChip(
          label: 'customers_total_debit'.tr,
          value: currency.format(controller.totalDebit),
        ),
        _TotalChip(
          label: 'customers_total_credit'.tr,
          value: currency.format(controller.totalCredit),
        ),
        _TotalChip(
          label: 'customers_final_balance'.tr,
          value: currency.format(controller.finalBalance),
        ),
      ],
    );
  }
}

class _TotalChip extends StatelessWidget {
  const _TotalChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return DashboardCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: SizedBox(
        width: 240,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: Theme.of(context).textTheme.labelMedium),
            const SizedBox(height: 6),
            Text(
              value,
              maxLines: 2,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: AppColor.secondaryColor,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TransactionResults extends StatelessWidget {
  const _TransactionResults({required this.controller});
  final CustomerStatementController controller;

  @override
  Widget build(BuildContext context) {
    if (controller.statusRequest == StatusRequest.loading) {
      return const Center(
        key: ValueKey('statement-results-loading'),
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 48),
          child: CircularProgressIndicator(),
        ),
      );
    }
    if (controller.statusRequest != StatusRequest.success) {
      return BusinessEmptyState(
        key: const ValueKey('statement-results-error'),
        icon: Icons.error_outline_rounded,
        title: controller.loadErrorMessageKey.tr,
        action: OutlinedButton.icon(
          onPressed: controller.loadStatement,
          icon: const Icon(Icons.refresh_rounded),
          label: Text('items_retry'.tr),
        ),
      );
    }
    if (controller.transactions.isEmpty) {
      return BusinessEmptyState(
        key: const ValueKey('statement-results-empty'),
        icon: Icons.receipt_long_outlined,
        title: 'customers_no_transactions'.tr,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final largeText = MediaQuery.textScalerOf(context).scale(1) > 1.3;
            if (constraints.maxWidth >= 900 && !largeText) {
              return _TransactionsTable(transactions: controller.transactions);
            }
            final twoColumns = constraints.maxWidth >= 650 && !largeText;
            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final transaction in controller.transactions)
                  SizedBox(
                    width: twoColumns
                        ? (constraints.maxWidth - 12) / 2
                        : constraints.maxWidth,
                    child: StatementTransactionCard(transaction: transaction),
                  ),
              ],
            );
          },
        ),
        if (controller.loadMoreErrorMessageKey != null) ...[
          const SizedBox(height: 12),
          BusinessEmptyState(
            key: const ValueKey('statement-load-more-error'),
            icon: Icons.error_outline_rounded,
            title: controller.loadMoreErrorMessageKey!.tr,
            action: OutlinedButton.icon(
              onPressed: controller.loadMore,
              icon: const Icon(Icons.refresh_rounded),
              label: Text('items_retry'.tr),
            ),
          ),
        ],
        if (controller.hasMore &&
            controller.loadMoreErrorMessageKey == null) ...[
          const SizedBox(height: 12),
          BusinessLoadMoreButton(
            loading: controller.isLoadingMore,
            onPressed: controller.loadMore,
          ),
        ],
      ],
    );
  }
}

class StatementTransactionCard extends StatelessWidget {
  const StatementTransactionCard({super.key, required this.transaction});
  final CustomerTransactionModel transaction;

  @override
  Widget build(BuildContext context) {
    final money = NumberFormat.currency(symbol: 'JOD ', decimalDigits: 3);
    return DashboardCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  transaction.transactionType.tr,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: AppColor.secondaryColor,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Text(
                DateFormat.yMd().format(transaction.transactionDate),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
          if (transaction.sourceNumber.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              transaction.sourceNumber,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          if (transaction.notes.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              transaction.notes,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
          const SizedBox(height: 8),
          Wrap(
            spacing: 12,
            runSpacing: 5,
            children: [
              if (transaction.debitAmount != 0)
                Text(
                  '${'customers_debit'.tr}: '
                  '${money.format(transaction.debitAmount)}',
                ),
              if (transaction.creditAmount != 0)
                Text(
                  '${'customers_credit'.tr}: '
                  '${money.format(transaction.creditAmount)}',
                ),
            ],
          ),
          const SizedBox(height: 5),
          Text(
            '${'customers_balance'.tr}: '
            '${money.format(transaction.balanceAfter)}',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

class _TransactionsTable extends StatelessWidget {
  const _TransactionsTable({required this.transactions});

  final List<CustomerTransactionModel> transactions;

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(symbol: 'JOD ', decimalDigits: 3);
    final date = DateFormat.yMd();
    return ResponsiveDataTableCard(
      minWidth: 980,
      child: DataTable(
        columnSpacing: 14,
        horizontalMargin: 14,
        columns: [
          _column('invoice_date', width: 94),
          _column('customers_transaction_type', width: 130),
          _column('invoice_number', width: 132),
          _column('description', width: 250),
          _column('customers_debit', width: 112, numeric: true),
          _column('customers_credit', width: 112, numeric: true),
          _column('customers_balance', width: 122, numeric: true),
        ],
        rows: transactions
            .map(
              (transaction) => DataRow(
                cells: [
                  DataCell(
                    BoundedTableText(
                      date.format(transaction.transactionDate),
                      width: 94,
                      forceLtr: true,
                    ),
                  ),
                  DataCell(
                    BoundedTableText(
                      transaction.transactionType.tr,
                      width: 130,
                    ),
                  ),
                  DataCell(
                    BoundedTableText(
                      transaction.sourceNumber,
                      width: 132,
                      forceLtr: true,
                    ),
                  ),
                  DataCell(BoundedTableText(transaction.notes, width: 250)),
                  DataCell(
                    BoundedTableText(
                      currency.format(transaction.debitAmount),
                      width: 112,
                      textAlign: TextAlign.end,
                      forceLtr: true,
                    ),
                  ),
                  DataCell(
                    BoundedTableText(
                      currency.format(transaction.creditAmount),
                      width: 112,
                      textAlign: TextAlign.end,
                      forceLtr: true,
                    ),
                  ),
                  DataCell(
                    BoundedTableText(
                      currency.format(transaction.balanceAfter),
                      width: 122,
                      textAlign: TextAlign.end,
                      forceLtr: true,
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
