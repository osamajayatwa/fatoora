import 'package:fatoora/core/constants/color.dart';
import 'package:fatoora/features/auth/admin_login/view/widgets/login/admin_google_sign_in_button.dart';
import 'package:fatoora/features/auth/user_login/controller/user_login_controller.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class UserLoginFooter extends StatelessWidget {
  const UserLoginFooter({super.key, required this.controller});
  final UserLoginControllerImp controller;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Row(
        children: [
          const Expanded(child: Divider(color: AppColor.border)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text('or_continue_with'.tr),
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
      const SizedBox(height: 16),
      Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text('no_account'.tr),
          TextButton(
            onPressed: controller.goToSignUp,
            child: Text('create_account'.tr),
          ),
        ],
      ),
    ],
  );
}
