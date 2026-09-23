import 'package:fatoora/core/class/statusrequest.dart';
import 'package:fatoora/core/constants/color.dart';
import 'package:fatoora/core/motion/fatoora_overlays.dart';
import 'package:fatoora/core/widgets/responsive_data_table_card.dart';
import 'package:fatoora/features/receipts/controllers/receipts_list_controller.dart';
import 'package:fatoora/features/receipts/data/models/receipt_model.dart';
import 'package:fatoora/features/receipts/view/widgets/receipt_presentation.dart';
import 'package:fatoora/features/shared/business/business_page_widgets.dart';
import 'package:fatoora/features/shared/business/business_shell.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

class ReceiptsListScreen extends StatelessWidget {
  const ReceiptsListScreen({super.key});

  @override
  Widget build(BuildContext context) => GetBuilder<ReceiptsListController>(
    builder: (controller) => BusinessShell(
      title: 'receipts'.tr,
      child: RefreshIndicator(
        color: AppColor.primaryColor,
        onRefresh: controller.refreshReceipts,
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
                      BusinessPageHeader(
                        title: 'receipts'.tr,
                        trailing: controller.canCreateReceipt
                            ? BusinessPrimaryActionButton(
                                onPressed: controller.openCreateReceipt,
                                icon: Icons.add_rounded,
                                label: 'create_receipt'.tr,
                              )
                            : null,
                      ),
                      const SizedBox(height: 14),
                      _Controls(controller: controller),
                      const SizedBox(height: 14),
                      _Results(controller: controller),
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

class _Controls extends StatelessWidget {
  const _Controls({required this.controller});
  final ReceiptsListController controller;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      TextField(
        key: const ValueKey('receipt-search'),
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
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
      if (controller.searchIsTooShort) ...[
        const SizedBox(height: 5),
        Text(
          'receipts_search_minimum'.tr,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
      const SizedBox(height: 10),
      Align(
        alignment: AlignmentDirectional.centerStart,
        child: OutlinedButton.icon(
          key: const ValueKey('receipt-filter-button'),
          onPressed: () => _showDateFilter(context),
          icon: const Icon(Icons.tune_rounded),
          label: Text('receipts_filter'.tr),
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
                key: const ValueKey('receipt-search-chip'),
                label: Text(controller.searchText.trim()),
                onDeleted: controller.clearSearch,
              ),
            if (controller.fromDate != null && controller.toDate != null)
              InputChip(
                key: const ValueKey('receipt-date-chip'),
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

  Future<void> _showDateFilter(BuildContext context) async {
    final action = await showFatooraModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Text(
                'financial_filter_dates'.tr,
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            ListTile(
              key: const ValueKey('receipt-date-choose'),
              leading: const Icon(Icons.date_range_outlined),
              title: Text('financial_filter_dates'.tr),
              onTap: () => Navigator.of(sheetContext).pop('choose'),
            ),
            if (controller.fromDate != null || controller.toDate != null)
              ListTile(
                key: const ValueKey('receipt-date-clear'),
                leading: const Icon(Icons.close_rounded),
                title: Text('financial_clear_dates'.tr),
                onTap: () => Navigator.of(sheetContext).pop('clear'),
              ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
    if (action == 'clear') {
      controller.setDateRange(null);
    } else if (action == 'choose' && context.mounted) {
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
      if (range != null) controller.setDateRange(range);
    }
  }
}

class _Results extends StatelessWidget {
  const _Results({required this.controller});
  final ReceiptsListController controller;

  @override
  Widget build(BuildContext context) {
    if (controller.statusRequest == StatusRequest.loading) {
      return const Center(
        key: ValueKey('receipt-results-loading'),
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 48),
          child: CircularProgressIndicator(),
        ),
      );
    }
    if (controller.statusRequest != StatusRequest.success) {
      return BusinessEmptyState(
        key: const ValueKey('receipt-results-error'),
        icon: Icons.error_outline_rounded,
        title: controller.loadErrorMessageKey.tr,
        action: OutlinedButton.icon(
          onPressed: controller.loadReceipts,
          icon: const Icon(Icons.refresh_rounded),
          label: Text('items_retry'.tr),
        ),
      );
    }
    if (controller.receipts.isEmpty) {
      return BusinessEmptyState(
        key: const ValueKey('receipt-results-empty'),
        icon: Icons.receipt_long_outlined,
        title: controller.hasAppliedFilters
            ? 'receipts_no_search_results'.tr
            : 'receipts_empty'.tr,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final largeText = MediaQuery.textScalerOf(context).scale(1) > 1.3;
            if (width >= 760 && !largeText) {
              return _ReceiptTable(controller: controller);
            }
            final columns = width >= 650 && !largeText ? 2 : 1;
            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final receipt in controller.receipts)
                  SizedBox(
                    width: columns == 1 ? width : (width - 12) / 2,
                    child: ReceiptListCard(
                      receipt: receipt,
                      showSalesRepresentative:
                          controller.showSalesRepresentative,
                      onTap: () => controller.openDetails(receipt),
                    ),
                  ),
              ],
            );
          },
        ),
        if (controller.loadMoreErrorMessageKey != null) ...[
          const SizedBox(height: 12),
          BusinessEmptyState(
            key: const ValueKey('receipt-load-more-error'),
            icon: Icons.error_outline_rounded,
            title: controller.loadMoreErrorMessageKey!.tr,
            action: OutlinedButton.icon(
              onPressed: controller.loadMoreReceipts,
              icon: const Icon(Icons.refresh_rounded),
              label: Text('items_retry'.tr),
            ),
          ),
        ],
        if (controller.hasMore &&
            controller.loadMoreErrorMessageKey == null) ...[
          const SizedBox(height: 16),
          BusinessLoadMoreButton(
            loading: controller.isLoadingMore,
            onPressed: controller.loadMoreReceipts,
          ),
        ],
      ],
    );
  }
}

class ReceiptListCard extends StatelessWidget {
  const ReceiptListCard({
    super.key,
    required this.receipt,
    required this.showSalesRepresentative,
    required this.onTap,
  });
  final ReceiptModel receipt;
  final bool showSalesRepresentative;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final money = NumberFormat.currency(symbol: 'JOD ', decimalDigits: 3);
    final allocations = receiptAllocationRows(receipt);
    final cashKey = receiptCashDestinationKey(receipt);
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: AppColor.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: Color(0xFFE4E8EF)),
      ),
      child: InkWell(
        key: ValueKey('receipt-card-${receipt.id}'),
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    receipt.receiptNumber,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: AppColor.secondaryColor,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  _PaymentMethodChip(method: receipt.paymentMethod),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                receipt.customerSnapshot.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 8),
              Text(
                money.format(receipt.amount),
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: AppColor.primaryColor,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              _ReceiptMeta(
                icon: Icons.calendar_today_outlined,
                text: DateFormat.yMd().format(receipt.receiptDate),
              ),
              if (allocations.isNotEmpty)
                _ReceiptMeta(
                  icon: Icons.receipt_long_outlined,
                  text: 'receipts_allocated_invoices'.trParams({
                    'count': '${allocations.length}',
                  }),
                ),
              if (cashKey != null)
                _ReceiptMeta(
                  icon: Icons.account_balance_wallet_outlined,
                  text: '${'receipts_cash_destination'.tr}: ${cashKey.tr}',
                ),
              if (showSalesRepresentative &&
                  receipt.salesRepName.trim().isNotEmpty)
                _ReceiptMeta(
                  icon: Icons.person_outline,
                  text: receipt.salesRepName,
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
    final money = NumberFormat.currency(symbol: 'JOD ', decimalDigits: 3);
    final showRep = controller.showSalesRepresentative;
    return ResponsiveDataTableCard(
      minWidth: showRep ? 1360 : 1200,
      child: DataTable(
        showCheckboxColumn: false,
        columnSpacing: 20,
        horizontalMargin: 16,
        columns: [
          DataColumn(
            label: BoundedTableText(
              'receipt_number'.tr,
              width: 120,
              maxLines: 2,
            ),
          ),
          DataColumn(
            label: BoundedTableText(
              'customer_name'.tr,
              width: 165,
              maxLines: 2,
            ),
          ),
          DataColumn(
            label: BoundedTableText('receipt_date'.tr, width: 100, maxLines: 2),
          ),
          DataColumn(
            label: BoundedTableText(
              'receipt_amount'.tr,
              width: 125,
              maxLines: 2,
            ),
          ),
          DataColumn(
            label: BoundedTableText(
              'payment_method'.tr,
              width: 100,
              maxLines: 2,
            ),
          ),
          DataColumn(
            label: BoundedTableText(
              'receipts_allocations'.tr,
              width: 120,
              maxLines: 2,
            ),
          ),
          if (showRep)
            DataColumn(
              label: BoundedTableText('sales_rep'.tr, width: 130, maxLines: 2),
            ),
          DataColumn(label: Text('actions'.tr)),
        ],
        rows: [
          for (final receipt in controller.receipts)
            DataRow(
              key: ValueKey('receipt-row-${receipt.id}'),
              onSelectChanged: (_) => controller.openDetails(receipt),
              cells: [
                DataCell(
                  BoundedTableText(
                    receipt.receiptNumber,
                    width: 120,
                    forceLtr: true,
                  ),
                ),
                DataCell(
                  BoundedTableText(receipt.customerSnapshot.name, width: 165),
                ),
                DataCell(
                  BoundedTableText(
                    DateFormat.yMd().format(receipt.receiptDate),
                    width: 100,
                  ),
                ),
                DataCell(
                  BoundedTableText(money.format(receipt.amount), width: 125),
                ),
                DataCell(
                  BoundedTableWidget(
                    width: 100,
                    child: _PaymentMethodChip(method: receipt.paymentMethod),
                  ),
                ),
                DataCell(
                  BoundedTableText(
                    receiptAllocationRows(receipt).isEmpty
                        ? '-'
                        : '${receiptAllocationRows(receipt).length}',
                    width: 120,
                  ),
                ),
                if (showRep)
                  DataCell(BoundedTableText(receipt.salesRepName, width: 130)),
                DataCell(
                  IconButton.filledTonal(
                    tooltip: 'receipt_details'.tr,
                    onPressed: () => controller.openDetails(receipt),
                    icon: const Icon(Icons.visibility_outlined),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _PaymentMethodChip extends StatelessWidget {
  const _PaymentMethodChip({required this.method});
  final String method;

  @override
  Widget build(BuildContext context) => Container(
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

class _ReceiptMeta extends StatelessWidget {
  const _ReceiptMeta({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon, size: 15, color: AppColor.grey),
      const SizedBox(width: 5),
      Expanded(
        child: Text(
          text,
          softWrap: true,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ),
    ],
  );
}
