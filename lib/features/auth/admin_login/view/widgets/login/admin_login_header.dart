import 'package:fatoora/core/constants/color.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class AdminLoginHeader extends StatelessWidget {
  const AdminLoginHeader({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      children: [
        Text(
          'admin_login_title'.tr,
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineSmall?.copyWith(
            color: AppColor.primaryColor,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'admin_login_subtitle'.tr,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(color: AppColor.grey),
        ),
      ],
    );
  }
}
