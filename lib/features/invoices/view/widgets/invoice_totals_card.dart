import 'package:fatoora/core/constant/color.dart';
import 'package:fatoora/modules/admin_dashboard/view/widgets/dashboard_card.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

class InvoiceTotalsCard extends StatelessWidget {
  const InvoiceTotalsCard({
    super.key,
    required this.subtotal,
    required this.totalDiscount,
    required this.totalTax,
    required this.grandTotal,
  });

  final double subtotal;
  final double totalDiscount;
  final double totalTax;
  final double grandTotal;

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(symbol: 'JOD ', decimalDigits: 3);
    return DashboardCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'invoice_totals'.tr,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: AppColor.secondaryColor,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 16),
          _TotalLine(label: 'subtotal'.tr, value: currency.format(subtotal)),
          _TotalLine(
            label: 'discount'.tr,
            value: currency.format(totalDiscount),
          ),
          _TotalLine(label: 'tax'.tr, value: currency.format(totalTax)),
          const Divider(height: 26),
          _TotalLine(
            label: 'grand_total'.tr,
            value: currency.format(grandTotal),
            emphasized: true,
          ),
        ],
      ),
    );
  }
}

class _TotalLine extends StatelessWidget {
  const _TotalLine({
    required this.label,
    required this.value,
    this.emphasized = false,
  });

  final String label;
  final String value;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final style = emphasized
        ? Theme.of(context).textTheme.titleMedium?.copyWith(
            color: AppColor.primaryColor,
            fontWeight: FontWeight.w900,
          )
        : Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: AppColor.secondaryColor,
            fontWeight: FontWeight.w600,
          );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(child: Text(label, style: style)),
          Text(value, style: style),
        ],
      ),
    );
  }
}
