import 'package:fatoora/app/routes/app_routes.dart';
import 'package:fatoora/core/services/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class MyMiddleware extends GetMiddleware {
  @override
  int? get priority => 1;
  final MyServices myServices = Get.find<MyServices>();

  @override
  RouteSettings? redirect(String? route) {
    final session = _SessionSnapshot.fromServices(myServices);
    if (!session.hasCachedUser) return null;
    if (session.isRejected || session.isInactiveApproved) {
      return const RouteSettings(name: AppRoute.approvalRejected);
    }
    if (session.isPending) {
      return const RouteSettings(name: AppRoute.waitingApproval);
    }
    if (session.isApprovedAdmin) {
      return const RouteSettings(name: AppRoute.adminHome);
    }
    if (session.isApprovedSalesRep) {
      return const RouteSettings(name: AppRoute.home);
    }
    return null;
  }
}

class AdminMiddleware extends GetMiddleware {
  @override
  int? get priority => 1;

  final MyServices myServices = Get.find<MyServices>();

  @override
  RouteSettings? redirect(String? route) {
    if (FirebaseAuth.instance.currentUser == null) {
      return const RouteSettings(name: AppRoute.adminLogin);
    }
    final session = _SessionSnapshot.fromServices(myServices);
    if (session.isRejected || session.isInactiveApproved) {
      return const RouteSettings(name: AppRoute.approvalRejected);
    }
    if (session.isPending) {
      return const RouteSettings(name: AppRoute.waitingApproval);
    }
    if (session.isApprovedSalesRep) {
      return const RouteSettings(name: AppRoute.home);
    }
    if (!session.isApprovedAdmin) {
      return const RouteSettings(name: AppRoute.adminLogin);
    }
    return null;
  }
}

class ApprovedUserMiddleware extends GetMiddleware {
  @override
  int? get priority => 1;

  final MyServices myServices = Get.find<MyServices>();

  @override
  RouteSettings? redirect(String? route) {
    if (FirebaseAuth.instance.currentUser == null) {
      return const RouteSettings(name: AppRoute.userLogin);
    }
    final session = _SessionSnapshot.fromServices(myServices);
    if (session.isRejected || session.isInactiveApproved) {
      return const RouteSettings(name: AppRoute.approvalRejected);
    }
    if (session.isPending) {
      return const RouteSettings(name: AppRoute.waitingApproval);
    }
    if (session.isApprovedAdmin || session.isApprovedSalesRep) {
      return null;
    }
    return const RouteSettings(name: AppRoute.userLogin);
  }
}

class AdminSettingsMiddleware extends GetMiddleware {
  @override
  int? get priority => 2;

  final MyServices myServices = Get.find<MyServices>();

  @override
  RouteSettings? redirect(String? route) {
    if (FirebaseAuth.instance.currentUser == null) {
      return const RouteSettings(name: AppRoute.userLogin);
    }
    final session = _SessionSnapshot.fromServices(myServices);
    if (session.isRejected || session.isInactiveApproved) {
      return const RouteSettings(name: AppRoute.approvalRejected);
    }
    if (session.isPending) {
      return const RouteSettings(name: AppRoute.waitingApproval);
    }
    if (!session.isApprovedAdmin) {
      return const RouteSettings(name: AppRoute.settings);
    }
    return null;
  }
}

class SalesRepMiddleware extends GetMiddleware {
  @override
  int? get priority => 1;

  final MyServices myServices = Get.find<MyServices>();

  @override
  RouteSettings? redirect(String? route) {
    if (FirebaseAuth.instance.currentUser == null) {
      return const RouteSettings(name: AppRoute.userLogin);
    }
    final session = _SessionSnapshot.fromServices(myServices);
    if (session.isRejected || session.isInactiveApproved) {
      return const RouteSettings(name: AppRoute.approvalRejected);
    }
    if (session.isPending) {
      return const RouteSettings(name: AppRoute.waitingApproval);
    }
    if (session.isApprovedAdmin) {
      return const RouteSettings(name: AppRoute.adminHome);
    }
    if (!session.isApprovedSalesRep) {
      return const RouteSettings(name: AppRoute.userLogin);
    }
    return null;
  }
}

class _SessionSnapshot {
  const _SessionSnapshot({
    required this.uid,
    required this.role,
    required this.approvalStatus,
    required this.active,
  });

  final String uid;
  final String role;
  final String approvalStatus;
  final bool active;

  bool get hasCachedUser => uid.isNotEmpty;
  bool get isPending =>
      role == 'pending_sales_rep' || approvalStatus == 'pending';
  bool get isRejected => approvalStatus == 'rejected';
  bool get isInactiveApproved => approvalStatus == 'approved' && !active;
  bool get isApprovedAdmin =>
      role == 'admin' && active && approvalStatus == 'approved';
  bool get isApprovedSalesRep =>
      role == 'sales_rep' && active && approvalStatus == 'approved';

  factory _SessionSnapshot.fromServices(MyServices services) {
    final preferences = services.sharedPreferences;
    final step = preferences.getString('step') ?? '';
    final role = (preferences.getString('role') ?? '').trim().toLowerCase();
    final approvalStatus =
        (preferences.getString('approvalStatus') ??
                ((step == '2' || step == '3') ? 'approved' : ''))
            .trim()
            .toLowerCase();
    final active =
        preferences.getBool('active') ?? (step == '2' || step == '3');

    return _SessionSnapshot(
      uid: preferences.getString('uid') ?? '',
      role: role,
      approvalStatus: approvalStatus.isEmpty ? 'pending' : approvalStatus,
      active: active,
    );
  }
}
