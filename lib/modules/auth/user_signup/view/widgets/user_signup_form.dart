import 'package:fatoora/modules/auth/admin_login/view/widgets/login/admin_login_gradient_button.dart';
import 'package:fatoora/modules/auth/admin_login/view/widgets/login/admin_login_text_field.dart';
import 'package:fatoora/modules/auth/user_signup/controller/user_signup_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

class UserSignUpForm extends StatelessWidget {
  const UserSignUpForm({super.key, required this.controller});
  final UserSignUpControllerImp controller;

  @override
  Widget build(BuildContext context) => AutofillGroup(
    child: Form(
      key: controller.formKey,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      child: Column(
        children: [
          AdminLoginTextField(
            controller: controller.nameController,
            label: 'full_name'.tr,
            hint: 'full_name_hint'.tr,
            icon: Icons.person_outline,
            textInputAction: TextInputAction.next,
            autofillHints: const [AutofillHints.name],
            validator: (value) {
              final name = value?.trim() ?? '';
              if (name.isEmpty) return 'validation_name_required'.tr;
              return name.length >= 2 ? null : 'validation_name_short'.tr;
            },
          ),
          const SizedBox(height: 16),
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
          const SizedBox(height: 16),
          AdminLoginTextField(
            controller: controller.ageController,
            label: 'age'.tr,
            hint: 'age_hint'.tr,
            icon: Icons.cake_outlined,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.next,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            validator: (value) {
              final age = int.tryParse(value?.trim() ?? '');
              if (age == null) return 'validation_age_required'.tr;
              return age >= 1 && age <= 120 ? null : 'validation_age_range'.tr;
            },
          ),
          const SizedBox(height: 16),
          AdminLoginTextField(
            controller: controller.phoneController,
            label: 'phone_number'.tr,
            hint: 'phone_number_hint'.tr,
            icon: Icons.phone_outlined,
            keyboardType: TextInputType.phone,
            textInputAction: TextInputAction.next,
            autofillHints: const [AutofillHints.telephoneNumber],
            validator: (value) {
              final phone = value?.trim() ?? '';
              if (phone.isEmpty) return 'validation_phone_required'.tr;
              return RegExp(r'^\+?[0-9]{7,15}$').hasMatch(phone)
                  ? null
                  : 'validation_phone_invalid'.tr;
            },
          ),
          const SizedBox(height: 16),
          _passwordField(confirm: false),
          const SizedBox(height: 16),
          _passwordField(confirm: true),
          const SizedBox(height: 24),
          AdminLoginGradientButton(
            text: 'create_account'.tr,
            onPressed: controller.signUp,
            isLoading: controller.isLoading,
          ),
          const SizedBox(height: 10),
          Text(
            'phone_verification_later'.tr,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    ),
  );

  Widget _passwordField({required bool confirm}) {
    final visible = confirm
        ? controller.showConfirmPassword
        : controller.showPassword;
    return AdminLoginTextField(
      controller: confirm
          ? controller.confirmPasswordController
          : controller.passwordController,
      label: (confirm ? 'confirm_password' : 'password').tr,
      hint: (confirm ? 'confirm_password_hint' : 'password_hint').tr,
      icon: Icons.lock_outline,
      obscureText: !visible,
      textInputAction: confirm ? TextInputAction.done : TextInputAction.next,
      autofillHints: confirm ? null : const [AutofillHints.newPassword],
      onFieldSubmitted: confirm ? (_) => controller.signUp() : null,
      suffixIcon: IconButton(
        tooltip: visible ? 'hide_password'.tr : 'show_password'.tr,
        onPressed: confirm
            ? controller.toggleConfirmPassword
            : controller.togglePassword,
        icon: Icon(
          visible ? Icons.visibility_off_outlined : Icons.visibility_outlined,
        ),
      ),
      validator: (value) {
        if (value == null || value.isEmpty) {
          return (confirm
                  ? 'validation_confirm_password_required'
                  : 'validation_password_required')
              .tr;
        }
        if (!confirm && value.length < 8) {
          return 'validation_signup_password_min'.tr;
        }
        if (confirm && value != controller.passwordController.text) {
          return 'validation_passwords_mismatch'.tr;
        }
        return null;
      },
    );
  }
}
