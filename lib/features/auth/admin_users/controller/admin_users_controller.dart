import 'dart:async';

import 'package:fatoora/core/class/statusrequest.dart';
import 'package:fatoora/core/constants/color.dart';
import 'package:fatoora/core/services/services.dart';
import 'package:fatoora/features/auth/data/models/app_user_model.dart';
import 'package:fatoora/features/auth/data/repositories/admin_auth_repository.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class AdminUsersController extends GetxController {
  AdminUsersController({
    required AdminAuthRepository repository,
    required MyServices myServices,
  }) : _repository = repository,
       _myServices = myServices;

  final AdminAuthRepository _repository;
  final MyServices _myServices;

  StatusRequest statusRequest = StatusRequest.loading;
  String loadErrorMessageKey = 'admin_users_load_error';
  List<AppUserModel> pendingUsers = const [];
  List<AppUserModel> salesReps = const [];
  String? activeActionUid;
  int selectedTab = 0;

  int get pendingCount => pendingUsers.length;

  String get companyId =>
      _myServices.sharedPreferences.getString('companyId') ?? 'default_company';

  @override
  void onReady() {
    super.onReady();
    loadUsers();
  }

  Future<void> loadUsers() async {
    statusRequest = StatusRequest.loading;
    loadErrorMessageKey = 'admin_users_load_error';
    update();
    try {
      final results = await Future.wait([
        _repository.fetchPendingUsers(),
        _repository.fetchSalesReps(),
      ]);
      pendingUsers = results[0];
      salesReps = results[1];
      statusRequest = StatusRequest.success;
    } catch (error) {
      statusRequest = _statusFor(error);
      loadErrorMessageKey = _messageFor(
        error,
        fallback: 'admin_users_load_error',
      );
    }
    if (!isClosed) update();
  }

  Future<void> refreshUsers() => loadUsers();

  void selectTab(int index) {
    selectedTab = index.clamp(0, 1).toInt();
    update();
  }

  Future<void> approveUser(AppUserModel user) async {
    await _runAction(
      user.uid,
      () => _repository.approveSalesRep(user.uid),
      successKey: 'admin_users_approved',
    );
  }

  Future<void> rejectUser(AppUserModel user) async {
    final confirmed = await _confirm(
      titleKey: 'admin_users_reject',
      bodyKey: 'admin_users_reject_confirm',
      danger: true,
    );
    if (!confirmed) return;
    await _runAction(
      user.uid,
      () => _repository.rejectSalesRep(user.uid),
      successKey: 'admin_users_rejected',
    );
  }

  Future<void> updateSalesRep(AppUserModel user, String name, String phone) {
    return _runAction(
      user.uid,
      () => _repository.updateSalesRep(uid: user.uid, name: name, phone: phone),
      successKey: 'admin_users_updated',
    );
  }

  Future<void> deactivateSalesRep(AppUserModel user) async {
    final confirmed = await _confirm(
      titleKey: 'admin_users_deactivate',
      bodyKey: 'admin_users_deactivate_confirm',
      danger: true,
    );
    if (!confirmed) return;
    await _runAction(
      user.uid,
      () => _repository.deactivateSalesRep(user.uid),
      successKey: 'admin_users_deactivated',
    );
  }

  Future<void> activateSalesRep(AppUserModel user) {
    return _runAction(
      user.uid,
      () => _repository.activateSalesRep(user.uid),
      successKey: 'admin_users_activated',
    );
  }

  Future<void> _runAction(
    String uid,
    Future<void> Function() action, {
    required String successKey,
  }) async {
    if (activeActionUid != null) return;
    activeActionUid = uid;
    update();
    try {
      await action();
      await loadUsers();
      _showSuccess(successKey);
    } catch (error) {
      _showError(_messageFor(error, fallback: 'admin_users_action_error'));
    } finally {
      activeActionUid = null;
      if (!isClosed) update();
    }
  }

  Future<bool> _confirm({
    required String titleKey,
    required String bodyKey,
    bool danger = false,
  }) async {
    final result = await Get.dialog<bool>(
      AlertDialog(
        title: Text(titleKey.tr),
        content: Text(bodyKey.tr),
        actions: [
          TextButton(
            onPressed: () => Get.back(result: false),
            child: Text('dashboard_cancel'.tr),
          ),
          FilledButton(
            onPressed: () => Get.back(result: true),
            style: danger
                ? FilledButton.styleFrom(backgroundColor: AppColor.error)
                : null,
            child: Text(titleKey.tr),
          ),
        ],
      ),
    );
    return result == true;
  }

  StatusRequest _statusFor(Object error) {
    if (error is TimeoutException) return StatusRequest.timeout;
    if (error is FirebaseAuthException && error.code == 'unauthenticated') {
      return StatusRequest.unauthorized;
    }
    if (error is FirebaseException) {
      return switch (error.code) {
        'permission-denied' || 'unauthenticated' => StatusRequest.unauthorized,
        'unavailable' => StatusRequest.offlinefailure,
        'deadline-exceeded' => StatusRequest.timeout,
        _ => StatusRequest.serverfailure,
      };
    }
    return StatusRequest.serverfailure;
  }

  String _messageFor(Object error, {required String fallback}) {
    if (error is TimeoutException) return 'admin_users_timeout_error';
    if (error is FormatException) return 'admin_users_invalid_data';
    if (error is FirebaseAuthException && error.code == 'unauthenticated') {
      return 'admin_users_session_error';
    }
    if (error is FirebaseException) {
      return switch (error.code) {
        'permission-denied' => 'admin_users_permission_error',
        'unauthenticated' => 'admin_users_session_error',
        'unavailable' => 'admin_users_offline_error',
        'deadline-exceeded' => 'admin_users_timeout_error',
        _ => fallback,
      };
    }
    return fallback;
  }

  void _showSuccess(String messageKey) {
    Get.snackbar(
      'admin_users'.tr,
      messageKey.tr,
      snackPosition: SnackPosition.BOTTOM,
      backgroundColor: AppColor.success,
      colorText: AppColor.surface,
    );
  }

  void _showError(String messageKey) {
    Get.snackbar(
      'admin_users'.tr,
      messageKey.tr,
      snackPosition: SnackPosition.BOTTOM,
      backgroundColor: AppColor.error,
      colorText: AppColor.surface,
    );
  }
}
