import 'package:fatoora/core/class/statusrequest.dart';
import 'package:fatoora/core/constants/color.dart';
import 'package:fatoora/app/routes/app_routes.dart';
import 'package:fatoora/core/services/services.dart';
import 'package:fatoora/features/auth/data/repositories/user_auth_repository.dart';
import 'package:fatoora/features/auth/utils/auth_session.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class UserLoginControllerImp extends GetxController {
  UserLoginControllerImp({
    required UserAuthRepository repository,
    required MyServices myServices,
  }) : _repository = repository,
       _myServices = myServices;

  final UserAuthRepository _repository;
  final MyServices _myServices;

  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  final formKey = GlobalKey<FormState>();

  StatusRequest statusRequest = StatusRequest.none;
  bool isShowPassword = true;
  bool get isLoading => statusRequest == StatusRequest.loading;

  void togglePassword() {
    isShowPassword = !isShowPassword;
    update();
  }

  void goToSignUp() => Get.toNamed(AppRoute.userSignUp);

  Future<void> login() async {
    if (isLoading || !(formKey.currentState?.validate() ?? false)) return;
    await _authenticate(
      () => _repository.signIn(
        email: emailController.text.trim(),
        password: passwordController.text,
      ),
    );
  }

  Future<void> loginWithGoogle() =>
      _authenticate(_repository.signInWithGoogle, googleFlow: true);

  Future<void> _authenticate(
    Future<UserCredential?> Function() request, {
    bool googleFlow = false,
  }) async {
    if (isLoading) return;
    _setStatus(StatusRequest.loading);
    var signedIn = false;

    try {
      final credential = await request();
      if (credential == null) {
        _setStatus(StatusRequest.none);
        return;
      }
      signedIn = true;

      final firebaseUser = credential.user;
      if (firebaseUser == null) {
        throw FirebaseAuthException(code: 'user-not-found');
      }
      final profile = await _repository.getOrCreatePendingProfile(firebaseUser);

      await AuthSession.save(_myServices, profile);
      _setStatus(StatusRequest.success);
      Get.offAllNamed(AuthSession.routeForProfile(profile));
      _success(
        profile.isPending ? 'signed_in_waiting_approval' : 'login_success',
      );
    } on FirebaseAuthException catch (error) {
      await _cleanup(signedIn);
      if (_cancelled(error.code)) {
        _setStatus(StatusRequest.none);
        return;
      }
      _setStatus(
        error.code == 'network-request-failed'
            ? StatusRequest.offlinefailure
            : StatusRequest.failure,
      );
      _error(_authMessage(error.code, googleFlow));
    } on FirebaseException catch (error) {
      await _cleanup(signedIn);
      _setStatus(
        error.code == 'permission-denied'
            ? StatusRequest.unauthorized
            : StatusRequest.serverfailure,
      );
      _error(
        error.code == 'permission-denied'
            ? 'login_permission_denied'
            : 'login_server_error',
      );
    } on FormatException {
      await _cleanup(signedIn);
      _setStatus(StatusRequest.failure);
      _error('login_profile_invalid');
    } catch (_) {
      await _cleanup(signedIn);
      _setStatus(StatusRequest.failure);
      _error(googleFlow ? 'google_sign_in_failed' : 'login_unknown_error');
    }
  }

  String _authMessage(String code, bool googleFlow) {
    switch (code) {
      case 'invalid-email':
        return 'login_invalid_email';
      case 'user-disabled':
        return 'login_user_disabled';
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
        return 'login_invalid_credentials';
      case 'network-request-failed':
      case 'network_error':
        return 'login_network_error';
      case 'too-many-requests':
        return 'login_too_many_requests';
      case 'popup-blocked':
        return 'google_popup_blocked';
      case 'account-exists-with-different-credential':
        return 'google_account_exists';
      default:
        return googleFlow ? 'google_sign_in_failed' : 'login_unknown_error';
    }
  }

  bool _cancelled(String code) =>
      code == 'popup-closed-by-user' ||
      code == 'cancelled-popup-request' ||
      code == 'sign_in_canceled';

  Future<void> _cleanup(bool signedIn) async {
    if (signedIn) {
      try {
        await _repository.signOut();
      } catch (_) {}
    }
    await AuthSession.clear(_myServices);
  }

  void _setStatus(StatusRequest status) {
    if (isClosed) return;
    statusRequest = status;
    update();
  }

  void _error(String key) => Get.snackbar(
    'login_error_title'.tr,
    key.tr,
    backgroundColor: AppColor.error,
    colorText: AppColor.surface,
    snackPosition: SnackPosition.BOTTOM,
  );

  void _success(String key) => Get.snackbar(
    'login_success_title'.tr,
    key.tr,
    backgroundColor: AppColor.success,
    colorText: AppColor.surface,
    snackPosition: SnackPosition.BOTTOM,
  );

  @override
  void onClose() {
    emailController.dispose();
    passwordController.dispose();
    super.onClose();
  }
}
