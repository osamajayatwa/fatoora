import 'dart:convert';

/// Server-validated draft. A complete draft is still unapproved and cannot post.
class AccountingConfigurationSnapshot {
  AccountingConfigurationSnapshot._(
    this.companyId,
    this.bookId,
    this.revision,
    this.configuration,
    this.missing,
    this.configurationComplete,
  );

  final String companyId, bookId;
  final int revision;
  final Map<String, dynamic>? configuration;
  final List<String> missing;
  final bool configurationComplete;

  factory AccountingConfigurationSnapshot.fromMap(
    Map<String, dynamic> data, {
    required String companyId,
    required String bookId,
  }) {
    final revision = data['revision'];
    final config = data['configuration'];
    final ready = data['readiness'];
    if (data['schemaVersion'] != 1 ||
        data['companyId'] != companyId ||
        data['bookId'] != bookId ||
        revision is! int ||
        revision < 0 ||
        (revision == 0
            ? config != null || ready != null
            : config is! Map || ready is! Map)) {
      throw const FormatException('Invalid accounting configuration response');
    }
    if (revision > 0 &&
        (ready['postingEnabled'] != false ||
            ready['approvalStatus'] != 'unreviewed' ||
            ready['configurationComplete'] is! bool ||
            ready['missing'] is! List ||
            (ready['missing'] as List).any((v) => v is! String) ||
            config['schemaVersion'] != 1 ||
            config['inventoryMode'] != 'quantity_only' ||
            config['costCoverage'] != 'not_recorded')) {
      throw const FormatException('Invalid accounting configuration state');
    }
    if (revision > 0) {
      bool strings(Map values, List<String> keys) =>
          keys.every((k) => values[k] is String);
      bool rows(String key, int limit, List<String> keys) =>
          config[key] is List &&
          (config[key] as List).length <= limit &&
          (config[key] as List).every((r) => r is Map && strings(r, keys));
      final tax = config['taxPolicy'], opening = config['openingBoundary'];
      if (!strings(config, ['name', 'currency', 'timezone']) ||
          config['timezone'] != 'Asia/Amman' ||
          ![
            'moneyScale',
            'quantityScale',
            'priceScale',
            'fiscalYearStartMonth',
            'fiscalYearStartDay',
          ].every((k) => config[k] is int) ||
          !rows('accounts', 80, [
            'id',
            'code',
            'name',
            'accountType',
            'normalSide',
            'control',
          ]) ||
          !(config['accounts'] as List).every(
            (a) =>
                a['active'] is bool &&
                a['postingAllowed'] is bool &&
                (a['parentId'] == null || a['parentId'] is String),
          ) ||
          !rows('periods', 36, ['id', 'name', 'startsOn', 'endsBefore']) ||
          !rows('taxCodes', 80, [
            'code',
            'ratePercent',
            'startsOn',
            'endsBefore',
            'outputAccountId',
          ]) ||
          config['mappings'] is! Map ||
          !(config['mappings'] as Map).values.every((v) => v is String) ||
          tax is! Map ||
          !['unconfirmed', 'documented'].contains(tax['status']) ||
          ![null, 'inclusive', 'exclusive'].contains(tax['priceBasis']) ||
          (tax['evidenceRef'] != null && tax['evidenceRef'] is! String) ||
          opening is! Map ||
          !['unknown', 'documented'].contains(opening['financialCoverage']) ||
          !['unknown', 'documented'].contains(opening['quantityCoverage']) ||
          opening['evidenceRefs'] is! List ||
          !(opening['evidenceRefs'] as List).every((v) => v is String) ||
          (opening['cutoverDate'] != null &&
              opening['cutoverDate'] is! String) ||
          (opening['retainedEarningsTreatment'] != null &&
              opening['retainedEarningsTreatment'] is! String)) {
        throw const FormatException('Malformed accounting draft');
      }
    }
    dynamic freeze(dynamic value) => value is Map
        ? Map<String, dynamic>.unmodifiable(
            value.map((k, v) => MapEntry(k.toString(), freeze(v))),
          )
        : value is List
        ? List<dynamic>.unmodifiable(value.map(freeze))
        : value;
    return AccountingConfigurationSnapshot._(
      companyId,
      bookId,
      revision,
      config == null
          ? null
          : freeze(jsonDecode(jsonEncode(config))) as Map<String, dynamic>,
      List<String>.unmodifiable(
        revision == 0 ? <String>[] : (ready['missing'] as List).cast<String>(),
      ),
      revision > 0 && ready['configurationComplete'] == true,
    );
  }
}
