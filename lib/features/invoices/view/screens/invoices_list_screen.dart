import 'package:fatoora/core/class/statusrequest.dart';
import 'package:fatoora/core/constants/color.dart';
import 'package:fatoora/core/motion/fatoora_motion_widgets.dart';
import 'package:fatoora/core/widgets/responsive_data_table_card.dart';
import 'package:fatoora/features/invoices/controllers/invoices_list_controller.dart';
import 'package:fatoora/features/invoices/data/models/invoice_model.dart';
import 'package:fatoora/features/invoices/view/widgets/empty_invoices_widget.dart';
import 'package:fatoora/features/invoices/view/widgets/invoice_actions_menu.dart';
import 'package:fatoora/features/invoices/view/widgets/invoice_card.dart';
import 'package:fatoora/features/invoices/view/widgets/invoice_filter_bar.dart';
import 'package:fatoora/features/invoices/view/widgets/invoice_list_controls.dart';
import 'package:fatoora/features/invoices/view/widgets/invoice_search_bar.dart';
import 'package:fatoora/features/invoices/view/widgets/invoice_status_chip.dart';
import 'package:fatoora/features/invoices/view/widgets/invoice_type_chip.dart';
import 'package:fatoora/features/shared/business/business_page_widgets.dart';
import 'package:fatoora/features/shared/business/business_shell.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

class InvoicesListScreen extends StatelessWidget {
  const InvoicesListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return GetBuilder<InvoicesListController>(
      builder: (controller) => BusinessShell(
        title: 'invoices'.tr,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 900;
            final padding = constraints.maxWidth < 600 ? 14.0 : 24.0;
            return RefreshIndicator(
              onRefresh: controller.refreshInvoices,
              color: AppColor.primaryColor,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.fromLTRB(padding, padding, padding, 96),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1320),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _InvoicesHeader(
                          controller: controller,
                          showCreateAction: !compact,
                        ),
                        const SizedBox(height: 16),
                        InvoiceSearchBar(
                          controller: controller.searchController,
                          onChanged: controller.onSearchChanged,
                          onSubmitted: (_) => controller.submitSearch(),
                          onClear: controller.clearSearch,
                          showMinimumLengthHint: controller.searchIsTooShort,
                        ),
                        const SizedBox(height: 12),
                        if (compact)
                          _CompactInvoiceControls(controller: controller)
                        else
                          InvoiceFilterBar(
                            type: controller.typeFilter,
                            status: controller.statusFilter,
                            paymentStatus: controller.paymentStatusFilter,
                            returnStatus: controller.returnStatusFilter,
                            salesRep: controller.salesRepFilter,
                            customer: controller.customerFilter,
                            fromDate: controller.fromDate,
                            toDate: controller.toDate,
                            sortField: controller.sortField,
                            sortDirection: controller.sortDirection,
                            hasActiveFilters: controller.hasActiveFilters,
                            showSalesRepresentative:
                                controller.showSalesRepresentative,
                            loadSalesRepOptions:
                                controller.loadSalesRepFilterOptions,
                            loadCustomerOptions:
                                controller.loadCustomerFilterOptions,
                            onTypeChanged: controller.setTypeFilter,
                            onStatusChanged: controller.setStatusFilter,
                            onPaymentStatusChanged:
                                controller.setPaymentStatusFilter,
                            onReturnStatusChanged:
                                controller.setReturnStatusFilter,
                            onSalesRepChanged: controller.setSalesRepFilter,
                            onCustomerChanged: controller.setCustomerFilter,
                            onDateRangeChanged: controller.setDateRange,
                            onSortFieldChanged: controller.setSortField,
                            onSortDirectionChanged: controller.setSortDirection,
                            onClear: controller.clearFilters,
                          ),
                        const SizedBox(height: 14),
                        _InvoiceResults(
                          controller: controller,
                          compact: compact,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _InvoicesHeader extends StatelessWidget {
  const _InvoicesHeader({
    required this.controller,
    required this.showCreateAction,
  });

  final InvoicesListController controller;
  final bool showCreateAction;

  @override
  Widget build(BuildContext context) {
    return BusinessPageHeader(
      title: 'invoices'.tr,
      trailing: showCreateAction
          ? BusinessPrimaryActionButton(
              onPressed: controller.openCreateInvoice,
              icon: Icons.add_rounded,
              label: 'create_invoice'.tr,
            )
          : null,
    );
  }
}

class _CompactInvoiceControls extends StatelessWidget {
  const _CompactInvoiceControls({required this.controller});

  final InvoicesListController controller;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InvoiceCompactToolbar(
          activeFilterCount: controller.activeFilterCount,
          sortField: controller.sortField,
          sortDirection: controller.sortDirection,
          onFiltersPressed: () => _openFilters(context),
          onSortPressed: () => _openSort(context),
        ),
        if (controller.hasActiveFilters) ...[
          const SizedBox(height: 8),
          InvoiceActiveFilterChips(
            type: controller.typeFilter,
            status: controller.statusFilter,
            paymentStatus: controller.paymentStatusFilter,
            returnStatus: controller.returnStatusFilter,
            salesRep: controller.showSalesRepresentative
                ? controller.salesRepFilter
                : null,
            customer: controller.customerFilter,
            fromDate: controller.fromDate,
            toDate: controller.toDate,
            onTypeRemoved: () => controller.setTypeFilter(null),
            onStatusRemoved: () => controller.setStatusFilter(null),
            onPaymentStatusRemoved: () =>
                controller.setPaymentStatusFilter(null),
            onReturnStatusRemoved: () => controller.setReturnStatusFilter(null),
            onSalesRepRemoved: () => controller.setSalesRepFilter(null),
            onCustomerRemoved: () => controller.setCustomerFilter(null),
            onDateRangeRemoved: () => controller.setDateRange(null),
            onClearAll: controller.clearFilters,
          ),
        ],
      ],
    );
  }

  void _openFilters(BuildContext context) {
    final dateRange = controller.fromDate != null && controller.toDate != null
        ? DateTimeRange(start: controller.fromDate!, end: controller.toDate!)
        : null;
    showInvoiceFilterSheet(
      context: context,
      initial: InvoiceFilterSelection(
        type: controller.typeFilter,
        status: controller.statusFilter,
        paymentStatus: controller.paymentStatusFilter,
        returnStatus: controller.returnStatusFilter,
        salesRep: controller.salesRepFilter,
        customer: controller.customerFilter,
        dateRange: dateRange,
      ),
      showSalesRepresentative: controller.showSalesRepresentative,
      loadSalesRepOptions: controller.loadSalesRepFilterOptions,
      loadCustomerOptions: controller.loadCustomerFilterOptions,
      onApply: (selection) => controller.applyFilters(
        type: selection.type,
        status: selection.status,
        paymentStatus: selection.paymentStatus,
        returnStatus: selection.returnStatus,
        salesRep: selection.salesRep,
        customer: selection.customer,
        dateRange: selection.dateRange,
      ),
    );
  }

  void _openSort(BuildContext context) {
    showInvoiceSortSheet(
      context: context,
      initialField: controller.sortField,
      initialDirection: controller.sortDirection,
      forceInvoiceDate: controller.hasDateRange,
      onApply: (selection) =>
          controller.applySort(selection.field, selection.direction),
    );
  }
}

class _InvoiceResults extends StatelessWidget {
  const _InvoiceResults({required this.controller, required this.compact});

  final InvoicesListController controller;
  final bool compact;

  bool get _loading => controller.statusRequest == StatusRequest.loading;
  bool get _hasError =>
      controller.statusRequest != StatusRequest.none &&
      controller.statusRequest != StatusRequest.success &&
      controller.statusRequest != StatusRequest.loading;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const ValueKey('invoice-results-area'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_loading)
          const ClipRRect(
            borderRadius: BorderRadius.all(Radius.circular(999)),
            child: LinearProgressIndicator(
              key: ValueKey('invoice-results-loader'),
              minHeight: 3,
            ),
          ),
        if (_loading) const SizedBox(height: 10),
        if (_hasError && controller.invoices.isNotEmpty) ...[
          _InlineLoadError(controller: controller),
          const SizedBox(height: 10),
        ],
        if (_hasError && controller.invoices.isEmpty)
          BusinessEmptyState(
            icon: Icons.sync_problem_outlined,
            title: controller.loadErrorMessageKey.tr,
            action: FilledButton.icon(
              key: const ValueKey('invoice-retry-button'),
              onPressed: controller.loadInvoices,
              icon: const Icon(Icons.refresh_rounded),
              label: Text('items_retry'.tr),
            ),
          )
        else if (_loading && controller.invoices.isEmpty)
          const SizedBox(
            height: 210,
            child: Center(child: FatooraProgressIndicator(size: 34)),
          )
        else if (controller.invoices.isEmpty)
          EmptyInvoicesWidget(searching: controller.hasFilters)
        else if (compact)
          _InvoicesCards(controller: controller)
        else
          _InvoicesTable(controller: controller),
        if (controller.hasMore && !_hasError) ...[
          const SizedBox(height: 18),
          BusinessLoadMoreButton(
            loading: controller.isLoadingMore,
            onPressed: controller.loadMoreInvoices,
          ),
        ],
      ],
    );
  }
}

class _InlineLoadError extends StatelessWidget {
  const _InlineLoadError({required this.controller});

  final InvoicesListController controller;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.errorContainer,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(14, 8, 8, 8),
        child: Row(
          children: [
            Icon(
              Icons.sync_problem_outlined,
              color: Theme.of(context).colorScheme.onErrorContainer,
            ),
            const SizedBox(width: 10),
            Expanded(child: Text(controller.loadErrorMessageKey.tr)),
            TextButton(
              onPressed: controller.loadInvoices,
              child: Text('items_retry'.tr),
            ),
          ],
        ),
      ),
    );
  }
}

class _InvoicesCards extends StatelessWidget {
  const _InvoicesCards({required this.controller});

  final InvoicesListController controller;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final invoice in controller.invoices) ...[
          InvoiceCard(
            key: ValueKey('invoice-card-${invoice.id}'),
            invoice: invoice,
            showSalesRepresentative: controller.showSalesRepresentative,
            onView: () => controller.openDetails(invoice),
            onEdit: () => controller.editInvoice(invoice),
            onDelete: () => controller.deleteDraftInvoice(invoice),
            onPrint: () => controller.printInvoicePdf(invoice),
          ),
          const SizedBox(height: 10),
        ],
      ],
    );
  }
}

class _InvoicesTable extends StatelessWidget {
  const _InvoicesTable({required this.controller});

  final InvoicesListController controller;

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(symbol: 'JOD ', decimalDigits: 3);
    return LayoutBuilder(
      builder: (context, constraints) {
        final mode = _InvoiceTableMode.forWidth(
          constraints.maxWidth,
          showSalesRepresentative: controller.showSalesRepresentative,
        );
        return ResponsiveDataTableCard(
          minWidth: mode.minimumWidth,
          child: DataTable(
            columnSpacing: mode.columnSpacing,
            horizontalMargin: mode.horizontalMargin,
            showCheckboxColumn: false,
            headingTextStyle: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: AppColor.secondaryColor,
              fontWeight: FontWeight.w800,
            ),
            dataTextStyle: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: AppColor.secondaryColor),
            columns: _columns(mode),
            rows: controller.invoices
                .map(
                  (invoice) => DataRow(
                    onSelectChanged: (_) => controller.openDetails(invoice),
                    cells: _cells(
                      context: context,
                      mode: mode,
                      invoice: invoice,
                      currency: currency,
                    ),
                  ),
                )
                .toList(growable: false),
          ),
        );
      },
    );
  }

  List<DataColumn> _columns(_InvoiceTableMode mode) => [
    _column('invoice_number', width: 126),
    _column('invoice_date', width: 88),
    _column('customer_name', width: mode.customerWidth),
    if (mode.showType) _column('invoice_type', width: mode.typeWidth),
    _column('invoice_status', width: mode.statusWidth),
    _column('payment_status', width: mode.paymentStatusWidth),
    if (mode.showReturnStatus)
      _column('return_status', width: mode.returnStatusWidth),
    _column('grand_total', width: 112, numeric: true),
    if (mode.showCreatedBy) _column('sales_rep', width: mode.createdByWidth),
    _column('actions', width: 58),
  ];

  DataColumn _column(
    String labelKey, {
    required double width,
    bool numeric = false,
  }) => DataColumn(
    numeric: numeric,
    label: SizedBox(
      width: width,
      child: Text(labelKey.tr, maxLines: 2, overflow: TextOverflow.ellipsis),
    ),
  );

  List<DataCell> _cells({
    required BuildContext context,
    required _InvoiceTableMode mode,
    required InvoiceModel invoice,
    required NumberFormat currency,
  }) => [
    DataCell(
      BoundedTableText(invoice.invoiceNumber, width: 126, forceLtr: true),
    ),
    DataCell(
      BoundedTableText(
        DateFormat.yMd().format(invoice.invoiceDate),
        width: 88,
        forceLtr: true,
      ),
    ),
    DataCell(
      BoundedTableText(
        invoice.customerSnapshot?.name ?? '',
        width: mode.customerWidth,
      ),
    ),
    if (mode.showType)
      DataCell(
        BoundedTableWidget(
          width: mode.typeWidth,
          child: InvoiceTypeChip(type: invoice.invoiceType),
        ),
      ),
    DataCell(
      BoundedTableWidget(
        width: mode.statusWidth,
        child: InvoiceStatusChip(status: invoice.invoiceStatus),
      ),
    ),
    DataCell(
      BoundedTableWidget(
        width: mode.paymentStatusWidth,
        child: InvoicePaymentStatusChip(status: invoice.paymentStatus),
      ),
    ),
    if (mode.showReturnStatus)
      DataCell(
        BoundedTableWidget(
          width: mode.returnStatusWidth,
          child: InvoiceReturnStatusChip(status: invoice.returnStatus),
        ),
      ),
    DataCell(
      BoundedTableText(
        currency.format(invoice.grandTotal),
        width: 112,
        forceLtr: true,
        textAlign: TextAlign.end,
      ),
    ),
    if (mode.showCreatedBy)
      DataCell(
        BoundedTableText(invoice.salesRepName, width: mode.createdByWidth),
      ),
    DataCell(
      BoundedTableWidget(
        width: 58,
        child: InvoiceActionsMenu(
          showView: true,
          showDelete: true,
          canEdit: invoice.canEdit,
          canDelete: invoice.canDelete,
          onView: () => controller.openDetails(invoice),
          onEdit: () => controller.editInvoice(invoice),
          onDelete: () => controller.deleteDraftInvoice(invoice),
          onPrint: () => controller.printInvoicePdf(invoice),
        ),
      ),
    ),
  ];
}

class _InvoiceTableMode {
  const _InvoiceTableMode({
    required this.minimumWidth,
    required this.customerWidth,
    required this.typeWidth,
    required this.statusWidth,
    required this.paymentStatusWidth,
    required this.returnStatusWidth,
    required this.createdByWidth,
    required this.columnSpacing,
    required this.horizontalMargin,
    required this.showType,
    required this.showReturnStatus,
    required this.showCreatedBy,
  });

  final double minimumWidth;
  final double customerWidth;
  final double typeWidth;
  final double statusWidth;
  final double paymentStatusWidth;
  final double returnStatusWidth;
  final double createdByWidth;
  final double columnSpacing;
  final double horizontalMargin;
  final bool showType;
  final bool showReturnStatus;
  final bool showCreatedBy;

  static _InvoiceTableMode forWidth(
    double width, {
    required bool showSalesRepresentative,
  }) {
    if (width < 1120) {
      return const _InvoiceTableMode(
        minimumWidth: 860,
        customerWidth: 180,
        typeWidth: 88,
        statusWidth: 100,
        paymentStatusWidth: 106,
        returnStatusWidth: 96,
        createdByWidth: 112,
        columnSpacing: 14,
        horizontalMargin: 14,
        showType: false,
        showReturnStatus: false,
        showCreatedBy: false,
      );
    }
    if (width < 1320) {
      return const _InvoiceTableMode(
        minimumWidth: 1040,
        customerWidth: 220,
        typeWidth: 90,
        statusWidth: 100,
        paymentStatusWidth: 108,
        returnStatusWidth: 96,
        createdByWidth: 112,
        columnSpacing: 16,
        horizontalMargin: 16,
        showType: true,
        showReturnStatus: false,
        showCreatedBy: false,
      );
    }
    return _InvoiceTableMode(
      minimumWidth: showSalesRepresentative ? 1230 : 1090,
      customerWidth: 200,
      typeWidth: 86,
      statusWidth: 94,
      paymentStatusWidth: 104,
      returnStatusWidth: 94,
      createdByWidth: 110,
      columnSpacing: 12,
      horizontalMargin: 12,
      showType: true,
      showReturnStatus: true,
      showCreatedBy: showSalesRepresentative,
    );
  }
}
