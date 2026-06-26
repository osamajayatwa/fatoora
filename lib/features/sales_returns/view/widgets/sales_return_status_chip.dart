import 'package:fatoora/core/constants/color.dart';
import 'package:fatoora/features/sales_returns/data/models/sales_return_enums.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class SalesReturnStatusChip extends StatelessWidget {
  const SalesReturnStatusChip({super.key, required this.status});

  final SalesReturnStatus status;

  @override
  Widget build(BuildContext context) {
    final (background, foreground) = switch (status) {
      SalesReturnStatus.draft => (
        const Color(0xFFFFF1D7),
        const Color(0xFF9A6200),
      ),
      SalesReturnStatus.confirmed => (
        const Color(0xFFDDF7E7),
        AppColor.success,
      ),
      SalesReturnStatus.cancelled => (const Color(0xFFFFE2E2), AppColor.error),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        'sales_return_status_${status.value}'.tr,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: foreground,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}
