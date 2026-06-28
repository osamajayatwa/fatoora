import 'package:fatoora/core/constants/color.dart';
import 'package:fatoora/features/invoices/data/models/invoice_item_snapshot.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

class InvoiceItemRow extends StatelessWidget {
  const InvoiceItemRow({
    super.key,
    required this.item,
    required this.index,
    required this.editable,
    required this.canEditUnitPrice,
    required this.canEditDiscount,
    required this.onUpdate,
    required this.onRemove,
  });

  final InvoiceItemSnapshot item;
  final int index;
  final bool editable;
  final bool canEditUnitPrice;
  final bool canEditDiscount;
  final void Function({
    double? quantity,
    double? unitPrice,
    double? discount,
    double? taxPercent,
  })
  onUpdate;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(symbol: 'JOD ', decimalDigits: 3);
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: AppColor.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: Color(0xFFE4E8EF)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    item.itemName,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: AppColor.secondaryColor,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                if (editable)
                  IconButton(
                    onPressed: onRemove,
                    icon: const Icon(Icons.close_rounded),
                    color: AppColor.error,
                    tooltip: 'remove_item'.tr,
                  ),
              ],
            ),
            const SizedBox(height: 10),
            if (editable)
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _NumberField(
                    width: 130,
                    label: 'quantity'.tr,
                    value: item.quantity,
                    onChanged: (value) => onUpdate(quantity: value),
                  ),
                  if (canEditUnitPrice)
                    _NumberField(
                      width: 150,
                      label: 'unit_price'.tr,
                      value: item.unitPrice,
                      onChanged: (value) => onUpdate(unitPrice: value),
                    )
                  else
                    _Pill(
                      label: 'unit_price'.tr,
                      value: currency.format(item.unitPrice),
                    ),
                  if (canEditDiscount)
                    _NumberField(
                      width: 140,
                      label: 'discount'.tr,
                      value: item.discount,
                      onChanged: (value) => onUpdate(discount: value),
                    )
                  else
                    _Pill(
                      label: 'discount'.tr,
                      value: currency.format(item.discount),
                    ),
                  _NumberField(
                    width: 130,
                    label: 'tax'.tr,
                    value: item.taxPercent,
                    onChanged: (value) => onUpdate(taxPercent: value),
                  ),
                ],
              )
            else
              Wrap(
                spacing: 10,
                runSpacing: 8,
                children: [
                  _Pill(label: 'quantity'.tr, value: item.quantity.toString()),
                  _Pill(
                    label: 'unit_price'.tr,
                    value: currency.format(item.unitPrice),
                  ),
                  _Pill(
                    label: 'discount'.tr,
                    value: currency.format(item.discount),
                  ),
                  _Pill(label: 'tax'.tr, value: '${item.taxPercent}%'),
                ],
              ),
            const SizedBox(height: 12),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: Text(
                '${'line_total'.tr}: ${currency.format(item.total)}',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: AppColor.primaryColor,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NumberField extends StatelessWidget {
  const _NumberField({
    required this.width,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final double width;
  final String label;
  final double value;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: TextFormField(
        initialValue: value.toString(),
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(
          labelText: label,
          isDense: true,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        ),
        onChanged: (text) => onChanged(double.tryParse(text.trim()) ?? 0),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFFF4F6FA),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        '$label: $value',
        style: Theme.of(context).textTheme.labelMedium,
      ),
    );
  }
}
