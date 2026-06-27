import 'package:fatoora/core/class/handilingdataview.dart';
import 'package:fatoora/core/constants/color.dart';
import 'package:fatoora/features/invoices/controllers/invoices_list_controller.dart';
import 'package:fatoora/features/invoices/data/models/invoice_model.dart';
import 'package:fatoora/features/invoices/view/widgets/empty_invoices_widget.dart';
import 'package:fatoora/features/invoices/view/widgets/invoice_action_buttons.dart';
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
                  final compact = constraints.maxWidth < 760;
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
                              fromDate: controller.fromDate,
                              toDate: controller.toDate,
                              hasFilters: controller.hasFilters,
                              onTypeChanged: controller.setTypeFilter,
                              onStatusChanged: controller.setStatusFilter,
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

class _InvoicesTable extends StatelessWidget {
  const _InvoicesTable({required this.controller});

  final InvoicesListController controller;

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
          dataTextStyle: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: AppColor.secondaryColor),
          columns: [
            DataColumn(label: Text('invoice_number'.tr)),
            DataColumn(label: Text('invoice_date'.tr)),
            DataColumn(label: Text('customer_name'.tr)),
            DataColumn(label: Text('invoice_type'.tr)),
            DataColumn(label: Text('invoice_status'.tr)),
            DataColumn(label: Text('grand_total'.tr)),
            DataColumn(label: Text('created_by'.tr)),
            DataColumn(label: Text('actions'.tr)),
          ],
          rows: controller.invoices
              .map(
                (invoice) => DataRow(
                  cells: [
                    DataCell(Text(invoice.invoiceNumber)),
                    DataCell(
                      Text(DateFormat.yMd().format(invoice.invoiceDate)),
                    ),
                    DataCell(
                      SizedBox(
                        width: 180,
                        child: Text(
                          invoice.customerSnapshot?.name ?? '',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    DataCell(InvoiceTypeChip(type: invoice.invoiceType)),
                    DataCell(InvoiceStatusChip(status: invoice.invoiceStatus)),
                    DataCell(Text(currency.format(invoice.grandTotal))),
                    DataCell(
                      SizedBox(
                        width: 140,
                        child: Text(
                          invoice.createdByName,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    DataCell(
                      _TableActions(controller: controller, invoice: invoice),
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

class _TableActions extends StatelessWidget {
  const _TableActions({required this.controller, required this.invoice});

  final InvoicesListController controller;
  final InvoiceModel invoice;

  @override
  Widget build(BuildContext context) {
    return InvoiceActionButtons(
      canEdit: invoice.canEdit,
      canDelete: invoice.canDelete,
      onView: () => controller.openDetails(invoice),
      onEdit: () => controller.editInvoice(invoice),
      onDelete: () => controller.deleteDraftInvoice(invoice),
      onPrint: () => controller.printInvoicePdf(invoice),
    );
  }
}
