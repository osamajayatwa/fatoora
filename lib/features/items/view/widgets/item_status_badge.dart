import 'package:fatoora/core/constants/color.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class ItemStatusBadge extends StatelessWidget {
  const ItemStatusBadge({super.key, required this.active});

  final bool active;

  @override
  Widget build(BuildContext context) {
    final color = active ? AppColor.success : AppColor.error;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.11),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 7),
          Text(
            active ? 'items_active'.tr : 'items_inactive'.tr,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
