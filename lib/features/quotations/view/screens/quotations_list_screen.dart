import 'package:fatoora/core/class/handilingdataview.dart';
import 'package:fatoora/core/constants/color.dart';
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
  Widget build(BuildContext context) {
    return GetBuilder<QuotationsListController>(
      builder: (controller) => BusinessShell(
        title: 'quotations'.tr,
        child: HandilingDataView(
          statusrequest: controller.statusRequest,
          errorMessage: controller.loadErrorMessageKey.tr,
          retryLabel: 'items_retry'.tr,
          onRetry: controller.loadQuotations,
          widget: RefreshIndicator(
            color: AppColor.primaryColor,
            onRefresh: controller.refreshQuotations,
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
                          _Header(controller: controller),
                          const SizedBox(height: 18),
                          _Filters(controller: controller),
                          const SizedBox(height: 18),
                          if (controller.quotations.isEmpty)
                            _EmptyQuotations(hasFilters: controller.hasFilters)
                          else if (compact)
                            _Cards(controller: controller)
                          else
                            _Table(controller: controller),
                          if (controller.quotations.isNotEmpty &&
                              controller.hasMore) ...[
                            const SizedBox(height: 18),
                            BusinessLoadMoreButton(
                              loading: controller.isLoadingMore,
                              onPressed: controller.loadMoreQuotations,
                            ),
                          ],
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

class _Header extends StatelessWidget {
  const _Header({required this.controller});

  final QuotationsListController controller;

  @override
  Widget build(BuildContext context) {
    return BusinessPageHeader(
      title: 'quotations'.tr,
      trailing: controller.canCreateQuotation
          ? BusinessPrimaryActionButton(
              onPressed: controller.openCreateQuotation,
              icon: Icons.add_rounded,
              label: 'create_quotation'.tr,
            )
          : null,
    );
  }
}

class _Filters extends StatelessWidget {
  const _Filters({required this.controller});

  final QuotationsListController controller;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final searchWidth = constraints.maxWidth < 360
            ? constraints.maxWidth
            : 330.0;
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
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ),
            DropdownButton<QuotationStatus?>(
              value: controller.statusFilter,
              hint: Text('quotation_status'.tr),
              items: [
                DropdownMenuItem<QuotationStatus?>(
                  value: null,
                  child: Text('all_quotation_statuses'.tr),
                ),
                for (final status in QuotationStatus.values)
                  DropdownMenuItem<QuotationStatus?>(
                    value: status,
                    child: Text(status.value.tr),
                  ),
              ],
              onChanged: controller.setStatusFilter,
            ),
            if (controller.hasFilters)
              TextButton.icon(
                onPressed: controller.clearFilters,
                icon: const Icon(Icons.close_rounded),
                label: Text('clear_filters'.tr),
              ),
          ],
        );
      },
    );
  }
}

class _Cards extends StatelessWidget {
  const _Cards({required this.controller});

  final QuotationsListController controller;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final quotation in controller.quotations) ...[
          _Card(
            quotation: quotation,
            onTap: () => controller.openDetails(quotation),
          ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.quotation, required this.onTap});

  final QuotationModel quotation;
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
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      quotation.quotationNumber,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: AppColor.secondaryColor,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  QuotationStatusChip(status: quotation.status),
                ],
              ),
              const SizedBox(height: 10),
              Text(quotation.customerSnapshot?.name ?? '-'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 14,
                runSpacing: 8,
                children: [
                  _MiniInfo(
                    icon: Icons.calendar_today_outlined,
                    text: DateFormat.yMd().format(quotation.quotationDate),
                  ),
                  _MiniInfo(
                    icon: Icons.person_outline,
                    text: quotation.salesRepName,
                  ),
                  _MiniInfo(
                    icon: Icons.payments_outlined,
                    text: currency.format(quotation.grandTotal),
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
            DataColumn(label: Text('quotation_number'.tr)),
            DataColumn(label: Text('quotation_date'.tr)),
            DataColumn(label: Text('customer_name'.tr)),
            DataColumn(label: Text('sales_rep'.tr)),
            DataColumn(label: Text('grand_total'.tr)),
            DataColumn(label: Text('quotation_status'.tr)),
            DataColumn(label: Text('actions'.tr)),
          ],
          rows: controller.quotations
              .map(
                (quotation) => DataRow(
                  cells: [
                    DataCell(Text(quotation.quotationNumber)),
                    DataCell(
                      Text(DateFormat.yMd().format(quotation.quotationDate)),
                    ),
                    DataCell(Text(quotation.customerSnapshot?.name ?? '-')),
                    DataCell(Text(quotation.salesRepName)),
                    DataCell(Text(currency.format(quotation.grandTotal))),
                    DataCell(QuotationStatusChip(status: quotation.status)),
                    DataCell(
                      IconButton.filledTonal(
                        tooltip: 'quotation_details'.tr,
                        onPressed: () => controller.openDetails(quotation),
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

class _EmptyQuotations extends StatelessWidget {
  const _EmptyQuotations({required this.hasFilters});

  final bool hasFilters;

  @override
  Widget build(BuildContext context) {
    return BusinessEmptyState(
      icon: Icons.request_quote_outlined,
      title: hasFilters ? 'no_search_results'.tr : 'no_quotations_found'.tr,
    );
  }
}
