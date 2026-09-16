import 'package:fatoora/core/class/handilingdataview.dart';
import 'package:fatoora/core/constants/color.dart';
import 'package:fatoora/features/admin_dashboard/view/widgets/dashboard_card.dart';
import 'package:fatoora/features/sales_returns/controllers/sales_return_form_controller.dart';
import 'package:fatoora/features/sales_returns/data/models/sales_return_enums.dart';
import 'package:fatoora/features/sales_returns/data/models/sales_return_item_model.dart';
import 'package:fatoora/features/shared/business/business_shell.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

class SalesReturnFormScreen extends StatelessWidget {
  const SalesReturnFormScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return GetBuilder<SalesReturnFormController>(
      builder: (controller) => BusinessShell(
        title: 'create_sales_return'.tr,
        showBackButton: true,
        child: HandilingDataView(
          statusrequest: controller.statusRequest,
          errorMessage: controller.loadErrorMessageKey.tr,
          retryLabel: 'items_retry'.tr,
          onRetry: controller.initialize,
          widget: LayoutBuilder(
            builder: (context, constraints) {
              final padding = constraints.maxWidth < 600 ? 14.0 : 24.0;
              return SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(padding, padding, padding, 96),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1200),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _Header(controller: controller),
                        const SizedBox(height: 18),
                        _InvoiceInfo(controller: controller),
                        const SizedBox(height: 18),
                        _ReturnMeta(controller: controller),
                        const SizedBox(height: 18),
                        DashboardCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                'return_items'.tr,
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(
                                      color: AppColor.secondaryColor,
                                      fontWeight: FontWeight.w800,
                                    ),
                              ),
                              const SizedBox(height: 12),
                              _ItemsEditor(controller: controller),
                            ],
                          ),
                        ),
                        const SizedBox(height: 18),
                        _Totals(controller: controller),
                        const SizedBox(height: 18),
                        _Actions(controller: controller),
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

class _Header extends StatelessWidget {
  const _Header({required this.controller});

  final SalesReturnFormController controller;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'create_sales_return'.tr,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            color: AppColor.secondaryColor,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          'sales_return_form_subtitle'.tr,
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: AppColor.grey),
        ),
      ],
    );
  }
}

class _InvoiceInfo extends StatelessWidget {
  const _InvoiceInfo({required this.controller});

  final SalesReturnFormController controller;

  @override
  Widget build(BuildContext context) {
    final invoice = controller.originalInvoice;
    if (invoice == null) return const SizedBox.shrink();
    return DashboardCard(
      child: Wrap(
        spacing: 28,
        runSpacing: 12,
        children: [
          _LabelValue(
            label: 'original_invoice_number'.tr,
            value: invoice.invoiceNumber,
          ),
          _LabelValue(
            label: 'customer_name'.tr,
            value: invoice.customerSnapshot?.name ?? '-',
          ),
          _LabelValue(
            label: 'invoice_date'.tr,
            value: DateFormat.yMd().format(invoice.invoiceDate),
          ),
        ],
      ),
    );
  }
}

class _ReturnMeta extends StatelessWidget {
  const _ReturnMeta({required this.controller});

  final SalesReturnFormController controller;

  @override
  Widget build(BuildContext context) {
    return DashboardCard(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final reason = TextField(
            controller: controller.reasonController,
            maxLines: 3,
            onChanged: (_) => controller.update(),
            decoration: InputDecoration(
              labelText: 'return_reason'.tr,
              alignLabelWithHint: true,
              border: const OutlineInputBorder(),
            ),
          );
          final controls = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _DateField(controller: controller),
              const SizedBox(height: 16),
              Text(
                'refund_type'.tr,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: AppColor.secondaryColor,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final type in RefundType.values)
                    ChoiceChip(
                      selected: controller.refundType == type,
                      onSelected: (_) => controller.setRefundType(type),
                      label: Text('refund_type_${type.value}'.tr),
                    ),
                ],
              ),
            ],
          );
          if (constraints.maxWidth < 760) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [controls, const SizedBox(height: 16), reason],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: controls),
              const SizedBox(width: 18),
              Expanded(child: reason),
            ],
          );
        },
      ),
    );
  }
}

class _DateField extends StatelessWidget {
  const _DateField({required this.controller});

  final SalesReturnFormController controller;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () async {
        final selected = await showDatePicker(
          context: context,
          initialDate: controller.returnDate,
          firstDate: DateTime(2020),
          lastDate: DateTime.now().add(const Duration(days: 365)),
        );
        if (selected != null) controller.setReturnDate(selected);
      },
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: 'return_date'.tr,
          prefixIcon: const Icon(Icons.calendar_today_outlined),
          border: const OutlineInputBorder(),
        ),
        child: Text(DateFormat.yMd().format(controller.returnDate)),
      ),
    );
  }
}

class _ItemsEditor extends StatelessWidget {
  const _ItemsEditor({required this.controller});

  final SalesReturnFormController controller;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => constraints.maxWidth < 720
          ? _ItemCards(controller: controller)
          : _ItemTable(controller: controller),
    );
  }
}

class _ItemCards extends StatelessWidget {
  const _ItemCards({required this.controller});

  final SalesReturnFormController controller;

  @override
  Widget build(BuildContext context) {
    final money = NumberFormat.currency(symbol: 'JOD ', decimalDigits: 3);
    return Column(
      children: [
        for (final item in controller.items) ...[
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFF9FAFC),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFE4E8EF)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  item.itemName,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: AppColor.secondaryColor,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (item.itemCode.isNotEmpty) Text(item.itemCode),
                const SizedBox(height: 10),
                Text(
                  '${'available_to_return'.tr}: ${_quantity(controller.availableFor(item))} ${item.unit}',
                ),
                const SizedBox(height: 10),
                _QuantityField(controller: controller, item: item),
                const SizedBox(height: 8),
                Text('${'grand_total'.tr}: ${money.format(item.total)}'),
              ],
            ),
          ),
          const SizedBox(height: 10),
        ],
      ],
    );
  }
}

class _ItemTable extends StatelessWidget {
  const _ItemTable({required this.controller});

  final SalesReturnFormController controller;

  @override
  Widget build(BuildContext context) {
    final money = NumberFormat.currency(symbol: 'JOD ', decimalDigits: 3);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columns: [
          DataColumn(label: Text('item_name'.tr)),
          DataColumn(label: Text('unit'.tr)),
          DataColumn(label: Text('available_to_return'.tr)),
          DataColumn(label: Text('returned_quantity'.tr)),
          DataColumn(label: Text('unit_price'.tr)),
          DataColumn(label: Text('tax'.tr)),
          DataColumn(label: Text('grand_total'.tr)),
        ],
        rows: controller.items
            .map(
              (item) => DataRow(
                cells: [
                  DataCell(
                    SizedBox(
                      width: 180,
                      child: Text(
                        item.itemName,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  DataCell(Text(item.unit)),
                  DataCell(Text(_quantity(controller.availableFor(item)))),
                  DataCell(
                    SizedBox(
                      width: 142,
                      child: _QuantityField(controller: controller, item: item),
                    ),
                  ),
                  DataCell(Text(money.format(item.unitPrice))),
                  DataCell(Text('${item.taxPercent.toStringAsFixed(2)}%')),
                  DataCell(Text(money.format(item.total))),
                ],
              ),
            )
            .toList(growable: false),
      ),
    );
  }
}

class _QuantityField extends StatelessWidget {
  const _QuantityField({required this.controller, required this.item});

  final SalesReturnFormController controller;
  final SalesReturnItemModel item;

  @override
  Widget build(BuildContext context) {
    final lineId = item.originalInvoiceItemId;
    return TextField(
      controller: controller.quantityControllers[lineId],
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      onChanged: (value) => controller.updateReturnedQuantity(lineId, value),
      decoration: InputDecoration(
        isDense: true,
        border: const OutlineInputBorder(),
        errorText: controller.quantityErrors[lineId]?.tr,
      ),
    );
  }
}

class _Totals extends StatelessWidget {
  const _Totals({required this.controller});

  final SalesReturnFormController controller;

  @override
  Widget build(BuildContext context) {
    final money = NumberFormat.currency(symbol: 'JOD ', decimalDigits: 3);
    return DashboardCard(
      child: LayoutBuilder(
        builder: (context, constraints) => Align(
          alignment: AlignmentDirectional.centerEnd,
          child: SizedBox(
            width:
                constraints.maxWidth < 560 ||
                    MediaQuery.textScalerOf(context).scale(1) > 1.3
                ? constraints.maxWidth
                : 290,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _TotalRow(
                  label: 'subtotal'.tr,
                  value: money.format(controller.subtotal),
                ),
                _TotalRow(
                  label: 'tax'.tr,
                  value: money.format(controller.totalTax),
                ),
                const Divider(height: 22),
                _TotalRow(
                  label: 'grand_total'.tr,
                  value: money.format(controller.grandTotal),
                  bold: true,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Actions extends StatelessWidget {
  const _Actions({required this.controller});

  final SalesReturnFormController controller;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final draft = OutlinedButton.icon(
          onPressed: controller.isSaving ? null : controller.saveDraft,
          icon: controller.isSaving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.save_outlined),
          label: Text('save_return_draft'.tr),
        );
        final confirm = FilledButton.icon(
          onPressed: controller.isSaving ? null : controller.confirmReturn,
          style: FilledButton.styleFrom(
            backgroundColor: AppColor.primaryColor,
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
          icon: const Icon(Icons.assignment_turned_in_outlined),
          label: Text('confirm_return'.tr),
        );
        if (constraints.maxWidth < 560) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [draft, const SizedBox(height: 10), confirm],
          );
        }
        return Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [draft, const SizedBox(width: 12), confirm],
        );
      },
    );
  }
}

class _LabelValue extends StatelessWidget {
  const _LabelValue({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelMedium),
        const SizedBox(height: 3),
        Text(
          value,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: AppColor.secondaryColor,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

class _TotalRow extends StatelessWidget {
  const _TotalRow({
    required this.label,
    required this.value,
    this.bold = false,
  });

  final String label;
  final String value;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    final valueText = Text(
      value,
      style: TextStyle(
        color: AppColor.secondaryColor,
        fontWeight: bold ? FontWeight.w900 : FontWeight.w700,
      ),
    );
    if (MediaQuery.textScalerOf(context).scale(1) > 1.3) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(label),
          const SizedBox(height: 3),
          Align(alignment: AlignmentDirectional.centerEnd, child: valueText),
        ],
      );
    }
    return Row(
      children: [
        Expanded(child: Text(label)),
        valueText,
      ],
    );
  }
}

String _quantity(double value) => value == value.roundToDouble()
    ? value.toStringAsFixed(0)
    : value.toStringAsFixed(3);
