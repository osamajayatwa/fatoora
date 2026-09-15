import 'dart:convert';

import 'package:crypto/crypto.dart';

class FinancialLedgerFilters {
  const FinancialLedgerFilters({
    required this.fromDate,
    required this.toDate,
    this.type = '',
    this.accountKey = '',
    this.customerId = '',
    this.salesRepId = '',
    this.paymentMethod = '',
    this.search = '',
  });

  final DateTime fromDate;
  final DateTime toDate;
  final String type;
  final String accountKey;
  final String customerId;
  final String salesRepId;
  final String paymentMethod;
  final String search;

  factory FinancialLedgerFilters.currentMonth([DateTime? now]) {
    final date = now ?? DateTime.now();
    return FinancialLedgerFilters(
      fromDate: DateTime(date.year, date.month),
      toDate: DateTime(date.year, date.month + 1, 0),
    );
  }

  DateTime get fromInclusive =>
      DateTime(fromDate.year, fromDate.month, fromDate.day);

  DateTime get toInclusive =>
      DateTime(toDate.year, toDate.month, toDate.day, 23, 59, 59, 999);

  String get queryKey => canonicalLedgerQueryKey(
    type: type,
    accountKey: accountKey,
    customerId: customerId,
    paymentMethod: paymentMethod,
  );

  String get indexedQueryKey => ledgerQueryKeyHash(queryKey);

  String get indexedSearchToken {
    final normalized = normalizeLedgerSearch(search);
    return ledgerSearchTokenHash(
      normalized.substring(0, normalized.length.clamp(0, 20)),
    );
  }

  bool get hasFilters =>
      type.isNotEmpty ||
      accountKey.isNotEmpty ||
      customerId.isNotEmpty ||
      salesRepId.isNotEmpty ||
      paymentMethod.isNotEmpty ||
      search.trim().isNotEmpty;

  FinancialLedgerFilters copyWith({
    DateTime? fromDate,
    DateTime? toDate,
    String? type,
    String? accountKey,
    String? customerId,
    String? salesRepId,
    String? paymentMethod,
    String? search,
  }) {
    return FinancialLedgerFilters(
      fromDate: fromDate ?? this.fromDate,
      toDate: toDate ?? this.toDate,
      type: type ?? this.type,
      accountKey: accountKey ?? this.accountKey,
      customerId: customerId ?? this.customerId,
      salesRepId: salesRepId ?? this.salesRepId,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      search: search ?? this.search,
    );
  }
}

const financialLedgerSchemaVersion = 3;
const financialLedgerQueryKeyHashBytes = 46;
const financialLedgerSearchTokenHashBytes = 47;

String ledgerQueryKeyHash(String value) {
  final digest = sha256.convert(utf8.encode(value));
  final encoded = base64UrlEncode(digest.bytes).replaceAll('=', '');
  return 'v3:$encoded';
}

String ledgerSearchTokenHash(String value) {
  final digest = sha256.convert(utf8.encode(value));
  final encoded = base64UrlEncode(digest.bytes).replaceAll('=', '');
  return 'v3s:$encoded';
}

String canonicalLedgerQueryKey({
  String type = '',
  String accountKey = '',
  String customerId = '',
  String paymentMethod = '',
}) {
  final parts = <String>[];
  void add(String key, String value) {
    if (value.isNotEmpty) parts.add('$key=${Uri.encodeComponent(value)}');
  }

  add('type', type);
  add('account', accountKey);
  add('customer', customerId);
  add('payment', paymentMethod);
  return parts.isEmpty ? 'all' : parts.join('|');
}

String normalizeLedgerSearch(String value) {
  return value
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[|=]+'), ' ')
      .replaceAll(RegExp(r'[^a-z0-9\u0600-\u06ff]+', caseSensitive: false), ' ')
      .trim()
      .replaceAll(RegExp(r'\s+'), ' ');
}
