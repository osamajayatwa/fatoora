import 'package:fatoora/core/class/handilingdataview.dart';
import 'package:fatoora/core/constants/color.dart';
import 'package:fatoora/core/widgets/responsive_data_table_card.dart';
import 'package:fatoora/features/customers/controllers/customer_statement_controller.dart';
import 'package:fatoora/features/customers/data/models/customer_transaction_model.dart';
import 'package:fatoora/features/admin_dashboard/view/widgets/dashboard_card.dart';
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
        child: HandilingDataView(
          statusrequest: controller.statusRequest,
          errorMessage: controller.loadErrorMessageKey.tr,
          retryLabel: 'items_retry'.tr,
          onRetry: controller.loadStatement,
          widget: _StatementBody(controller: controller),
        ),
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
    if (customer == null) return const SizedBox.shrink();
    final currency = NumberFormat.currency(symbol: 'JOD ', decimalDigits: 3);
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
                                customer.name,
                                style: Theme.of(context).textTheme.headlineSmall
                                    ?.copyWith(
                                      color: AppColor.secondaryColor,
                                      fontWeight: FontWeight.w900,
                                    ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                '${'customers_balance'.tr}: ${currency.format(controller.finalBalance)}',
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(
                                      color: AppColor.primaryColor,
                                      fontWeight: FontWeight.w800,
                                    ),
                              ),
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
                          TextButton.icon(
                            onPressed: controller.clearDateRange,
                            icon: const Icon(Icons.close_rounded),
                            label: Text('clear_filters'.tr),
                          ),
                        OutlinedButton.icon(
                          onPressed: controller.isPrinting
                              ? null
                              : controller.printStatement,
                          icon: const Icon(Icons.print_outlined),
                          label: Text('print'.tr),
                        ),
                        FilledButton.icon(
                          onPressed: controller.isPrinting
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
              _Totals(controller: controller),
              const SizedBox(height: 16),
              if (controller.transactions.isEmpty)
                DashboardCard(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 34),
                    child: Text(
                      'customers_no_transactions'.tr,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: AppColor.secondaryColor,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                )
              else
                _TransactionsTable(transactions: controller.transactions),
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
              overflow: TextOverflow.ellipsis,
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
