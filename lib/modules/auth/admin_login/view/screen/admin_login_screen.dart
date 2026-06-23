import 'package:fatoora/core/constant/color.dart';
import 'package:fatoora/modules/auth/admin_login/controller/admin_login_controller.dart';
import 'package:fatoora/modules/auth/admin_login/view/widgets/login/admin_login_footer.dart';
import 'package:fatoora/modules/auth/admin_login/view/widgets/login/admin_login_form.dart';
import 'package:fatoora/modules/auth/admin_login/view/widgets/login/admin_login_header.dart';
import 'package:fatoora/modules/auth/admin_login/view/widgets/login/admin_login_wave_header.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class AdminLoginScreen extends GetView<AdminLoginControllerImp> {
  const AdminLoginScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColor.background,
      body: SafeArea(
        bottom: false,
        child: GetBuilder<AdminLoginControllerImp>(
          builder: (controller) {
            return SingleChildScrollView(
              child: Column(
                children: [
                  const AdminLoginWaveHeader(),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 12, 24, 40),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 520),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: AppColor.surface,
                            borderRadius: BorderRadius.circular(24),
                            boxShadow: [
                              BoxShadow(
                                color: AppColor.black.withValues(alpha: 0.06),
                                blurRadius: 24,
                                offset: const Offset(0, 10),
                              ),
                            ],
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              children: [
                                const AdminLoginHeader(),
                                const SizedBox(height: 28),
                                AdminLoginForm(controller: controller),
                                const SizedBox(height: 26),
                                AdminLoginFooter(controller: controller),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
