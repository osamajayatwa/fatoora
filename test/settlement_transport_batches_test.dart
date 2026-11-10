import 'dart:convert';
import 'dart:io';

import 'package:fatoora/features/financial/controllers/settlement_details_preview_controller.dart';
import 'package:fatoora/features/financial/data/models/settlement_details.dart';
import 'package:flutter_test/flutter_test.dart';

import 'settlement_transport_test.dart' show SettlementWireHarness, wireClone;

void main() {
  test(
    'bounded authenticated delivery assembles existing pages in one call',
    () async {
      final h = SettlementWireHarness()..batchSize = 2;
      final source = h.source();
      final controller = SettlementDetailsPreviewController(source)..onInit();
      await controller.loadNext();
      expect(controller.state, SettlementPreviewState.verified);
      expect(controller.assembly.loadedPages, 2);
      expect(h.calls, 1);
      expect(h.requests.single['schemaVersion'], 2);
      expect(
        controller.totals!['remainingUnits'].toString(),
        h.data['pages'][0]['totals']['remainingUnits'],
      );
      final report = controller.reportForPdf();
      await source.authorizePdf(report);
      source.requirePdfPermission(report);
      expect(h.requests.last['schemaVersion'], 2);
      controller.onClose();
    },
  );

  for (final corruption in [
    'empty',
    'oversized',
    'duplicate',
    'missing',
    'reordered',
    'mixed',
    'extra',
    'version',
    'provenance',
    'partial-final',
    'truncated-envelope',
  ]) {
    test(
      'batch fails closed for $corruption without publishing a valid prefix',
      () async {
        final h = SettlementWireHarness()..batchSize = 2;
        h.corruptBatch = (v) {
          final pages = v['pages'] as List;
          if (corruption == 'empty') pages.clear();
          if (corruption == 'oversized') {
            pages.addAll(List.generate(5, (_) => wireClone(pages.first)));
          }
          if (corruption == 'duplicate') pages[1] = wireClone(pages[0]);
          if (corruption == 'missing') pages.removeAt(0);
          if (corruption == 'truncated-envelope') pages.removeLast();
          if (corruption == 'reordered') v['pages'] = pages.reversed.toList();
          if (corruption == 'mixed') {
            (pages[1]['page'] as Map)['snapshotDigest'] = 'f' * 64;
          }
          if (corruption == 'extra') v['untrustedTotals'] = 0;
          if (corruption == 'version') v['schemaVersion'] = 3;
          if (corruption == 'provenance') v['provenance'] = 'synthetic_fixture';
          if (corruption == 'partial-final') {
            (pages[1]['page']['rows'] as List).removeLast();
          }
        };
        final controller = SettlementDetailsPreviewController(h.source())
          ..onInit();
        await controller.loadNext();
        expect(controller.state, SettlementPreviewState.expired);
        expect(controller.assembly.rows, isEmpty);
        expect(controller.totals, isNull);
        expect(() => controller.reportForPdf(), throwsStateError);
        controller.onClose();
      },
    );
  }

  test(
    'a legitimate short batch stays incomplete and requires another authorized request',
    () async {
      final h = SettlementWireHarness();
      final controller = SettlementDetailsPreviewController(h.source())
        ..onInit();
      await controller.loadNext();
      expect(controller.state, SettlementPreviewState.incomplete);
      expect(controller.totals, isNull);
      h.denied = true;
      await controller.loadNext();
      expect(controller.state, SettlementPreviewState.denied);
      expect(controller.assembly.rows, isEmpty);
      controller.onClose();
    },
  );

  test('assembly rolls back the entire batch on a late cash-chain failure', () {
    final h = SettlementWireHarness(), assembly = h.assembly();
    final first = SettlementDetailPage.fromJson(wireClone(h.data['pages'][0]));
    expect(() => assembly.addBatch([first, first]), throwsFormatException);
    expect(assembly.loadedPages, 0);
    expect(assembly.rows, isEmpty);
    assembly.addBatch([
      for (final p in h.data['pages'])
        SettlementDetailPage.fromJson(wireClone(p)),
    ]);
    expect(assembly.complete, isTrue);
  });

  test(
    'delivery version is pinned, and expired or revoked complete reports cannot export',
    () async {
      final h = SettlementWireHarness()..batchSize = 2;
      final source = h.source();
      final pages = await source.readBatch(0);
      await expectLater(
        source.read(1),
        throwsA(isA<SettlementReadException>()),
      );
      expect(source.expired, isTrue);
      source.reset();
      final assembly = h.assembly()..addBatch(await source.readBatch(0));
      expect(pages.length, 2);
      h.denied = true;
      await expectLater(
        source.authorizePdf(assembly.finish()),
        throwsA(isA<SettlementReadException>()),
      );
      expect(source.expired, isTrue);
      source.reset();
      h.denied = false;
      final report = (h.assembly()..addBatch(await source.readBatch(0)))
          .finish();
      h.now = h.now.add(const Duration(minutes: 6));
      await expectLater(
        source.authorizePdf(report),
        throwsA(isA<SettlementReadException>()),
      );
    },
  );

  test(
    'profile identical large authenticated captures through existing Dart validators',
    () async {
      final directory = Platform.environment['SETTLEMENT_PROFILE_CAPTURE_DIR'];
      if (directory == null) return;
      final results = <Map<String, dynamic>>[];
      for (final count in [3000, 6000]) {
        final capture =
            jsonDecode(File('$directory/$count.json').readAsStringSync())
                as Map<String, dynamic>;
        final h = SettlementWireHarness()..batchSize = 6;
        h.data
          ..clear()
          ..addAll({
            ...capture,
            'pages': [
              for (final batch in capture['batches'] as List) ...batch as List,
            ],
          });
        final wire = <int, String>{};
        for (var index = 0; index < h.data['pages'].length; index += 6) {
          wire[index] = jsonEncode(
            await h.invoke(
              index == 0
                  ? {'schemaVersion': 2, 'action': 'start'}
                  : {
                      'schemaVersion': 2,
                      'action': 'page',
                      'token': h.token('page$index'),
                    },
            ),
          );
        }
        for (var repeat = 0; repeat < 5; repeat++) {
          var decodeMicros = 0, calls = 0;
          final source = h.source(
            call: (request) async {
              final index = request['action'] == 'start'
                  ? 0
                  : int.parse(
                      (request['token'] as String)
                          .split('.')
                          .first
                          .substring(4),
                    );
              final timer = Stopwatch()..start();
              final decoded = jsonDecode(wire[index]!) as Map<String, dynamic>;
              decodeMicros += timer.elapsedMicroseconds;
              calls++;
              return decoded;
            },
          );
          final clock = Stopwatch()..start();
          final assembly = h.assembly(), batchMicros = <int>[];
          while (!assembly.complete) {
            final timer = Stopwatch()..start();
            assembly.addBatch(await source.readBatch(assembly.loadedPages));
            batchMicros.add(timer.elapsedMicroseconds);
          }
          expect(
            assembly.finish().certifiedTotals!['remainingUnits'].toString(),
            capture['remainingUnits'],
          );
          results.add({
            'count': count,
            'repeat': repeat,
            'decodeMicros': decodeMicros,
            'totalDecodeValidateAssembleMicros': clock.elapsedMicroseconds,
            'firstBatchMicros': batchMicros.first,
            'subsequentBatchMicros': batchMicros.skip(1).toList(),
            'calls': calls,
            'logicalPages': assembly.loadedPages,
            'jsonPayloadBytes': wire.values.fold<int>(
              0,
              (n, text) => n + utf8.encode(text).length,
            ),
          });
        }
      }
      File(
        'output/phase2b13/flutter-delivery.json',
      ).writeAsStringSync(jsonEncode({'synthetic': true, 'records': results}));
    },
    timeout: const Timeout(Duration(minutes: 2)),
    skip: Platform.environment['SETTLEMENT_PROFILE_CAPTURE_DIR'] == null
        ? 'Requires explicit synthetic profiling captures'
        : false,
  );
}
