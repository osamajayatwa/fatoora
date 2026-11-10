import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:fatoora/firebase_options.dart';
import 'package:fatoora/core/firebase/trusted_callable_client.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:flutter/foundation.dart';

enum FatooraEnvironment { production, staging, test }

class FirebaseEnvironmentConfiguration {
  const FirebaseEnvironmentConfiguration({
    required this.environment,
    required this.options,
    required this.useEmulators,
    required this.emulatorHost,
  });

  static const productionProjectId = 'fatoora-6b192';
  static const localTestProjectId = 'demo-fatoora-test';
  static const settlementTransportTesting = bool.fromEnvironment(
    'FATOORA_SETTLEMENT_TRANSPORT_TEST',
  );
  static String get configuredTestProjectId =>
      settlementTransportTesting ? 'demo-fatoora-phase2b7' : localTestProjectId;
  static const stagingProjectId = 'fatoora-original-staging';
  static const stagingProjectNumber = '5438538531';
  static const stagingAndroidAppId =
      '1:5438538531:android:560f7feecdb97bf5240296';
  static const stagingWebAppId = '1:5438538531:web:1fb5d6aac646d3b1240296';
  // Pin pairing without checking SDK API key values into the repository.
  static const _stagingApiKeyHashes = {
    stagingWebAppId:
        '57ad25d6f6537201fd4e3f1f7f3b383fb87731e3b01fd19eb3a3f20bb8579c55',
    stagingAndroidAppId:
        '20d4663137cc721e0e767177f9a1257ac3c879b4094bc0b4ed1b00ec557d62a1',
  };

  static const _environmentValue = String.fromEnvironment(
    'FATOORA_ENV',
    defaultValue: 'production',
  );
  static const _stagingProjectId = String.fromEnvironment(
    'FIREBASE_PROJECT_ID',
  );
  static const _stagingProjectConfirmation = String.fromEnvironment(
    'FIREBASE_PROJECT_ID_CONFIRM',
  );
  static const _stagingApiKey = String.fromEnvironment('FIREBASE_API_KEY');
  static const _stagingAppId = String.fromEnvironment('FIREBASE_APP_ID');
  static const _stagingMessagingSenderId = String.fromEnvironment(
    'FIREBASE_MESSAGING_SENDER_ID',
  );
  static const _stagingStorageBucket = String.fromEnvironment(
    'FIREBASE_STORAGE_BUCKET',
  );
  static const _stagingAuthDomain = String.fromEnvironment(
    'FIREBASE_AUTH_DOMAIN',
  );
  static const _stagingMeasurementId = String.fromEnvironment(
    'FIREBASE_MEASUREMENT_ID',
  );
  static const _emulatorHostOverride = String.fromEnvironment(
    'FIREBASE_EMULATOR_HOST',
  );

  final FatooraEnvironment environment;
  final FirebaseOptions options;
  final bool useEmulators;
  final String emulatorHost;

  bool get isProduction => environment == FatooraEnvironment.production;

  static FirebaseEnvironmentConfiguration current() {
    final environment = parseEnvironment(_environmentValue);
    if (settlementTransportTesting && environment != FatooraEnvironment.test) {
      throw StateError(
        'Settlement transport testing requires FATOORA_ENV=test',
      );
    }
    switch (environment) {
      case FatooraEnvironment.production:
        return FirebaseEnvironmentConfiguration(
          environment: environment,
          options: DefaultFirebaseOptions.currentPlatform,
          useEmulators: false,
          emulatorHost: '',
        );
      case FatooraEnvironment.staging:
        validateStagingConfiguration(
          projectId: _stagingProjectId,
          projectConfirmation: _stagingProjectConfirmation,
          apiKey: _stagingApiKey,
          appId: _stagingAppId,
          messagingSenderId: _stagingMessagingSenderId,
          storageBucket: _stagingStorageBucket,
          authDomain: _stagingAuthDomain,
        );
        return FirebaseEnvironmentConfiguration(
          environment: environment,
          options: FirebaseOptions(
            apiKey: _stagingApiKey,
            appId: _stagingAppId,
            messagingSenderId: _stagingMessagingSenderId,
            projectId: _stagingProjectId,
            authDomain: _optional(_stagingAuthDomain),
            storageBucket: _optional(_stagingStorageBucket),
            measurementId: _optional(_stagingMeasurementId),
          ),
          useEmulators: false,
          emulatorHost: '',
        );
      case FatooraEnvironment.test:
        return FirebaseEnvironmentConfiguration(
          environment: environment,
          options: FirebaseOptions(
            apiKey: 'fatoora-local-test-api-key',
            appId: '1:1234567890:web:fatoora-local-test',
            messagingSenderId: '1234567890',
            projectId: configuredTestProjectId,
            authDomain: '$configuredTestProjectId.firebaseapp.com',
            storageBucket: '$configuredTestProjectId.firebasestorage.app',
          ),
          useEmulators: true,
          emulatorHost: _emulatorHostOverride.trim().isNotEmpty
              ? _emulatorHostOverride.trim()
              : defaultEmulatorHost(),
        );
    }
  }

  static FatooraEnvironment parseEnvironment(String value) {
    switch (value.trim().toLowerCase()) {
      case 'production':
        return FatooraEnvironment.production;
      case 'staging':
        return FatooraEnvironment.staging;
      case 'test':
        return FatooraEnvironment.test;
      default:
        throw StateError(
          'Unsupported FATOORA_ENV "$value". '
          'Expected production, staging, or test.',
        );
    }
  }

  @visibleForTesting
  static void validateStagingConfiguration({
    required String projectId,
    required String projectConfirmation,
    required String apiKey,
    required String appId,
    required String messagingSenderId,
    required String storageBucket,
    String authDomain = '',
  }) {
    final missing = <String>[
      if (_isUnset(projectId)) 'FIREBASE_PROJECT_ID',
      if (_isUnset(projectConfirmation)) 'FIREBASE_PROJECT_ID_CONFIRM',
      if (_isUnset(apiKey)) 'FIREBASE_API_KEY',
      if (_isUnset(appId)) 'FIREBASE_APP_ID',
      if (_isUnset(messagingSenderId)) 'FIREBASE_MESSAGING_SENDER_ID',
    ];
    if (missing.isNotEmpty) {
      throw StateError(
        'Missing staging Firebase configuration: ${missing.join(', ')}.',
      );
    }
    if (projectId.trim() != stagingProjectId) {
      throw StateError(
        'Staging requires the approved original staging project.',
      );
    }
    if (projectConfirmation.trim() != projectId.trim()) {
      throw StateError(
        'FIREBASE_PROJECT_ID_CONFIRM must exactly match FIREBASE_PROJECT_ID.',
      );
    }
    if (messagingSenderId.trim() != stagingProjectNumber ||
        ![stagingAndroidAppId, stagingWebAppId].contains(appId.trim())) {
      throw StateError(
        'Staging app registration and project number must match.',
      );
    }
    if (storageBucket.trim().isNotEmpty &&
        storageBucket.trim() != '$stagingProjectId.appspot.com' &&
        storageBucket.trim() != '$stagingProjectId.firebasestorage.app') {
      throw StateError('Staging storage metadata belongs to another project.');
    }
    if (authDomain.trim().isNotEmpty &&
        authDomain.trim() != '$stagingProjectId.firebaseapp.com' &&
        authDomain.trim() != '$stagingProjectId.web.app') {
      throw StateError('Staging Auth domain belongs to another project.');
    }
    if (storageBucket.trim() == '$productionProjectId.appspot.com' ||
        storageBucket.trim() == '$productionProjectId.firebasestorage.app' ||
        authDomain.trim() == '$productionProjectId.firebaseapp.com' ||
        authDomain.trim() == '$productionProjectId.web.app') {
      throw StateError('Staging must not use production Firebase resources.');
    }
    const productionOptions = [
      DefaultFirebaseOptions.web,
      DefaultFirebaseOptions.android,
      DefaultFirebaseOptions.ios,
      DefaultFirebaseOptions.macos,
      DefaultFirebaseOptions.windows,
    ];
    if (productionOptions.any(
      (options) =>
          apiKey.trim() == options.apiKey ||
          appId.trim() == options.appId ||
          messagingSenderId.trim() == options.messagingSenderId,
    )) {
      throw StateError('Staging must use its own Firebase app registration.');
    }
    if (sha256.convert(utf8.encode(apiKey)).toString() !=
        _stagingApiKeyHashes[appId.trim()]) {
      throw StateError('Staging API key and app registration do not match.');
    }
  }

  /// Validate even explicitly constructed configurations before SDK startup.
  void validateRuntimeTarget() {
    if (TrustedCallableClient.settlementStagingPilot &&
        (environment != FatooraEnvironment.staging ||
            useEmulators ||
            settlementTransportTesting ||
            options.appId != (kIsWeb ? stagingWebAppId : stagingAndroidAppId) ||
            (!kIsWeb && defaultTargetPlatform != TargetPlatform.android))) {
      throw StateError(
        'Settlement staging pilot requires the pinned staging app',
      );
    }
    if (TrustedCallableClient.settlementStagingPilot &&
        kIsWeb &&
        !RegExp(r'^[A-Za-z0-9_-]{30,128}$').hasMatch(
          const String.fromEnvironment('FATOORA_STAGING_APPCHECK_SITE_KEY'),
        )) {
      throw StateError('Explicit staging App Check site key required');
    }
    if (settlementTransportTesting && !kDebugMode) {
      throw StateError('Settlement transport is disabled in release builds');
    }
    if (settlementTransportTesting &&
        !['127.0.0.1', 'localhost', '10.0.2.2'].contains(emulatorHost)) {
      throw StateError(
        'Settlement testing requires an explicit local emulator host',
      );
    }
    if (environment == FatooraEnvironment.test) {
      if (!useEmulators ||
          options.projectId != configuredTestProjectId ||
          emulatorHost.trim().isEmpty ||
          emulatorHost.contains('://') ||
          emulatorHost.contains('/')) {
        throw StateError('Local tests require the demo project and emulators.');
      }
    } else if (useEmulators ||
        (environment == FatooraEnvironment.production &&
            options.projectId != productionProjectId) ||
        (environment == FatooraEnvironment.staging &&
            options.projectId != stagingProjectId)) {
      throw StateError('Firebase environment and target do not agree.');
    }
    if (environment == FatooraEnvironment.staging) {
      validateStagingConfiguration(
        projectId: options.projectId,
        projectConfirmation: options.projectId,
        apiKey: options.apiKey,
        appId: options.appId,
        messagingSenderId: options.messagingSenderId,
        storageBucket: options.storageBucket ?? '',
        authDomain: options.authDomain ?? '',
      );
    }
  }

  static String defaultEmulatorHost() {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      return '10.0.2.2';
    }
    return '127.0.0.1';
  }

  static String? _optional(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  static bool _isUnset(String value) {
    final normalized = value.trim().toLowerCase();
    return normalized.isEmpty || normalized.startsWith('replace-with-');
  }
}

Future<void> initializeFirebaseForEnvironment(
  FirebaseEnvironmentConfiguration configuration,
) async {
  configuration.validateRuntimeTarget();
  final app = Firebase.apps.isEmpty
      ? await Firebase.initializeApp(options: configuration.options)
      : Firebase.app();
  if (app.options.projectId != configuration.options.projectId) {
    throw StateError(
      'Firebase is already initialized for ${app.options.projectId}; '
      'refusing to switch to ${configuration.options.projectId}.',
    );
  }
  if (!configuration.useEmulators) {
    if (TrustedCallableClient.settlementStagingPilot) {
      await FirebaseAppCheck.instanceFor(app: app).activate(
        webProvider: ReCaptchaEnterpriseProvider(
          const String.fromEnvironment('FATOORA_STAGING_APPCHECK_SITE_KEY'),
        ),
        androidProvider: AndroidProvider.playIntegrity,
      );
      TrustedCallableClient.markSettlementStagingConfigured(app);
    }
    return;
  }
  if (FirebaseEnvironmentConfiguration.settlementTransportTesting) {
    FirebaseFirestore.instanceFor(
      app: app,
    ).useFirestoreEmulator(configuration.emulatorHost, 8192);
    await FirebaseAuth.instanceFor(
      app: app,
    ).useAuthEmulator(configuration.emulatorHost, 9098);
    FirebaseFunctions.instanceFor(
      app: app,
      region: 'us-central1',
    ).useFunctionsEmulator(configuration.emulatorHost, 5005);
    await TrustedCallableClient.markSettlementEmulatorConfigured(
      app,
      configuration.emulatorHost,
    );
    return;
  }

  FirebaseFirestore.instanceFor(
    app: app,
  ).useFirestoreEmulator(configuration.emulatorHost, 8080);
  await FirebaseAuth.instanceFor(
    app: app,
  ).useAuthEmulator(configuration.emulatorHost, 9099);
  FirebaseFunctions.instanceFor(
    app: app,
    region: 'us-central1',
  ).useFunctionsEmulator(configuration.emulatorHost, 5001);
}
