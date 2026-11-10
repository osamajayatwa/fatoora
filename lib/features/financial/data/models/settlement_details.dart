import 'dart:collection';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:fatoora/core/finance/exact_decimal.dart';

enum SettlementDetailsOrigin {
  syntheticFixture,
  authenticatedEmulator,
  authenticatedStaging,
}

enum SettlementReadFailure { expired, denied, unavailable, corrupt }

final class SettlementReadException implements Exception {
  const SettlementReadException(this.failure);
  final SettlementReadFailure failure;
}

/// One presentation contract for explicit fixtures and authenticated emulator
/// reads. Implementations cannot turn an incomplete inventory into detail pages.
abstract interface class SettlementDetailsSource {
  Stream<SettlementReadFailure> get invalidations;
  String get companyId;
  String get representativeId;
  String get settlementId;
  String get representativeLabel;
  String get settlementLabel;
  SettlementDetailsOrigin get origin;
  bool get coverageIncomplete;
  bool get expired;
  int? get expiresAtMillis;
  Future<SettlementDetailPage> read(int index);
  void reset();
  Future<void> authorizePdf(SettlementDetailsReport report);
  void requirePdfPermission(SettlementDetailsReport report);
}

/// A bounded delivery of existing detail pages, authorized as one server response.
/// No client prefetch cache or alternative accounting DTO is introduced.
abstract interface class SettlementDetailsBatchSource
    implements SettlementDetailsSource {
  Future<List<SettlementDetailPage>> readBatch(int index);
}

/// JSON checksum compatibility with the backend's read-only inventory codec.
/// Checksums detect corruption/mixed pages; they do not authenticate a source.
String settlementEvidenceDigest(Object? value) {
  var nodes = 0;
  Object? normalize(Object? v, int depth) {
    _require(++nodes <= 300000 && depth <= 16, 'Evidence structural bound');
    if (v == null || v is bool) return v;
    if (v is String) {
      _require(v.length <= 2048, 'Evidence string bound');
      return v;
    }
    if (v is int) {
      _require(v.abs() <= 9007199254740991, 'Unsafe JSON integer');
      return v;
    }
    if (v is List) {
      _require(v.length <= 16000, 'Evidence list bound');
      return v.map((e) => normalize(e, depth + 1)).toList();
    }
    _require(
      v is Map && v.keys.every((k) => k is String),
      'Plain JSON required',
    );
    final map = v as Map;
    _require(map.length <= 64, 'Evidence object bound');
    final keys = map.keys.cast<String>().toList()..sort();
    for (final key in keys) {
      _require(key.length <= 128, 'Evidence key bound');
    }
    return {for (final key in keys) key: normalize(map[key], depth + 1)};
  }

  final bytes = utf8.encode(jsonEncode(normalize(value, 0)));
  _require(bytes.length <= 16777216, 'Evidence byte bound');
  return sha256.convert(bytes).toString();
}

void _require(bool condition, String message) {
  if (!condition) throw FormatException(message);
}

Map<String, dynamic> _map(Object? value) {
  _require(
    value is Map && value.keys.every((k) => k is String),
    'Object required',
  );
  return Map<String, dynamic>.from(value as Map);
}

String _text(Object? value, {bool nullable = false}) {
  if (nullable && value == null) return '';
  _require(value is String && value.length <= 2048, 'Bounded text required');
  return value as String;
}

String _id(Object? value) {
  final s = _text(value);
  _require(
    s.isNotEmpty &&
        s.length <= 256 &&
        s.trim() == s &&
        s != '.' &&
        s != '..' &&
        !RegExp(r'[\\/\x00-\x1f\x7f]').hasMatch(s),
    'Invalid identifier',
  );
  return s;
}

BigInt settlementUnits(Object? value) {
  _require(
    value is String &&
        RegExp(r'^(0|-?[1-9][0-9]*)$').firstMatch(value)?.end == value.length,
    'Canonical integer units required',
  );
  final units = BigInt.parse(value as String);
  _require(units.abs() <= ExactDecimal.maxUnits, 'Unit range exceeded');
  return units;
}

int _integer(Object? value, int min, int max) {
  _require(
    value is int && value >= min && value <= max,
    'Bounded integer required',
  );
  return value as int;
}

void _keys(Map<String, dynamic> value, Iterable<String> keys) {
  _require(
    value.length == keys.length && keys.every(value.containsKey),
    'Unexpected or missing contract fields',
  );
}

Object? _freeze(Object? value) => value is Map
    ? Map<String, dynamic>.unmodifiable({
        for (final entry in value.entries)
          entry.key as String: _freeze(entry.value),
      })
    : value is List
    ? List<Object?>.unmodifiable(value.map(_freeze))
    : value;

final class SettlementTime implements Comparable<SettlementTime> {
  const SettlementTime._(this.seconds, this.nanoseconds);
  factory SettlementTime.fromJson(Object? value) {
    final m = _map(value);
    _keys(m, ['seconds', 'nanoseconds']);
    return SettlementTime._(
      _integer(m['seconds'], -62135596800, 253402300799),
      _integer(m['nanoseconds'], 0, 999999999),
    );
  }
  final int seconds, nanoseconds;
  BigInt get _ticks =>
      BigInt.from(seconds) * BigInt.from(1000000000) + BigInt.from(nanoseconds);
  @override
  int compareTo(SettlementTime other) => _ticks.compareTo(other._ticks);
  String get isoUtc =>
      '${DateTime.fromMillisecondsSinceEpoch(seconds * 1000, isUtc: true).toIso8601String().split('.').first}.${nanoseconds.toString().padLeft(9, '0')}Z';
  String get dateUtc => isoUtc.substring(0, 10);
}

final class SettlementActor {
  SettlementActor.fromJson(Object? value) {
    final m = _map(value);
    _keys(m, ['uid', 'name', 'role', 'basis']);
    uid = m['uid'] == null ? null : _id(m['uid']);
    name = m['name'] == null ? null : _text(m['name']);
    role = m['role'] == null ? null : _text(m['role']);
    basis = _text(m['basis']);
  }
  late final String? uid, name, role;
  late final String basis;
}

final class SettlementSourceReference {
  SettlementSourceReference._(
    this.id,
    this.path,
    this.number,
    this.role,
    this.versionAfterCutoff,
  );
  factory SettlementSourceReference.linked(
    Object? value,
    String companyId,
    SettlementTime cutoff,
  ) {
    final m = _map(value);
    _keys(m, [
      'id',
      'path',
      'number',
      'businessDate',
      'createTime',
      'updateTime',
      'role',
      'versionAfterCutoff',
    ]);
    final id = _id(m['id']), path = _text(m['path']);
    _require(
      path.startsWith('companies/$companyId/') &&
          path.split('/').length == 4 &&
          path.split('/').last == id,
      'Cross-company source',
    );
    final created = SettlementTime.fromJson(m['createTime']),
        updated = SettlementTime.fromJson(m['updateTime']);
    _require(
      created.compareTo(updated) <= 0 &&
          m['versionAfterCutoff'] == (updated.compareTo(cutoff) > 0),
      'Source version evidence differs',
    );
    if (m['businessDate'] != null) SettlementTime.fromJson(m['businessDate']);
    return SettlementSourceReference._(
      id,
      path,
      m['number'] == null ? null : _text(m['number']),
      _text(m['role']),
      m['versionAfterCutoff'] as bool,
    );
  }
  final String id, path, role;
  final String? number;
  final bool versionAfterCutoff;
}

final class SettlementDetailRow {
  SettlementDetailRow._(
    this.raw,
    String companyId,
    String representativeId,
    SettlementTime cutoff,
  ) {
    _keys(raw, [
      'id',
      'path',
      'category',
      'verification',
      'cashAccount',
      'holderType',
      'holderUid',
      'amountUnits',
      'signedUnits',
      'beforeUnits',
      'afterUnits',
      'committedAt',
      'recordedAt',
      'businessDate',
      'source',
      'sourceNumber',
      'movementCreator',
      'sourceCreator',
      'collector',
      'postingActor',
      'recordedProvenance',
      'recordedSalesRepId',
      'originalSellers',
      'receivableAllocations',
      'collectionMovementIds',
      'reversesMovementId',
      'counterpartMovementId',
      'unallocatedReceiptUnits',
      'referencedDocuments',
    ]);
    id = _id(raw['id']);
    path = _text(raw['path']);
    category = _text(raw['category']);
    verification = _text(raw['verification']);
    _require(
      path == 'companies/$companyId/cash_movements/$id' &&
          raw['cashAccount'] == 'rep_cash' &&
          raw['holderType'] == 'representative' &&
          raw['holderUid'] == representativeId,
      'Wrong cash holder or scope',
    );
    _require(
      ['verified', 'blocked'].contains(verification) &&
          categories.contains(category),
      'Unknown cash category/state',
    );
    amount = settlementUnits(raw['amountUnits']);
    signed = settlementUnits(raw['signedUnits']);
    before = settlementUnits(raw['beforeUnits']);
    after = settlementUnits(raw['afterUnits']);
    _require(
      amount > BigInt.zero &&
          signed.abs() == amount &&
          before >= BigInt.zero &&
          after >= BigInt.zero &&
          before + signed == after,
      'Exact cash equation differs',
    );
    if ([
      'opening',
      'invoice_collection',
      'receipt_collection',
    ].contains(category)) {
      _require(signed > BigInt.zero, 'Wrong inflow sign');
    }
    if ([
      'cash_refund',
      'cash_expense',
      'receipt_cancellation',
      'settlement',
    ].contains(category)) {
      _require(signed < BigInt.zero, 'Wrong outflow sign');
    }
    committedAt = SettlementTime.fromJson(raw['committedAt']);
    recordedAt = SettlementTime.fromJson(raw['recordedAt']);
    businessDate = SettlementTime.fromJson(raw['businessDate']);
    _require(
      committedAt.compareTo(cutoff) <= 0 &&
          recordedAt.compareTo(committedAt) <= 0,
      'Cash timestamp exceeds cutoff/commit',
    );
    final source = _map(raw['source']);
    _keys(source, [
      'collection',
      'id',
      'path',
      'createTime',
      'updateTime',
      'versionAfterCutoff',
      'recordedCreatedAt',
      'recordedPostedAt',
      'businessDate',
    ]);
    sourceId = _id(source['id']);
    sourceCollection = _text(source['collection']);
    sourcePath = _text(source['path']);
    _require(
      [
            'cash_movements',
            'invoices',
            'receipts',
            'sales_returns',
            'expenses',
            'settlements',
          ].contains(sourceCollection) &&
          sourcePath == 'companies/$companyId/$sourceCollection/$sourceId',
      'Invalid source reference',
    );
    final created = SettlementTime.fromJson(source['createTime']),
        updated = SettlementTime.fromJson(source['updateTime']);
    _require(
      created.compareTo(committedAt) <= 0 &&
          created.compareTo(updated) <= 0 &&
          source['versionAfterCutoff'] == (updated.compareTo(cutoff) > 0),
      'Invalid source version',
    );
    for (final key in [
      'recordedCreatedAt',
      'recordedPostedAt',
      'businessDate',
    ]) {
      if (source[key] != null) SettlementTime.fromJson(source[key]);
    }
    sourceNumber = raw['sourceNumber'] == null
        ? null
        : _text(raw['sourceNumber']);
    holderUid = representativeId;
    movementCreator = SettlementActor.fromJson(raw['movementCreator']);
    sourceCreator = SettlementActor.fromJson(raw['sourceCreator']);
    collector = SettlementActor.fromJson(raw['collector']);
    postingActor = SettlementActor.fromJson(raw['postingActor']);
    final provenance = _map(raw['recordedProvenance']);
    _keys(provenance, [
      'sellerId',
      'sellerName',
      'collector',
      'postedBy',
      'sourceCreatedBy',
    ]);
    for (final key in ['collector', 'postedBy', 'sourceCreatedBy']) {
      SettlementActor.fromJson(provenance[key]);
    }
    for (final key in ['sellerId', 'sellerName']) {
      if (provenance[key] != null) _text(provenance[key]);
    }
    if (raw['recordedSalesRepId'] != null) _id(raw['recordedSalesRepId']);
    for (final key in ['reversesMovementId', 'counterpartMovementId']) {
      if (raw[key] != null) _id(raw[key]);
    }
    if (raw['unallocatedReceiptUnits'] != null) {
      _require(
        settlementUnits(raw['unallocatedReceiptUnits']) >= BigInt.zero,
        'Negative unallocated receipt',
      );
    }
    final sellers = raw['originalSellers'];
    _require(
      sellers is List && sellers.length <= 2048,
      'Seller reference bound',
    );
    for (final s in sellers as List) {
      final m = _map(s);
      _keys(m, ['invoiceId', 'uid', 'name']);
      _id(m['invoiceId']);
      if (m['uid'] != null) _id(m['uid']);
      if (m['name'] != null) _text(m['name']);
    }
    final allocations = raw['receivableAllocations'];
    _require(
      allocations is List && allocations.length <= 2048,
      'Allocation reference bound',
    );
    final seenInvoices = <String>{};
    var allocated = BigInt.zero;
    for (final a in allocations as List) {
      final m = _map(a);
      _keys(m, ['invoiceId', 'amountUnits']);
      _require(
        seenInvoices.add(_id(m['invoiceId'])),
        'Duplicate receivable annotation',
      );
      final units = settlementUnits(m['amountUnits']);
      _require(units > BigInt.zero, 'Nonpositive annotation');
      allocated += units;
    }
    if (category == 'receipt_collection' ||
        category == 'receipt_cancellation') {
      _require(
        allocated <= amount &&
            raw['unallocatedReceiptUnits'] != null &&
            amount - allocated ==
                settlementUnits(raw['unallocatedReceiptUnits']),
        'Receipt annotations multiply cash',
      );
    }
    final refs = raw['collectionMovementIds'];
    _require(refs is List && refs.length <= 2048, 'Collection reference bound');
    final refIds = (refs as List).map(_id).toList();
    _require(
      refIds.toSet().length == refIds.length,
      'Duplicate collection reference',
    );
    final linked = raw['referencedDocuments'];
    _require(linked is List && linked.length <= 2048, 'Linked-document bound');
    references = List.unmodifiable(
      (linked as List).map(
        (r) => SettlementSourceReference.linked(r, companyId, cutoff),
      ),
    );
    _require(
      references.map((r) => r.path).toSet().length == references.length,
      'Duplicate linked document',
    );
  }
  static const categories = {
    'opening',
    'invoice_collection',
    'receipt_collection',
    'cash_refund',
    'cash_expense',
    'receipt_cancellation',
    'settlement',
    'unsupported_adjustment',
  };
  final Map<String, dynamic> raw;
  late final String id,
      path,
      category,
      verification,
      sourceId,
      sourceCollection,
      sourcePath,
      holderUid;
  late final String? sourceNumber;
  late final BigInt amount, signed, before, after;
  late final SettlementTime committedAt, recordedAt, businessDate;
  late final SettlementActor movementCreator,
      sourceCreator,
      collector,
      postingActor;
  late final List<SettlementSourceReference> references;
}

final class SettlementDetailPage {
  SettlementDetailPage._(this.raw) {
    _keys(raw, [
      'schemaVersion',
      'companyId',
      'salesRepId',
      'settlementId',
      'evidenceDigest',
      'snapshotDigest',
      'cutoff',
      'status',
      'currency',
      'moneyScale',
      'opening',
      'carry',
      'totals',
      'issues',
      'issueCount',
      'detailScope',
      'order',
      'rowCount',
      'pageSize',
      'pageCount',
      'pageIndex',
      'offset',
      'nextPageIndex',
      'rows',
      'pageDigest',
    ]);
    _require(
      raw['schemaVersion'] == 1 &&
          raw['moneyScale'] == 3 &&
          raw['pageSize'] == 64 &&
          raw['detailScope'] == 'through_cutoff' &&
          raw['order'] == 'sdk_commit',
      'Unsupported settlement contract',
    );
    companyId = _id(raw['companyId']);
    representativeId = _id(raw['salesRepId']);
    settlementId = raw['settlementId'] == null
        ? null
        : _id(raw['settlementId']);
    for (final key in ['evidenceDigest', 'snapshotDigest', 'pageDigest']) {
      _require(
        raw[key] is String &&
            (raw[key] as String).length == 64 &&
            RegExp(r'^[a-f0-9]{64}$').hasMatch(raw[key]),
        'Invalid digest',
      );
    }
    evidenceDigest = raw['evidenceDigest'] as String;
    snapshotDigest = raw['snapshotDigest'] as String;
    currency = _text(raw['currency']);
    _require(
      currency.length == 3 && RegExp(r'^[A-Z]{3}$').hasMatch(currency),
      'Invalid currency',
    );
    final cut = _map(raw['cutoff']);
    _keys(cut, ['basis', 'inclusiveThrough']);
    _require(cut['basis'] == 'sdk_commit_order', 'Invalid cutoff basis');
    cutoff = SettlementTime.fromJson(cut['inclusiveThrough']);
    status = _text(raw['status']);
    _require(
      ['verified_cash_reconstruction', 'blocked'].contains(status),
      'Unknown financial state',
    );
    rowCount = _integer(raw['rowCount'], 0, 16000);
    pageCount = _integer(raw['pageCount'], 1, 250);
    pageIndex = _integer(raw['pageIndex'], 0, pageCount - 1);
    _require(
      pageCount == (rowCount == 0 ? 1 : (rowCount + 63) ~/ 64) &&
          raw['offset'] == pageIndex * 64 &&
          raw['nextPageIndex'] ==
              (pageIndex + 1 < pageCount ? pageIndex + 1 : null),
      'Invalid page coverage/continuation',
    );
    final opening = _map(raw['opening']);
    _keys(opening, ['state', 'amountUnits', 'movementId']);
    final carry = _map(raw['carry']);
    _keys(carry, ['state', 'amountUnits', 'previousSettlementId']);
    _require(
      ['verified_recorded_opening', 'unknown'].contains(opening['state']) &&
          ['verified', 'unverifiable'].contains(carry['state']),
      'Invalid opening/carry state',
    );
    if (opening['state'] == 'unknown') {
      _require(
        opening['amountUnits'] == null && opening['movementId'] == null,
        'Unknown opening cannot be zero',
      );
    } else {
      _require(
        settlementUnits(opening['amountUnits']) > BigInt.zero,
        'Invalid opening',
      );
      _id(opening['movementId']);
    }
    if (carry['previousSettlementId'] != null) {
      _id(carry['previousSettlementId']);
    }
    if (carry['state'] == 'unverifiable') {
      _require(carry['amountUnits'] == null, 'Unknown carry cannot be zero');
    } else {
      _require(
        settlementUnits(carry['amountUnits']) >= BigInt.zero,
        'Invalid carry',
      );
    }
    if (status == 'blocked') {
      _require(raw['totals'] == null, 'Blocked evidence cannot certify totals');
      totals = null;
    } else {
      _require(
        opening['state'] == 'verified_recorded_opening' &&
            carry['state'] == 'verified',
        'Totals require verified opening/carry',
      );
      final t = _map(raw['totals']);
      _keys(t, totalKeys);
      totals = Map.unmodifiable({
        for (final key in totalKeys) key: settlementUnits(t[key]),
      });
      for (final key in totalKeys.where(
        (k) => k != 'activitySinceCarryUnits',
      )) {
        _require(totals![key]! >= BigInt.zero, 'Negative certified balance');
      }
      _require(
        totals!['openingUnits'] == settlementUnits(opening['amountUnits']) &&
            totals!['carryUnits'] == settlementUnits(carry['amountUnits']) &&
            totals!['carryUnits']! + totals!['activitySinceCarryUnits']! ==
                totals!['cashAvailableBeforeUnits'] &&
            totals!['cashAvailableBeforeUnits']! -
                    totals!['transferredUnits']! ==
                totals!['remainingUnits'],
        'Exact summary equation differs',
      );
    }
    _integer(raw['issueCount'], 0, 1000000);
    final issues = raw['issues'];
    _require(
      issues is List &&
          issues.length <= 64 &&
          raw['issueCount'] >= issues.length,
      'Issue coverage differs',
    );
    for (final issue in issues as List) {
      final m = _map(issue);
      _keys(m, ['code', 'path', 'message']);
      for (final key in m.keys) {
        _text(m[key]);
      }
    }
    _require(
      status == 'blocked' ? raw['issueCount'] > 0 : raw['issueCount'] == 0,
      'Financial state and issues differ',
    );
    final data = raw['rows'];
    _require(
      data is List && data.length == ((rowCount - pageIndex * 64).clamp(0, 64)),
      'Missing/extra page rows',
    );
    rows = List.unmodifiable(
      (data as List).map(
        (r) => SettlementDetailRow._(
          Map.unmodifiable(_map(r)),
          companyId,
          representativeId,
          cutoff,
        ),
      ),
    );
    final header = Map<String, dynamic>.from(raw)
      ..remove('pageDigest')
      ..remove('rows');
    _require(
      settlementEvidenceDigest({
            ...header,
            'rowDigests': rows
                .map((r) => settlementEvidenceDigest(r.raw))
                .toList(),
          }) ==
          raw['pageDigest'],
      'Modified settlement page',
    );
    final common = Map<String, dynamic>.from(raw)
      ..remove('pageIndex')
      ..remove('offset')
      ..remove('nextPageIndex')
      ..remove('rows')
      ..remove('pageDigest');
    headerDigest = settlementEvidenceDigest(common);
  }
  factory SettlementDetailPage.fromJson(Map<String, dynamic> value) {
    settlementEvidenceDigest(value); // Validate types/ranges before freezing.
    return SettlementDetailPage._(_freeze(value) as Map<String, dynamic>);
  }
  static const totalKeys = [
    'openingUnits',
    'carryUnits',
    'activitySinceCarryUnits',
    'cashAvailableBeforeUnits',
    'transferredUnits',
    'remainingUnits',
    'currentBalanceUnits',
  ];
  final Map<String, dynamic> raw;
  late final String companyId,
      representativeId,
      evidenceDigest,
      snapshotDigest,
      currency,
      status,
      headerDigest;
  late final String? settlementId;
  late final int pageIndex, pageCount, rowCount;
  late final SettlementTime cutoff;
  late final Map<String, BigInt>? totals;
  late final List<SettlementDetailRow> rows;
}

/// Incremental page validation with O(new page) work; totals remain unavailable
/// until the whole immutable snapshot sequence has passed reconciliation.
final class SettlementDetailsAssembly {
  SettlementDetailsAssembly({
    required this.companyId,
    required this.representativeId,
    required this.settlementId,
    this.origin = SettlementDetailsOrigin.syntheticFixture,
  });
  final SettlementDetailsOrigin origin;
  final String companyId, representativeId, settlementId;
  final List<SettlementDetailPage> _pages = [];
  final List<SettlementDetailRow> _rows = [];
  final Set<String> _seen = {};
  SettlementDetailPage? get header => _pages.isEmpty ? null : _pages.first;
  List<SettlementDetailRow> get rows => UnmodifiableListView(_rows);
  int get loadedPages => _pages.length;
  bool get complete => header != null && _pages.length == header!.pageCount;
  bool get verified =>
      complete && header!.status == 'verified_cash_reconstruction';
  Map<String, BigInt>? get certifiedTotals => verified ? header!.totals : null;
  void addBatch(List<SettlementDetailPage> pages) {
    _require(
      pages.isNotEmpty && pages.length <= 6,
      'Bounded page batch required',
    );
    final pageCount = _pages.length, rowCount = _rows.length;
    try {
      for (final page in pages) {
        add(page);
      }
    } catch (_) {
      _seen.removeAll(_rows.skip(rowCount).map((row) => row.id));
      _rows.removeRange(rowCount, _rows.length);
      _pages.removeRange(pageCount, _pages.length);
      rethrow;
    }
  }

  void add(SettlementDetailPage page) {
    _require(
      !complete &&
          page.companyId == companyId &&
          page.representativeId == representativeId &&
          page.settlementId == settlementId &&
          page.pageIndex == _pages.length,
      'Mixed scope, missing or duplicate page',
    );
    if (header != null) {
      _require(
        page.headerDigest == header!.headerDigest,
        'Mixed snapshot/header',
      );
    }
    final newIds = <String>{};
    SettlementDetailRow? previous = _rows.isEmpty ? null : _rows.last;
    for (final row in page.rows) {
      _require(
        !_seen.contains(row.id) && newIds.add(row.id),
        'Duplicate cash movement',
      );
      if (previous != null) {
        _require(
          previous.committedAt.compareTo(row.committedAt) <=
              (page.status == 'blocked' ? 0 : -1),
          'Invalid committed ordering',
        );
        if (page.status != 'blocked') {
          _require(previous.after == row.before, 'Cash chain gap');
        }
      }
      if (page.status != 'blocked') {
        _require(
          row.verification == 'verified',
          'Unverified movement in certified report',
        );
      }
      previous = row;
    }
    // Stage first: rejection must leave the previous valid pages unchanged.
    if (_pages.length + 1 == page.pageCount) {
      _reconcile(page, [..._rows, ...page.rows]);
    }
    _pages.add(page);
    _rows.addAll(page.rows);
    _seen.addAll(newIds);
  }

  void _reconcile(SettlementDetailPage page, List<SettlementDetailRow> all) {
    _require(all.length == page.rowCount, 'Truncated settlement');
    if (page.status == 'blocked') return;
    final t = page.totals!,
        opening = _map(page.raw['opening']),
        carry = _map(page.raw['carry']);
    _require(
      all.isNotEmpty &&
          all.first.category == 'opening' &&
          all.first.id == opening['movementId'] &&
          all.first.before == BigInt.zero &&
          all.first.amount == t['openingUnits'],
      'Opening witness differs',
    );
    _require(
      ExactDecimal.sumUnits(all.map((r) => r.signed)) == t['remainingUnits'],
      'Settlement detail cash sum differs',
    );
    final targets = all
        .where((r) => r.category == 'settlement' && r.sourceId == settlementId)
        .toList();
    _require(
      targets.length == 1 && identical(targets.single, all.last),
      'Selected transfer missing or not last',
    );
    final target = targets.single;
    _require(
      target.committedAt.compareTo(page.cutoff) == 0 &&
          target.amount == t['transferredUnits'] &&
          target.before == t['cashAvailableBeforeUnits'] &&
          target.after == t['remainingUnits'],
      'Transfer/cutoff summary differs',
    );
    final prior = all
        .take(all.length - 1)
        .where((r) => r.category == 'settlement')
        .toList();
    _require(
      carry['previousSettlementId'] ==
              (prior.isEmpty ? null : prior.last.sourceId) &&
          t['carryUnits'] ==
              (prior.isEmpty ? all.first.after : prior.last.after),
      'Carried balance witness differs',
    );
    final start = prior.isEmpty ? 1 : all.indexOf(prior.last) + 1;
    _require(
      ExactDecimal.sumUnits(
            all.sublist(start, all.length - 1).map((r) => r.signed),
          ) ==
          t['activitySinceCarryUnits'],
      'Carry activity differs',
    );
  }

  SettlementDetailsReport finish() {
    _require(complete, 'Complete settlement pages required');
    return SettlementDetailsReport._(header!, List.unmodifiable(_rows), origin);
  }
}

final class SettlementDetailsReport {
  const SettlementDetailsReport._(this.header, this.rows, this.origin);
  final SettlementDetailsOrigin origin;
  final SettlementDetailPage header;
  final List<SettlementDetailRow> rows;
  bool get verified => header.status == 'verified_cash_reconstruction';
  Map<String, BigInt>? get certifiedTotals => verified ? header.totals : null;
}
