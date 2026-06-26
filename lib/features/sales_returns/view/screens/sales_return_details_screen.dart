import 'package:fatoora/core/class/handilingdataview.dart';
import 'package:fatoora/core/constants/color.dart';
import 'package:fatoora/features/admin_dashboard/view/widgets/dashboard_card.dart';
import 'package:fatoora/features/sales_returns/controllers/sales_return_details_controller.dart';
import 'package:fatoora/features/sales_returns/data/models/sales_return_enums.dart';
import 'package:fatoora/features/sales_returns/data/models/sales_return_model.dart';
import 'package:fatoora/features/sales_returns/view/widgets/sales_return_status_chip.dart';
import 'package:fatoora/features/shared/business/business_shell.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

class SalesReturnDetailsScreen extends StatelessWidget {
  const SalesReturnDetailsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return GetBuilder<SalesReturnDetailsController>(
      builder: (controller) => BusinessShell(
        title: 'sales_return_details'.tr,
        showBackButton: true,
        child: HandilingDataView(
          statusrequest: controller.statusRequest,
          errorMessage: controller.loadErrorMessageKey.tr,
          retryLabel: 'items_retry'.tr,
          onRetry: controller.loadSalesReturn,
          widget: controller.salesReturn == null
              ? const SizedBox.shrink()
              : _Details(
                  controller: controller,
                  salesReturn: controller.salesReturn!,
                ),
        ),
      ),
    );
  }
}

class _Details extends StatelessWidget {
  const _Details({required this.controller, required this.salesReturn});

  final SalesReturnDetailsController controller;
  final SalesReturnModel salesReturn;

  @override
  Widget build(BuildContext context) {
    final money = NumberFormat.currency(symbol: 'JOD ', decimalDigits: 3);
    return SingleChildScrollView(
      padding: EdgeInsets.all(MediaQuery.sizeOf(context).width < 600 ? 14 : 24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1200),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          salesReturn.returnNumber,
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(
                                color: AppColor.secondaryColor,
                                fontWeight: FontWeight.w900,
                              ),
                        ),
                        const SizedBox(height: 4),
                        Text(DateFormat.yMMMd().format(salesReturn.returnDate)),
                      ],
                    ),
                  ),
                  SalesReturnStatusChip(status: salesReturn.status),
                ],
              ),
              const SizedBox(height: 18),
              _InfoCard(salesReturn: salesReturn),
              const SizedBox(height: 18),
              _ItemsCard(salesReturn: salesReturn),
              const SizedBox(height: 18),
              LayoutBuilder(
                builder: (context, constraints) {
                  final totals = _TotalsCard(
                    salesReturn: salesReturn,
                    money: money,
                  );
                  final posting = _PostingCard(salesReturn: salesReturn);
                  if (constraints.maxWidth < 820) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [totals, const SizedBox(height: 18), posting],
                    );
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: totals),
                      const SizedBox(width: 18),
                      Expanded(child: posting),
                    ],
                  );
                },
              ),
              if (controller.canConfirm) ...[
                const SizedBox(height: 18),
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: FilledButton.icon(
                    onPressed: controller.confirmReturn,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColor.primaryColor,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 14,
                      ),
                    ),
                    icon: controller.isConfirming
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColor.surface,
                            ),
                          )
                        : const Icon(Icons.assignment_turned_in_outlined),
                    label: Text('confirm_return'.tr),
                  ),
                ),
              ],
              // TODO: Add a printable sales-return PDF without changing invoice PDFs.
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.salesReturn});

  final SalesReturnModel salesReturn;

  @override
  Widget build(BuildContext context) {
    return DashboardCard(
      child: Wrap(
        spacing: 30,
        runSpacing: 14,
        children: [
          _Field(
            label: 'original_invoice_number'.tr,
            value: salesReturn.originalInvoiceNumber,
          ),
          _Field(
            label: 'customer_name'.tr,
            value: salesReturn.customerSnapshot?.name ?? '-',
          ),
          _Field(label: 'sales_rep'.tr, value: salesReturn.salesRepName),
          _Field(
            label: 'refund_type'.tr,
            value: 'refund_type_${salesReturn.refundType.value}'.tr,
          ),
          _Field(label: 'return_reason'.tr, value: salesReturn.reason),
        ],
      ),
    );
  }
}

class _ItemsCard extends StatelessWidget {
  const _ItemsCard({required this.salesReturn});

  final SalesReturnModel salesReturn;

  @override
  Widget build(BuildContext context) {
    final money = NumberFormat.currency(symbol: 'JOD ', decimalDigits: 3);
    return DashboardCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'return_items'.tr,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: AppColor.secondaryColor,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columns: [
                DataColumn(label: Text('item_name'.tr)),
                DataColumn(label: Text('returned_quantity'.tr)),
                DataColumn(label: Text('unit'.tr)),
                DataColumn(label: Text('unit_price'.tr)),
                DataColumn(label: Text('tax'.tr)),
                DataColumn(label: Text('grand_total'.tr)),
              ],
              rows: salesReturn.items
                  .map(
                    (item) => DataRow(
                      cells: [
                        DataCell(Text(item.itemName)),
                        DataCell(Text(_quantity(item.returnedQuantity))),
                        DataCell(Text(item.unit)),
                        DataCell(Text(money.format(item.unitPrice))),
                        DataCell(
                          Text('${item.taxPercent.toStringAsFixed(2)}%'),
                        ),
                        DataCell(Text(money.format(item.total))),
                      ],
                    ),
                  )
                  .toList(growable: false),
            ),
          ),
        ],
      ),
    );
  }
}

class _TotalsCard extends StatelessWidget {
  const _TotalsCard({required this.salesReturn, required this.money});

  final SalesReturnModel salesReturn;
  final NumberFormat money;

  @override
  Widget build(BuildContext context) {
    return DashboardCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'return_totals'.tr,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          _Field(
            label: 'subtotal'.tr,
            value: money.format(salesReturn.subtotal),
          ),
          _Field(label: 'tax'.tr, value: money.format(salesReturn.totalTax)),
          const Divider(height: 22),
          _Field(
            label: 'grand_total'.tr,
            value: money.format(salesReturn.grandTotal),
            bold: true,
          ),
        ],
      ),
    );
  }
}

class _PostingCard extends StatelessWidget {
  const _PostingCard({required this.salesReturn});

  final SalesReturnModel salesReturn;

  @override
  Widget build(BuildContext context) {
    return DashboardCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'posting_status'.tr,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          _Field(
            label: 'inventory_return_posted'.tr,
            value: salesReturn.inventoryPosted ? 'yes'.tr : 'no'.tr,
          ),
          _Field(
            label: 'financial_return_posted'.tr,
            value: salesReturn.financialPosted ? 'yes'.tr : 'no'.tr,
          ),
          _Ids(
            label: 'stock_movements'.tr,
            values: salesReturn.stockMovementIds,
          ),
          _Ids(
            label: 'customer_transactions'.tr,
            values: salesReturn.customerTransactionIds,
          ),
          _Ids(label: 'cash_movements'.tr, values: salesReturn.cashMovementIds),
        ],
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({required this.label, required this.value, this.bold = false});

  final String label;
  final String value;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 150,
            child: Text(label, style: Theme.of(context).textTheme.labelMedium),
          ),
          Expanded(
            child: Text(
              value,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: AppColor.secondaryColor,
                fontWeight: bold ? FontWeight.w900 : FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Ids extends StatelessWidget {
  const _Ids({required this.label, required this.values});

  final String label;
  final List<String> values;

  @override
  Widget build(BuildContext context) {
    return _Field(
      label: label,
      value: values.isEmpty ? '-' : values.join('\n'),
    );
  }
}

String _quantity(double value) => value == value.roundToDouble()
    ? value.toStringAsFixed(0)
    : value.toStringAsFixed(3);
