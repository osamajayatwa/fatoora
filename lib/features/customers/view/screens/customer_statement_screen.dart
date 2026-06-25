import 'package:fatoora/core/class/handilingdataview.dart';
import 'package:fatoora/core/constants/color.dart';
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
                child: Wrap(
                  spacing: 14,
                  runSpacing: 14,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    SizedBox(
                      width: 420,
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
                    FilledButton.icon(
                      onPressed: controller.isPrinting
                          ? null
                          : controller.printStatement,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColor.primaryColor,
                      ),
                      icon: const Icon(Icons.picture_as_pdf_outlined),
                      label: Text('print_export'.tr),
                    ),
                  ],
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
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: AppColor.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: Color(0xFFE4E8EF)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columns: [
            DataColumn(label: Text('invoice_date'.tr)),
            DataColumn(label: Text('customers_transaction_type'.tr)),
            DataColumn(label: Text('invoice_number'.tr)),
            DataColumn(label: Text('customers_debit'.tr)),
            DataColumn(label: Text('customers_credit'.tr)),
            DataColumn(label: Text('customers_balance'.tr)),
          ],
          rows: transactions
              .map(
                (transaction) => DataRow(
                  cells: [
                    DataCell(Text(date.format(transaction.transactionDate))),
                    DataCell(Text(transaction.transactionType.tr)),
                    DataCell(Text(transaction.sourceNumber)),
                    DataCell(Text(currency.format(transaction.debitAmount))),
                    DataCell(Text(currency.format(transaction.creditAmount))),
                    DataCell(Text(currency.format(transaction.balanceAfter))),
                  ],
                ),
              )
              .toList(),
        ),
      ),
    );
  }
}
