import 'dart:convert';

import 'package:fatoora/features/financial/data/models/settlement_details.dart';

/// Deliberately final, fixture-only and absent from all application bindings.
/// No transport interface, Firebase dependency, asset loading or HTTP fallback.
final class SettlementDetailsFixtures implements SettlementDetailsSource {
  @override
  Stream<SettlementReadFailure> get invalidations => const Stream.empty();
  SettlementDetailsFixtures._(
    this._json,
    this.companyId,
    this.representativeId,
    this.settlementId,
    this.representativeLabel,
    this.settlementLabel,
    this.coverageIncomplete,
    this.latency,
    Set<int> failures,
  ) : _failures = Set.from(failures);
  factory SettlementDetailsFixtures.fromJson(
    Map<String, dynamic> fixture, {
    Duration latency = Duration.zero,
    Set<int> failFirstReads = const {},
  }) {
    final json = jsonEncode(fixture),
        own = jsonDecode(json) as Map<String, dynamic>;
    if (own['fixture'] != 'phase2b11-synthetic') {
      throw const FormatException('Synthetic fixtures only');
    }
    final incomplete = own['notice'] != null;
    final Map<String, dynamic> scope;
    if (incomplete) {
      scope = Map<String, dynamic>.from(own['notice'] as Map);
      if (scope['state'] != 'incomplete_coverage' || own.containsKey('pages')) {
        throw const FormatException('Invalid coverage fixture');
      }
    } else {
      final first = SettlementDetailPage.fromJson(
        Map<String, dynamic>.from((own['pages'] as List).first as Map),
      );
      scope = {
        'companyId': first.companyId,
        'salesRepId': first.representativeId,
        'settlementId': first.settlementId,
      };
    }
    final company = scope['companyId'] as String,
        rep = scope['salesRepId'] as String,
        settlement = scope['settlementId'] as String;
    if (!company.startsWith('synthetic-') ||
        !rep.startsWith('synthetic-') ||
        settlement.isEmpty) {
      throw const FormatException('Fixture scope must be synthetic');
    }
    return SettlementDetailsFixtures._(
      json,
      company,
      rep,
      settlement,
      own['representativeLabel'] as String,
      own['settlementLabel'] as String,
      incomplete,
      latency,
      failFirstReads,
    );
  }
  final String _json;
  @override
  final String companyId;
  @override
  final String representativeId;
  @override
  final String settlementId;
  @override
  final String representativeLabel;
  @override
  final String settlementLabel;
  @override
  final bool coverageIncomplete;
  final Duration latency;
  final Set<int> _failures;
  @override
  SettlementDetailsOrigin get origin =>
      SettlementDetailsOrigin.syntheticFixture;
  @override
  bool get expired => false;
  @override
  int? get expiresAtMillis => null;
  @override
  void reset() {}
  @override
  Future<void> authorizePdf(SettlementDetailsReport report) async =>
      requirePdfPermission(report);
  @override
  void requirePdfPermission(SettlementDetailsReport report) {
    if (report.origin != origin ||
        report.header.companyId != companyId ||
        report.header.representativeId != representativeId ||
        report.header.settlementId != settlementId) {
      throw const SettlementReadException(SettlementReadFailure.corrupt);
    }
  }

  @override
  Future<SettlementDetailPage> read(int index) async {
    if (coverageIncomplete) {
      throw const FormatException(
        'Incomplete source coverage has no certified detail pages',
      );
    }
    if (latency > Duration.zero) await Future<void>.delayed(latency);
    if (_failures.remove(index)) {
      throw StateError('Synthetic transient page failure');
    }
    final pages = (jsonDecode(_json) as Map<String, dynamic>)['pages'] as List;
    if (index < 0 || index >= pages.length) {
      throw const FormatException('Missing fixture page');
    }
    return SettlementDetailPage.fromJson(
      Map<String, dynamic>.from(pages[index] as Map),
    );
  }
}
