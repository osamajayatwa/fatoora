import 'package:fatoora/core/firebase/firebase_environment.dart';
import 'package:fatoora/core/firebase/trusted_callable_client.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'settlement opt-in selects only its synthetic project and otherwise preserves defaults',
    () {
      final enabled = const bool.fromEnvironment(
        'FATOORA_SETTLEMENT_TRANSPORT_TEST',
      );
      if (enabled) {
        final config = FirebaseEnvironmentConfiguration.current();
        expect(config.environment, FatooraEnvironment.test);
        expect(config.useEmulators, true);
        expect(config.options.projectId, 'demo-fatoora-phase2b7');
        config.validateRuntimeTarget();
      } else {
        expect(
          FirebaseEnvironmentConfiguration.configuredTestProjectId,
          FirebaseEnvironmentConfiguration.localTestProjectId,
        );
      }
    },
  );
  test(
    'settlement SDK routing rejects production/staging and arbitrary hosts before any initialization',
    () async {
      for (final project in [
        FirebaseEnvironmentConfiguration.productionProjectId,
        FirebaseEnvironmentConfiguration.stagingProjectId,
      ]) {
        await expectLater(
          TrustedCallableClient.markSettlementEmulatorConfigured(
            _App(project),
            '127.0.0.1',
          ),
          throwsStateError,
        );
      }
      await expectLater(
        TrustedCallableClient.markSettlementEmulatorConfigured(
          _App('demo-fatoora-phase2b7'),
          'example.com',
        ),
        throwsStateError,
      );
    },
  );
}

class _App implements FirebaseApp {
  _App(String project)
    : options = FirebaseOptions(
        apiKey: 'synthetic',
        appId: 'synthetic',
        messagingSenderId: '123',
        projectId: project,
      );
  @override
  final FirebaseOptions options;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
