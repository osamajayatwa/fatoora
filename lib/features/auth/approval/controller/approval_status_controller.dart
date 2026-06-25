import 'package:fatoora/app/routes/app_routes.dart';
import 'package:fatoora/core/services/services.dart';
import 'package:fatoora/features/auth/utils/auth_session.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:get/get.dart';

class ApprovalStatusController extends GetxController {
  ApprovalStatusController({required MyServices myServices})
    : _myServices = myServices;

  final MyServices _myServices;

  bool isLoggingOut = false;

  String get name => AuthSession.cachedDisplayName(_myServices);
  String get email => _myServices.sharedPreferences.getString('email') ?? '';
  bool get isInactiveApproved {
    final preferences = _myServices.sharedPreferences;
    return preferences.getString('approvalStatus') == 'approved' &&
        preferences.getBool('active') == false;
  }

  Future<void> logout() async {
    if (isLoggingOut) return;
    isLoggingOut = true;
    update();
    try {
      await FirebaseAuth.instance.signOut();
    } catch (_) {
    }
    await AuthSession.clear(_myServices);
    await _myServices.secureStorage.deleteAll();
    isLoggingOut = false;
    if (!isClosed) update();
    Get.offAllNamed(AppRoute.userLogin);
  }
}
