import 'package:fatoora/core/firebase/firebase_environment.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:fatoora/firebase_options.dart';

void main() {
  if (const String.fromEnvironment('FATOORA_ENV') == 'test') {
    test('the local launch file selects demo project and emulator routing', () {
      final configuration = FirebaseEnvironmentConfiguration.current();
      configuration.validateRuntimeTarget();
      expect(configuration.environment, FatooraEnvironment.test);
      expect(configuration.options.projectId, 'demo-fatoora-test');
      expect(configuration.useEmulators, isTrue);
      expect(configuration.emulatorHost, '127.0.0.1');
      expect(configuration.isProduction, isFalse);
    });
  }
  group('Firebase environment selection', () {
    test('production remains the default environment', () {
      expect(
        FirebaseEnvironmentConfiguration.parseEnvironment('production'),
        FatooraEnvironment.production,
      );
      expect(
        FirebaseEnvironmentConfiguration.productionProjectId,
        'fatoora-6b192',
      );
    });

    test('staging and local test environments are explicit', () {
      expect(
        FirebaseEnvironmentConfiguration.parseEnvironment('staging'),
        FatooraEnvironment.staging,
      );
      expect(
        FirebaseEnvironmentConfiguration.parseEnvironment('test'),
        FatooraEnvironment.test,
      );
      expect(
        FirebaseEnvironmentConfiguration.localTestProjectId,
        allOf(
          startsWith('demo-'),
          isNot(FirebaseEnvironmentConfiguration.productionProjectId),
        ),
      );
    });

    test('unknown environment fails closed', () {
      expect(
        () => FirebaseEnvironmentConfiguration.parseEnvironment('preview'),
        throwsStateError,
      );
    });
  });

  group('Remote staging safeguards', () {
    test(
      'rejects production app identifiers paired with a staging project label',
      () {
        expect(
          () => FirebaseEnvironmentConfiguration.validateStagingConfiguration(
            projectId: 'fatoora-staging-example',
            projectConfirmation: 'fatoora-staging-example',
            apiKey: DefaultFirebaseOptions.web.apiKey,
            appId: 'staging-app',
            messagingSenderId: 'staging-sender',
            storageBucket: 'staging-bucket',
          ),
          throwsStateError,
        );
      },
    );
    for (final bucket in [
      'fatoora-6b192.appspot.com',
      'fatoora-6b192.firebasestorage.app',
    ]) {
      test('rejects production storage $bucket in staging', () {
        expect(
          () => FirebaseEnvironmentConfiguration.validateStagingConfiguration(
            projectId: 'fatoora-staging-example',
            projectConfirmation: 'fatoora-staging-example',
            apiKey: 'api-key',
            appId: 'app-id',
            messagingSenderId: 'sender-id',
            storageBucket: bucket,
          ),
          throwsStateError,
        );
      });
    }
    test('rejects production auth domain in staging', () {
      expect(
        () => FirebaseEnvironmentConfiguration.validateStagingConfiguration(
          projectId: 'fatoora-staging-example',
          projectConfirmation: 'fatoora-staging-example',
          apiKey: 'api-key',
          appId: 'app-id',
          messagingSenderId: 'sender-id',
          storageBucket: 'staging-bucket',
          authDomain: 'fatoora-6b192.firebaseapp.com',
        ),
        throwsStateError,
      );
    });
    test('rejects the production project', () {
      expect(
        () => FirebaseEnvironmentConfiguration.validateStagingConfiguration(
          projectId: FirebaseEnvironmentConfiguration.productionProjectId,
          projectConfirmation:
              FirebaseEnvironmentConfiguration.productionProjectId,
          apiKey: 'api-key',
          appId: 'app-id',
          messagingSenderId: 'sender-id',
          storageBucket: 'bucket',
        ),
        throwsStateError,
      );
    });

    test('requires explicit project confirmation', () {
      expect(
        () => FirebaseEnvironmentConfiguration.validateStagingConfiguration(
          projectId: 'fatoora-staging-example',
          projectConfirmation: 'another-project',
          apiKey: 'api-key',
          appId: 'app-id',
          messagingSenderId: 'sender-id',
          storageBucket: 'bucket',
        ),
        throwsStateError,
      );
    });

    test('requires every Firebase core value', () {
      expect(
        () => FirebaseEnvironmentConfiguration.validateStagingConfiguration(
          projectId: 'fatoora-staging-example',
          projectConfirmation: 'fatoora-staging-example',
          apiKey: '',
          appId: '',
          messagingSenderId: '',
          storageBucket: '',
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            allOf(
              contains('FIREBASE_API_KEY'),
              contains('FIREBASE_APP_ID'),
              contains('FIREBASE_MESSAGING_SENDER_ID'),
              contains('FIREBASE_STORAGE_BUCKET'),
            ),
          ),
        ),
      );
    });

    test('rejects unchanged example placeholders', () {
      expect(
        () => FirebaseEnvironmentConfiguration.validateStagingConfiguration(
          projectId: 'replace-with-staging-project-id',
          projectConfirmation: 'replace-with-staging-project-id',
          apiKey: 'replace-with-staging-api-key',
          appId: 'replace-with-staging-app-id',
          messagingSenderId: 'replace-with-staging-sender-id',
          storageBucket: 'replace-with-staging-storage-bucket',
        ),
        throwsStateError,
      );
    });

    test('accepts a complete confirmed non-production project', () {
      expect(
        () => FirebaseEnvironmentConfiguration.validateStagingConfiguration(
          projectId: 'fatoora-staging-example',
          projectConfirmation: 'fatoora-staging-example',
          apiKey: 'api-key',
          appId: 'app-id',
          messagingSenderId: 'sender-id',
          storageBucket: 'bucket',
        ),
        returnsNormally,
      );
    });
  });

  test(
    'local test configuration requires both demo namespace and emulators',
    () {
      for (final configuration in [
        FirebaseEnvironmentConfiguration(
          environment: FatooraEnvironment.test,
          options: const FirebaseOptions(
            apiKey: 'test',
            appId: 'test',
            messagingSenderId: 'test',
            projectId: 'fatoora-6b192',
          ),
          useEmulators: true,
          emulatorHost: '127.0.0.1',
        ),
        FirebaseEnvironmentConfiguration(
          environment: FatooraEnvironment.test,
          options: const FirebaseOptions(
            apiKey: 'test',
            appId: 'test',
            messagingSenderId: 'test',
            projectId: 'demo-fatoora-test',
          ),
          useEmulators: false,
          emulatorHost: '127.0.0.1',
        ),
        FirebaseEnvironmentConfiguration(
          environment: FatooraEnvironment.test,
          options: const FirebaseOptions(
            apiKey: 'test',
            appId: 'test',
            messagingSenderId: 'test',
            projectId: 'demo-fatoora-test',
          ),
          useEmulators: true,
          emulatorHost: 'https://example.com',
        ),
      ]) {
        expect(configuration.validateRuntimeTarget, throwsStateError);
      }
    },
  );
}
