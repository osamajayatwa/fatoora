import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:fatoora/firebase_options.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
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
        );
        return FirebaseEnvironmentConfiguration(
          environment: environment,
          options: FirebaseOptions(
            apiKey: _stagingApiKey,
            appId: _stagingAppId,
            messagingSenderId: _stagingMessagingSenderId,
            projectId: _stagingProjectId,
            authDomain: _optional(_stagingAuthDomain),
            storageBucket: _stagingStorageBucket,
            measurementId: _optional(_stagingMeasurementId),
          ),
          useEmulators: false,
          emulatorHost: '',
        );
      case FatooraEnvironment.test:
        return FirebaseEnvironmentConfiguration(
          environment: environment,
          options: const FirebaseOptions(
            apiKey: 'fatoora-local-test-api-key',
            appId: '1:1234567890:web:fatoora-local-test',
            messagingSenderId: '1234567890',
            projectId: localTestProjectId,
            authDomain: '$localTestProjectId.firebaseapp.com',
            storageBucket: '$localTestProjectId.firebasestorage.app',
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
  }) {
    final missing = <String>[
      if (_isUnset(projectId)) 'FIREBASE_PROJECT_ID',
      if (_isUnset(projectConfirmation)) 'FIREBASE_PROJECT_ID_CONFIRM',
      if (_isUnset(apiKey)) 'FIREBASE_API_KEY',
      if (_isUnset(appId)) 'FIREBASE_APP_ID',
      if (_isUnset(messagingSenderId)) 'FIREBASE_MESSAGING_SENDER_ID',
      if (_isUnset(storageBucket)) 'FIREBASE_STORAGE_BUCKET',
    ];
    if (missing.isNotEmpty) {
      throw StateError(
        'Missing staging Firebase configuration: ${missing.join(', ')}.',
      );
    }
    if (projectId.trim() == productionProjectId) {
      throw StateError('Staging must not use the production Firebase project.');
    }
    if (projectConfirmation.trim() != projectId.trim()) {
      throw StateError(
        'FIREBASE_PROJECT_ID_CONFIRM must exactly match FIREBASE_PROJECT_ID.',
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
  final app = Firebase.apps.isEmpty
      ? await Firebase.initializeApp(options: configuration.options)
      : Firebase.app();
  if (app.options.projectId != configuration.options.projectId) {
    throw StateError(
      'Firebase is already initialized for ${app.options.projectId}; '
      'refusing to switch to ${configuration.options.projectId}.',
    );
  }
  if (!configuration.useEmulators) return;

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
