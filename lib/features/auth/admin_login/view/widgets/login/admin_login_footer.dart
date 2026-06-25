import 'package:fatoora/core/constants/color.dart';
import 'package:fatoora/features/auth/admin_login/controller/admin_login_controller.dart';
import 'package:fatoora/features/auth/admin_login/view/widgets/login/admin_google_sign_in_button.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class AdminLoginFooter extends StatelessWidget {
  const AdminLoginFooter({super.key, required this.controller});

  final AdminLoginControllerImp controller;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            const Expanded(child: Divider(color: AppColor.border)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                'or_continue_with'.tr,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: AppColor.grey),
              ),
            ),
            const Expanded(child: Divider(color: AppColor.border)),
          ],
        ),
        const SizedBox(height: 18),
        AdminGoogleSignInButton(
          text: 'continue_with_google'.tr,
          onPressed: controller.loginWithGoogle,
          isLoading: controller.isLoading,
        ),
      ],
    );
  }
}
