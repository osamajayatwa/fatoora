import 'package:fatoora/core/class/handilingdataview.dart';
import 'package:fatoora/core/constants/color.dart';
import 'package:fatoora/features/receipts/controllers/receipts_list_controller.dart';
import 'package:fatoora/features/receipts/data/models/receipt_model.dart';
import 'package:fatoora/features/shared/business/business_shell.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

class ReceiptsListScreen extends StatelessWidget {
  const ReceiptsListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return GetBuilder<ReceiptsListController>(
      builder: (controller) {
        return BusinessShell(
          title: 'receipts'.tr,
          child: HandilingDataView(
            statusrequest: controller.statusRequest,
            errorMessage: controller.loadErrorMessageKey.tr,
            retryLabel: 'items_retry'.tr,
            onRetry: controller.loadReceipts,
            widget: RefreshIndicator(
              color: AppColor.primaryColor,
              onRefresh: controller.refreshReceipts,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final compact = constraints.maxWidth < 760;
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
                            _ReceiptsHeader(controller: controller),
                            const SizedBox(height: 18),
                            _ReceiptFilters(controller: controller),
                            const SizedBox(height: 18),
                            if (controller.receipts.isEmpty)
                              _EmptyReceipts(hasFilters: controller.hasFilters)
                            else if (compact)
                              _ReceiptCards(controller: controller)
                            else
                              _ReceiptTable(controller: controller),
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
      },
    );
  }
}

class _ReceiptsHeader extends StatelessWidget {
  const _ReceiptsHeader({required this.controller});

  final ReceiptsListController controller;

  @override
  Widget build(BuildContext context) {
    final compact =
        MediaQuery.sizeOf(context).width < 620 ||
        MediaQuery.textScalerOf(context).scale(1) > 1.3;
    final title = Text(
      'receipts'.tr,
      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
        color: AppColor.secondaryColor,
        fontWeight: FontWeight.w900,
      ),
    );
    final action = controller.canCreateReceipt
        ? FilledButton.icon(
            onPressed: controller.openCreateReceipt,
            style: FilledButton.styleFrom(
              backgroundColor: AppColor.primaryColor,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            ),
            icon: const Icon(Icons.add_rounded),
            label: Text('create_receipt'.tr),
          )
        : null;
    if (compact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          title,
          if (action != null) ...[const SizedBox(height: 12), action],
        ],
      );
    }
    return Row(
      children: [
        Expanded(child: title),
        if (action != null) ...[const SizedBox(width: 16), action],
      ],
    );
  }
}

class _ReceiptFilters extends StatelessWidget {
  const _ReceiptFilters({required this.controller});

  final ReceiptsListController controller;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final searchWidth = constraints.maxWidth < 350
            ? constraints.maxWidth
            : 320.0;
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: searchWidth,
              child: TextField(
                controller: controller.searchController,
                onChanged: controller.onSearchChanged,
                onSubmitted: (_) => controller.submitSearch(),
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: 'receipts_search_hint'.tr,
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: controller.searchText.isEmpty
                      ? null
                      : IconButton(
                          onPressed: controller.clearSearch,
                          icon: const Icon(Icons.close_rounded),
                        ),
                  filled: true,
                  fillColor: AppColor.surface,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
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
    );
  }
}

class _ReceiptCards extends StatelessWidget {
  const _ReceiptCards({required this.controller});

  final ReceiptsListController controller;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final receipt in controller.receipts) ...[
          _ReceiptCard(
            receipt: receipt,
            onTap: () => controller.openDetails(receipt),
          ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}

class _ReceiptCard extends StatelessWidget {
  const _ReceiptCard({required this.receipt, required this.onTap});

  final ReceiptModel receipt;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(symbol: 'JOD ', decimalDigits: 3);
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
                      receipt.receiptNumber,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: AppColor.secondaryColor,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  _PaymentMethodChip(method: receipt.paymentMethod),
                ],
              ),
              const SizedBox(height: 10),
              Text(receipt.customerSnapshot.name),
              const SizedBox(height: 8),
              Wrap(
                spacing: 14,
                runSpacing: 8,
                children: [
                  _MiniInfo(
                    icon: Icons.calendar_today_outlined,
                    text: DateFormat.yMd().format(receipt.receiptDate),
                  ),
                  _MiniInfo(
                    icon: Icons.person_outline,
                    text: receipt.salesRepName,
                  ),
                  _MiniInfo(
                    icon: Icons.payments_outlined,
                    text: currency.format(receipt.amount),
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

class _ReceiptTable extends StatelessWidget {
  const _ReceiptTable({required this.controller});

  final ReceiptsListController controller;

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(symbol: 'JOD ', decimalDigits: 3);
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
          headingTextStyle: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: AppColor.secondaryColor,
            fontWeight: FontWeight.w800,
          ),
          columns: [
            DataColumn(label: Text('receipt_number'.tr)),
            DataColumn(label: Text('receipt_date'.tr)),
            DataColumn(label: Text('customer_name'.tr)),
            DataColumn(label: Text('receipt_amount'.tr)),
            DataColumn(label: Text('payment_method'.tr)),
            DataColumn(label: Text('sales_rep'.tr)),
            DataColumn(label: Text('actions'.tr)),
          ],
          rows: controller.receipts
              .map(
                (receipt) => DataRow(
                  cells: [
                    DataCell(Text(receipt.receiptNumber)),
                    DataCell(
                      Text(DateFormat.yMd().format(receipt.receiptDate)),
                    ),
                    DataCell(
                      SizedBox(
                        width: 190,
                        child: Text(
                          receipt.customerSnapshot.name,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    DataCell(Text(currency.format(receipt.amount))),
                    DataCell(_PaymentMethodChip(method: receipt.paymentMethod)),
                    DataCell(Text(receipt.salesRepName)),
                    DataCell(
                      IconButton.filledTonal(
                        tooltip: 'invoice_details'.tr,
                        onPressed: () => controller.openDetails(receipt),
                        icon: const Icon(Icons.visibility_outlined),
                      ),
                    ),
                  ],
                ),
              )
              .toList(),
        ),
      ),
    );
  }
}

class _PaymentMethodChip extends StatelessWidget {
  const _PaymentMethodChip({required this.method});

  final String method;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColor.primaryLight,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        'payment_method_$method'.tr,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: AppColor.primaryDark,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _MiniInfo extends StatelessWidget {
  const _MiniInfo({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: AppColor.grey),
        const SizedBox(width: 5),
        Text(text.isEmpty ? '-' : text),
      ],
    );
  }
}

class _EmptyReceipts extends StatelessWidget {
  const _EmptyReceipts({required this.hasFilters});

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
              Icons.receipt_long_outlined,
              size: 42,
              color: AppColor.primaryColor,
            ),
            const SizedBox(height: 12),
            Text(
              hasFilters
                  ? 'receipts_no_search_results'.tr
                  : 'receipts_empty'.tr,
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
