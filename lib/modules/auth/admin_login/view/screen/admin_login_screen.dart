import 'package:fatoora/core/class/statusrequest.dart';
import 'package:fatoora/core/constant/color.dart';
import 'package:fatoora/core/constant/imageassests.dart';
import 'package:fatoora/modules/auth/admin_login/controller/admin_login_controller.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class AdminLoginScreen extends GetView<AdminLoginControllerImp> {
  const AdminLoginScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColor.background,
      body: SafeArea(
        child: GetBuilder<AdminLoginControllerImp>(
          builder: (controller) {
            return Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 32,
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: Column(
                    children: [
                      const _LoginHeader(),
                      const SizedBox(height: 32),
                      _LoginForm(controller: controller),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _LoginHeader extends StatelessWidget {
  const _LoginHeader();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      children: [
        Container(
          width: 132,
          height: 132,
          padding: const EdgeInsets.all(16),
          decoration: const BoxDecoration(
            gradient: AppColor.mainGradient,
            shape: BoxShape.circle,
          ),
          child: Image.asset(ImageAssest.logo, fit: BoxFit.contain),
        ),
        const SizedBox(height: 24),
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

class _LoginForm extends StatelessWidget {
  const _LoginForm({required this.controller});

  final AdminLoginControllerImp controller;

  @override
  Widget build(BuildContext context) {
    return Form(
      key: controller.formKey,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      child: Column(
        children: [
          TextFormField(
            controller: controller.emailController,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            autofillHints: const [AutofillHints.email],
            decoration: InputDecoration(
              labelText: 'email'.tr,
              hintText: 'email_hint'.tr,
              prefixIcon: const Icon(
                Icons.email_outlined,
                color: AppColor.primaryColor,
              ),
            ),
            validator: (value) {
              final email = value?.trim() ?? '';
              if (email.isEmpty) return 'validation_email_required'.tr;
              if (!GetUtils.isEmail(email)) {
                return 'validation_email_invalid'.tr;
              }
              return null;
            },
          ),
          const SizedBox(height: 18),
          TextFormField(
            controller: controller.passwordController,
            obscureText: controller.isShowPassword,
            textInputAction: TextInputAction.done,
            autofillHints: const [AutofillHints.password],
            onFieldSubmitted: (_) => controller.login(),
            decoration: InputDecoration(
              labelText: 'password'.tr,
              hintText: 'password_hint'.tr,
              prefixIcon: const Icon(
                Icons.lock_outline,
                color: AppColor.primaryColor,
              ),
              suffixIcon: IconButton(
                tooltip: controller.isShowPassword
                    ? 'show_password'.tr
                    : 'hide_password'.tr,
                onPressed: controller.togglePassword,
                icon: Icon(
                  controller.isShowPassword
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                  color: AppColor.grey,
                ),
              ),
            ),
            validator: (value) {
              if (value == null || value.isEmpty) {
                return 'validation_password_required'.tr;
              }
              if (value.length < 6) {
                return 'validation_password_min'.tr;
              }
              return null;
            },
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: AppColor.mainGradient,
                borderRadius: BorderRadius.circular(16),
              ),
              child: ElevatedButton(
                onPressed: controller.statusRequest == StatusRequest.loading
                    ? null
                    : controller.login,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  disabledBackgroundColor: Colors.transparent,
                  shadowColor: Colors.transparent,
                  foregroundColor: AppColor.surface,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: controller.statusRequest == StatusRequest.loading
                    ? const SizedBox.square(
                        dimension: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: AppColor.surface,
                        ),
                      )
                    : Text(
                        'login'.tr,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
