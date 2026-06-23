import 'package:fatoora/core/class/statusrequest.dart';
import 'package:fatoora/core/constant/color.dart';
import 'package:fatoora/core/constant/routes.dart';
import 'package:fatoora/core/services/services.dart';
import 'package:fatoora/data/models/app_user_model.dart';
import 'package:fatoora/data/repositories/user_auth_repository.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class UserSignUpControllerImp extends GetxController {
  UserSignUpControllerImp({
    required UserAuthRepository repository,
    required MyServices myServices,
  }) : _repository = repository,
       _myServices = myServices;

  final UserAuthRepository _repository;
  final MyServices _myServices;

  final nameController = TextEditingController();
  final emailController = TextEditingController();
  final ageController = TextEditingController();
  final phoneController = TextEditingController();
  final passwordController = TextEditingController();
  final confirmPasswordController = TextEditingController();
  final formKey = GlobalKey<FormState>();

  StatusRequest statusRequest = StatusRequest.none;
  bool showPassword = false;
  bool showConfirmPassword = false;
  bool get isLoading => statusRequest == StatusRequest.loading;

  void togglePassword() {
    showPassword = !showPassword;
    update();
  }

  void toggleConfirmPassword() {
    showConfirmPassword = !showConfirmPassword;
    update();
  }

  void goToLogin() => Get.offNamed(AppRoute.userLogin);

  Future<void> signUp() async {
    if (isLoading || !(formKey.currentState?.validate() ?? false)) return;
    _setStatus(StatusRequest.loading);

    try {
      final credential = await _repository.registerViewer(
        name: nameController.text.trim(),
        email: emailController.text.trim(),
        age: int.parse(ageController.text.trim()),
        phone: phoneController.text.trim(),
        password: passwordController.text,
      );
      final uid = credential.user?.uid;
      if (uid == null) throw FirebaseAuthException(code: 'user-not-found');
      final profile = await _repository.getUser(uid);
      if (profile == null) throw const FormatException('Missing profile');

      await _saveSession(profile);
      _setStatus(StatusRequest.success);
      Get.offAllNamed(AppRoute.home);
      Get.snackbar(
        'signup_success_title'.tr,
        'signup_success_message'.tr,
        backgroundColor: AppColor.success,
        colorText: AppColor.surface,
        snackPosition: SnackPosition.BOTTOM,
      );
    } on FirebaseAuthException catch (error) {
      _setStatus(
        error.code == 'network-request-failed'
            ? StatusRequest.offlinefailure
            : StatusRequest.failure,
      );
      _showError(_authMessage(error.code));
    } on FirebaseException catch (error) {
      _setStatus(
        error.code == 'permission-denied'
            ? StatusRequest.unauthorized
            : StatusRequest.serverfailure,
      );
      _showError(
        error.code == 'permission-denied'
            ? 'signup_permission_denied'
            : 'login_server_error',
      );
    } catch (_) {
      _setStatus(StatusRequest.failure);
      _showError('signup_unknown_error');
    }
  }

  String _authMessage(String code) {
    switch (code) {
      case 'email-already-in-use':
        return 'signup_email_in_use';
      case 'weak-password':
        return 'signup_weak_password';
      case 'invalid-email':
        return 'validation_email_invalid';
      case 'network-request-failed':
        return 'login_network_error';
      case 'operation-not-allowed':
        return 'login_server_error';
      default:
        return 'signup_unknown_error';
    }
  }

  Future<void> _saveSession(AppUserModel user) async {
    final preferences = _myServices.sharedPreferences;
    await preferences.setString('uid', user.uid);
    await preferences.setString('role', user.role);
    await preferences.setString('name', user.name);
    await preferences.setString('email', user.email);
    await preferences.setString('step', '2');
  }

  void _setStatus(StatusRequest status) {
    if (isClosed) return;
    statusRequest = status;
    update();
  }

  void _showError(String key) => Get.snackbar(
    'signup_error_title'.tr,
    key.tr,
    backgroundColor: AppColor.error,
    colorText: AppColor.surface,
    snackPosition: SnackPosition.BOTTOM,
  );

  @override
  void onClose() {
    nameController.dispose();
    emailController.dispose();
    ageController.dispose();
    phoneController.dispose();
    passwordController.dispose();
    confirmPasswordController.dispose();
    super.onClose();
  }
}
