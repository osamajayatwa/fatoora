import 'package:fatoora/core/constant/color.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class LockedElectronicInvoiceBanner extends StatelessWidget {
  const LockedElectronicInvoiceBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColor.primaryLight.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppColor.primaryColor.withValues(alpha: 0.25),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.lock_outline_rounded, color: AppColor.primaryColor),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'invoice_locked'.tr,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: AppColor.primaryDark,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
