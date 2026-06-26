import 'package:fatoora/core/class/handilingdataview.dart';
import 'package:fatoora/core/constants/color.dart';
import 'package:fatoora/features/sales_returns/controllers/sales_returns_list_controller.dart';
import 'package:fatoora/features/sales_returns/data/models/sales_return_enums.dart';
import 'package:fatoora/features/sales_returns/data/models/sales_return_model.dart';
import 'package:fatoora/features/sales_returns/view/widgets/sales_return_status_chip.dart';
import 'package:fatoora/features/shared/business/business_shell.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

class SalesReturnsListScreen extends StatelessWidget {
  // TODO: Keep return summary cards out of the main dashboards until their
  // aggregate query can be added without making dashboard loading heavier.
  const SalesReturnsListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return GetBuilder<SalesReturnsListController>(
      builder: (controller) => BusinessShell(
        title: 'sales_returns'.tr,
        child: HandilingDataView(
          statusrequest: controller.statusRequest,
          errorMessage: controller.loadErrorMessageKey.tr,
          retryLabel: 'items_retry'.tr,
          onRetry: controller.loadSalesReturns,
          widget: RefreshIndicator(
            color: AppColor.primaryColor,
            onRefresh: controller.refreshSalesReturns,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 760;
                final padding = constraints.maxWidth < 600 ? 14.0 : 24.0;
                return SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: EdgeInsets.fromLTRB(padding, padding, padding, 96),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1260),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            'sales_returns'.tr,
                            style: Theme.of(context).textTheme.headlineSmall
                                ?.copyWith(
                                  color: AppColor.secondaryColor,
                                  fontWeight: FontWeight.w900,
                                ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'sales_returns_subtitle'.tr,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(color: AppColor.grey),
                          ),
                          const SizedBox(height: 18),
                          _Filters(controller: controller),
                          const SizedBox(height: 18),
                          if (controller.salesReturns.isEmpty)
                            _EmptyReturns(hasFilters: controller.hasFilters)
                          else if (compact)
                            _ReturnCards(controller: controller)
                          else
                            _ReturnTable(controller: controller),
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

class _Filters extends StatelessWidget {
  const _Filters({required this.controller});

  final SalesReturnsListController controller;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SizedBox(
          width: 320,
          child: TextField(
            controller: controller.searchController,
            onChanged: controller.onSearchChanged,
            decoration: InputDecoration(
              hintText: 'sales_returns_search_hint'.tr,
              prefixIcon: const Icon(Icons.search_rounded),
              filled: true,
              fillColor: AppColor.surface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
        ),
        DropdownButtonHideUnderline(
          child: DropdownButton<SalesReturnStatus?>(
            value: controller.statusFilter,
            hint: Text('status'.tr),
            borderRadius: BorderRadius.circular(14),
            items: [
              DropdownMenuItem<SalesReturnStatus?>(
                value: null,
                child: Text('all'.tr),
              ),
              for (final status in SalesReturnStatus.values)
                DropdownMenuItem<SalesReturnStatus?>(
                  value: status,
                  child: Text('sales_return_status_${status.value}'.tr),
                ),
            ],
            onChanged: controller.setStatusFilter,
          ),
        ),
        if (controller.hasFilters)
          TextButton.icon(
            onPressed: controller.clearFilters,
            icon: const Icon(Icons.close_rounded),
            label: Text('clear_filters'.tr),
          ),
      ],
    );
  }
}

class _ReturnCards extends StatelessWidget {
  const _ReturnCards({required this.controller});

  final SalesReturnsListController controller;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final salesReturn in controller.salesReturns) ...[
          _ReturnCard(
            salesReturn: salesReturn,
            onTap: () => controller.openDetails(salesReturn),
          ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}

class _ReturnCard extends StatelessWidget {
  const _ReturnCard({required this.salesReturn, required this.onTap});

  final SalesReturnModel salesReturn;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final money = NumberFormat.currency(symbol: 'JOD ', decimalDigits: 3);
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: AppColor.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: Color(0xFFE4E8EF)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      salesReturn.returnNumber,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: AppColor.secondaryColor,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  SalesReturnStatusChip(status: salesReturn.status),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                '${'original_invoice'.tr}: ${salesReturn.originalInvoiceNumber}',
              ),
              const SizedBox(height: 5),
              Text(salesReturn.customerSnapshot?.name ?? '-'),
              const SizedBox(height: 10),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                children: [
                  _Info(
                    icon: Icons.calendar_today_outlined,
                    text: DateFormat.yMd().format(salesReturn.returnDate),
                  ),
                  _Info(
                    icon: Icons.account_balance_wallet_outlined,
                    text: 'refund_type_${salesReturn.refundType.value}'.tr,
                  ),
                  _Info(
                    icon: Icons.payments_outlined,
                    text: money.format(salesReturn.grandTotal),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReturnTable extends StatelessWidget {
  const _ReturnTable({required this.controller});

  final SalesReturnsListController controller;

  @override
  Widget build(BuildContext context) {
    final money = NumberFormat.currency(symbol: 'JOD ', decimalDigits: 3);
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
            DataColumn(label: Text('return_number'.tr)),
            DataColumn(label: Text('original_invoice_number'.tr)),
            DataColumn(label: Text('customer_name'.tr)),
            DataColumn(label: Text('return_date'.tr)),
            DataColumn(label: Text('status'.tr)),
            DataColumn(label: Text('refund_type'.tr)),
            DataColumn(label: Text('grand_total'.tr)),
            DataColumn(label: Text('sales_rep'.tr)),
            DataColumn(label: Text('actions'.tr)),
          ],
          rows: controller.salesReturns
              .map(
                (salesReturn) => DataRow(
                  cells: [
                    DataCell(Text(salesReturn.returnNumber)),
                    DataCell(Text(salesReturn.originalInvoiceNumber)),
                    DataCell(
                      SizedBox(
                        width: 170,
                        child: Text(
                          salesReturn.customerSnapshot?.name ?? '-',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    DataCell(
                      Text(DateFormat.yMd().format(salesReturn.returnDate)),
                    ),
                    DataCell(SalesReturnStatusChip(status: salesReturn.status)),
                    DataCell(
                      Text('refund_type_${salesReturn.refundType.value}'.tr),
                    ),
                    DataCell(Text(money.format(salesReturn.grandTotal))),
                    DataCell(Text(salesReturn.salesRepName)),
                    DataCell(
                      IconButton.filledTonal(
                        tooltip: 'sales_return_details'.tr,
                        onPressed: () => controller.openDetails(salesReturn),
                        icon: const Icon(Icons.visibility_outlined),
                      ),
                    ),
                  ],
                ),
              )
              .toList(growable: false),
        ),
      ),
    );
  }
}

class _Info extends StatelessWidget {
  const _Info({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: AppColor.grey),
        const SizedBox(width: 5),
        Text(text),
      ],
    );
  }
}

class _EmptyReturns extends StatelessWidget {
  const _EmptyReturns({required this.hasFilters});

  final bool hasFilters;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: AppColor.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: Color(0xFFE4E8EF)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 58, horizontal: 20),
        child: Column(
          children: [
            const Icon(
              Icons.assignment_return_outlined,
              size: 42,
              color: AppColor.primaryColor,
            ),
            const SizedBox(height: 12),
            Text(
              hasFilters
                  ? 'sales_returns_no_search_results'.tr
                  : 'no_returns_found'.tr,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: AppColor.secondaryColor,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
