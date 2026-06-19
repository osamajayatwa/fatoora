import 'package:fatoora/core/class/statusrequest.dart';
import 'package:fatoora/core/constant/color.dart';
import 'package:fatoora/core/constant/routes.dart';
import 'package:fatoora/core/services/services.dart';
import 'package:fatoora/data/models/app_user_model.dart';
import 'package:fatoora/data/repositories/admin_auth_repository.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class AdminLoginControllerImp extends GetxController {
  AdminLoginControllerImp({
    required AdminAuthRepository repository,
    required MyServices myServices,
  }) : _repository = repository,
       _myServices = myServices;

  final AdminAuthRepository _repository;
  final MyServices _myServices;

  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  final GlobalKey<FormState> formKey = GlobalKey<FormState>();

  StatusRequest statusRequest = StatusRequest.none;
  bool isShowPassword = true;
  bool _inputsDisposed = false;

  void togglePassword() {
    isShowPassword = !isShowPassword;
    update();
  }

  Future<void> login() async {
    if (statusRequest == StatusRequest.loading) return;

    final isValid = formKey.currentState?.validate() ?? false;
    if (!isValid) {
      _setStatus(StatusRequest.failure);
      return;
    }

    _setStatus(StatusRequest.loading);
    var firebaseSessionCreated = false;

    try {
      final credential = await _repository.signIn(
        email: emailController.text.trim(),
        password: passwordController.text,
      );

      final firebaseUser = credential.user;
      if (firebaseUser == null) {
        throw FirebaseAuthException(
          code: 'user-not-found',
          message: 'Firebase did not return a user after sign in.',
        );
      }
      firebaseSessionCreated = true;

      final appUser = await _repository.getUser(firebaseUser.uid);
      if (appUser == null) {
        await _rejectLogin(
          status: StatusRequest.unauthorized,
          messageKey: 'login_profile_not_found',
        );
        return;
      }

      if (appUser.role != 'admin') {
        await _rejectLogin(
          status: StatusRequest.unauthorized,
          messageKey: 'login_admin_only',
        );
        return;
      }

      if (!appUser.active) {
        await _rejectLogin(
          status: StatusRequest.unauthorized,
          messageKey: 'login_account_inactive',
        );
        return;
      }

      await _saveSession(appUser);
      _setStatus(StatusRequest.success);

      Get.offAllNamed(AppRoute.home);
      _showSuccess('login_success_message');
    } on FirebaseAuthException catch (error) {
      await _signOutIfNeeded(firebaseSessionCreated);
      final failure = _mapAuthError(error.code);
      _setStatus(failure.status);
      _showError(failure.messageKey);
    } on FirebaseException catch (error) {
      await _signOutIfNeeded(firebaseSessionCreated);
      final failure = _mapFirestoreError(error.code);
      _setStatus(failure.status);
      _showError(failure.messageKey);
    } on FormatException {
      await _signOutIfNeeded(firebaseSessionCreated);
      _setStatus(StatusRequest.failure);
      _showError('login_profile_invalid');
    } catch (_) {
      await _signOutIfNeeded(firebaseSessionCreated);
      _setStatus(StatusRequest.failure);
      _showError('login_unknown_error');
    }
  }

  Future<void> _saveSession(AppUserModel user) async {
    final preferences = _myServices.sharedPreferences;
    await Future.wait([
      preferences.setString('step', '3'),
      preferences.setString('uid', user.uid),
      preferences.setString('role', 'admin'),
      preferences.setString('name', user.name),
      preferences.setString('email', user.email),
    ]);
  }

  Future<void> _rejectLogin({
    required StatusRequest status,
    required String messageKey,
  }) async {
    await _repository.signOut();
    await _clearSession();
    _setStatus(status);
    _showError(messageKey);
  }

  Future<void> _signOutIfNeeded(bool firebaseSessionCreated) async {
    if (!firebaseSessionCreated) return;
    try {
      await _repository.signOut();
      await _clearSession();
    } catch (_) {
      // Preserve the original login error shown to the user.
    }
  }

  Future<void> _clearSession() async {
    final preferences = _myServices.sharedPreferences;
    await Future.wait([
      preferences.remove('step'),
      preferences.remove('uid'),
      preferences.remove('role'),
      preferences.remove('name'),
      preferences.remove('email'),
    ]);
  }

  _LoginFailure _mapAuthError(String code) {
    switch (code) {
      case 'invalid-email':
        return const _LoginFailure(
          StatusRequest.failure,
          'login_invalid_email',
        );
      case 'user-disabled':
        return const _LoginFailure(
          StatusRequest.unauthorized,
          'login_user_disabled',
        );
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
        return const _LoginFailure(
          StatusRequest.unauthorized,
          'login_invalid_credentials',
        );
      case 'network-request-failed':
        return const _LoginFailure(
          StatusRequest.offlinefailure,
          'login_network_error',
        );
      case 'too-many-requests':
        return const _LoginFailure(
          StatusRequest.failure,
          'login_too_many_requests',
        );
      case 'operation-not-allowed':
      case 'internal-error':
        return const _LoginFailure(
          StatusRequest.serverfailure,
          'login_server_error',
        );
      default:
        return const _LoginFailure(
          StatusRequest.failure,
          'login_unknown_error',
        );
    }
  }

  _LoginFailure _mapFirestoreError(String code) {
    switch (code) {
      case 'permission-denied':
      case 'unauthenticated':
        return const _LoginFailure(
          StatusRequest.unauthorized,
          'login_permission_denied',
        );
      case 'unavailable':
        return const _LoginFailure(
          StatusRequest.offlinefailure,
          'login_network_error',
        );
      case 'deadline-exceeded':
        return const _LoginFailure(StatusRequest.timeout, 'login_timeout');
      case 'aborted':
      case 'cancelled':
        return const _LoginFailure(
          StatusRequest.failure,
          'login_unknown_error',
        );
      default:
        return const _LoginFailure(
          StatusRequest.serverfailure,
          'login_server_error',
        );
    }
  }

  void _setStatus(StatusRequest status) {
    statusRequest = status;
    update();
  }

  void _showError(String messageKey) {
    Get.snackbar(
      'login_error_title'.tr,
      messageKey.tr,
      snackPosition: SnackPosition.BOTTOM,
      backgroundColor: AppColor.error,
      colorText: AppColor.surface,
    );
  }

  void _showSuccess(String messageKey) {
    Get.snackbar(
      'login_success_title'.tr,
      messageKey.tr,
      snackPosition: SnackPosition.BOTTOM,
      backgroundColor: AppColor.success,
      colorText: AppColor.surface,
    );
  }

  @override
  void onClose() {
    _disposeInputs();
    super.onClose();
  }

  @override
  void dispose() {
    _disposeInputs();
    super.dispose();
  }

  void _disposeInputs() {
    if (_inputsDisposed) return;
    emailController.dispose();
    passwordController.dispose();
    _inputsDisposed = true;
  }
}

class _LoginFailure {
  const _LoginFailure(this.status, this.messageKey);

  final StatusRequest status;
  final String messageKey;
}
