import 'package:fatoora/core/constants/color.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class UserSignUpHeader extends StatelessWidget {
  const UserSignUpHeader({super.key});

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Text(
        'signup_title'.tr,
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
          color: AppColor.primaryColor,
          fontWeight: FontWeight.w700,
        ),
      ),
      const SizedBox(height: 8),
      Text(
        'signup_subtitle'.tr,
        textAlign: TextAlign.center,
        style: Theme.of(
          context,
        ).textTheme.bodyMedium?.copyWith(color: AppColor.grey),
      ),
    ],
  );
}
