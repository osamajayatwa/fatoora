import 'package:fatoora/core/constants/color.dart';
import 'package:fatoora/features/auth/admin_login/view/widgets/login/admin_login_wave_header.dart';
import 'package:fatoora/features/auth/user_signup/controller/user_signup_controller.dart';
import 'package:fatoora/features/auth/user_signup/view/widgets/user_signup_footer.dart';
import 'package:fatoora/features/auth/user_signup/view/widgets/user_signup_form.dart';
import 'package:fatoora/features/auth/user_signup/view/widgets/user_signup_header.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class UserSignUpScreen extends GetView<UserSignUpControllerImp> {
  const UserSignUpScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColor.background,
    body: SafeArea(
      bottom: false,
      child: GetBuilder<UserSignUpControllerImp>(
        builder: (controller) => SingleChildScrollView(
          child: Column(
            children: [
              const AdminLoginWaveHeader(),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 40),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 620),
                    child: Card(
                      color: AppColor.surface,
                      elevation: 3,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          children: [
                            const UserSignUpHeader(),
                            const SizedBox(height: 28),
                            UserSignUpForm(controller: controller),
                            const SizedBox(height: 12),
                            UserSignUpFooter(controller: controller),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
