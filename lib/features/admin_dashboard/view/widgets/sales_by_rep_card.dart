import 'package:fatoora/app/routes/app_routes.dart';
import 'package:fatoora/core/constants/color.dart';
import 'package:fatoora/features/admin_dashboard/controller/admin_dashboard_controller.dart';
import 'package:fatoora/features/admin_dashboard/view/widgets/dashboard_card.dart';
import 'package:fatoora/features/financial/data/models/financial_dashboard_snapshot.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

class SalesByRepCard extends StatelessWidget {
  const SalesByRepCard({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<AdminDashboardController>();
    final rows = controller.snapshot.salesByRepSummary;
    return DashboardCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'sales_by_rep'.tr,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: AppColor.secondaryColor,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: () => controller.navigateTo(AppRoute.adminUsers),
                icon: const Icon(Icons.manage_accounts_outlined),
                label: Text('admin_users'.tr),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (rows.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 34),
              child: Center(child: Text('sales_by_rep_empty'.tr)),
            )
          else if (MediaQuery.sizeOf(context).width < 760)
            Column(
              children: [
                for (final row in rows) ...[
                  _RepSummaryCard(row: row),
                  const SizedBox(height: 10),
                ],
              ],
            )
          else
            _RepSummaryTable(rows: rows),
        ],
      ),
    );
  }
}

class _RepSummaryTable extends StatelessWidget {
  const _RepSummaryTable({required this.rows});

  final List<FinancialRepSalesSummary> rows;

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(symbol: 'JOD ', decimalDigits: 3);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        headingTextStyle: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: AppColor.secondaryColor,
          fontWeight: FontWeight.w800,
        ),
        columns: [
          DataColumn(label: Text('sales_rep'.tr)),
          DataColumn(label: Text('financial_total_sales'.tr)),
          DataColumn(label: Text('financial_cash_sales'.tr)),
          DataColumn(label: Text('financial_credit_sales'.tr)),
          DataColumn(label: Text('financial_partial_sales'.tr)),
          DataColumn(label: Text('receipts_collected'.tr)),
          DataColumn(label: Text('financial_cash_in_hand'.tr)),
          DataColumn(label: Text('dashboard_invoices_count'.tr)),
        ],
        rows: rows
            .map(
              (row) => DataRow(
                cells: [
                  DataCell(Text(_repName(row))),
                  DataCell(Text(currency.format(row.totalSales))),
                  DataCell(Text(currency.format(row.cashSales))),
                  DataCell(Text(currency.format(row.creditSales))),
                  DataCell(Text(currency.format(row.partialSales))),
                  DataCell(Text(currency.format(row.receiptsCollected))),
                  DataCell(Text(currency.format(row.cashInHand))),
                  DataCell(Text(row.invoiceCount.toString())),
                ],
              ),
            )
            .toList(),
      ),
    );
  }
}

class _RepSummaryCard extends StatelessWidget {
  const _RepSummaryCard({required this.row});

  final FinancialRepSalesSummary row;

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(symbol: 'JOD ', decimalDigits: 3);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFD),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE4E8EF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            _repName(row),
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: AppColor.secondaryColor,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 14,
            runSpacing: 10,
            children: [
              _Metric(
                label: 'financial_total_sales'.tr,
                value: currency.format(row.totalSales),
              ),
              _Metric(
                label: 'financial_cash_sales'.tr,
                value: currency.format(row.cashSales),
              ),
              _Metric(
                label: 'financial_credit_sales'.tr,
                value: currency.format(row.creditSales),
              ),
              _Metric(
                label: 'financial_partial_sales'.tr,
                value: currency.format(row.partialSales),
              ),
              _Metric(
                label: 'receipts_collected'.tr,
                value: currency.format(row.receiptsCollected),
              ),
              _Metric(
                label: 'financial_cash_in_hand'.tr,
                value: currency.format(row.cashInHand),
              ),
              _Metric(
                label: 'dashboard_invoices_count'.tr,
                value: row.invoiceCount.toString(),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 150,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.labelSmall?.copyWith(color: AppColor.grey),
          ),
          const SizedBox(height: 3),
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

String _repName(FinancialRepSalesSummary row) {
  return row.salesRepName.isEmpty ? 'sales_rep'.tr : row.salesRepName;
}
