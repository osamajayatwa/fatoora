import 'package:fatoora/app/routes/app_routes.dart';
import 'package:fatoora/core/services/services.dart';
import 'package:fatoora/features/auth/data/models/app_user_model.dart';
import 'package:fatoora/features/shared/business/business_user_context.dart';

class AuthSession {
  const AuthSession._();

  static Future<void> save(MyServices services, AppUserModel user) async {
    final preferences = services.sharedPreferences;
    BusinessUserContextReader.invalidateCache();
    final step = user.isAdmin && user.canAccessApp
        ? '3'
        : user.isSalesRep && user.canAccessApp
        ? '2'
        : '1';
    await Future.wait([
      preferences.setString('uid', user.uid),
      preferences.setString('name', validDisplayName(user)),
      preferences.setString('email', user.email),
      preferences.setString('phone', user.phone),
      preferences.setString('photoUrl', user.photoUrl),
      preferences.setString('role', user.role),
      preferences.setString('approvalStatus', user.approvalStatus),
      preferences.setString('companyId', user.companyId),
      preferences.setBool('active', user.active),
      preferences.setString('step', step),
    ]);
  }

  static Future<void> clear(MyServices services) async {
    final preferences = services.sharedPreferences;
    BusinessUserContextReader.invalidateCache();
    await Future.wait([
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
      ])
        preferences.remove(key),
      preferences.remove('active'),
    ]);
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
