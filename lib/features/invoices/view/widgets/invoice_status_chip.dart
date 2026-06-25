import 'package:fatoora/core/constants/color.dart';
import 'package:fatoora/features/invoices/data/models/invoice_enums.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class InvoiceStatusChip extends StatelessWidget {
  const InvoiceStatusChip({super.key, required this.status});

  final InvoiceStatus status;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      InvoiceStatus.draft => AppColor.grey,
      InvoiceStatus.confirmed => AppColor.primaryColor,
      InvoiceStatus.pendingSubmit => const Color(0xFFFF9F2E),
      InvoiceStatus.accepted => AppColor.success,
      InvoiceStatus.rejected => AppColor.error,
      InvoiceStatus.cancelled => AppColor.darkGrey,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        _labelKey(status).tr,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  String _labelKey(InvoiceStatus status) {
    return switch (status) {
      InvoiceStatus.draft => 'draft',
      InvoiceStatus.confirmed => 'confirmed',
      InvoiceStatus.pendingSubmit => 'pending_submit',
      InvoiceStatus.accepted => 'accepted',
      InvoiceStatus.rejected => 'rejected',
      InvoiceStatus.cancelled => 'cancelled',
    };
  }
}
