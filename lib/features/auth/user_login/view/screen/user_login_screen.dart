import 'package:fatoora/core/constants/color.dart';
import 'package:fatoora/features/auth/admin_login/view/widgets/login/admin_login_wave_header.dart';
import 'package:fatoora/features/auth/user_login/controller/user_login_controller.dart';
import 'package:fatoora/features/auth/user_login/view/widgets/user_login_footer.dart';
import 'package:fatoora/features/auth/user_login/view/widgets/user_login_form.dart';
import 'package:fatoora/features/auth/user_login/view/widgets/user_login_header.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class UserLoginScreen extends GetView<UserLoginControllerImp> {
  const UserLoginScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColor.background,
    body: SafeArea(
      bottom: false,
      child: GetBuilder<UserLoginControllerImp>(
        builder: (controller) => SingleChildScrollView(
          child: Column(
            children: [
              const AdminLoginWaveHeader(),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 40),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 520),
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
                            const UserLoginHeader(),
                            const SizedBox(height: 28),
                            UserLoginForm(controller: controller),
                            const SizedBox(height: 26),
                            UserLoginFooter(controller: controller),
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
