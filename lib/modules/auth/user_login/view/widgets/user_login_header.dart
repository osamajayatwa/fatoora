import 'package:fatoora/core/constant/color.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class UserLoginHeader extends StatelessWidget {
  const UserLoginHeader({super.key});

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Text(
        'user_login_title'.tr,
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
          color: AppColor.primaryColor,
          fontWeight: FontWeight.w700,
        ),
      ),
      const SizedBox(height: 8),
      Text(
        'user_login_subtitle'.tr,
        textAlign: TextAlign.center,
        style: Theme.of(
          context,
        ).textTheme.bodyMedium?.copyWith(color: AppColor.grey),
      ),
    ],
  );
}
