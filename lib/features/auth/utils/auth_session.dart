import 'package:fatoora/app/routes/app_routes.dart';
import 'package:fatoora/core/services/services.dart';
import 'package:fatoora/features/auth/data/models/app_user_model.dart';

class AuthSession {
  const AuthSession._();

  static Future<void> save(MyServices services, AppUserModel user) async {
    final preferences = services.sharedPreferences;
    await preferences.setString('uid', user.uid);
    await preferences.setString('name', validDisplayName(user));
    await preferences.setString('email', user.email);
    await preferences.setString('phone', user.phone);
    await preferences.setString('photoUrl', user.photoUrl);
    await preferences.setString('role', user.role);
    await preferences.setString('approvalStatus', user.approvalStatus);
    await preferences.setString('companyId', user.companyId);
    await preferences.setBool('active', user.active);

    if (user.isAdmin && user.canAccessApp) {
      await preferences.setString('step', '3');
    } else if (user.isSalesRep && user.canAccessApp) {
      await preferences.setString('step', '2');
    } else {
      await preferences.setString('step', '1');
    }
  }

  static Future<void> clear(MyServices services) async {
    final preferences = services.sharedPreferences;
    for (final key in [
      'step',
      'uid',
      'role',
      'name',
      'email',
      'phone',
      'photoUrl',
      'approvalStatus',
      'companyId',
    ]) {
      await preferences.remove(key);
    }
    await preferences.remove('active');
  }

  static String routeForProfile(AppUserModel user) {
    if (user.isRejected) return AppRoute.approvalRejected;
    if (user.isPending || !user.isApproved) return AppRoute.waitingApproval;
    if (!user.active) return AppRoute.approvalRejected;
    if (user.isAdmin) return AppRoute.adminHome;
    if (user.isSalesRep) return AppRoute.home;
    return AppRoute.approvalRejected;
  }

  static String validDisplayName(AppUserModel user) {
    final name = user.name.trim();
    if (name.isNotEmpty && name.toLowerCase() != 'undefined') return name;
    final emailPrefix = user.email.split('@').first.trim();
    if (emailPrefix.isNotEmpty && emailPrefix.toLowerCase() != 'undefined') {
      return emailPrefix;
    }
    return 'User';
  }

  static String cachedDisplayName(MyServices services) {
    final preferences = services.sharedPreferences;
    final name = (preferences.getString('name') ?? '').trim();
    if (name.isNotEmpty && name.toLowerCase() != 'undefined') return name;
    final email = preferences.getString('email') ?? '';
    final emailPrefix = email.split('@').first.trim();
    if (emailPrefix.isNotEmpty && emailPrefix.toLowerCase() != 'undefined') {
      return emailPrefix;
    }
    return 'User';
  }
}
