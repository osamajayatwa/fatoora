import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:fatoora/core/services/services.dart';
import 'package:fatoora/features/financial/controllers/cash_movements_controller.dart';
import 'package:fatoora/features/financial/data/repositories/financial_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fatoora/features/financial/controllers/settlement_details_preview_controller.dart';
import 'package:fatoora/features/financial/data/models/settlement_details.dart';
import 'package:fatoora/features/financial/data/services/settlement_details_transport.dart';
import 'package:flutter_test/flutter_test.dart';

import 'settlement_details_test.dart' show rehash;

Map<String, dynamic> emulatorCapture() =>
    jsonDecode(
          File(
            'test/fixtures/settlement_transport_emulator.json',
          ).readAsStringSync(),
        )
        as Map<String, dynamic>;
Map<String, dynamic> wireClone(Object value) =>
    jsonDecode(jsonEncode(value)) as Map<String, dynamic>;

/// Immutable captured financial pages plus a synthetic protocol harness. Only
/// tests use this; no fixture asset or credential enters application bindings.
class SettlementWireHarness {
  SettlementWireHarness() : data = emulatorCapture();
  final Map<String, dynamic> data;
  DateTime now = DateTime.now();
  int lifetimeMillis = 120000;
  bool denied = false, failOnce = false;
  int calls = 0;
  int batchSize = 1;
  void Function(Map<String, dynamic>)? corrupt;
  void Function(Map<String, dynamic>)? corruptBatch;
  final requests = <Map<String, dynamic>>[];
  int get expires => now.millisecondsSinceEpoch + lifetimeMillis;
  String token(String kind) => '$kind.${'a' * 43}';
  Map<String, dynamic> response(int index) {
    final page = wireClone(data['pages'][index]);
    return {
      'schemaVersion': 1,
      'kind': 'page',
      'provenance': 'authenticated_firebase',
      'expiresAtMillis': expires,
      'representativeLabel': 'مندوب اختبار / Emulator representative',
      'settlementLabel': 'SYNTHETIC-TRANSPORT',
      'page': page,
      'nextToken': page['nextPageIndex'] == null
          ? null
          : token('page${index + 1}'),
      'exportToken': page['nextPageIndex'] == null ? token('pdf') : null,
    };
  }

  Future<Map<String, dynamic>> invoke(Map<String, dynamic> request) async {
    calls++;
    requests.add(Map.from(request));
    if (denied) {
      throw FirebaseFunctionsException(
        code: 'permission-denied',
        message: 'Synthetic denial',
      );
    }
    if (failOnce && request['action'] == 'page') {
      failOnce = false;
      throw FirebaseFunctionsException(
        code: 'unavailable',
        message: 'Synthetic retry',
      );
    }
    if (request['action'] == 'authorizePdf') {
      final page = data['pages'][0];
      return {
        'schemaVersion': 1,
        'kind': 'pdf_permission',
        'provenance': 'authenticated_firebase',
        'evidenceDigest': page['evidenceDigest'],
        'snapshotDigest': page['snapshotDigest'],
        'validUntilMillis': now.millisecondsSinceEpoch + 15000,
      };
    }
    final index = request['action'] == 'start'
        ? 0
        : int.parse((request['token'] as String).split('.').first.substring(4));
    if (request['schemaVersion'] == 2) {
      final value = {
        'schemaVersion': 2,
        'kind': 'pages',
        'provenance': 'authenticated_firebase',
        'firstPageIndex': index,
        'nextPageIndex': (index + batchSize < data['pages'].length)
            ? index + batchSize
            : null,
        'pageCount': (data['pages'].length - index < batchSize)
            ? data['pages'].length - index
            : batchSize,
        'pages': [
          for (
            var i = index;
            i < data['pages'].length && i < index + batchSize;
            i++
          )
            response(i),
        ],
      };
      value['deliveryDigest'] = settlementEvidenceDigest({
        'schemaVersion': 2,
        'kind': 'pages',
        'provenance': 'authenticated_firebase',
        'firstPageIndex': value['firstPageIndex'],
        'nextPageIndex': value['nextPageIndex'],
        'pageCount': value['pageCount'],
        'pageDigests': [
          for (final envelope in value['pages'] as List)
            envelope['page']['pageDigest'],
        ],
      });
      for (final envelope in value['pages'] as List) {
        corrupt?.call(envelope as Map<String, dynamic>);
      }
      corruptBatch?.call(value);
      return value;
    }
    final value = response(index);
    corrupt?.call(value);
    return value;
  }

  AuthenticatedSettlementDetailsSource source({SettlementCallable? call}) =>
      AuthenticatedSettlementDetailsSource(
        companyId: data['companyId'],
        representativeId: data['salesRepId'],
        settlementId: data['settlementId'],
        invoke: call ?? invoke,
        clock: () => now,
      );
  SettlementDetailsAssembly assembly({
    SettlementDetailsOrigin origin =
        SettlementDetailsOrigin.authenticatedEmulator,
  }) => SettlementDetailsAssembly(
    companyId: data['companyId'],
    representativeId: data['salesRepId'],
    settlementId: data['settlementId'],
    origin: origin,
  );
  SettlementDetailsReport report() {
    final a = assembly();
    for (final p in data['pages']) {
      a.add(SettlementDetailPage.fromJson(wireClone(p)));
    }
    return a.finish();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'existing cash controller connects the scoped source and keeps default/role/company paths disabled',
    () async {
      final h = SettlementWireHarness(), source = h.source();
      SharedPreferences.setMockInitialValues({
        'companyId': source.companyId,
        'role': 'admin',
      });
      final services = await MyServices().init();
      final c = CashMovementsController(
        repository: _UnusedRepository(),
        myServices: services,
        settlementSourceFactory: (rep, settlement) => source,
      );
      expect(
        c.settlementSourceFor(source.settlementId, source.representativeId),
        same(source),
      );
      expect(
        c.settlementSourceFor(source.settlementId, 'other-representative'),
        isNull,
      );
      expect(
        c.settlementSourceFor('other-settlement', source.representativeId),
        isNull,
      );
      await services.sharedPreferences.setString('companyId', 'other-company');
      expect(
        c.settlementSourceFor(source.settlementId, source.representativeId),
        isNull,
      );
      await services.sharedPreferences.setString('companyId', source.companyId);
      await services.sharedPreferences.setString('role', 'sales_rep');
      expect(
        c.settlementSourceFor(source.settlementId, source.representativeId),
        isNull,
      );
      final normal = CashMovementsController(
        repository: _UnusedRepository(),
        myServices: services,
      );
      expect(
        normal.settlementSourceFor(
          source.settlementId,
          source.representativeId,
        ),
        isNull,
      );
    },
  );
  test(
    'bulk loading stops at a failed page without hidden retries or partial totals',
    () async {
      final h = SettlementWireHarness()..failOnce = true;
      final c = SettlementDetailsPreviewController(h.source());
      c.onInit();
      addTearDown(c.onClose);
      await c.loadAll();
      expect(c.state, SettlementPreviewState.error);
      expect(h.calls, 2);
      expect(c.totals, isNull);
      await c.loadAll();
      expect(c.state, SettlementPreviewState.verified);
      expect(h.calls, 3);
    },
  );
  test(
    'inherited snapshot contracts reject noncanonical currency and root strings',
    () {
      for (final field in ['currency', 'evidenceDigest', 'snapshotDigest']) {
        final h = SettlementWireHarness(), p = wireClone(h.data['pages'][0]);
        p[field] = '${p[field]}\n';
        rehash(p);
        expect(() => SettlementDetailPage.fromJson(p), throwsFormatException);
      }
    },
  );
  test(
    'strict authenticated envelope retains backend exact units and requests only scope/token fields',
    () async {
      final h = SettlementWireHarness(), s = h.source(), a = h.assembly();
      a.add(await s.read(0));
      expect(a.certifiedTotals, isNull);
      a.add(await s.read(1));
      expect(a.finish().origin, SettlementDetailsOrigin.authenticatedEmulator);
      expect(
        a.finish().certifiedTotals!['remainingUnits'].toString(),
        h.data['pages'][0]['totals']['remainingUnits'],
      );
      expect(h.requests[0].keys.toSet(), {
        'schemaVersion',
        'action',
        'companyId',
        'salesRepId',
        'settlementId',
      });
      expect(h.requests[1].keys.toSet(), {'schemaVersion', 'action', 'token'});
      expect(
        () => s.requirePdfPermission(a.finish()),
        throwsA(isA<SettlementReadException>()),
      );
      await s.authorizePdf(a.finish());
      s.requirePdfPermission(a.finish());
      h.now = h.now.add(const Duration(seconds: 16));
      expect(
        () => s.requirePdfPermission(a.finish()),
        throwsA(isA<SettlementReadException>()),
      );
    },
  );
  for (final entry in <String, void Function(Map<String, dynamic>)>{
    'extra fields': (v) => v['balance'] = 123,
    'missing provenance': (v) => v.remove('provenance'),
    'fake provenance': (v) => v['provenance'] = 'synthetic_fixture',
    'unsupported version': (v) => v['schemaVersion'] = 2,
    'missing next page': (v) => v['nextToken'] = null,
    'premature export': (v) => v['exportToken'] = 'pdf.${'a' * 43}',
    'malformed token': (v) => v['nextToken'] = 'not-a-token',
    'modified amounts': (v) => v['page']['rows'][0]['amountUnits'] = '1',
    'modified document': (v) =>
        v['page']['rows'][0]['sourceNumber'] = 'changed',
    'wrong holder': (v) => v['page']['rows'][0]['holderUid'] = 'wrong',
    'expired': (v) => v['expiresAtMillis'] = 1,
    'oversized': (v) => v['representativeLabel'] = 'X' * 1100000,
  }.entries) {
    test('transport rejects ${entry.key} without publishing totals', () async {
      final h = SettlementWireHarness()..corrupt = entry.value;
      final c = SettlementDetailsPreviewController(h.source());
      c.onInit();
      addTearDown(c.onClose);
      await c.loadNext();
      expect(c.totals, isNull);
      expect(c.assembly.rows, isEmpty);
      expect(c.state, SettlementPreviewState.expired);
    });
  }
  test(
    'failed page retries reuse the original token, never a new start/snapshot',
    () async {
      final h = SettlementWireHarness()..failOnce = true;
      final c = SettlementDetailsPreviewController(h.source());
      c.onInit();
      addTearDown(c.onClose);
      await c.loadNext();
      await c.loadNext();
      expect(c.state, SettlementPreviewState.error);
      expect(c.assembly.loadedPages, 1);
      expect(c.totals, isNull);
      await c.loadNext();
      expect(c.state, SettlementPreviewState.verified);
      expect(h.requests[1], h.requests[2]);
    },
  );
  test(
    'mixed roots/expiry/descriptor versions fail closed and clear previously displayed rows',
    () async {
      for (final key in [
        'snapshotDigest',
        'evidenceDigest',
        'expiresAtMillis',
        'representativeLabel',
      ]) {
        final h = SettlementWireHarness();
        final c = SettlementDetailsPreviewController(h.source());
        c.onInit();
        await c.loadNext();
        h.corrupt = (v) {
          if (key.endsWith('Digest')) {
            v['page'][key] = 'a' * 64;
          } else if (key == 'expiresAtMillis') {
            v[key] = h.expires - 1;
          } else {
            v[key] = 'Changed representative';
          }
        };
        await c.loadNext();
        expect(c.state, SettlementPreviewState.expired);
        expect(c.assembly.rows, isEmpty);
        c.onClose();
      }
    },
  );
  test(
    'permission revocation during PDF authorization clears complete financial presentation',
    () async {
      final h = SettlementWireHarness(),
          s = h.source(),
          c = SettlementDetailsPreviewController(s);
      c.onInit();
      addTearDown(c.onClose);
      await c.loadNext();
      await c.loadNext();
      final report = c.reportForPdf();
      expect(c.totals, isNotNull);
      h.denied = true;
      await expectLater(
        s.authorizePdf(report),
        throwsA(isA<SettlementReadException>()),
      );
      expect(c.state, SettlementPreviewState.denied);
      expect(c.assembly.rows, isEmpty);
      expect(c.totals, isNull);
    },
  );
  test(
    'incomplete coverage never creates zero openings or detail/PDF certification',
    () async {
      final h = SettlementWireHarness(),
          s = h.source(
            call: (_) async => {
              'schemaVersion': 1,
              'kind': 'incomplete',
              'provenance': 'authenticated_firebase',
              'companyId': h.data['companyId'],
              'salesRepId': h.data['salesRepId'],
              'settlementId': h.data['settlementId'],
              'reason': 'incomplete_coverage',
            },
          );
      final c = SettlementDetailsPreviewController(s);
      c.onInit();
      addTearDown(c.onClose);
      await c.loadNext();
      expect(c.state, SettlementPreviewState.coverageIncomplete);
      expect(c.totals, isNull);
      expect(c.assembly.header, isNull);
      expect(() => c.reportForPdf(), throwsStateError);
    },
  );
  test(
    'fixture reports cannot be exported as authenticated evidence',
    () async {
      final h = SettlementWireHarness(),
          s = h.source(),
          a = h.assembly(origin: SettlementDetailsOrigin.syntheticFixture);
      a.add(await s.read(0));
      a.add(await s.read(1));
      await expectLater(
        s.authorizePdf(a.finish()),
        throwsA(isA<SettlementReadException>()),
      );
    },
  );
  test(
    'expiry clears all presentation state and requires explicit restart',
    () async {
      final h = SettlementWireHarness()..lifetimeMillis = 100;
      final c = SettlementDetailsPreviewController(h.source());
      c.onInit();
      addTearDown(c.onClose);
      await c.loadNext();
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(c.state, SettlementPreviewState.expired);
      expect(c.assembly.rows, isEmpty);
      expect(c.canLoad, false);
      h.now = DateTime.now();
      h.lifetimeMillis = 120000;
      await c.restart();
      expect(c.assembly.loadedPages, 1);
      expect(c.totals, isNull);
    },
  );
  test('closed controller ignores a late authenticated response', () async {
    final h = SettlementWireHarness(),
        response = Completer<Map<String, dynamic>>();
    final c = SettlementDetailsPreviewController(
      h.source(call: (_) => response.future),
    );
    c.onInit();
    final pending = c.loadNext();
    c.onClose();
    response.complete(h.response(0));
    await pending;
    expect(c.assembly.rows, isEmpty);
    expect(c.totals, isNull);
  });
  test(
    'Dart transport reconstructs a complete real callable/Auth-emulator sequence',
    () async {
      final captureFile =
          Platform.environment['SETTLEMENT_TRANSPORT_PROTOCOL_CAPTURE'];
      final data = captureFile == null
          ? emulatorCapture()
          : jsonDecode(File(captureFile).readAsStringSync())
                as Map<String, dynamic>;
      final client = _RealHttp().createHttpClient(null);
      try {
        final auth = await _post(
          client,
          Uri.parse(
            'http://127.0.0.1:9098/identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=synthetic',
          ),
          {
            'email': '${data['viewerUid']}@example.test',
            'password': 'Synthetic-Phase2B12-123!',
            'returnSecureToken': true,
          },
        );
        expect(auth['idToken'], isA<String>());
        for (final batched in [false, true]) {
          final source = AuthenticatedSettlementDetailsSource(
            companyId: data['companyId'],
            representativeId: data['salesRepId'],
            settlementId: data['settlementId'],
            invoke: (request) async {
              final value = await _post(
                client,
                Uri.parse(
                  'http://127.0.0.1:5005/demo-fatoora-phase2b7/us-central1/getSettlementBreakdown',
                ),
                {'data': request},
                token: auth['idToken'] as String,
              );
              if (value['error'] != null) {
                throw FirebaseFunctionsException(
                  message: 'Synthetic emulator transport error',
                  code: (value['error']['status'] as String)
                      .toLowerCase()
                      .replaceAll('_', '-'),
                );
              }
              return Map<String, dynamic>.from(value['result'] as Map);
            },
          );
          final assembly = SettlementDetailsAssembly(
            companyId: source.companyId,
            representativeId: source.representativeId,
            settlementId: source.settlementId,
            origin: source.origin,
          );
          while (!assembly.complete) {
            assembly.addBatch(
              batched
                  ? await source.readBatch(assembly.loadedPages)
                  : [await source.read(assembly.loadedPages)],
            );
          }
          expect(
            assembly.certifiedTotals!['remainingUnits'].toString(),
            data['pages'][0]['totals']['remainingUnits'],
          );
          await source.authorizePdf(assembly.finish());
          source.requirePdfPermission(assembly.finish());
        }
      } finally {
        client.close(force: true);
      }
    },
    skip: Platform.environment['SETTLEMENT_EMULATOR_INTEGRATION'] != '1'
        ? 'Requires explicit isolated Auth/Functions emulators'
        : false,
  );
}

class _RealHttp extends HttpOverrides {}

class _UnusedRepository implements FinancialRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<Map<String, dynamic>> _post(
  HttpClient client,
  Uri uri,
  Map<String, dynamic> body, {
  String? token,
}) async {
  if (uri.host != '127.0.0.1' || ![9098, 5005].contains(uri.port)) {
    throw StateError('Isolated emulators only');
  }
  final request = await client.postUrl(uri);
  request.headers.contentType = ContentType.json;
  if (token != null) {
    request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
  }
  request.write(jsonEncode(body));
  final response = await request.close();
  return jsonDecode(await utf8.decoder.bind(response).join())
      as Map<String, dynamic>;
}
