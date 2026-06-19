import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:firebase_messaging/firebase_messaging.dart';


class MyServices extends GetxService {
  late SharedPreferences sharedPreferences;
  late FlutterSecureStorage secureStorage;

  Future<MyServices> init() async {
    WidgetsFlutterBinding.ensureInitialized();
    //await Firebase.initializeApp();

    sharedPreferences = await SharedPreferences.getInstance();
    secureStorage = const FlutterSecureStorage();

    return this;
  }
}

class FirebaseService extends GetxService {
  late FlutterSecureStorage secureStorage;

  @override
  void onInit() {
    final myServices = Get.find<MyServices>();
    secureStorage = myServices.secureStorage;
    _setupTokenListeners();
    super.onInit();
  }

  void _setupTokenListeners() {
    FirebaseMessaging.instance.onTokenRefresh.listen((newToken) async {
      print("Refreshed FCM Token: $newToken");
      await secureStorage.write(key: "fcmToken", value: newToken);

      final myServices = Get.find<MyServices>();
      if (myServices.sharedPreferences.containsKey("manager_id")) {
        await _updateFcmTokenOnServer(newToken);
      }
    });
  }

  Future<void> _updateFcmTokenOnServer(String newToken) async {
    try {
      final myServices = Get.find<MyServices>();
      final parentId = myServices.sharedPreferences.getString("id");
      if (parentId == null) return;



      print("Simulated FCM token update on server for user $parentId with token $newToken");
    } catch (e) {
      print("Error updating FCM token: $e");
    }
  }
}


Future<void> initialServices() async {
  await Get.putAsync(() => MyServices().init());
 // Get.put(FirebaseService());
 
  //  await NotificationService.instance.init();
}
