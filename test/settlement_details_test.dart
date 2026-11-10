import 'dart:convert';
import 'dart:io';

import 'package:fatoora/features/financial/controllers/settlement_details_preview_controller.dart';
import 'package:fatoora/features/financial/data/models/settlement_details.dart';
import 'package:fatoora/features/financial/data/services/settlement_details_fixtures.dart';
import 'package:fatoora/features/financial/data/services/settlement_details_formatter.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> settlementFixture(
  String name,
) => Map<String, dynamic>.from(
  (jsonDecode(File('test/fixtures/settlement_details.json').readAsStringSync())
          as Map)[name]
      as Map,
);
List<SettlementDetailPage> pages(String name) =>
    (settlementFixture(name)['pages'] as List)
        .map(
          (p) => SettlementDetailPage.fromJson(
            Map<String, dynamic>.from(p as Map),
          ),
        )
        .toList();
SettlementDetailsAssembly assembly() => SettlementDetailsAssembly(
  companyId: 'synthetic-phase2b11',
  representativeId: 'synthetic-representative',
  settlementId: 'current',
);
Map<String, dynamic> clonePage([int index = 0]) => Map<String, dynamic>.from(
  (settlementFixture('verified')['pages'] as List)[index] as Map,
);
void rehash(Map<String, dynamic> page) {
  final header = Map<String, dynamic>.from(page)
    ..remove('rows')
    ..remove('pageDigest');
  page['pageDigest'] = settlementEvidenceDigest({
    ...header,
    'rowDigests': (page['rows'] as List).map(settlementEvidenceDigest).toList(),
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'backend-generated hashes, exact totals, actors and source references match Dart',
    () {
      final a = assembly(), input = pages('verified');
      a.add(input.first);
      expect(a.certifiedTotals, isNull);
      expect(a.complete, false);
      a.add(input.last);
      final report = a.finish();
      expect(report.verified, true);
      expect(report.rows, hasLength(72));
      expect(
        report.certifiedTotals!['cashAvailableBeforeUnits'],
        BigInt.from(109940),
      );
      expect(report.certifiedTotals!['remainingUnits'], BigInt.from(99940));
      expect(
        report.rows
            .where((r) => r.category == 'receipt_collection')
            .single
            .references
            .single
            .number,
        'INV-credit',
      );
      final expense = report.rows
          .where((r) => r.category == 'cash_expense')
          .single;
      expect(expense.sourceCreator.uid, 'synthetic-representative');
      expect(expense.postingActor.uid, 'synthetic-administrator');
      expect(() => input.first.raw['currency'] = 'USD', throwsUnsupportedError);
      expect(
        () => input.first.rows.first.raw['amountUnits'] = '0',
        throwsUnsupportedError,
      );
      expect(() => report.rows.clear(), throwsUnsupportedError);
    },
  );
  test(
    'unknown opening and carry never become zero and blocked evidence has no totals',
    () {
      final a = assembly();
      for (final p in pages('blocked')) {
        a.add(p);
      }
      final r = a.finish();
      expect(r.verified, false);
      expect(r.certifiedTotals, isNull);
      expect((r.header.raw['opening'] as Map)['amountUnits'], isNull);
      expect((r.header.raw['carry'] as Map)['amountUnits'], isNull);
    },
  );
  for (final value in [
    '1.0',
    '1e3',
    ' 1',
    '1\n',
    '-0',
    '01',
    '+1',
    '1000000000000000000000000000000',
  ]) {
    test(
      'rejects noncanonical or out-of-range units $value',
      () => expect(() => settlementUnits(value), throwsFormatException),
    );
  }
  test(
    'large exact values and negative mills are never routed through double or rounded',
    () {
      const fmt = SettlementDetailsFormatter();
      expect(
        fmt.money(settlementUnits('999999999999999999999999999999'), 'JOD'),
        'JOD 999999999999999999999999999.999',
      );
      expect(fmt.money(settlementUnits('-1'), 'JOD'), 'JOD -0.001');
      expect(fmt.money(null, 'JOD'), contains('Unavailable'));
      expect(
        const SettlementDetailsFormatter(arabic: true).money(null, 'JOD'),
        contains('غير'),
      );
    },
  );
  for (final entry in <String, void Function(Map<String, dynamic>)>{
    'changed source number': (p) =>
        (p['rows'] as List).first['sourceNumber'] = 'FORGED',
    'fractional units': (p) => (p['rows'] as List).first['amountUnits'] = 0.1,
    'wrong holder': (p) =>
        (p['rows'] as List).first['holderUid'] = 'other-representative',
    'foreign source': (p) => (p['rows'] as List).first['source']['path'] =
        'companies/foreign/invoices/id',
    'wrong currency': (p) => p['currency'] = 'usd',
    'extra field': (p) => p['allocatedInvoices'] = [],
    'missing source': (p) => (p['rows'] as List).first.remove('source'),
    'unknown zero opening': (p) => p['opening'] = {
      'state': 'unknown',
      'amountUnits': '0',
      'movementId': null,
    },
    'page missing rows': (p) => (p['rows'] as List).removeLast(),
    'future commit': (p) => (p['rows'] as List).first['committedAt'] = {
      'seconds': 253402300799,
      'nanoseconds': 0,
    },
  }.entries) {
    test('strict page rejects ${entry.key}', () {
      final p = clonePage();
      entry.value(p);
      expect(() => SettlementDetailPage.fromJson(p), throwsFormatException);
    });
  }
  test(
    'self-consistently rehashed false cash equations are rejected independently of checksums',
    () {
      final p = clonePage();
      p['totals']['remainingUnits'] = '99941';
      rehash(p);
      expect(() => SettlementDetailPage.fromJson(p), throwsFormatException);
      final q = clonePage();
      q['rows'][0]['afterUnits'] = '100001';
      rehash(q);
      expect(() => SettlementDetailPage.fromJson(q), throwsFormatException);
    },
  );
  test(
    'missing/duplicate/reordered/mixed-snapshot pages cannot complete a report',
    () {
      final input = pages('verified');
      expect(() => assembly().add(input.last), throwsFormatException);
      final a = assembly()..add(input.first);
      expect(() => a.finish(), throwsFormatException);
      expect(() => a.add(input.first), throwsFormatException);
      expect(a.loadedPages, 1);
      final changed = clonePage(1)..['snapshotDigest'] = 'a' * 64;
      rehash(changed);
      expect(
        () => a.add(SettlementDetailPage.fromJson(changed)),
        throwsFormatException,
      );
      expect(a.loadedPages, 1);
      expect(a.certifiedTotals, isNull);
      a.add(input.last);
      expect(a.finish().rows.length, 72);
    },
  );
  test(
    'preview controller keeps totals hidden through loading/errors and retries only the rejected page',
    () async {
      final c = SettlementDetailsPreviewController(
        SettlementDetailsFixtures.fromJson(
          settlementFixture('verified'),
          failFirstReads: {1},
        ),
      );
      await c.loadNext();
      expect(c.state, SettlementPreviewState.incomplete);
      expect(c.totals, isNull);
      await c.loadNext();
      expect(c.state, SettlementPreviewState.error);
      expect(c.assembly.loadedPages, 1);
      expect(() => c.reportForPdf(), throwsStateError);
      await c.loadNext();
      expect(c.state, SettlementPreviewState.verified);
      expect(c.reportForPdf().rows.length, 72);
      c.onClose();
    },
  );
  test(
    'rehashing does not permit duplicate movements or broken cash chains',
    () {
      for (final duplicate in [true, false]) {
        final a = assembly()..add(pages('verified').first);
        final q = clonePage(1), row = q['rows'][0];
        if (duplicate) {
          row['id'] = a.rows.first.id;
          row['path'] = a.rows.first.path;
        } else {
          row['beforeUnits'] =
              (settlementUnits(row['beforeUnits']) + BigInt.one).toString();
          row['afterUnits'] = (settlementUnits(row['afterUnits']) + BigInt.one)
              .toString();
        }
        rehash(q);
        expect(
          () => a.add(SettlementDetailPage.fromJson(q)),
          throwsFormatException,
        );
        expect(a.loadedPages, 1);
        expect(a.certifiedTotals, isNull);
      }
    },
  );
  test('coherent summary arithmetic cannot substitute for a carry witness', () {
    final a = assembly();
    for (var i = 0; i < 2; i++) {
      final p = clonePage(i);
      p['carry']['amountUnits'] = '109876';
      p['totals']['carryUnits'] = '109876';
      p['totals']['activitySinceCarryUnits'] = '64';
      rehash(p);
      final page = SettlementDetailPage.fromJson(p);
      if (i == 0) {
        a.add(page);
      } else {
        expect(() => a.add(page), throwsFormatException);
      }
    }
    expect(a.loadedPages, 1);
    expect(a.certifiedTotals, isNull);
  });
  test(
    'concurrent loads serialize and disposed late completions are ignored',
    () async {
      final c = SettlementDetailsPreviewController(
        SettlementDetailsFixtures.fromJson(
          settlementFixture('verified'),
          latency: const Duration(milliseconds: 10),
        ),
      );
      await Future.wait([c.loadNext(), c.loadNext(), c.loadNext()]);
      expect(c.assembly.loadedPages, 1);
      final pending = c.loadNext();
      c.onClose();
      await pending;
      expect(c.assembly.loadedPages, 1);
      expect(c.totals, isNull);
    },
  );
  test(
    'coverage-incomplete fixture has no pages, no totals and no PDF export',
    () async {
      final c = SettlementDetailsPreviewController(
        SettlementDetailsFixtures.fromJson(settlementFixture('incomplete')),
      );
      await c.loadNext();
      expect(c.state, SettlementPreviewState.coverageIncomplete);
      expect(c.totals, isNull);
      expect(() => c.reportForPdf(), throwsStateError);
      c.onClose();
    },
  );
  test(
    'fixture catalog pins immutable input and forbids real company scope',
    () async {
      final f = settlementFixture('verified'),
          source = SettlementDetailsFixtures.fromJson(f);
      f['pages'][0]['currency'] = 'USD';
      expect((await source.read(0)).currency, 'JOD');
      expect(
        () => SettlementDetailsFixtures.fromJson({'fixture': 'production'}),
        throwsFormatException,
      );
    },
  );
}
