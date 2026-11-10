import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:flutter/foundation.dart';

/// Invokes trusted callables only after Auth restoration and token refresh.
class TrustedCallableClient {
  TrustedCallableClient._({
    required FirebaseApp app,
    required FirebaseAuth auth,
    required FirebaseFunctions functions,
  }) : _app = app,
       _auth = auth,
       _functions = functions {
    if (_auth.app.name != _app.name || _functions.app.name != _app.name) {
      throw StateError(
        'Firebase Auth and Functions must use the same Firebase app.',
      );
    }
  }

  factory TrustedCallableClient.forDefaultApp({
    FirebaseAuth? firebaseAuth,
    FirebaseFunctions? functions,
  }) {
    final app = Firebase.app();
    return TrustedCallableClient._(
      app: app,
      auth: firebaseAuth ?? FirebaseAuth.instanceFor(app: app),
      functions:
          functions ?? FirebaseFunctions.instanceFor(app: app, region: region),
    );
  }

  static const String region = 'us-central1';
  static final Set<String> _settlementEmulatorApps = {};
  static final Set<String> _settlementStagingApps = {};
  static const settlementStagingPilot = bool.fromEnvironment(
    'FATOORA_SETTLEMENT_STAGING_PILOT',
  );

  /// Called only after the central bootstrap validates the pinned registration
  /// and activates the real App Check provider. No debug provider or fallback.
  static void markSettlementStagingConfigured(FirebaseApp app) {
    if (!settlementStagingPilot ||
        const String.fromEnvironment('FATOORA_ENV') != 'staging' ||
        const bool.fromEnvironment('FATOORA_SETTLEMENT_TRANSPORT_TEST') ||
        app.name != '[DEFAULT]' ||
        app.options.projectId != 'fatoora-original-staging' ||
        app.options.messagingSenderId != '5438538531' ||
        ![
          '1:5438538531:web:1fb5d6aac646d3b1240296',
          '1:5438538531:android:560f7feecdb97bf5240296',
        ].contains(app.options.appId)) {
      throw StateError('Settlement staging target is not approved');
    }
    _settlementStagingApps.add(app.name);
  }

  bool get isSettlementStaging =>
      settlementStagingPilot &&
      const String.fromEnvironment('FATOORA_ENV') == 'staging' &&
      _app.options.projectId == 'fatoora-original-staging' &&
      _settlementStagingApps.contains(_app.name);

  /// Explicit opt-in bootstrap for the isolated settlement acceptance target.
  /// No cloud configuration, existing credentials or production fallback.
  static Future<void> markSettlementEmulatorConfigured(
    FirebaseApp app,
    String host,
  ) async {
    if (!kDebugMode ||
        !const bool.fromEnvironment('FATOORA_SETTLEMENT_TRANSPORT_TEST') ||
        app.options.projectId != 'demo-fatoora-phase2b7' ||
        !['127.0.0.1', '10.0.2.2', 'localhost'].contains(host) ||
        app.name != '[DEFAULT]') {
      throw StateError(
        'Settlement transport requires explicit isolated emulator testing',
      );
    }
    _settlementEmulatorApps.add(app.name);
  }

  bool get isSettlementEmulator =>
      kDebugMode &&
      const bool.fromEnvironment('FATOORA_SETTLEMENT_TRANSPORT_TEST') &&
      _app.options.projectId == 'demo-fatoora-phase2b7' &&
      _settlementEmulatorApps.contains(_app.name);
  String get projectId => _app.options.projectId;
  String get appName => _app.name;
  static const Duration _authRestorationTimeout = Duration(seconds: 10);

  final FirebaseApp _app;
  final FirebaseAuth _auth;
  final FirebaseFunctions _functions;

  Future<HttpsCallableResult<T>> callAuthenticated<T>(
    String functionName,
    Map<String, dynamic> payload,
  ) async {
    final user = await _restoredUser();
    if (functionName == 'getSettlementBreakdown' && isSettlementStaging) {
      try {
        // The SDK refreshes expired attestations. Avoid a paid attestation for
        // every page; the server still validates App Check and current access.
        final attestation = await FirebaseAppCheck.instanceFor(
          app: _app,
        ).getToken().timeout(_authRestorationTimeout);
        if (attestation == null || attestation.isEmpty) {
          throw FirebaseAuthException(code: 'permission-denied');
        }
      } catch (_) {
        throw FirebaseAuthException(code: 'permission-denied');
      }
    }
    var tokenRefreshSucceeded = false;
    try {
      final token = await user
          .getIdToken(true)
          .timeout(_authRestorationTimeout);
      tokenRefreshSucceeded = token != null && token.isNotEmpty;
      if (!tokenRefreshSucceeded) {
        throw FirebaseAuthException(
          code: 'unauthenticated',
          message: 'Firebase Auth did not provide an ID token.',
        );
      }
    } finally {
      _logAuthenticationState(
        functionName: functionName,
        uid: user.uid,
        tokenRefreshSucceeded: tokenRefreshSucceeded,
      );
    }

    return _functions.httpsCallable(functionName).call<T>(payload);
  }

  Future<User> _restoredUser() async {
    final current = _auth.currentUser;
    if (current != null) return current;

    try {
      return await _auth
          .authStateChanges()
          .where((candidate) => candidate != null)
          .cast<User>()
          .first
          .timeout(_authRestorationTimeout);
    } on TimeoutException {
      throw FirebaseAuthException(
        code: 'unauthenticated',
        message: 'Firebase Auth restoration did not complete.',
      );
    }
  }

  void _logAuthenticationState({
    required String functionName,
    required String uid,
    required bool tokenRefreshSucceeded,
  }) {
    debugPrint(
      '[TrustedCallableAuth] function=$functionName uid=$uid '
      'app=${_app.name} project=${_app.options.projectId} region=$region '
      'tokenRefresh=${tokenRefreshSucceeded ? 'succeeded' : 'failed'}',
    );
  }
}
