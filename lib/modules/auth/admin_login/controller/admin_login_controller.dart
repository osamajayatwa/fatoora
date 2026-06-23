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

  bool get isLoading => statusRequest == StatusRequest.loading;

  void togglePassword() {
    isShowPassword = !isShowPassword;
    update();
  }

  Future<void> login() async {
    if (isLoading) return;

    final isValid = formKey.currentState?.validate() ?? false;
    if (!isValid) {
      _setStatus(StatusRequest.failure);
      return;
    }

    await _authenticate(
      () => _repository.signIn(
        email: emailController.text.trim(),
        password: passwordController.text,
      ),
    );
  }

  Future<void> loginWithGoogle() async {
    if (isLoading) return;
    await _authenticate(_repository.signInWithGoogle, isGoogleFlow: true);
  }

  Future<void> _authenticate(
    Future<UserCredential?> Function() request, {
    bool isGoogleFlow = false,
  }) async {
    _setStatus(StatusRequest.loading);
    var firebaseSessionCreated = false;

    try {
      final credential = await request();
      if (credential == null) {
        _setStatus(StatusRequest.none);
        return;
      }
      firebaseSessionCreated = true;

      if (isClosed) {
        await _repository.signOut();
        return;
      }

      final isAuthorized = await _authorizeAdmin(credential);
      if (!isAuthorized || isClosed) return;

      _setStatus(StatusRequest.success);
      Get.offAllNamed(AppRoute.adminHome);
      _showSuccess('login_success_message');
    } on FirebaseAuthException catch (error) {
      await _signOutIfNeeded(firebaseSessionCreated);
      if (_isCancellation(error.code)) {
        _setStatus(StatusRequest.none);
        return;
      }

      final failure = _mapAuthError(error.code, isGoogleFlow: isGoogleFlow);
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
      _showError(
        isGoogleFlow ? 'google_sign_in_failed' : 'login_unknown_error',
      );
    }
  }

  Future<bool> _authorizeAdmin(UserCredential credential) async {
    final firebaseUser = credential.user;
    if (firebaseUser == null) {
      throw FirebaseAuthException(
        code: 'user-not-found',
        message: 'Firebase did not return a user after sign in.',
      );
    }

    final appUser = await _repository.getUser(firebaseUser.uid);
    if (appUser == null) {
      await _rejectLogin(
        status: StatusRequest.unauthorized,
        messageKey: 'login_profile_not_found',
      );
      return false;
    }

    if (appUser.role != 'admin') {
      await _rejectLogin(
        status: StatusRequest.unauthorized,
        messageKey: 'login_admin_only',
      );
      return false;
    }

    if (!appUser.active) {
      await _rejectLogin(
        status: StatusRequest.unauthorized,
        messageKey: 'login_account_inactive',
      );
      return false;
    }

    await _saveSession(appUser);
    return true;
  }

  Future<void> _saveSession(AppUserModel user) async {
    final preferences = _myServices.sharedPreferences;
    await preferences.setString('uid', user.uid);
    await preferences.setString('role', 'admin');
    await preferences.setString('name', user.name);
    await preferences.setString('email', user.email);

    // Save the authenticated step last so a partial profile is never resumed.
    await preferences.setString('step', '3');
  }

  Future<void> _rejectLogin({
    required StatusRequest status,
    required String messageKey,
  }) async {
    try {
      await _repository.signOut();
    } catch (_) {
      // Local session data must still be cleared and the denial shown.
    } finally {
      await _clearSession();
    }

    _setStatus(status);
    _showError(messageKey);
  }

  Future<void> _signOutIfNeeded(bool firebaseSessionCreated) async {
    if (!firebaseSessionCreated) return;
    try {
      await _repository.signOut();
    } catch (_) {
      // Preserve the original authentication error shown to the user.
    } finally {
      await _clearSession();
    }
  }

  Future<void> _clearSession() async {
    final preferences = _myServices.sharedPreferences;
    await preferences.remove('step');
    await preferences.remove('uid');
    await preferences.remove('role');
    await preferences.remove('name');
    await preferences.remove('email');
  }

  bool _isCancellation(String code) {
    return code == 'popup-closed-by-user' ||
        code == 'cancelled-popup-request' ||
        code == 'sign_in_canceled';
  }

  _LoginFailure _mapAuthError(String code, {required bool isGoogleFlow}) {
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
      case 'network_error':
        return const _LoginFailure(
          StatusRequest.offlinefailure,
          'login_network_error',
        );
      case 'too-many-requests':
        return const _LoginFailure(
          StatusRequest.failure,
          'login_too_many_requests',
        );
      case 'popup-blocked':
        return const _LoginFailure(
          StatusRequest.failure,
          'google_popup_blocked',
        );
      case 'account-exists-with-different-credential':
        return const _LoginFailure(
          StatusRequest.failure,
          'google_account_exists',
        );
      case 'operation-not-allowed':
      case 'internal-error':
        return const _LoginFailure(
          StatusRequest.serverfailure,
          'login_server_error',
        );
      default:
        return _LoginFailure(
          StatusRequest.failure,
          isGoogleFlow ? 'google_sign_in_failed' : 'login_unknown_error',
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
    if (isClosed) return;
    statusRequest = status;
    update();
  }

  void _showError(String messageKey) {
    if (isClosed) return;
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
