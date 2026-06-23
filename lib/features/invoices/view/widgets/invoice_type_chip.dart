import 'package:fatoora/core/constant/color.dart';
import 'package:fatoora/features/invoices/data/models/invoice_enums.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class InvoiceTypeChip extends StatelessWidget {
  const InvoiceTypeChip({super.key, required this.type});

  final InvoiceType type;

  @override
  Widget build(BuildContext context) {
    final electronic = type == InvoiceType.electronic;
    final color = electronic ? AppColor.tertiaryColor : AppColor.primaryColor;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            electronic ? Icons.verified_outlined : Icons.receipt_long_outlined,
            size: 14,
            color: color,
          ),
          const SizedBox(width: 6),
          Text(
            (electronic ? 'electronic_invoice' : 'regular_invoice').tr,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
