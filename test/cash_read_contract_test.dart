// Firestore SDK fakes exercise the existing query contract without a connection.
// ignore_for_file: subtype_of_sealed_class

import 'dart:convert';
import 'dart:io';

import 'package:fatoora/core/localization/translation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:fatoora/core/firebase/trusted_callable_client.dart';
import 'package:fatoora/core/localization/financial_translations.dart';
import 'package:fatoora/core/pdf/app_pdf_localization.dart';
import 'package:fatoora/features/financial/data/models/cash_movement_model.dart';
import 'package:fatoora/features/financial/data/models/financial_dashboard_snapshot.dart';
import 'package:fatoora/features/financial/data/repositories/financial_repository.dart';
import 'package:fatoora/features/financial/view/widgets/cash_movement_presentation.dart';
import 'package:fatoora/features/shared/business/business_user_context.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

String tr(String key) => financialEnglishTranslations[key] ?? key;
CashMovementModel movement([Map<String, dynamic> overrides = const {}]) =>
    CashMovementModel.fromMap({
      'id': 'cash-1',
      'companyId': 'company',
      'cashAccount': 'rep_cash',
      'salesRepId': 'holder',
      'salesRepName': 'Stored representative',
      'type': 'receipt_cash',
      'movementType': 'receipt',
      'direction': 'in',
      'amount': 0.001,
      'sourceCollection': 'receipts',
      'sourceId': 'receipt-1',
      'sourceNumber': 'REC-1',
      'date': '2026-11-01T10:00:00Z',
      'createdAt': '2026-11-04T10:00:00Z',
      'createdByUid': 'creator',
      'createdByName': 'Creator',
      'createdByRole': 'admin',
      'paymentType': 'cash',
      'balanceBefore': 10,
      'balanceAfter': 10.001,
      ...overrides,
    });
BusinessUserContext user({
  String uid = 'holder',
  String role = 'sales_rep',
  String company = 'company',
  bool active = true,
}) => BusinessUserContext(
  uid: uid,
  name: 'User',
  email: 'x@example.invalid',
  phone: '',
  role: role,
  companyId: company,
  active: active,
  approvalStatus: 'approved',
);

void main() {
  final settlementFixture =
      Platform.environment['SETTLEMENT_METADATA_FIXTURE_PATH'] ??
      'test/fixtures/cash_settlement_metadata.json';
  test(
    'Phase 2B-3 trusted settlement payload uses the existing read contract',
    () {
      final rows =
          (jsonDecode(File(settlementFixture).readAsStringSync()) as List)
              .map(
                (raw) => CashMovementModel.fromMap(
                  Map<String, dynamic>.from(raw as Map),
                ),
              )
              .toList();
      expect(rows, hasLength(2));
      final out = rows.singleWhere((m) => m.isOut);
      final incoming = rows.singleWhere((m) => m.isIn);
      expect(cashMovementPresentationGroups(rows).single, [out, incoming]);
      expect(out.holderUid, out.salesRepId);
      expect(out.holderUid, isNot(out.createdByUid));
      expect(incoming.holderUid, isNull); // Company has no person cash holder.
      expect(incoming.detail('holderUid'), incoming.companyId);
      expect(incoming.salesRepId, isEmpty);
      expect(out.detail('counterpartMovementId'), incoming.id);
      expect(incoming.detail('counterpartMovementId'), out.id);
      expect(out.amountUnits, BigInt.from(30123));
      expect(incoming.amountUnits, out.amountUnits);
      expect(out.balanceAfterUnits, BigInt.from(69988));
      expect(incoming.balanceAfterUnits, BigInt.from(50345));
      for (final m in rows) {
        expect(m.hasVerifiedHolder, isTrue);
        expect(m.hasTraceGaps, isFalse);
        expect(m.committedBalanceConsistent, isTrue);
        expect(m.sourceCreatorUid, m.createdByUid);
        expect(m.postingActorUid, m.createdByUid);
        expect(m.sellerId, isEmpty);
        expect(m.collectorUid, isEmpty);
        expect(m.detail('sellerIdentityStatus'), 'not_applicable');
        expect(m.detail('collectorIdentityStatus'), 'not_applicable');
        expect(m.paymentMethod, 'cash');
        expect(m.toMap()['postedAt'], m.storedDetails['postedAt']);
        expect(m.toMap()['settlementMetadataVersion'], 1);
        validateCashReadScope(
          m,
          m.companyId,
          user(uid: m.createdByUid, role: 'admin', company: m.companyId),
        );
        if (m.isRepCashAccount) {
          validateCashReadScope(
            m,
            m.companyId,
            user(uid: m.holderUid!, company: m.companyId),
          );
        } else {
          expect(
            () => validateCashReadScope(
              m,
              m.companyId,
              user(uid: out.holderUid!, company: m.companyId),
            ),
            throwsA(isA<FinancialRepositoryException>()),
          );
        }
        // Screen and PDF share this exact projection and its translations.
        for (final language in ['en', 'ar']) {
          final loc = AppPdfLocalization.forLanguage(language);
          final details = cashMovementDetails(
            m,
            t: loc.t,
            timestamp: (date) => date.toIso8601String(),
            arabic: language == 'ar',
          );
          CashMovementDetail field(String key) =>
              details.singleWhere((d) => d.key == key);
          expect(
            field('cash_detail_counterpart').value,
            m.detail('counterpartMovementId'),
          );
          expect(
            field('cash_detail_account_id').value,
            m.detail('treasuryAccountId'),
          );
          expect(field('cash_detail_audit').value, m.settlementId);
          expect(
            field('cash_detail_source_creator').value,
            contains(m.createdByUid),
          );
          expect(field('cash_detail_poster').value, contains(m.createdByUid));
          expect(field('cash_detail_seller').available, isFalse);
          expect(field('cash_detail_collector').available, isFalse);
        }
      }
    },
  );
  test(
    'stored exact amount, balances, dates and references survive decoding',
    () {
      final m = movement();
      expect(m.amountUnits, BigInt.one);
      expect(m.balanceBeforeUnits, BigInt.from(10000));
      expect(m.balanceAfterUnits, BigInt.from(10001));
      expect(m.committedBalanceConsistent, isTrue);
      expect(m.date, DateTime.utc(2026, 11, 1, 10));
      expect(m.createdAt, DateTime.utc(2026, 11, 4, 10));
      expect(m.referenceId, 'receipt-1');
      expect(m.effectiveReferenceNumber, 'REC-1');
    },
  );
  test('missing and malformed fields never become zero, IN or now', () {
    for (final raw in <Map<String, dynamic>>[
      {},
      {'amount': 'NaN', 'direction': 'unknown', 'date': '2026-02-30'},
      {'amount': double.infinity, 'createdAt': 'not-a-date'},
      {'amount': -1, 'date': '2026-01-01T25:00:00Z'},
      {'amount': 1.0001},
      {'amount': true},
    ]) {
      final m = CashMovementModel.fromMap(raw);
      expect(m.amountUnits, isNull);
      expect(m.isIn, isFalse);
      expect(m.isOut, isFalse);
      expect(m.date, isNull);
      expect(m.createdAt, isNull);
      expect(m.hasVerifiedHolder, isFalse);
      expect(() => m.amount, throwsFormatException);
    }
  });
  test(
    'exact large decimal strings never pass through double presentation',
    () {
      final m = movement({
        'amount': '9007199254740.991',
        'balanceAfter': '9007199254750.991',
      });
      expect(m.amountUnits.toString(), '9007199254740991');
      expect(cashAmountText(m, t: tr), '+JOD 9007199254740.991');
      expect(() => m.amount, throwsFormatException);
    },
  );
  test(
    'creator, seller, collector, poster and cash holder remain separate',
    () {
      final m = movement({
        'sellerId': 'seller',
        'collectorUid': 'collector',
        'postedByUid': 'poster',
      });
      expect(m.createdByUid, 'creator');
      expect(m.sellerId, 'seller');
      expect(m.collectorUid, 'collector');
      expect(m.postingActorUid, 'poster');
      expect(m.sellerName, isEmpty);
      expect(m.collectorName, isEmpty);
      expect(m.postingActorName, isEmpty);
      expect(m.holderUid, 'holder');
      final company = movement({
        'cashAccount': 'company_cash',
        'salesRepId': 'seller',
      });
      expect(cashAccountText(company, tr), 'Company cash');
      expect(company.holderUid, isNull);
    },
  );
  test(
    'legacy invoice creator is not assumed to be its confirmation actor',
    () {
      final m = movement({
        'sourceCollection': 'invoices',
        'movementType': 'invoice_payment',
        'paymentType': 'partial',
      });
      expect(m.sourceCreatorUid, 'creator');
      expect(m.sellerId, 'holder');
      expect(m.postingActorUid, isEmpty);
      expect(m.collectorUid, isEmpty);
      expect(m.paymentMethod, isEmpty);
    },
  );
  test(
    'expense approver does not become holder or original source creator',
    () {
      final m = movement({
        'sourceCollection': 'expenses',
        'movementType': 'expense',
        'createdByUid': 'approver',
        'createdByRole': 'admin',
      });
      expect(m.postingActorUid, 'approver');
      expect(m.holderUid, 'holder');
      expect(m.sourceCreatorUid, isEmpty);
    },
  );
  test('ambiguous holder and committed balance mismatch remain explicit', () {
    final m = movement({'holderUid': 'other', 'balanceAfter': 900});
    expect(m.holderUid, isNull);
    expect(m.hasVerifiedHolder, isFalse);
    expect(cashAccountText(m, tr), 'Unavailable');
    expect(m.committedBalanceConsistent, isFalse);
    expect(m.hasTraceGaps, isTrue);
    expect(
      movement({
        'holderUid': 'holder',
        'cashAccountSalesRepId': 'other',
      }).hasVerifiedHolder,
      isFalse,
    );
    expect(m.balanceAfterUnits, BigInt.from(900000));
    expect(
      movement({
        'cashAccount': 'company_cash',
        'holderType': 'representative',
      }).hasVerifiedHolder,
      isFalse,
    );
  });
  test('payment methods are distinct from payment and refund state', () {
    for (final method in ['cash', 'bank', 'check', 'cliq', 'card']) {
      expect(movement({'paymentMethod': method}).paymentMethod, method);
    }
    expect(movement({'paymentType': 'cash_refund'}).paymentMethod, isEmpty);
    expect(movement({'paymentType': 'credit'}).paymentMethod, isEmpty);
    expect(movement({'paymentMethod': 'partial'}).paymentMethod, isEmpty);
  });
  test('all current cash types and account labels translate in UI and PDF', () {
    for (final language in ['en', 'ar']) {
      final loc = AppPdfLocalization.forLanguage(language);
      final labels = language == 'ar'
          ? financialArabicTranslations
          : financialEnglishTranslations;
      for (final type in [
        'invoice_cash',
        'invoice_partial',
        'receipt_cash',
        'expense_cash',
        'sales_return_cash_refund',
        'receipt_cancellation',
        'settlement_to_admin',
        'opening_balance',
      ]) {
        final m = movement({'type': type});
        expect(cashTypeText(m, loc.t), labels['financial_movement_$type']);
      }
      expect(cashAccountText(movement(), loc.t), isNot(contains('ledger_')));
    }
  });
  test(
    'reversal and refund links are preserved without deleting originals',
    () {
      final m = movement({
        'type': 'receipt_cancellation',
        'movementType': 'receipt_cancellation',
        'direction': 'out',
        'reversesMovementId': 'original',
        'reversesReceiptId': 'REC-original',
        'originalCollectionSourceIds': ['collection-1', 'collection-2'],
        'notes': 'Reason',
      });
      final details = cashMovementDetails(
        m,
        t: tr,
        timestamp: (v) => v.toIso8601String(),
      );
      expect(
        details.firstWhere((f) => f.key == 'cash_detail_reversal').value,
        'original',
      );
      expect(
        details.firstWhere((f) => f.key == 'cash_detail_refund_sources').value,
        'collection-1, collection-2',
      );
      expect(m.sourceCreatorUid, isEmpty);
      expect(m.postingActorUid, 'creator');
      expect(m.isOut, isTrue);
      expect(
        movement({'sourceCollection': 'unknown'}).postingActorUid,
        isEmpty,
      );
    },
  );
  test('unavailable summary values are not fabricated zero openings', () {
    const snapshot = FinancialCashSnapshot(
      movements: [],
      cashInHand: 0,
      totalIn: 0,
      totalOut: 0,
      cashBySalesRep: [],
      reportedValues: {},
    );
    expect(snapshot.units('openingBalance'), isNull);
    expect(
      cashMoneyText(snapshot.units('openingBalance'), t: tr),
      'Unavailable',
    );
  });
  test(
    'exact transfer grouping rejects ambiguity, different companies and invalid amounts',
    () {
      final out = movement({
        'id': 'out',
        'direction': 'out',
        'settlementId': 'S',
      });
      final incoming = movement({
        'id': 'in',
        'cashAccount': 'company_cash',
        'settlementId': 'S',
      });
      expect(cashMovementPresentationGroups([out, incoming]), hasLength(1));
      expect(cashMovementPresentationGroups([out]), hasLength(1));
      for (final amount in [null, -1, 0.002]) {
        expect(
          cashMovementPresentationGroups([
            out,
            movement({
              'id': 'in',
              'cashAccount': 'company_cash',
              'settlementId': 'S',
              'amount': amount,
            }),
          ]),
          hasLength(2),
        );
      }
      expect(
        cashMovementPresentationGroups([
          out,
          incoming,
          movement({'id': 'extra', 'settlementId': 'S'}),
        ]),
        hasLength(3),
      );
      expect(
        cashMovementPresentationGroups([
          out,
          movement({
            'id': 'in',
            'cashAccount': 'company_cash',
            'companyId': 'foreign',
            'settlementId': 'S',
          }),
        ]),
        hasLength(2),
      );
    },
  );
  test(
    'read scope rejects cross-company, wrong-holder and unapproved access',
    () {
      expect(
        () => validateCashReadScope(movement(), 'company', user()),
        returnsNormally,
      );
      for (final context in [
        user(uid: 'other'),
        user(company: 'foreign'),
        user(active: false),
      ]) {
        expect(
          () => validateCashReadScope(movement(), 'company', context),
          throwsA(isA<FinancialRepositoryException>()),
        );
      }
      expect(
        () => validateCashReadScope(
          movement({'cashAccount': 'company_cash'}),
          'company',
          user(),
        ),
        throwsA(isA<FinancialRepositoryException>()),
      );
      expect(
        () => validateCashReadScope(
          movement({'holderUid': 'other'}),
          'company',
          user(),
        ),
        throwsA(isA<FinancialRepositoryException>()),
      );
      expect(
        () => validateCashReadScope(movement(), 'company', user(role: 'admin')),
        returnsNormally,
      );
    },
  );
  test(
    'repository keeps rep account isolation, cursor paging and full-scope totals',
    () async {
      final store = _Store([
        _row('own-new', 'holder', 'rep_cash', 4),
        _row('own-old', 'holder', 'rep_cash', 2),
        _row('foreign-rep', 'other', 'rep_cash', 3),
        _row('company-row', '', 'company_cash', 3),
      ]);
      final calls = _Calls();
      final repo = FinancialRepository(
        firestore: store,
        contextReader: _Context(user()),
        trustedCallableClient: calls,
      );
      final page = await repo.fetchCashPage(companyId: 'company', pageSize: 1);
      expect(page.snapshot.movements.map((m) => m.id), ['own-new']);
      expect(page.hasMore, isTrue);
      expect(page.snapshot.units('closingBalance'), BigInt.from(80000));
      final more = await repo.fetchCashMovementDetailsPage(
        companyId: 'company',
        pageSize: 1,
        after: page.cursor,
      );
      expect(more.items.map((m) => m.id), ['own-old']);
      expect(more.hasMore, isFalse);
      expect(calls.names.toSet(), {'getCashOpeningBalance'});
      expect(
        store.filters,
        containsAll(['salesRepId=holder', 'cashAccount=rep_cash']),
      );
    },
  );
  test(
    'date filters and full export use the complete authorized scope',
    () async {
      final rows = List.generate(
        205,
        (i) => _row('row-$i', 'holder', 'rep_cash', 2),
      );
      rows.add(_row('outside', 'holder', 'rep_cash', 1));
      final store = _Store(rows);
      final repo = FinancialRepository(
        firestore: store,
        contextReader: _Context(user()),
        trustedCallableClient: _Calls(),
      );
      final export = await repo.fetchCash(
        companyId: 'company',
        fromDate: DateTime(2026, 11, 2),
        toDate: DateTime(2026, 11, 3),
      );
      expect(export.movements, hasLength(205));
      expect(export.movements.every((m) => m.id != 'outside'), isTrue);
      expect(export.units('openingBalance'), BigInt.from(10000));
      expect(export.units('closingBalance'), BigInt.from(80000));
      expect(export.units('totalIn'), BigInt.from(205));
      expect(export.units('totalOut'), BigInt.zero);
    },
  );
  test(
    'missing reported openings and rep balances remain unavailable',
    () async {
      final repo = FinancialRepository(
        firestore: _Store([_row('one', 'holder', 'rep_cash', 2)]),
        contextReader: _Context(user()),
        trustedCallableClient: _Calls(missing: true),
      );
      final page = await repo.fetchCashPage(companyId: 'company');
      expect(page.snapshot.units('openingBalance'), isNull);
      expect(page.snapshot.units('closingBalance'), isNull);
      expect(
        page.snapshot.repCashOutstandingBySalesRep.single.cashUnits,
        isNull,
      );
    },
  );
  test(
    'repository refuses cross-company access before querying movements',
    () async {
      final store = _Store([]);
      final repo = FinancialRepository(
        firestore: store,
        contextReader: _Context(user()),
        trustedCallableClient: _Calls(),
      );
      await expectLater(
        repo.fetchCashPage(companyId: 'foreign'),
        throwsA(isA<FinancialRepositoryException>()),
      );
      expect(store.reads, 0);
    },
  );
  for (final locale in ['en', 'ar']) {
    testWidgets('cash details $locale remain selectable at 320px and 2x text', (
      tester,
    ) async {
      Get.reset();
      Get.locale = Locale(locale);
      await tester.binding.setSurfaceSize(const Size(320, 700));
      addTearDown(() {
        tester.binding.setSurfaceSize(null);
        Get.reset();
      });
      await tester.pumpWidget(
        GetMaterialApp(
          translations: MyTranslation(),
          locale: Locale(locale),
          home: Directionality(
            textDirection: locale == 'ar'
                ? TextDirection.rtl
                : TextDirection.ltr,
            child: MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(2)),
              child: Scaffold(
                body: SingleChildScrollView(
                  child: CashMovementDetails(
                    movement: movement(),
                    initiallyExpanded: true,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(SelectableText), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  }
}

Map<String, dynamic> _row(String id, String rep, String account, int day) => {
  'id': id,
  'companyId': 'company',
  'salesRepId': rep,
  'cashAccount': account,
  'type': 'receipt_cash',
  'movementType': 'receipt',
  'direction': 'in',
  'amount': 0.001,
  'date': Timestamp.fromDate(DateTime(2026, 11, day)),
  'createdAt': Timestamp.fromDate(DateTime(2026, 11, day)),
};

class _Context implements BusinessUserContextReader {
  _Context(this.context);
  final BusinessUserContext context;
  @override
  Future<BusinessUserContext> requireApprovedUser() async => context;
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _Calls implements TrustedCallableClient {
  _Calls({this.missing = false});
  final bool missing;
  final names = <String>[];
  int count = 0;
  @override
  Future<HttpsCallableResult<T>> callAuthenticated<T>(
    String name,
    Map<String, dynamic> payload,
  ) async {
    names.add(name);
    final closing = count++ % 2 == 1;
    final data = <String, dynamic>{
      if (!missing) 'openingBalance': 10,
      if (!missing) 'companyCashOpening': closing ? 1000 : 100,
      if (!missing) 'repCashOpening': closing ? 80 : 10,
      'repCashOpeningBySalesRep': [
        {
          'salesRepId': 'holder',
          'salesRepName': 'Holder',
          if (!missing) 'amount': 80,
        },
      ],
    };
    return _Result<T>(data as T);
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _Result<T> implements HttpsCallableResult<T> {
  _Result(this.data);
  @override
  final T data;
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _Store implements FirebaseFirestore {
  _Store(this.rows);
  final List<Map<String, dynamic>> rows;
  final filters = <String>[];
  int reads = 0;
  @override
  CollectionReference<Map<String, dynamic>> collection(String path) =>
      _Collection(this, path);
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _Collection implements CollectionReference<Map<String, dynamic>> {
  _Collection(this.store, this.path);
  final _Store store;
  @override
  final String path;
  @override
  DocumentReference<Map<String, dynamic>> doc([String? path]) =>
      _Ref(store, '${this.path}/$path');
  @override
  dynamic noSuchMethod(Invocation i) => _Query(store).noSuchMethod(i);
}

class _Ref implements DocumentReference<Map<String, dynamic>> {
  _Ref(this.store, this.path);
  final _Store store;
  @override
  final String path;
  @override
  CollectionReference<Map<String, dynamic>> collection(String path) =>
      _Collection(store, '${this.path}/$path');
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _Query implements Query<Map<String, dynamic>> {
  _Query(this.store, {this.conditions = const [], this.limitCount, this.after});
  final _Store store;
  final List<bool Function(Map<String, dynamic>)> conditions;
  final int? limitCount;
  final String? after;
  List<Map<String, dynamic>> selected() {
    var rows = store.rows
        .where((r) => conditions.every((test) => test(r)))
        .toList();
    rows.sort((a, b) {
      final date = (b['date'] as Timestamp).compareTo(a['date'] as Timestamp);
      return date != 0
          ? date
          : (b['id'] as String).compareTo(a['id'] as String);
    });
    if (after != null) {
      rows = rows.skip(rows.indexWhere((r) => r['id'] == after) + 1).toList();
    }
    if (limitCount != null) rows = rows.take(limitCount!).toList();
    return rows;
  }

  @override
  dynamic noSuchMethod(Invocation i) {
    if (i.memberName == #where) {
      final field = i.positionalArguments[0] as String;
      final eq = i.namedArguments[#isEqualTo],
          low = i.namedArguments[#isGreaterThanOrEqualTo],
          high = i.namedArguments[#isLessThanOrEqualTo];
      if (eq != null) store.filters.add('$field=$eq');
      return _Query(
        store,
        conditions: [
          ...conditions,
          (r) => eq != null
              ? r[field] == eq
              : low != null
              ? (r[field] as Timestamp).compareTo(low as Timestamp) >= 0
              : (r[field] as Timestamp).compareTo(high as Timestamp) <= 0,
        ],
        limitCount: limitCount,
        after: after,
      );
    }
    if (i.memberName == #orderBy) return this;
    if (i.memberName == #limit) {
      return _Query(
        store,
        conditions: conditions,
        limitCount: i.positionalArguments[0] as int,
        after: after,
      );
    }
    if (i.memberName == #startAfterDocument) {
      return _Query(
        store,
        conditions: conditions,
        limitCount: limitCount,
        after: (i.positionalArguments[0] as DocumentSnapshot).id,
      );
    }
    if (i.memberName == #get) {
      store.reads++;
      return Future<QuerySnapshot<Map<String, dynamic>>>.value(
        _Snapshot(selected()),
      );
    }
    if (i.memberName == #aggregate) return _Aggregate(this);
    return super.noSuchMethod(i);
  }
}

class _Snapshot implements QuerySnapshot<Map<String, dynamic>> {
  _Snapshot(List<Map<String, dynamic>> rows)
    : docs = rows.map(_Doc.new).toList();
  @override
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs;
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _Doc implements QueryDocumentSnapshot<Map<String, dynamic>> {
  _Doc(this.value);
  final Map<String, dynamic> value;
  @override
  String get id => value['id'] as String;
  @override
  Map<String, dynamic> data() => value;
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _Aggregate implements AggregateQuery {
  _Aggregate(this.query);
  @override
  final _Query query;
  @override
  Future<AggregateQuerySnapshot> get({
    AggregateSource source = AggregateSource.server,
  }) async => _AggregateResult(query.selected());
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _AggregateResult implements AggregateQuerySnapshot {
  _AggregateResult(this.rows);
  final List<Map<String, dynamic>> rows;
  @override
  double? getSum(String field) =>
      rows.fold<double>(0, (total, r) => total + (r[field] as num).toDouble());
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}
