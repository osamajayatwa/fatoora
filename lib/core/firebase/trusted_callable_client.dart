import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
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
  static const Duration _authRestorationTimeout = Duration(seconds: 10);

  final FirebaseApp _app;
  final FirebaseAuth _auth;
  final FirebaseFunctions _functions;

  Future<HttpsCallableResult<T>> callAuthenticated<T>(
    String functionName,
    Map<String, dynamic> payload,
  ) async {
    final user = await _restoredUser();
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
