import 'package:fatoora/core/firebase/firebase_environment.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:fatoora/firebase_options.dart';

void main() {
  if (const String.fromEnvironment('FATOORA_ENV') == 'staging') {
    test('the actual staging launch file selects its pinned registration', () {
      final configuration = FirebaseEnvironmentConfiguration.current();
      configuration.validateRuntimeTarget();
      expect(configuration.environment, FatooraEnvironment.staging);
      expect(
        configuration.options.projectId,
        FirebaseEnvironmentConfiguration.stagingProjectId,
      );
      expect(
        configuration.options.messagingSenderId,
        FirebaseEnvironmentConfiguration.stagingProjectNumber,
      );
      expect(configuration.useEmulators, isFalse);
      FirebaseEnvironmentConfiguration.validateStagingConfiguration(
        projectId: configuration.options.projectId,
        projectConfirmation: configuration.options.projectId,
        apiKey: configuration.options.apiKey,
        appId: configuration.options.appId,
        messagingSenderId: configuration.options.messagingSenderId,
        storageBucket: '',
      );
    });
  }
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
            projectId: FirebaseEnvironmentConfiguration.stagingProjectId,
            projectConfirmation:
                FirebaseEnvironmentConfiguration.stagingProjectId,
            apiKey: DefaultFirebaseOptions.web.apiKey,
            appId: FirebaseEnvironmentConfiguration.stagingWebAppId,
            messagingSenderId:
                FirebaseEnvironmentConfiguration.stagingProjectNumber,
            storageBucket: '',
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
            projectId: FirebaseEnvironmentConfiguration.stagingProjectId,
            projectConfirmation:
                FirebaseEnvironmentConfiguration.stagingProjectId,
            apiKey: 'api-key',
            appId: FirebaseEnvironmentConfiguration.stagingWebAppId,
            messagingSenderId:
                FirebaseEnvironmentConfiguration.stagingProjectNumber,
            storageBucket: bucket,
          ),
          throwsStateError,
        );
      });
    }
    test('rejects production auth domain in staging', () {
      expect(
        () => FirebaseEnvironmentConfiguration.validateStagingConfiguration(
          projectId: FirebaseEnvironmentConfiguration.stagingProjectId,
          projectConfirmation:
              FirebaseEnvironmentConfiguration.stagingProjectId,
          apiKey: 'api-key',
          appId: FirebaseEnvironmentConfiguration.stagingWebAppId,
          messagingSenderId:
              FirebaseEnvironmentConfiguration.stagingProjectNumber,
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
          appId: FirebaseEnvironmentConfiguration.stagingWebAppId,
          messagingSenderId:
              FirebaseEnvironmentConfiguration.stagingProjectNumber,
          storageBucket: '',
        ),
        throwsStateError,
      );
    });

    test('requires explicit project confirmation', () {
      expect(
        () => FirebaseEnvironmentConfiguration.validateStagingConfiguration(
          projectId: FirebaseEnvironmentConfiguration.stagingProjectId,
          projectConfirmation: 'another-project',
          apiKey: 'api-key',
          appId: FirebaseEnvironmentConfiguration.stagingWebAppId,
          messagingSenderId:
              FirebaseEnvironmentConfiguration.stagingProjectNumber,
          storageBucket: '',
        ),
        throwsStateError,
      );
    });

    test('requires every Firebase core value', () {
      expect(
        () => FirebaseEnvironmentConfiguration.validateStagingConfiguration(
          projectId: FirebaseEnvironmentConfiguration.stagingProjectId,
          projectConfirmation:
              FirebaseEnvironmentConfiguration.stagingProjectId,
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

    test(
      'rejects an unregistered key with the pinned staging registration',
      () {
        expect(
          () => FirebaseEnvironmentConfiguration.validateStagingConfiguration(
            projectId: FirebaseEnvironmentConfiguration.stagingProjectId,
            projectConfirmation:
                FirebaseEnvironmentConfiguration.stagingProjectId,
            apiKey: 'api-key',
            appId: FirebaseEnvironmentConfiguration.stagingWebAppId,
            messagingSenderId:
                FirebaseEnvironmentConfiguration.stagingProjectNumber,
            storageBucket: '',
          ),
          throwsStateError,
        );
      },
    );
    for (final target in ['fatoora-platform-staging', 'unapproved-project']) {
      test('rejects another remote project $target', () {
        expect(
          () => FirebaseEnvironmentConfiguration.validateStagingConfiguration(
            projectId: target,
            projectConfirmation: target,
            apiKey: 'staging-key',
            appId: FirebaseEnvironmentConfiguration.stagingWebAppId,
            messagingSenderId:
                FirebaseEnvironmentConfiguration.stagingProjectNumber,
            storageBucket: '',
          ),
          throwsStateError,
        );
      });
    }
    test(
      'rejects a mismatched registration even with the approved project',
      () {
        expect(
          () => FirebaseEnvironmentConfiguration.validateStagingConfiguration(
            projectId: FirebaseEnvironmentConfiguration.stagingProjectId,
            projectConfirmation:
                FirebaseEnvironmentConfiguration.stagingProjectId,
            apiKey: 'staging-key',
            appId: '1:813911311333:web:foreign',
            messagingSenderId:
                FirebaseEnvironmentConfiguration.stagingProjectNumber,
            storageBucket: '',
          ),
          throwsStateError,
        );
      },
    );
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
