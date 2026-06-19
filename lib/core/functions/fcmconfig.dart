import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'package:get/get.dart';

/// Background message handler
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await NotificationService.initializeFlutterLocal();
  await NotificationService.instance._showNotification(message);
}

/// A singleton service to manage FCM and local notifications
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  // Firebase Messaging instance
  final FirebaseMessaging _fcm = FirebaseMessaging.instance;

  // Local notifications plugin
  static final FlutterLocalNotificationsPlugin _localNotif =
      FlutterLocalNotificationsPlugin();
  static bool _flutterLocalInitialized = false;

  /// Initialize FCM, local notifications and handlers
  Future<void> init() async {
    // Required for Firebase
    await Firebase.initializeApp();

    // Background handler
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    // Request and handle permission
    await _requestPermission();

    // Setup local notifications
    await setupFlutterLocalNotifications();

    // Setup FCM handlers
    _registerFCMHandlers();

    // Optionally subscribe to topics
    // await _fcm.subscribeToTopic('news');

    // Get & log the token
    final token = await _fcm.getToken();
    print('[FCM] Token: $token');
  }

  /// Request notification permissions from user
  Future<void> _requestPermission() async {
    NotificationSettings settings = await _fcm.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
      announcement: false,
      carPlay: false,
      criticalAlert: false,
    );
    print('[FCM] Permission granted: ${settings.authorizationStatus}');
  }

  /// Setup local notifications plugin and channel
  Future<void> setupFlutterLocalNotifications() async {
    if (_flutterLocalInitialized) return;

    const channel = AndroidNotificationChannel(
      'high_importance_channel',
      'High Importance Notifications',
      description: 'Used for important notifications',
      importance: Importance.high,
    );

    // Create channel for Android
    await _localNotif
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);

    // Initialization settings
    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );
    final iosSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    final initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _localNotif.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onSelectNotification,
    );

    _flutterLocalInitialized = true;
  }

  /// Static helper for background isolate
  static Future<void> initializeFlutterLocal() async {
    await instance.setupFlutterLocalNotifications();
  }

  /// Register foreground, background & click handlers
  void _registerFCMHandlers() {
    // Foreground: display in-app & local notification
    FirebaseMessaging.onMessage.listen((message) {
      print('[FCM] Received (foreground): ${message.notification?.title}');
      _showNotification(message);
    });

    // When tapping on notification & app in background
    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      print('[FCM] Notification clicked!');
      _handleMessageTap(message);
    });

    // When app launched via notification
    _fcm.getInitialMessage().then((message) {
      if (message != null) _handleMessageTap(message);
    });
  }

  /// Show a local notification
  Future<void> _showNotification(RemoteMessage message) async {
    final notif = message.notification;
    final android = message.notification?.android;
    if (notif == null || android == null) return;

    await _localNotif.show(
      notif.hashCode,
      notif.title,
      notif.body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          'high_importance_channel',
          'High Importance',
          channelDescription: 'Important notifications',
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
      payload: _encodePayload(message.data),
    );
  }

  /// Encode custom data for payload
  String _encodePayload(Map<String, dynamic> data) {
    return data.isNotEmpty ? data.toString() : '';
  }

  /// Handle notification taps
  void _onSelectNotification(NotificationResponse response) {
    if (response.payload == null || response.payload!.isEmpty) return;
    final data = _parsePayload(response.payload!);
    _navigate(data);
  }

  void _handleMessageTap(RemoteMessage message) {
    _navigate(message.data);
  }

  Map<String, dynamic> _parsePayload(String payload) {
    try {
      // crude parsing: expects {key: value, ...}
      final cleaned = payload.replaceAll(RegExp(r'[{} ]'), '');
      return Map.fromEntries(
        cleaned.split(',').map((pair) {
          final kv = pair.split(':');
          return MapEntry(kv[0], kv[1]);
        }),
      );
    } catch (_) {
      return {};
    }
  }

  /// Navigate based on custom data (e.g., open chat)
  void _navigate(Map<String, dynamic> data) {
    final type = data['type'];
    if (type == 'chat' && data.containsKey('chatId')) {
      Get.toNamed('/chat', arguments: {'id': data['chatId']});
    }
    // Add more routing logic here
  }
}
