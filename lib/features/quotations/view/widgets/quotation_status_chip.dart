import 'package:fatoora/core/constants/color.dart';
import 'package:fatoora/features/quotations/data/models/quotation_status.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class QuotationStatusChip extends StatelessWidget {
  const QuotationStatusChip({super.key, required this.status});

  final QuotationStatus status;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      QuotationStatus.draft => AppColor.grey,
      QuotationStatus.sent => AppColor.primaryColor,
      QuotationStatus.accepted => AppColor.success,
      QuotationStatus.rejected => AppColor.error,
      QuotationStatus.expired => const Color(0xFFFF9838),
      QuotationStatus.converted => AppColor.secondaryColor,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        status.value.tr,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}
