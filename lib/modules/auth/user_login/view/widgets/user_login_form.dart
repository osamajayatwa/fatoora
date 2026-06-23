import 'package:fatoora/modules/auth/admin_login/view/widgets/login/admin_login_gradient_button.dart';
import 'package:fatoora/modules/auth/admin_login/view/widgets/login/admin_login_text_field.dart';
import 'package:fatoora/modules/auth/user_login/controller/user_login_controller.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class UserLoginForm extends StatelessWidget {
  const UserLoginForm({super.key, required this.controller});
  final UserLoginControllerImp controller;

  @override
  Widget build(BuildContext context) => AutofillGroup(
    child: Form(
      key: controller.formKey,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      child: Column(
        children: [
          AdminLoginTextField(
            controller: controller.emailController,
            label: 'email'.tr,
            hint: 'email_hint'.tr,
            icon: Icons.email_outlined,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            autofillHints: const [AutofillHints.email],
            validator: (value) {
              final email = value?.trim() ?? '';
              if (email.isEmpty) return 'validation_email_required'.tr;
              return GetUtils.isEmail(email)
                  ? null
                  : 'validation_email_invalid'.tr;
            },
          ),
          const SizedBox(height: 18),
          AdminLoginTextField(
            controller: controller.passwordController,
            label: 'password'.tr,
            hint: 'password_hint'.tr,
            icon: Icons.lock_outline,
            obscureText: controller.isShowPassword,
            textInputAction: TextInputAction.done,
            autofillHints: const [AutofillHints.password],
            onFieldSubmitted: (_) => controller.login(),
            suffixIcon: IconButton(
              tooltip: controller.isShowPassword
                  ? 'show_password'.tr
                  : 'hide_password'.tr,
              onPressed: controller.togglePassword,
              icon: Icon(
                controller.isShowPassword
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
              ),
            ),
            validator: (value) => value == null || value.isEmpty
                ? 'validation_password_required'.tr
                : null,
          ),
          const SizedBox(height: 24),
          AdminLoginGradientButton(
            text: 'login'.tr,
            onPressed: controller.login,
            isLoading: controller.isLoading,
          ),
        ],
      ),
    ),
  );
}
