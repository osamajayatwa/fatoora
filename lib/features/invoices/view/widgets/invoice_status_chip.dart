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

class InvoicePaymentStatusChip extends StatelessWidget {
  const InvoicePaymentStatusChip({super.key, required this.status});

  final PaymentStatus status;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      PaymentStatus.paid => AppColor.success,
      PaymentStatus.partiallyPaid => const Color(0xFFFF9F2E),
      PaymentStatus.unpaid || PaymentStatus.overdue => AppColor.error,
    };
    return _FinancialStatusChip(label: status.value.tr, color: color);
  }
}

class InvoiceReturnStatusChip extends StatelessWidget {
  const InvoiceReturnStatusChip({super.key, required this.status});

  final InvoiceReturnStatus status;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      InvoiceReturnStatus.none => AppColor.grey,
      InvoiceReturnStatus.partiallyReturned => const Color(0xFFFF9F2E),
      InvoiceReturnStatus.returned => AppColor.error,
    };
    return _FinancialStatusChip(label: status.value.tr, color: color);
  }
}

class _FinancialStatusChip extends StatelessWidget {
  const _FinancialStatusChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
