import 'dart:ui' as ui;

import 'package:fatoora/core/class/handilingdataview.dart';
import 'package:fatoora/core/constants/color.dart';
import 'package:fatoora/core/motion/fatoora_motion_widgets.dart';
import 'package:fatoora/core/widgets/responsive_data_table_card.dart';
import 'package:fatoora/features/admin_dashboard/view/widgets/dashboard_card.dart';
import 'package:fatoora/features/invoices/data/models/invoice_item_snapshot.dart';
import 'package:fatoora/features/quotations/controllers/quotation_details_controller.dart';
import 'package:fatoora/features/quotations/data/models/quotation_item_model.dart';
import 'package:fatoora/features/quotations/data/models/quotation_model.dart';
import 'package:fatoora/features/quotations/data/models/quotation_status.dart';
import 'package:fatoora/features/quotations/view/widgets/quotation_status_chip.dart';
import 'package:fatoora/features/shared/business/business_shell.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

class QuotationDetailsScreen extends StatelessWidget {
  const QuotationDetailsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return GetBuilder<QuotationDetailsController>(
      builder: (controller) => BusinessShell(
        title: 'quotation_details'.tr,
        showBackButton: true,
        onBack: controller.requestBack,
        child: HandilingDataView(
          statusrequest: controller.statusRequest,
          errorMessage: controller.loadErrorMessageKey.tr,
          retryLabel: 'items_retry'.tr,
          onRetry: controller.loadQuotation,
          widget: controller.quotation == null
              ? const SizedBox.shrink()
              : _Details(
                  controller: controller,
                  quotation: controller.quotation!,
                ),
        ),
      ),
    );
  }
}

class _Details extends StatelessWidget {
  const _Details({required this.controller, required this.quotation});

  final QuotationDetailsController controller;
  final QuotationModel quotation;

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
              Wrap(
                spacing: 10,
                runSpacing: 10,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  IconButton.filledTonal(
                    tooltip: MaterialLocalizations.of(
                      context,
                    ).backButtonTooltip,
                    onPressed: controller.requestBack,
                    icon: Icon(
                      Directionality.of(context) == ui.TextDirection.rtl
                          ? Icons.arrow_forward_rounded
                          : Icons.arrow_back_rounded,
                    ),
                  ),
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: MediaQuery.sizeOf(context).width < 520
                          ? MediaQuery.sizeOf(context).width - 78
                          : 330,
                    ),
                    child: SizedBox(
                      width: double.infinity,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            quotation.quotationNumber,
                            softWrap: true,
                            style: Theme.of(context).textTheme.headlineSmall
                                ?.copyWith(
                                  color: AppColor.secondaryColor,
                                  fontWeight: FontWeight.w900,
                                ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            DateFormat.yMMMd().format(quotation.quotationDate),
                          ),
                        ],
                      ),
                    ),
                  ),
                  QuotationStatusChip(status: quotation.status),
                  OutlinedButton.icon(
                    onPressed: controller.isPrinting
                        ? null
                        : controller.printQuotation,
                    icon: controller.isPrinting
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: FatooraProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.picture_as_pdf_outlined),
                    label: Text('export_pdf'.tr),
                  ),
                  if (controller.canEdit)
                    OutlinedButton.icon(
                      onPressed: controller.editQuotation,
                      icon: const Icon(Icons.edit_outlined),
                      label: Text('edit_quotation'.tr),
                    ),
                  if (controller.canConvert)
                    FilledButton.icon(
                      onPressed: controller.isConverting
                          ? null
                          : controller.convertToInvoice,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColor.primaryColor,
                      ),
                      icon: controller.isConverting
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: FatooraProgressIndicator(
                                strokeWidth: 2,
                                color: AppColor.surface,
                              ),
                            )
                          : const Icon(Icons.receipt_long_outlined),
                      label: Text('convert_to_invoice'.tr),
                    ),
                ],
              ),
              const SizedBox(height: 18),
              _InfoCard(
                quotation: quotation,
                showSalesRepresentative: controller.showSalesRepresentative,
              ),
              const SizedBox(height: 18),
              _StatusActions(controller: controller, quotation: quotation),
              const SizedBox(height: 18),
              _ItemsCard(quotation: quotation, money: money),
              const SizedBox(height: 18),
              _TotalsCard(quotation: quotation, money: money),
              if (quotation.terms.isNotEmpty || quotation.notes.isNotEmpty) ...[
                const SizedBox(height: 18),
                _TextSection(quotation: quotation),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({
    required this.quotation,
    required this.showSalesRepresentative,
  });

  final QuotationModel quotation;
  final bool showSalesRepresentative;

  @override
  Widget build(BuildContext context) {
    return DashboardCard(
      child: Wrap(
        spacing: 30,
        runSpacing: 14,
        children: [
          _Field(
            label: 'customer_name'.tr,
            value: quotation.customerSnapshot?.name ?? '-',
          ),
          if (showSalesRepresentative)
            _Field(label: 'sales_rep'.tr, value: quotation.salesRepName),
          _Field(
            label: 'quotation_date'.tr,
            value: DateFormat.yMd().format(quotation.quotationDate),
          ),
          _Field(
            label: 'valid_until'.tr,
            value: DateFormat.yMd().format(quotation.validUntil),
          ),
          if (quotation.convertedInvoiceNumber.isNotEmpty)
            _Field(
              label: 'converted_invoice'.tr,
              value: quotation.convertedInvoiceNumber,
            ),
        ],
      ),
    );
  }
}

class _StatusActions extends StatelessWidget {
  const _StatusActions({required this.controller, required this.quotation});

  final QuotationDetailsController controller;
  final QuotationModel quotation;

  @override
  Widget build(BuildContext context) {
    if (quotation.status == QuotationStatus.converted) {
      return const SizedBox.shrink();
    }
    final actions = <Widget>[];
    if (quotation.status == QuotationStatus.draft) {
      actions.add(
        OutlinedButton.icon(
          onPressed: controller.isSavingStatus
              ? null
              : () => controller.updateStatus(QuotationStatus.sent),
          icon: const Icon(Icons.send_outlined),
          label: Text('sent'.tr),
        ),
      );
    }
    if (quotation.status == QuotationStatus.draft ||
        quotation.status == QuotationStatus.sent) {
      actions.addAll([
        OutlinedButton.icon(
          onPressed: controller.isSavingStatus
              ? null
              : () => controller.updateStatus(QuotationStatus.accepted),
          icon: const Icon(Icons.check_circle_outline),
          label: Text('accepted'.tr),
        ),
        OutlinedButton.icon(
          onPressed: controller.isSavingStatus
              ? null
              : () => controller.updateStatus(QuotationStatus.rejected),
          icon: const Icon(Icons.cancel_outlined),
          label: Text('rejected'.tr),
        ),
        OutlinedButton.icon(
          onPressed: controller.isSavingStatus
              ? null
              : () => controller.updateStatus(QuotationStatus.expired),
          icon: const Icon(Icons.event_busy_outlined),
          label: Text('expired'.tr),
        ),
      ]);
    }
    if (actions.isEmpty) return const SizedBox.shrink();
    return DashboardCard(
      child: Wrap(spacing: 10, runSpacing: 10, children: actions),
    );
  }
}

class _ItemsCard extends StatelessWidget {
  const _ItemsCard({required this.quotation, required this.money});

  final QuotationModel quotation;
  final NumberFormat money;

  @override
  Widget build(BuildContext context) {
    return DashboardCard(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact =
              constraints.maxWidth < 760 ||
              MediaQuery.textScalerOf(context).scale(1) > 1.3;
          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'item_name'.tr,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: AppColor.secondaryColor,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 10),
                for (
                  var index = 0;
                  index < quotation.items.length;
                  index++
                ) ...[
                  if (index > 0) const Divider(height: 22),
                  _LineCard(item: quotation.items[index], money: money),
                ],
              ],
            );
          }
          return ResponsiveDataTableCard(
            minWidth: 1120,
            child: DataTable(
              dataRowMinHeight: 60,
              dataRowMaxHeight: 110,
              columnSpacing: 18,
              horizontalMargin: 16,
              columns: [
                DataColumn(label: BoundedTableText('item_name'.tr, width: 220)),
                DataColumn(label: BoundedTableText('quantity'.tr, width: 65)),
                DataColumn(label: BoundedTableText('unit'.tr, width: 70)),
                DataColumn(
                  label: BoundedTableText('unit_price'.tr, width: 120),
                ),
                DataColumn(label: BoundedTableText('discount'.tr, width: 115)),
                DataColumn(label: BoundedTableText('tax'.tr, width: 110)),
                DataColumn(
                  label: BoundedTableText('grand_total'.tr, width: 120),
                ),
              ],
              rows: [
                for (final item in quotation.items)
                  DataRow(
                    cells: [
                      DataCell(
                        SizedBox(
                          width: 220,
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.itemName,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              if (item.description.trim().isNotEmpty)
                                Text(
                                  item.description,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                            ],
                          ),
                        ),
                      ),
                      DataCell(
                        BoundedTableText(_quantity(item.quantity), width: 65),
                      ),
                      DataCell(BoundedTableText(item.unit, width: 70)),
                      DataCell(
                        BoundedTableText(
                          money.format(item.unitPrice),
                          width: 120,
                        ),
                      ),
                      DataCell(
                        BoundedTableText(
                          money.format(item.discount),
                          width: 115,
                        ),
                      ),
                      DataCell(
                        BoundedTableText(
                          money.format(item.taxAmount),
                          width: 110,
                        ),
                      ),
                      DataCell(
                        BoundedTableText(money.format(item.total), width: 120),
                      ),
                    ],
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _LineCard extends StatelessWidget {
  const _LineCard({required this.item, required this.money});

  final QuotationItemModel item;
  final NumberFormat money;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Wrap(
        spacing: 8,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            item.itemName,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: AppColor.secondaryColor,
              fontWeight: FontWeight.w800,
            ),
          ),
          if (item.lineType == InvoiceLineType.custom)
            Chip(
              label: Text('custom_line'.tr),
              visualDensity: VisualDensity.compact,
            ),
        ],
      ),
      if (item.description.trim().isNotEmpty) ...[
        const SizedBox(height: 4),
        Text(item.description, softWrap: true),
      ],
      const SizedBox(height: 8),
      Wrap(
        spacing: 14,
        runSpacing: 4,
        children: [
          Text('${'quantity'.tr}: ${_quantity(item.quantity)} ${item.unit}'),
          Text('${'unit_price'.tr}: ${money.format(item.unitPrice)}'),
          Text('${'discount'.tr}: ${money.format(item.discount)}'),
          Text('${'tax'.tr}: ${money.format(item.taxAmount)}'),
        ],
      ),
      const SizedBox(height: 6),
      Text(
        '${'grand_total'.tr}: ${money.format(item.total)}',
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
          color: AppColor.primaryColor,
          fontWeight: FontWeight.w900,
        ),
      ),
    ],
  );
}

class _TotalsCard extends StatelessWidget {
  const _TotalsCard({required this.quotation, required this.money});

  final QuotationModel quotation;
  final NumberFormat money;

  @override
  Widget build(BuildContext context) {
    return DashboardCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Field(label: 'subtotal'.tr, value: money.format(quotation.subtotal)),
          _Field(
            label: 'discount'.tr,
            value: money.format(quotation.totalDiscount),
          ),
          _Field(label: 'tax'.tr, value: money.format(quotation.totalTax)),
          const Divider(height: 22),
          _Field(
            label: 'grand_total'.tr,
            value: money.format(quotation.grandTotal),
            bold: true,
          ),
        ],
      ),
    );
  }
}

class _TextSection extends StatelessWidget {
  const _TextSection({required this.quotation});

  final QuotationModel quotation;

  @override
  Widget build(BuildContext context) {
    return DashboardCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (quotation.terms.isNotEmpty) ...[
            Text(
              'terms'.tr,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: AppColor.secondaryColor,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(quotation.terms),
          ],
          if (quotation.notes.isNotEmpty) ...[
            if (quotation.terms.isNotEmpty) const SizedBox(height: 16),
            Text(
              'notes'.tr,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: AppColor.secondaryColor,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(quotation.notes),
          ],
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
      child: LayoutBuilder(
        builder: (context, constraints) {
          final labelWidget = Text(
            label,
            style: Theme.of(context).textTheme.labelMedium,
          );
          final valueWidget = Text(
            value.isEmpty ? '-' : value,
            softWrap: true,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: AppColor.secondaryColor,
              fontWeight: bold ? FontWeight.w900 : FontWeight.w700,
            ),
          );
          if (constraints.maxWidth < 420) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [labelWidget, const SizedBox(height: 4), valueWidget],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: 160, child: labelWidget),
              Expanded(child: valueWidget),
            ],
          );
        },
      ),
    );
  }
}

String _quantity(double value) => value == value.roundToDouble()
    ? value.toStringAsFixed(0)
    : value.toStringAsFixed(3);
