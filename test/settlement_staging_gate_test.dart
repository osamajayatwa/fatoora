import 'package:fatoora/core/firebase/trusted_callable_client.dart';
import 'package:fatoora/features/financial/data/models/settlement_details.dart';
import 'package:fatoora/features/financial/data/services/settlement_details_formatter.dart';
import 'package:fatoora/features/financial/data/services/settlement_details_transport.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const enabled = bool.fromEnvironment('FATOORA_SETTLEMENT_STAGING_PILOT');
  test(
    'staging origin requires explicit staging build and the sole company',
    () {
      AuthenticatedSettlementDetailsSource source(String company) =>
          AuthenticatedSettlementDetailsSource(
            companyId: company,
            representativeId: 'synthetic-rep',
            settlementId: 'synthetic-settlement',
            origin: SettlementDetailsOrigin.authenticatedStaging,
            invoke: (_) async => throw StateError('No network in gate tests'),
          );
      if (enabled && const String.fromEnvironment('FATOORA_ENV') == 'staging') {
        expect(
          source('default_company').origin,
          SettlementDetailsOrigin.authenticatedStaging,
        );
      } else {
        expect(() => source('default_company'), throwsStateError);
      }
      expect(() => source('other'), throwsStateError);
    },
  );
  test(
    'staging bootstrap rejects wrong projects and registrations before any SDK call',
    () {
      for (final options in [
        const FirebaseOptions(
          apiKey: 'synthetic',
          appId: 'synthetic',
          messagingSenderId: '5438538531',
          projectId: 'fatoora-original-staging',
        ),
        const FirebaseOptions(
          apiKey: 'synthetic',
          appId: '1:5438538531:web:1fb5d6aac646d3b1240296',
          messagingSenderId: '5438538531',
          projectId: 'demo-other',
        ),
      ]) {
        expect(
          () => TrustedCallableClient.markSettlementStagingConfigured(
            _App(options),
          ),
          throwsStateError,
        );
      }
    },
  );
  test(
    'Arabic/English staging provenance never labels real responses as synthetic',
    () {
      for (final ar in [false, true]) {
        final fmt = SettlementDetailsFormatter(arabic: ar);
        expect(
          fmt.provenance(SettlementDetailsOrigin.authenticatedStaging),
          fmt.t('staging'),
        );
        expect(
          fmt.provenance(
            SettlementDetailsOrigin.authenticatedStaging,
            footer: true,
          ),
          fmt.t('staging_footer'),
        );
        expect(
          fmt.provenance(SettlementDetailsOrigin.authenticatedStaging),
          isNot(fmt.t('fixture')),
        );
        expect(
          fmt.provenance(SettlementDetailsOrigin.authenticatedStaging),
          isNot(fmt.t('authenticated')),
        );
      }
    },
  );
}

class _App implements FirebaseApp {
  _App(this.options);
  @override
  String get name => '[DEFAULT]';
  @override
  final FirebaseOptions options;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
