import 'dart:convert';
import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:fatoora/features/financial/data/models/settlement_details.dart';

typedef SettlementCallable =
    Future<Map<String, dynamic>> Function(Map<String, dynamic> request);

/// Created by the repository only after the exact emulator target is configured.
/// No fixture fallback, direct Firestore query or client-supplied financial input.
final class AuthenticatedSettlementDetailsSource
    implements SettlementDetailsBatchSource {
  AuthenticatedSettlementDetailsSource({
    required this.companyId,
    required this.representativeId,
    required this.settlementId,
    required SettlementCallable invoke,
    SettlementDetailsOrigin origin =
        SettlementDetailsOrigin.authenticatedEmulator,
    DateTime Function()? clock,
  }) : _invoke = invoke,
       _origin = origin,
       _clock = clock ?? DateTime.now {
    if (origin == SettlementDetailsOrigin.syntheticFixture ||
        origin == SettlementDetailsOrigin.authenticatedEmulator &&
            !kDebugMode ||
        origin == SettlementDetailsOrigin.authenticatedStaging &&
            (!const bool.fromEnvironment('FATOORA_SETTLEMENT_STAGING_PILOT') ||
                const String.fromEnvironment('FATOORA_ENV') != 'staging' ||
                companyId != 'default_company')) {
      throw StateError('Settlement transport origin is not approved');
    }
  }
  final SettlementDetailsOrigin _origin;
  final SettlementCallable _invoke;
  final DateTime Function() _clock;
  final _invalidations = StreamController<SettlementReadFailure>.broadcast(
    sync: true,
  );
  @override
  Stream<SettlementReadFailure> get invalidations => _invalidations.stream;
  int _generation = 0;
  void _invalidate(SettlementReadFailure failure) {
    _invalid = true;
    _pdfUntil = null;
    _representativeLabel = null;
    _settlementLabel = null;
    _tokens.clear();
    _exportToken = null;
    _invalidations.add(failure);
  }

  @override
  final String companyId, representativeId, settlementId;
  String? _representativeLabel, _settlementLabel;
  @override
  String get representativeLabel => _representativeLabel ?? representativeId;
  @override
  String get settlementLabel => _settlementLabel ?? settlementId;
  @override
  SettlementDetailsOrigin get origin => _origin;
  @override
  bool coverageIncomplete = false;
  bool _invalid = false, _busy = false;
  int? _expires, _pdfUntil, _deliveryVersion;
  String? _evidence, _snapshot, _exportToken, _headerDigest;
  final Map<int, String> _tokens = {};
  @override
  int? get expiresAtMillis => _expires;
  @override
  bool get expired =>
      _invalid ||
      _expires != null && _clock().millisecondsSinceEpoch >= _expires!;
  void _need(bool value) {
    if (!value) {
      throw const FormatException('Invalid settlement transport response');
    }
  }

  void _keys(Map<String, dynamic> value, List<String> keys) =>
      _need(value.length == keys.length && keys.every(value.containsKey));
  String _text(Object? value) {
    _need(value is String && value.isNotEmpty && value.length <= 2048);
    return value as String;
  }

  String? _token(Object? value) {
    if (value == null) return null;
    _need(
      value is String &&
          value.length <= 4096 &&
          RegExp(r'^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]{43}$').hasMatch(value),
    );
    return value as String;
  }

  Future<Map<String, dynamic>> _call(Map<String, dynamic> request) async {
    try {
      final value = await _invoke(request);
      _need(utf8.encode(jsonEncode(value)).length <= 1048576);
      _need(
        (value['schemaVersion'] == 1 || value['schemaVersion'] == 2) &&
            value['provenance'] == 'authenticated_firebase',
      );
      return value;
    } on SettlementReadException catch (e) {
      if (e.failure != SettlementReadFailure.unavailable) {
        _invalidate(e.failure);
      }
      rethrow;
    } on FirebaseFunctionsException catch (e) {
      if (['permission-denied', 'unauthenticated'].contains(e.code)) {
        _invalidate(SettlementReadFailure.denied);
        throw const SettlementReadException(SettlementReadFailure.denied);
      }
      if (e.code == 'failed-precondition') {
        _invalidate(SettlementReadFailure.expired);
        throw const SettlementReadException(SettlementReadFailure.expired);
      }
      throw const SettlementReadException(SettlementReadFailure.unavailable);
    } on FirebaseAuthException {
      _invalidate(SettlementReadFailure.denied);
      throw const SettlementReadException(SettlementReadFailure.denied);
    } on FormatException {
      _invalidate(SettlementReadFailure.corrupt);
      throw const SettlementReadException(SettlementReadFailure.corrupt);
    }
  }

  @override
  Future<SettlementDetailPage> read(int index) async =>
      (await _read(index, 1)).single;

  @override
  Future<List<SettlementDetailPage>> readBatch(int index) => _read(index, 2);

  Future<List<SettlementDetailPage>> _read(int index, int version) async {
    if (expired) {
      throw const SettlementReadException(SettlementReadFailure.expired);
    }
    if (_busy) {
      throw const SettlementReadException(SettlementReadFailure.unavailable);
    }
    if (index < 0 || index > 249 || index > 0 && !_tokens.containsKey(index)) {
      throw const SettlementReadException(SettlementReadFailure.corrupt);
    }
    final generation = _generation;
    _busy = true;
    try {
      _need(_deliveryVersion == null || _deliveryVersion == version);
      _deliveryVersion = version;
      final v = await _call(
        index == 0
            ? {
                'schemaVersion': version,
                'action': 'start',
                'companyId': companyId,
                'salesRepId': representativeId,
                'settlementId': settlementId,
              }
            : {
                'schemaVersion': version,
                'action': 'page',
                'token': _tokens[index],
              },
      );
      if (generation != _generation) {
        throw const SettlementReadException(SettlementReadFailure.expired);
      }
      if (v['kind'] == 'incomplete') {
        _keys(v, [
          'schemaVersion',
          'kind',
          'provenance',
          'companyId',
          'salesRepId',
          'settlementId',
          'reason',
        ]);
        _need(
          v['schemaVersion'] == 1 &&
              index == 0 &&
              v['companyId'] == companyId &&
              v['salesRepId'] == representativeId &&
              v['settlementId'] == settlementId &&
              v['reason'] == 'incomplete_coverage',
        );
        coverageIncomplete = true;
        throw const SettlementReadException(SettlementReadFailure.unavailable);
      }
      final List<dynamic> envelopes;
      if (version == 2) {
        _keys(v, [
          'schemaVersion',
          'kind',
          'provenance',
          'firstPageIndex',
          'nextPageIndex',
          'pageCount',
          'pages',
          'deliveryDigest',
        ]);
        _need(
          v['schemaVersion'] == 2 && v['kind'] == 'pages' && v['pages'] is List,
        );
        envelopes = v['pages'] as List;
        _need(envelopes.isNotEmpty && envelopes.length <= 6);
      } else {
        envelopes = [v];
      }
      final pages = <SettlementDetailPage>[];
      for (final envelope in envelopes) {
        pages.add(
          _accept(
            Map<String, dynamic>.from(envelope as Map),
            index + pages.length,
          ),
        );
      }
      if (version == 2) {
        _need(
          v['firstPageIndex'] == index &&
              v['pageCount'] == pages.length &&
              v['nextPageIndex'] == pages.last.raw['nextPageIndex'] &&
              v['deliveryDigest'] ==
                  settlementEvidenceDigest({
                    'schemaVersion': 2,
                    'kind': 'pages',
                    'provenance': 'authenticated_firebase',
                    'firstPageIndex': index,
                    'nextPageIndex': v['nextPageIndex'],
                    'pageCount': pages.length,
                    'pageDigests': pages
                        .map((page) => page.raw['pageDigest'])
                        .toList(),
                  }),
        );
      }
      return List.unmodifiable(pages);
    } on FormatException {
      _invalidate(SettlementReadFailure.corrupt);
      throw const SettlementReadException(SettlementReadFailure.corrupt);
    } on TypeError {
      _invalidate(SettlementReadFailure.corrupt);
      throw const SettlementReadException(SettlementReadFailure.corrupt);
    } finally {
      _busy = false;
    }
  }

  SettlementDetailPage _accept(Map<String, dynamic> v, int index) {
    _keys(v, [
      'schemaVersion',
      'kind',
      'provenance',
      'expiresAtMillis',
      'representativeLabel',
      'settlementLabel',
      'page',
      'nextToken',
      'exportToken',
    ]);
    _need(
      v['schemaVersion'] == 1 &&
          v['provenance'] == 'authenticated_firebase' &&
          v['kind'] == 'page' &&
          v['expiresAtMillis'] is int &&
          v['expiresAtMillis'] > _clock().millisecondsSinceEpoch &&
          v['expiresAtMillis'] <= _clock().millisecondsSinceEpoch + 360000,
    );
    final page = SettlementDetailPage.fromJson(
      Map<String, dynamic>.from(v['page'] as Map),
    );
    _need(
      page.companyId == companyId &&
          page.representativeId == representativeId &&
          page.settlementId == settlementId &&
          page.pageIndex == index,
    );
    final next = _token(v['nextToken']), export = _token(v['exportToken']);
    _need(
      page.raw['nextPageIndex'] == null
          ? next == null && export != null
          : next != null && export == null,
    );
    final rep = _text(v['representativeLabel']),
        label = _text(v['settlementLabel']);
    if (_evidence != null) {
      _need(
        _evidence == page.evidenceDigest &&
            _snapshot == page.snapshotDigest &&
            _headerDigest == page.headerDigest &&
            _expires == v['expiresAtMillis'] &&
            _representativeLabel == rep &&
            _settlementLabel == label,
      );
    }
    _evidence = page.evidenceDigest;
    _snapshot = page.snapshotDigest;
    _headerDigest = page.headerDigest;
    _expires = v['expiresAtMillis'] as int;
    _representativeLabel = rep;
    _settlementLabel = label;
    _exportToken = export;
    if (next != null) _tokens[index + 1] = next;
    return page;
  }

  bool _matches(SettlementDetailsReport report) =>
      report.origin == origin &&
      report.header.companyId == companyId &&
      report.header.representativeId == representativeId &&
      report.header.settlementId == settlementId &&
      report.header.evidenceDigest == _evidence &&
      report.header.snapshotDigest == _snapshot;
  @override
  Future<void> authorizePdf(SettlementDetailsReport report) async {
    if (expired || !_matches(report) || _exportToken == null) {
      throw const SettlementReadException(SettlementReadFailure.expired);
    }
    _pdfUntil = null;
    final v = await _call({
      'schemaVersion': _deliveryVersion ?? 1,
      'action': 'authorizePdf',
      'token': _exportToken,
    });
    try {
      _keys(v, [
        'schemaVersion',
        'kind',
        'provenance',
        'evidenceDigest',
        'snapshotDigest',
        'validUntilMillis',
      ]);
      _need(
        v['schemaVersion'] == 1 &&
            v['kind'] == 'pdf_permission' &&
            v['evidenceDigest'] == _evidence &&
            v['snapshotDigest'] == _snapshot &&
            v['validUntilMillis'] is int &&
            v['validUntilMillis'] > _clock().millisecondsSinceEpoch &&
            v['validUntilMillis'] <= _expires! &&
            v['validUntilMillis'] <= _clock().millisecondsSinceEpoch + 20000,
      );
      _pdfUntil = v['validUntilMillis'] as int;
    } on FormatException {
      _invalidate(SettlementReadFailure.corrupt);
      throw const SettlementReadException(SettlementReadFailure.corrupt);
    }
  }

  @override
  void requirePdfPermission(SettlementDetailsReport report) {
    if (expired ||
        !_matches(report) ||
        _pdfUntil == null ||
        _clock().millisecondsSinceEpoch >= _pdfUntil!) {
      throw const SettlementReadException(SettlementReadFailure.expired);
    }
  }

  @override
  void reset() {
    _generation++;
    if (_evidence != null) _invalidations.add(SettlementReadFailure.expired);
    _invalid = false;
    coverageIncomplete = false;
    _expires = null;
    _pdfUntil = null;
    _evidence = null;
    _snapshot = null;
    _headerDigest = null;
    _deliveryVersion = null;
    _exportToken = null;
    _representativeLabel = null;
    _settlementLabel = null;
    _tokens.clear();
  }
}
