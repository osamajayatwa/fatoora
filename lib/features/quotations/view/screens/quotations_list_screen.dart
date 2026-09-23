import 'package:fatoora/core/class/statusrequest.dart';
import 'package:fatoora/core/constants/color.dart';
import 'package:fatoora/core/motion/fatoora_overlays.dart';
import 'package:fatoora/core/widgets/responsive_data_table_card.dart';
import 'package:fatoora/features/quotations/controllers/quotations_list_controller.dart';
import 'package:fatoora/features/quotations/data/models/quotation_model.dart';
import 'package:fatoora/features/quotations/data/models/quotation_status.dart';
import 'package:fatoora/features/quotations/view/widgets/quotation_status_chip.dart';
import 'package:fatoora/features/shared/business/business_page_widgets.dart';
import 'package:fatoora/features/shared/business/business_shell.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

class QuotationsListScreen extends StatelessWidget {
  const QuotationsListScreen({super.key});

  @override
  Widget build(BuildContext context) => GetBuilder<QuotationsListController>(
    builder: (controller) => BusinessShell(
      title: 'quotations'.tr,
      child: RefreshIndicator(
        color: AppColor.primaryColor,
        onRefresh: controller.refreshQuotations,
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
                        title: 'quotations'.tr,
                        trailing: controller.canCreateQuotation
                            ? BusinessPrimaryActionButton(
                                onPressed: controller.openCreateQuotation,
                                icon: Icons.add_rounded,
                                label: 'create_quotation'.tr,
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
  final QuotationsListController controller;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      TextField(
        key: const ValueKey('quotation-search'),
        controller: controller.searchController,
        onChanged: controller.onSearchChanged,
        onSubmitted: (_) => controller.submitSearch(),
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: 'search_quotations'.tr,
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
          'quotations_search_minimum'.tr,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
      const SizedBox(height: 10),
      Align(
        alignment: AlignmentDirectional.centerStart,
        child: OutlinedButton.icon(
          key: const ValueKey('quotation-filter-button'),
          onPressed: () => _showStatusFilter(context),
          icon: const Icon(Icons.tune_rounded),
          label: Text('quotations_filter'.tr),
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
                key: const ValueKey('quotation-search-chip'),
                label: Text(controller.searchText.trim()),
                onDeleted: controller.clearSearch,
              ),
            if (controller.statusFilter != null)
              InputChip(
                key: const ValueKey('quotation-status-chip'),
                label: Text(controller.statusFilter!.value.tr),
                onDeleted: () => controller.setStatusFilter(null),
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

  Future<void> _showStatusFilter(BuildContext context) async {
    // A sentinel distinguishes "All" from a dismissed sheet.
    final selected = await showFatooraModalBottomSheet<Object>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.only(bottom: 12),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Text(
                'quotation_status'.tr,
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            ListTile(
              title: Text('all_quotation_statuses'.tr),
              trailing: controller.statusFilter == null
                  ? const Icon(
                      Icons.check_rounded,
                      color: AppColor.primaryColor,
                    )
                  : null,
              onTap: () => Navigator.of(sheetContext).pop('all'),
            ),
            for (final status in QuotationStatus.values)
              ListTile(
                key: ValueKey('quotation-filter-${status.value}'),
                title: Text(status.value.tr),
                trailing: controller.statusFilter == status
                    ? const Icon(
                        Icons.check_rounded,
                        color: AppColor.primaryColor,
                      )
                    : null,
                onTap: () => Navigator.of(sheetContext).pop(status),
              ),
          ],
        ),
      ),
    );
    if (selected == 'all') controller.setStatusFilter(null);
    if (selected is QuotationStatus) controller.setStatusFilter(selected);
  }
}

class _Results extends StatelessWidget {
  const _Results({required this.controller});
  final QuotationsListController controller;

  @override
  Widget build(BuildContext context) {
    if (controller.statusRequest == StatusRequest.loading) {
      return const Center(
        key: ValueKey('quotation-results-loading'),
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 48),
          child: CircularProgressIndicator(),
        ),
      );
    }
    if (controller.statusRequest != StatusRequest.success) {
      return BusinessEmptyState(
        key: const ValueKey('quotation-results-error'),
        icon: Icons.error_outline_rounded,
        title: controller.loadErrorMessageKey.tr,
        action: OutlinedButton.icon(
          onPressed: controller.loadQuotations,
          icon: const Icon(Icons.refresh_rounded),
          label: Text('items_retry'.tr),
        ),
      );
    }
    if (controller.quotations.isEmpty) {
      return BusinessEmptyState(
        key: const ValueKey('quotation-results-empty'),
        icon: Icons.request_quote_outlined,
        title: controller.hasAppliedFilters
            ? 'no_search_results'.tr
            : 'no_quotations_found'.tr,
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
              return _Table(controller: controller);
            }
            final columns = width >= 650 && !largeText ? 2 : 1;
            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final quotation in controller.quotations)
                  SizedBox(
                    width: columns == 1 ? width : (width - 12) / 2,
                    child: QuotationListCard(
                      quotation: quotation,
                      showSalesRepresentative:
                          controller.showSalesRepresentative,
                      onTap: () => controller.openDetails(quotation),
                    ),
                  ),
              ],
            );
          },
        ),
        if (controller.loadMoreErrorMessageKey != null) ...[
          const SizedBox(height: 12),
          BusinessEmptyState(
            key: const ValueKey('quotation-load-more-error'),
            icon: Icons.error_outline_rounded,
            title: controller.loadMoreErrorMessageKey!.tr,
            action: OutlinedButton.icon(
              onPressed: controller.loadMoreQuotations,
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
            onPressed: controller.loadMoreQuotations,
          ),
        ],
      ],
    );
  }
}

class QuotationListCard extends StatelessWidget {
  const QuotationListCard({
    super.key,
    required this.quotation,
    required this.showSalesRepresentative,
    required this.onTap,
  });
  final QuotationModel quotation;
  final bool showSalesRepresentative;
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
        key: ValueKey('quotation-card-${quotation.id}'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
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
                    quotation.quotationNumber,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: AppColor.secondaryColor,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  QuotationStatusChip(status: quotation.status),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                quotation.customerSnapshot?.name ?? '-',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 8),
              Text(
                currency.format(quotation.grandTotal),
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: AppColor.primaryColor,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 14,
                runSpacing: 5,
                children: [
                  _Meta(
                    icon: Icons.calendar_today_outlined,
                    text: DateFormat.yMd().format(quotation.quotationDate),
                  ),
                  _Meta(
                    icon: Icons.event_available_outlined,
                    text:
                        '${'valid_until'.tr}: ${DateFormat.yMd().format(quotation.validUntil)}',
                  ),
                  if (showSalesRepresentative &&
                      quotation.salesRepName.trim().isNotEmpty)
                    _Meta(
                      icon: Icons.person_outline,
                      text: quotation.salesRepName,
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

class _Table extends StatelessWidget {
  const _Table({required this.controller});
  final QuotationsListController controller;

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(symbol: 'JOD ', decimalDigits: 3);
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
              'quotation_number'.tr,
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
            label: BoundedTableText(
              'quotation_date'.tr,
              width: 100,
              maxLines: 2,
            ),
          ),
          DataColumn(
            label: BoundedTableText('valid_until'.tr, width: 100, maxLines: 2),
          ),
          if (showRep) DataColumn(label: Text('sales_rep'.tr)),
          DataColumn(
            label: BoundedTableText('grand_total'.tr, width: 125, maxLines: 2),
          ),
          DataColumn(
            label: BoundedTableText(
              'quotation_status'.tr,
              width: 110,
              maxLines: 2,
            ),
          ),
          DataColumn(label: Text('actions'.tr)),
        ],
        rows: [
          for (final quotation in controller.quotations)
            DataRow(
              key: ValueKey('quotation-row-${quotation.id}'),
              onSelectChanged: (_) => controller.openDetails(quotation),
              cells: [
                DataCell(
                  BoundedTableText(
                    quotation.quotationNumber,
                    width: 120,
                    forceLtr: true,
                  ),
                ),
                DataCell(
                  BoundedTableText(
                    quotation.customerSnapshot?.name ?? '-',
                    width: 165,
                  ),
                ),
                DataCell(
                  BoundedTableText(
                    DateFormat.yMd().format(quotation.quotationDate),
                    width: 100,
                  ),
                ),
                DataCell(
                  BoundedTableText(
                    DateFormat.yMd().format(quotation.validUntil),
                    width: 100,
                  ),
                ),
                if (showRep)
                  DataCell(
                    BoundedTableText(quotation.salesRepName, width: 130),
                  ),
                DataCell(
                  BoundedTableText(
                    currency.format(quotation.grandTotal),
                    width: 125,
                  ),
                ),
                DataCell(
                  BoundedTableWidget(
                    width: 110,
                    child: QuotationStatusChip(status: quotation.status),
                  ),
                ),
                DataCell(
                  IconButton.filledTonal(
                    tooltip: 'quotation_details'.tr,
                    onPressed: () => controller.openDetails(quotation),
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

class _Meta extends StatelessWidget {
  const _Meta({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => SizedBox(
      width: constraints.maxWidth,
      child: Row(
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
      ),
    ),
  );
}
