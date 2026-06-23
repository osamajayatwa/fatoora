import 'package:fatoora/core/constant/color.dart';
import 'package:fatoora/features/invoices/data/models/invoice_item_snapshot.dart';
import 'package:fatoora/features/invoices/view/widgets/invoice_item_row.dart';
import 'package:fatoora/modules/admin_dashboard/view/widgets/dashboard_card.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

class InvoiceItemsTable extends StatelessWidget {
  const InvoiceItemsTable({
    super.key,
    required this.items,
    required this.editable,
    required this.onUpdateItem,
    required this.onRemoveItem,
  });

  final List<InvoiceItemSnapshot> items;
  final bool editable;
  final void Function({
    required int index,
    double? quantity,
    double? unitPrice,
    double? discount,
    double? taxPercent,
  })
  onUpdateItem;
  final ValueChanged<int> onRemoveItem;

  @override
  Widget build(BuildContext context) {
    return DashboardCard(
      padding: EdgeInsets.zero,
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (items.isEmpty) {
            return Padding(
              padding: const EdgeInsets.all(20),
              child: Text(
                'items_required'.tr,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: AppColor.grey),
              ),
            );
          }
          if (constraints.maxWidth < 780) {
            return Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                children: [
                  for (var i = 0; i < items.length; i++) ...[
                    InvoiceItemRow(
                      item: items[i],
                      index: i,
                      editable: editable,
                      onUpdate: ({quantity, unitPrice, discount, taxPercent}) =>
                          onUpdateItem(
                            index: i,
                            quantity: quantity,
                            unitPrice: unitPrice,
                            discount: discount,
                            taxPercent: taxPercent,
                          ),
                      onRemove: () => onRemoveItem(i),
                    ),
                    if (i != items.length - 1) const SizedBox(height: 12),
                  ],
                ],
              ),
            );
          }

          final currency = NumberFormat.currency(
            symbol: 'JOD ',
            decimalDigits: 3,
          );
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              headingTextStyle: Theme.of(context).textTheme.labelMedium
                  ?.copyWith(
                    color: AppColor.secondaryColor,
                    fontWeight: FontWeight.w800,
                  ),
              columns: [
                DataColumn(label: Text('item_name'.tr)),
                DataColumn(label: Text('quantity'.tr)),
                DataColumn(label: Text('unit_price'.tr)),
                DataColumn(label: Text('discount'.tr)),
                DataColumn(label: Text('tax'.tr)),
                DataColumn(label: Text('line_total'.tr)),
                if (editable) DataColumn(label: Text('actions'.tr)),
              ],
              rows: [
                for (var i = 0; i < items.length; i++)
                  DataRow(
                    cells: [
                      DataCell(
                        SizedBox(
                          width: 220,
                          child: Text(
                            items[i].itemName,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                      DataCell(
                        editable
                            ? _InlineNumberField(
                                value: items[i].quantity,
                                onChanged: (value) =>
                                    onUpdateItem(index: i, quantity: value),
                              )
                            : Text(items[i].quantity.toString()),
                      ),
                      DataCell(
                        editable
                            ? _InlineNumberField(
                                value: items[i].unitPrice,
                                onChanged: (value) =>
                                    onUpdateItem(index: i, unitPrice: value),
                              )
                            : Text(currency.format(items[i].unitPrice)),
                      ),
                      DataCell(
                        editable
                            ? _InlineNumberField(
                                value: items[i].discount,
                                onChanged: (value) =>
                                    onUpdateItem(index: i, discount: value),
                              )
                            : Text(currency.format(items[i].discount)),
                      ),
                      DataCell(
                        editable
                            ? _InlineNumberField(
                                value: items[i].taxPercent,
                                onChanged: (value) =>
                                    onUpdateItem(index: i, taxPercent: value),
                              )
                            : Text('${items[i].taxPercent}%'),
                      ),
                      DataCell(Text(currency.format(items[i].total))),
                      if (editable)
                        DataCell(
                          IconButton(
                            onPressed: () => onRemoveItem(i),
                            icon: const Icon(Icons.delete_outline_rounded),
                            color: AppColor.error,
                            tooltip: 'remove_item'.tr,
                          ),
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

class _InlineNumberField extends StatelessWidget {
  const _InlineNumberField({required this.value, required this.onChanged});

  final double value;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 90,
      child: TextFormField(
        initialValue: value.toString(),
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: const InputDecoration(isDense: true),
        onChanged: (text) => onChanged(double.tryParse(text.trim()) ?? 0),
      ),
    );
  }
}
