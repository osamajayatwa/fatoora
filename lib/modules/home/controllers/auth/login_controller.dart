import 'package:fatoora/core/class/statusrequest.dart';
import 'package:fatoora/core/constant/routes.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class LoginControllerImp extends GetxController {
  // 🔹 Text controllers
  late TextEditingController username;
  late TextEditingController password;

  // 🔹 State variables
  bool isshowpassword = true;
  StatusRequest statusRequest = StatusRequest.none;

  // 🔹 Toggle password visibility
  void showPassword() {
    isshowpassword = !isshowpassword;
    update();
  }

  // 🔹 Validate login
  Future<void> fakeLogin() async {
    
    final user = username.text.trim();
    final pass = password.text.trim();

    // 🧾 Basic empty check
    if (user.isEmpty || pass.isEmpty) {
      Get.snackbar(
        "Error",
        "Please enter username and password",
        backgroundColor: Colors.red.shade600,
        colorText: Colors.white,
        snackPosition: SnackPosition.BOTTOM,
      );
      return;
    }

    // 🔄 Simulate loading
    statusRequest = StatusRequest.loading;
    update();

    await Future.delayed(const Duration(seconds: 1));

    // ✅ Hardcoded validation
    if (user == "osamajayatweh" && pass == "osama123") {
      statusRequest = StatusRequest.success;
      update();
      Get.offAllNamed(AppRoute.home);

      Get.snackbar(
        "Login",
        "✅ Login successful",
        backgroundColor: Colors.green.shade600,
        colorText: Colors.white,
        snackPosition: SnackPosition.BOTTOM,
        duration: const Duration(seconds: 2),
      );

      // You can navigate here if you want:
      // Get.offAllNamed(AppRoute.home);
    } else {
      statusRequest = StatusRequest.failure;
      update();

      Get.snackbar(
        "Invalid Credentials",
        "❌ Username or password is incorrect",
        backgroundColor: Colors.red.shade600,
        colorText: Colors.white,
        snackPosition: SnackPosition.BOTTOM,
        duration: const Duration(seconds: 2),
      );
    }
  }

  @override
  void onInit() {
    username = TextEditingController();
    password = TextEditingController();
    super.onInit();
  }

  @override
  void onClose() {
    username.dispose();
    password.dispose();
    super.onClose();
  }
}
