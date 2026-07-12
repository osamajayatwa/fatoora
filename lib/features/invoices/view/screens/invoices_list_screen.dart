import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:fatoora/core/class/handilingdataview.dart';
import 'package:fatoora/core/constants/color.dart';
import 'package:fatoora/features/invoices/controllers/invoices_list_controller.dart';
import 'package:fatoora/features/invoices/data/models/invoice_model.dart';
import 'package:fatoora/features/invoices/view/widgets/empty_invoices_widget.dart';
import 'package:fatoora/features/invoices/view/widgets/invoice_card.dart';
import 'package:fatoora/features/invoices/view/widgets/invoice_filter_bar.dart';
import 'package:fatoora/features/invoices/view/widgets/invoice_search_bar.dart';
import 'package:fatoora/features/invoices/view/widgets/invoice_status_chip.dart';
import 'package:fatoora/features/invoices/view/widgets/invoice_type_chip.dart';
import 'package:fatoora/features/shared/business/business_shell.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

class InvoicesListScreen extends StatelessWidget {
  const InvoicesListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return GetBuilder<InvoicesListController>(
      builder: (controller) {
        return BusinessShell(
          title: 'invoices'.tr,
          child: HandilingDataView(
            statusrequest: controller.statusRequest,
            errorMessage: controller.loadErrorMessageKey.tr,
            retryLabel: 'items_retry'.tr,
            onRetry: controller.loadInvoices,
            widget: RefreshIndicator(
              onRefresh: controller.refreshInvoices,
              color: AppColor.primaryColor,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final compact = constraints.maxWidth < 900;
                  final padding = constraints.maxWidth < 600 ? 14.0 : 24.0;
                  return SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: EdgeInsets.fromLTRB(padding, padding, padding, 96),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1320),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _InvoicesHeader(controller: controller),
                            const SizedBox(height: 18),
                            InvoiceSearchBar(
                              controller: controller.searchController,
                              onChanged: controller.onSearchChanged,
                            ),
                            const SizedBox(height: 14),
                            InvoiceFilterBar(
                              type: controller.typeFilter,
                              status: controller.statusFilter,
                              paymentStatus: controller.paymentStatusFilter,
                              returnStatus: controller.returnStatusFilter,
                              fromDate: controller.fromDate,
                              toDate: controller.toDate,
                              hasFilters: controller.hasFilters,
                              onTypeChanged: controller.setTypeFilter,
                              onStatusChanged: controller.setStatusFilter,
                              onPaymentStatusChanged:
                                  controller.setPaymentStatusFilter,
                              onReturnStatusChanged:
                                  controller.setReturnStatusFilter,
                              onDateRangeChanged: controller.setDateRange,
                              onClear: controller.clearFilters,
                            ),
                            const SizedBox(height: 18),
                            if (controller.invoices.isEmpty)
                              EmptyInvoicesWidget(
                                searching: controller.hasFilters,
                              )
                            else if (compact)
                              _InvoicesCards(controller: controller)
                            else
                              _InvoicesTable(controller: controller),
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

class _InvoicesHeader extends StatelessWidget {
  const _InvoicesHeader({required this.controller});

  final InvoicesListController controller;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 620;
    final title = Text(
      'invoices'.tr,
      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
        color: AppColor.secondaryColor,
        fontWeight: FontWeight.w900,
      ),
    );
    final action = FilledButton.icon(
      onPressed: controller.openInvoiceTypePicker,
      style: FilledButton.styleFrom(
        backgroundColor: AppColor.primaryColor,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      icon: const Icon(Icons.add_rounded),
      label: Text('create_invoice'.tr),
    );

    if (compact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [title, const SizedBox(height: 12), action],
      );
    }
    return Row(
      children: [
        Expanded(child: title),
        const SizedBox(width: 16),
        action,
      ],
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
            invoice: invoice,
            onView: () => controller.openDetails(invoice),
            onEdit: () => controller.editInvoice(invoice),
            onDelete: () => controller.deleteDraftInvoice(invoice),
            onPrint: () => controller.printInvoicePdf(invoice),
          ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}

class _InvoicesTable extends StatefulWidget {
  const _InvoicesTable({required this.controller});

  final InvoicesListController controller;

  @override
  State<_InvoicesTable> createState() => _InvoicesTableState();
}

class _InvoicesTableState extends State<_InvoicesTable> {
  final ScrollController _horizontalController = ScrollController();

  @override
  void dispose() {
    _horizontalController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(symbol: 'JOD ', decimalDigits: 3);
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final tableMode = _InvoiceTableMode.forWidth(width);
        final tableWidth = math.max(width, tableMode.minimumWidth);
        return Card(
          margin: EdgeInsets.zero,
          elevation: 0,
          color: AppColor.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: const BorderSide(color: Color(0xFFE4E8EF)),
          ),
          clipBehavior: Clip.antiAlias,
          child: Scrollbar(
            controller: _horizontalController,
            thumbVisibility: true,
            trackVisibility: true,
            interactive: true,
            notificationPredicate: (notification) =>
                notification.metrics.axis == Axis.horizontal,
            child: SingleChildScrollView(
              controller: _horizontalController,
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: tableWidth,
                child: DataTable(
                  columnSpacing: tableMode.columnSpacing,
                  horizontalMargin: tableMode.horizontalMargin,
                  headingTextStyle: Theme.of(context).textTheme.labelMedium
                      ?.copyWith(
                        color: AppColor.secondaryColor,
                        fontWeight: FontWeight.w800,
                      ),
                  dataTextStyle: Theme.of(context).textTheme.bodyMedium
                      ?.copyWith(color: AppColor.secondaryColor),
                  columns: _columns(tableMode),
                  rows: widget.controller.invoices
                      .map(
                        (invoice) => DataRow(
                          cells: _cells(
                            context: context,
                            mode: tableMode,
                            invoice: invoice,
                            currency: currency,
                          ),
                        ),
                      )
                      .toList(),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  List<DataColumn> _columns(_InvoiceTableMode mode) {
    return [
      _column('invoice_number', width: 126),
      _column('invoice_date', width: 88),
      _column('customer_name', width: mode.customerWidth),
      if (mode.showType) _column('invoice_type', width: mode.typeWidth),
      _column('invoice_status', width: mode.statusWidth),
      _column('payment_status', width: mode.paymentStatusWidth),
      if (mode.showReturnStatus)
        _column('return_status', width: mode.returnStatusWidth),
      _column('grand_total', width: 112, numeric: true),
      if (mode.showCreatedBy) _column('created_by', width: mode.createdByWidth),
      _column('actions', width: 144),
    ];
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

  List<DataCell> _cells({
    required BuildContext context,
    required _InvoiceTableMode mode,
    required InvoiceModel invoice,
    required NumberFormat currency,
  }) {
    final customerName = invoice.customerSnapshot?.name ?? '';
    return [
      DataCell(_BoundedCell(invoice.invoiceNumber, width: 126, forceLtr: true)),
      DataCell(
        _BoundedCell(
          DateFormat.yMd().format(invoice.invoiceDate),
          width: 88,
          forceLtr: true,
        ),
      ),
      DataCell(_BoundedCell(customerName, width: mode.customerWidth)),
      if (mode.showType)
        DataCell(
          _BoundedChipCell(
            width: mode.typeWidth,
            child: InvoiceTypeChip(type: invoice.invoiceType),
          ),
        ),
      DataCell(
        _BoundedChipCell(
          width: mode.statusWidth,
          child: InvoiceStatusChip(status: invoice.invoiceStatus),
        ),
      ),
      DataCell(
        _BoundedChipCell(
          width: mode.paymentStatusWidth,
          child: InvoicePaymentStatusChip(status: invoice.paymentStatus),
        ),
      ),
      if (mode.showReturnStatus)
        DataCell(
          _BoundedChipCell(
            width: mode.returnStatusWidth,
            child: InvoiceReturnStatusChip(status: invoice.returnStatus),
          ),
        ),
      DataCell(
        _BoundedCell(
          currency.format(invoice.grandTotal),
          width: 112,
          forceLtr: true,
          textAlign: TextAlign.end,
        ),
      ),
      if (mode.showCreatedBy)
        DataCell(
          _BoundedCell(invoice.createdByName, width: mode.createdByWidth),
        ),
      DataCell(_TableActions(controller: widget.controller, invoice: invoice)),
    ];
  }
}

class _BoundedChipCell extends StatelessWidget {
  const _BoundedChipCell({required this.width, required this.child});

  final double width;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: FittedBox(fit: BoxFit.scaleDown, child: child),
      ),
    );
  }
}

class _BoundedCell extends StatelessWidget {
  const _BoundedCell(
    this.value, {
    required this.width,
    this.forceLtr = false,
    this.textAlign,
  });

  final String value;
  final double width;
  final bool forceLtr;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) {
    final text = value.trim();
    final child = SizedBox(
      width: width,
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: textAlign,
        textDirection: forceLtr ? ui.TextDirection.ltr : null,
      ),
    );
    if (text.isEmpty) return child;
    return Tooltip(message: text, child: child);
  }
}

enum _InvoiceRowAction { edit, delete }

class _TableActions extends StatelessWidget {
  const _TableActions({required this.controller, required this.invoice});

  final InvoicesListController controller;
  final InvoiceModel invoice;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 144,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'invoice_details'.tr,
            onPressed: () => controller.openDetails(invoice),
            icon: const Icon(Icons.visibility_outlined),
            color: AppColor.secondaryColor,
          ),
          IconButton(
            tooltip: 'print_export'.tr,
            onPressed: () => controller.printInvoicePdf(invoice),
            icon: const Icon(Icons.picture_as_pdf_outlined),
            color: AppColor.primaryColor,
          ),
          PopupMenuButton<_InvoiceRowAction>(
            tooltip: 'actions'.tr,
            onSelected: (action) {
              switch (action) {
                case _InvoiceRowAction.edit:
                  controller.editInvoice(invoice);
                case _InvoiceRowAction.delete:
                  controller.deleteDraftInvoice(invoice);
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: _InvoiceRowAction.edit,
                enabled: invoice.canEdit,
                child: ListTile(
                  dense: true,
                  leading: const Icon(Icons.edit_outlined),
                  title: Text('edit_invoice'.tr),
                ),
              ),
              PopupMenuItem(
                value: _InvoiceRowAction.delete,
                enabled: invoice.canDelete,
                child: ListTile(
                  dense: true,
                  leading: const Icon(Icons.delete_outline_rounded),
                  title: Text('delete_invoice'.tr),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _InvoiceTableMode {
  const _InvoiceTableMode._({
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

  static _InvoiceTableMode forWidth(double width) {
    if (width < 1120) {
      return const _InvoiceTableMode._(
        minimumWidth: 900,
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
      return const _InvoiceTableMode._(
        minimumWidth: 1080,
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
    return const _InvoiceTableMode._(
      minimumWidth: 1290,
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
      showCreatedBy: true,
    );
  }
}
