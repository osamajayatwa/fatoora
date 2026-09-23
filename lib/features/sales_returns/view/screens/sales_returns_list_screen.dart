import 'package:fatoora/core/class/statusrequest.dart';
import 'package:fatoora/core/constants/color.dart';
import 'package:fatoora/core/motion/fatoora_overlays.dart';
import 'package:fatoora/core/widgets/responsive_data_table_card.dart';
import 'package:fatoora/features/sales_returns/controllers/sales_returns_list_controller.dart';
import 'package:fatoora/features/sales_returns/data/models/sales_return_enums.dart';
import 'package:fatoora/features/sales_returns/data/models/sales_return_model.dart';
import 'package:fatoora/features/sales_returns/view/widgets/sales_return_status_chip.dart';
import 'package:fatoora/features/shared/business/business_page_widgets.dart';
import 'package:fatoora/features/shared/business/business_shell.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

class SalesReturnsListScreen extends StatelessWidget {
  const SalesReturnsListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return GetBuilder<SalesReturnsListController>(
      builder: (controller) => BusinessShell(
        title: 'sales_returns'.tr,
        child: RefreshIndicator(
          color: AppColor.primaryColor,
          onRefresh: controller.refreshSalesReturns,
          child: LayoutBuilder(
            builder: (context, constraints) {
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
                        BusinessPageHeader(
                          title: 'sales_returns'.tr,
                          subtitle: 'sales_returns_subtitle'.tr,
                        ),
                        const SizedBox(height: 14),
                        _Filters(controller: controller),
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
}

class _Filters extends StatelessWidget {
  const _Filters({required this.controller});

  final SalesReturnsListController controller;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          key: const ValueKey('return-search'),
          controller: controller.searchController,
          onChanged: controller.onSearchChanged,
          onSubmitted: (_) => controller.submitSearch(),
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: 'sales_returns_search_hint'.tr,
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
            'sales_returns_search_minimum'.tr,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
        const SizedBox(height: 10),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: OutlinedButton.icon(
            key: const ValueKey('return-filter-button'),
            onPressed: () => _showStatusFilter(context),
            icon: const Icon(Icons.tune_rounded),
            label: Text('sales_returns_filter'.tr),
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
                  key: const ValueKey('return-status-chip'),
                  label: Text(
                    'sales_return_status_${controller.statusFilter!.value}'.tr,
                  ),
                  onDeleted: () => controller.setStatusFilter(null),
                ),
              TextButton.icon(
                onPressed: controller.clearFilters,
                icon: const Icon(Icons.close_rounded),
                label: Text('clear_filters'.tr),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Future<void> _showStatusFilter(BuildContext context) async {
    final selected = await showFatooraModalBottomSheet<Object>(
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
                'status'.tr,
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            ListTile(
              title: Text('all'.tr),
              onTap: () => Navigator.of(sheetContext).pop('all'),
            ),
            for (final status in SalesReturnStatus.values)
              ListTile(
                title: Text('sales_return_status_${status.value}'.tr),
                onTap: () => Navigator.of(sheetContext).pop(status),
              ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
    if (selected == 'all') controller.setStatusFilter(null);
    if (selected is SalesReturnStatus) controller.setStatusFilter(selected);
  }
}

class _Results extends StatelessWidget {
  const _Results({required this.controller});
  final SalesReturnsListController controller;

  @override
  Widget build(BuildContext context) {
    if (controller.statusRequest == StatusRequest.loading) {
      return const Center(
        key: ValueKey('return-results-loading'),
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 48),
          child: CircularProgressIndicator(),
        ),
      );
    }
    if (controller.statusRequest != StatusRequest.success) {
      return BusinessEmptyState(
        key: const ValueKey('return-results-error'),
        icon: Icons.error_outline_rounded,
        title: controller.loadErrorMessageKey.tr,
        action: OutlinedButton.icon(
          onPressed: controller.loadSalesReturns,
          icon: const Icon(Icons.refresh_rounded),
          label: Text('items_retry'.tr),
        ),
      );
    }
    if (controller.salesReturns.isEmpty) {
      return _EmptyReturns(hasFilters: controller.hasAppliedFilters);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final largeText = MediaQuery.textScalerOf(context).scale(1) > 1.3;
            if (constraints.maxWidth >= 900 && !largeText) {
              return _ReturnTable(controller: controller);
            }
            return _ReturnCards(controller: controller);
          },
        ),
        if (controller.loadMoreErrorMessageKey != null) ...[
          const SizedBox(height: 12),
          BusinessEmptyState(
            key: const ValueKey('return-load-more-error'),
            icon: Icons.error_outline_rounded,
            title: controller.loadMoreErrorMessageKey!.tr,
            action: OutlinedButton.icon(
              onPressed: controller.loadMoreSalesReturns,
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
            onPressed: controller.loadMoreSalesReturns,
          ),
        ],
      ],
    );
  }
}

class _ReturnCards extends StatelessWidget {
  const _ReturnCards({required this.controller});

  final SalesReturnsListController controller;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final twoColumns =
            constraints.maxWidth >= 650 &&
            MediaQuery.textScalerOf(context).scale(1) <= 1.3;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final salesReturn in controller.salesReturns)
              SizedBox(
                width: twoColumns
                    ? (constraints.maxWidth - 12) / 2
                    : constraints.maxWidth,
                child: SalesReturnListCard(
                  salesReturn: salesReturn,
                  showSalesRepresentative: controller.showSalesRepresentative,
                  onTap: () => controller.openDetails(salesReturn),
                ),
              ),
          ],
        );
      },
    );
  }
}

class SalesReturnListCard extends StatelessWidget {
  const SalesReturnListCard({
    super.key,
    required this.salesReturn,
    required this.showSalesRepresentative,
    required this.onTap,
  });

  final SalesReturnModel salesReturn;
  final bool showSalesRepresentative;
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
        key: ValueKey('return-card-${salesReturn.id}'),
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
              const SizedBox(height: 6),
              Text(salesReturn.customerSnapshot?.name ?? '-'),
              const SizedBox(height: 8),
              Text(
                money.format(salesReturn.grandTotal),
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: AppColor.primaryColor,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
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
                  if (showSalesRepresentative &&
                      salesReturn.salesRepName.isNotEmpty)
                    _Info(
                      icon: Icons.person_outline_rounded,
                      text: salesReturn.salesRepName,
                    ),
                ],
              ),
              const SizedBox(height: 5),
              Text(
                '${'original_invoice'.tr}: ${salesReturn.originalInvoiceNumber}',
                style: Theme.of(context).textTheme.bodySmall,
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
    return LayoutBuilder(
      builder: (context, constraints) {
        final full = constraints.maxWidth >= 1120;
        return ResponsiveDataTableCard(
          minWidth: full ? 1070 : 860,
          child: DataTable(
            columnSpacing: 14,
            horizontalMargin: 14,
            columns: [
              _column('return_number', width: 120),
              _column('original_invoice_number', width: 132),
              _column('customer_name', width: full ? 190 : 220),
              _column('return_date', width: 92),
              _column('status', width: 92),
              if (full) _column('refund_type', width: 132),
              _column('grand_total', width: 116, numeric: true),
              if (full && controller.showSalesRepresentative)
                _column('sales_rep', width: 130),
              _column('actions', width: 68),
            ],
            rows: controller.salesReturns
                .map(
                  (salesReturn) => DataRow(
                    onSelectChanged: (_) => controller.openDetails(salesReturn),
                    cells: [
                      DataCell(
                        BoundedTableText(
                          salesReturn.returnNumber,
                          width: 120,
                          forceLtr: true,
                        ),
                      ),
                      DataCell(
                        BoundedTableText(
                          salesReturn.originalInvoiceNumber,
                          width: 132,
                          forceLtr: true,
                        ),
                      ),
                      DataCell(
                        BoundedTableText(
                          salesReturn.customerSnapshot?.name ?? '-',
                          width: full ? 190 : 220,
                        ),
                      ),
                      DataCell(
                        BoundedTableText(
                          DateFormat.yMd().format(salesReturn.returnDate),
                          width: 92,
                          forceLtr: true,
                        ),
                      ),
                      DataCell(
                        BoundedTableWidget(
                          width: 92,
                          child: SalesReturnStatusChip(
                            status: salesReturn.status,
                          ),
                        ),
                      ),
                      if (full && controller.showSalesRepresentative)
                        DataCell(
                          BoundedTableText(
                            'refund_type_${salesReturn.refundType.value}'.tr,
                            width: 132,
                          ),
                        ),
                      DataCell(
                        BoundedTableText(
                          money.format(salesReturn.grandTotal),
                          width: 116,
                          textAlign: TextAlign.end,
                          forceLtr: true,
                        ),
                      ),
                      if (full)
                        DataCell(
                          BoundedTableText(
                            salesReturn.salesRepName,
                            width: 130,
                          ),
                        ),
                      DataCell(
                        SizedBox(
                          width: 68,
                          child: IconButton.filledTonal(
                            tooltip: 'sales_return_details'.tr,
                            onPressed: () =>
                                controller.openDetails(salesReturn),
                            icon: const Icon(Icons.visibility_outlined),
                          ),
                        ),
                      ),
                    ],
                  ),
                )
                .toList(growable: false),
          ),
        );
      },
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
        Flexible(child: Text(text, softWrap: true)),
      ],
    );
  }
}

class _EmptyReturns extends StatelessWidget {
  const _EmptyReturns({required this.hasFilters});

  final bool hasFilters;

  @override
  Widget build(BuildContext context) {
    return BusinessEmptyState(
      icon: Icons.assignment_return_outlined,
      title: hasFilters
          ? 'sales_returns_no_search_results'.tr
          : 'no_returns_found'.tr,
    );
  }
}
