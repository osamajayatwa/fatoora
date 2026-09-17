import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:fatoora/core/firebase/trusted_callable_client.dart';
import 'package:fatoora/features/auth/data/models/app_user_model.dart';
import 'package:fatoora/features/customers/data/models/customer_model.dart';
import 'package:fatoora/features/financial_ledger/data/models/financial_ledger_entry.dart';
import 'package:fatoora/features/financial_ledger/data/models/financial_ledger_export_data.dart';
import 'package:fatoora/features/financial_ledger/data/models/financial_ledger_filters.dart';
import 'package:fatoora/features/financial_ledger/data/models/financial_ledger_summary.dart';
import 'package:fatoora/features/settings/data/models/app_settings_model.dart';
import 'package:flutter/services.dart';

class FinancialLedgerRepository {
  FinancialLedgerRepository({
    FirebaseFirestore? firestore,
    TrustedCallableClient? trustedCallableClient,
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _trustedCallableClient =
           trustedCallableClient ?? TrustedCallableClient.forDefaultApp();

  final FirebaseFirestore _firestore;
  final TrustedCallableClient _trustedCallableClient;

  CollectionReference<Map<String, dynamic>> _entries(String companyId) =>
      _firestore
          .collection('companies')
          .doc(companyId)
          .collection('financial_ledger_entries');

  Future<FinancialLedgerPage> fetchPage({
    required String companyId,
    required FinancialLedgerFilters filters,
    FinancialLedgerCursor? after,
    int pageSize = 40,
  }) async {
    if (filters.search.trim().isNotEmpty) {
      return _fetchSearchPage(
        companyId: companyId,
        filters: filters,
        after: after,
        pageSize: pageSize,
      );
    }
    Query<Map<String, dynamic>> query = _orderedQuery(companyId, filters);
    if (after != null) {
      query = query.startAfter([
        Timestamp.fromDate(after.occurredAt),
        after.id,
      ]);
    }
    final snapshot = await query.limit(pageSize + 1).get();
    final hasMore = snapshot.docs.length > pageSize;
    final visible = hasMore
        ? snapshot.docs.take(pageSize).toList(growable: false)
        : snapshot.docs;
    return FinancialLedgerPage(
      entries: visible
          .map(FinancialLedgerEntry.fromFirestore)
          .toList(growable: false),
      cursor: visible.isEmpty ? null : _cursorFromDocument(visible.last),
      hasMore: hasMore,
    );
  }

  Future<FinancialLedgerSummary> fetchSummary({
    required String companyId,
    required FinancialLedgerFilters filters,
  }) async {
    final result = await _trustedCallableClient
        .callAuthenticated<Map<String, dynamic>>(
          'getFinancialLedgerSummary',
          _filterPayload(companyId, filters),
        );
    final data = result.data;
    return FinancialLedgerSummary(
      entryCount: _integer(data['entryCount']),
      sales: _number(data['metricSales']),
      cashSales: _number(data['metricCashSales']),
      creditSales: _number(data['metricCreditSales']),
      receipts: _number(data['metricReceipts']),
      expenses: _number(data['metricExpenses']),
      returns: _number(data['metricReturns']),
      settlements: _number(data['metricSettlements']),
      receivables: _number(data['metricReceivables']),
      companyCashNet: _number(data['metricCompanyCashNet']),
      repCashIn: _number(data['metricRepCashIn']),
      repCashOut: _number(data['metricRepCashOut']),
    );
  }

  Future<List<FinancialLedgerEntry>> fetchAllForExport({
    required String companyId,
    required FinancialLedgerFilters filters,
  }) async {
    if (filters.search.trim().isNotEmpty) {
      final entries = <FinancialLedgerEntry>[];
      FinancialLedgerCursor? cursor;
      do {
        final page = await _fetchSearchPage(
          companyId: companyId,
          filters: filters,
          after: cursor,
          pageSize: 250,
        );
        entries.addAll(page.entries);
        cursor = page.cursor;
        if (!page.hasMore || cursor == null) break;
      } while (true);
      entries.sort((left, right) {
        final date = left.occurredAt.compareTo(right.occurredAt);
        return date != 0 ? date : left.id.compareTo(right.id);
      });
      return entries;
    }
    final entries = <FinancialLedgerEntry>[];
    FinancialLedgerCursor? cursor;
    do {
      Query<Map<String, dynamic>> query = _orderedQuery(
        companyId,
        filters,
        descending: false,
      );
      if (cursor != null) {
        query = query.startAfter([
          Timestamp.fromDate(cursor.occurredAt),
          cursor.id,
        ]);
      }
      final snapshot = await query.limit(250).get();
      entries.addAll(snapshot.docs.map(FinancialLedgerEntry.fromFirestore));
      cursor = snapshot.docs.isEmpty
          ? null
          : _cursorFromDocument(snapshot.docs.last);
      if (snapshot.docs.length < 250) break;
    } while (cursor != null);
    return entries;
  }

  Future<FinancialLedgerExportData> fetchExportData({
    required String companyId,
    required FinancialLedgerFilters filters,
  }) async {
    final entries = await fetchAllForExport(
      companyId: companyId,
      filters: filters,
    );
    final invoiceIds = <String>{};
    final salesReturnIds = <String>{};
    final accountKeys = <String>{};
    if (filters.accountKey.isNotEmpty) accountKeys.add(filters.accountKey);
    for (final entry in entries) {
      if (entry.debitAccountKey.isNotEmpty) {
        accountKeys.add(entry.debitAccountKey);
      }
      if (entry.creditAccountKey.isNotEmpty) {
        accountKeys.add(entry.creditAccountKey);
      }
      final sourceId = entry.sourceId.isNotEmpty
          ? entry.sourceId
          : entry.referenceId;
      final sourceCollection = entry.sourceCollection.isNotEmpty
          ? entry.sourceCollection
          : switch (entry.type) {
              'invoice_sale' => 'invoices',
              'sales_return' => 'sales_returns',
              _ => '',
            };
      if (entry.type == 'invoice_sale' &&
          sourceCollection == 'invoices' &&
          sourceId.isNotEmpty) {
        invoiceIds.add(sourceId);
      }
      if ((entry.type == 'sales_return' || entry.type == 'refund') &&
          sourceCollection == 'sales_returns' &&
          sourceId.isNotEmpty) {
        salesReturnIds.add(sourceId);
      }
    }

    final company = _firestore.collection('companies').doc(companyId);
    final results = await Future.wait<Object>([
      _fetchSourceMaps(company.collection('invoices'), invoiceIds),
      _fetchSourceMaps(company.collection('sales_returns'), salesReturnIds),
      company.collection('settings').doc('app').get(),
      if (filters.salesRepId.isNotEmpty)
        _firestore.collection('users').doc(filters.salesRepId).get(),
      _fetchOpeningBalances(
        companyId: companyId,
        filters: filters,
        accountKeys: accountKeys.toList()..sort(),
      ),
    ]);
    final invoices = results[0] as Map<String, Map<String, dynamic>>;
    final salesReturns = results[1] as Map<String, Map<String, dynamic>>;
    final settings = results[2] as DocumentSnapshot<Map<String, dynamic>>;
    var resultIndex = 3;
    String representativeName = '';
    if (filters.salesRepId.isNotEmpty) {
      final representative =
          results[resultIndex] as DocumentSnapshot<Map<String, dynamic>>;
      representativeName = _string(representative.data()?['name']);
      resultIndex += 1;
    }
    final openingBalances =
        results[resultIndex] as Map<String, FinancialLedgerOpeningBalance>;
    final salesAssembly = assembleFinancialLedgerSalesDetails(
      entries: entries,
      invoices: invoices,
      salesReturns: salesReturns,
    );
    final warnings = <String>[...salesAssembly.warnings];
    if (filters.type.isNotEmpty ||
        filters.customerId.isNotEmpty ||
        filters.paymentMethod.isNotEmpty ||
        filters.search.trim().isNotEmpty) {
      warnings.add(
        'GL opening balances include all historical activity for each account '
        'and representative scope; analytic filters apply only to period rows / '
        'الأرصدة السابقة تشمل كامل حركة الحساب التاريخية، بينما تنطبق فلاتر '
        'التحليل على قيود الفترة فقط.',
      );
    }
    final appSettings = AppSettingsModel.fromMap(settings.data());
    return FinancialLedgerExportData(
      companyId: companyId,
      companyName: appSettings.companySettings.name,
      representativeName: representativeName.isNotEmpty
          ? representativeName
          : entries
                .map((entry) => entry.salesRepName)
                .firstWhere((name) => name.isNotEmpty, orElse: () => ''),
      generatedAt: DateTime.now(),
      entries: List.unmodifiable(entries),
      salesDetails: salesAssembly.details,
      openingBalances: Map.unmodifiable(openingBalances),
      warnings: List.unmodifiable(warnings),
    );
  }

  Future<FinancialLedgerLookups> fetchLookups(String companyId) async {
    final results = await Future.wait<QuerySnapshot<Map<String, dynamic>>>([
      _firestore
          .collection('users')
          .where('role', isEqualTo: 'sales_rep')
          .get(),
      _firestore
          .collection('companies')
          .doc(companyId)
          .collection('customers')
          .orderBy('nameLower')
          .get(),
    ]);
    final reps =
        results[0].docs
            .map(AppUserModel.fromFirestore)
            .where((user) => user.companyId == companyId && user.isSalesRep)
            .toList(growable: false)
          ..sort(
            (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
          );
    final customers = results[1].docs
        .map(CustomerModel.fromFirestore)
        .toList(growable: false);
    return FinancialLedgerLookups(representatives: reps, customers: customers);
  }

  Future<Map<String, Map<String, dynamic>>> _fetchSourceMaps(
    CollectionReference<Map<String, dynamic>> collection,
    Set<String> ids,
  ) async {
    final result = <String, Map<String, dynamic>>{};
    final orderedIds = ids.toList()..sort();
    const maximumConcurrentBatches = 6;
    for (
      var windowStart = 0;
      windowStart < orderedIds.length;
      windowStart += 30 * maximumConcurrentBatches
    ) {
      final windowEnd = math.min(
        windowStart + (30 * maximumConcurrentBatches),
        orderedIds.length,
      );
      final requests = <Future<QuerySnapshot<Map<String, dynamic>>>>[];
      for (var offset = windowStart; offset < windowEnd; offset += 30) {
        final batch = orderedIds.sublist(
          offset,
          math.min(offset + 30, windowEnd),
        );
        requests.add(
          collection.where(FieldPath.documentId, whereIn: batch).get(),
        );
      }
      final snapshots = await Future.wait(requests);
      for (final document in snapshots.expand((snapshot) => snapshot.docs)) {
        result[document.id] = document.data();
      }
    }
    return result;
  }

  Future<Map<String, FinancialLedgerOpeningBalance>> _fetchOpeningBalances({
    required String companyId,
    required FinancialLedgerFilters filters,
    required List<String> accountKeys,
  }) async {
    if (accountKeys.isEmpty) return const {};
    final openings = <String, FinancialLedgerOpeningBalance>{};
    for (var offset = 0; offset < accountKeys.length; offset += 200) {
      late final HttpsCallableResult<Map<String, dynamic>> result;
      try {
        result = await _trustedCallableClient
            .callAuthenticated<Map<String, dynamic>>(
              'getFinancialLedgerOpeningBalances',
              {
                'companyId': companyId,
                'fromInclusive': filters.fromInclusive.millisecondsSinceEpoch,
                'salesRepId': filters.salesRepId,
                'accountKeys': accountKeys.skip(offset).take(200).toList(),
              },
            );
      } catch (error) {
        if (FinancialLedgerProjectionNotReadyException.matches(error)) {
          throw const FinancialLedgerProjectionNotReadyException();
        }
        rethrow;
      }
      final data = result.data;
      if (data['projectionVersion'] != 1 || data['openings'] is! List) {
        throw const FormatException(
          'Financial ledger opening balance response is invalid.',
        );
      }
      for (final raw in data['openings'] as List) {
        if (raw is! Map) {
          throw const FormatException(
            'A financial ledger opening balance is invalid.',
          );
        }
        final opening = FinancialLedgerOpeningBalance.fromMap(
          Map<String, dynamic>.from(raw),
        );
        openings[opening.accountKey] = opening;
      }
    }
    return openings;
  }

  Query<Map<String, dynamic>> _orderedQuery(
    String companyId,
    FinancialLedgerFilters filters, {
    bool descending = true,
  }) {
    return _filteredQuery(companyId, filters)
        .orderBy('occurredAt', descending: descending)
        .orderBy(FieldPath.documentId, descending: descending);
  }

  Query<Map<String, dynamic>> _filteredQuery(
    String companyId,
    FinancialLedgerFilters filters,
  ) {
    Query<Map<String, dynamic>> query = _entries(companyId)
        .where('queryKeys', arrayContains: filters.indexedQueryKey)
        .where(
          'occurredAt',
          isGreaterThanOrEqualTo: Timestamp.fromDate(filters.fromInclusive),
        )
        .where(
          'occurredAt',
          isLessThanOrEqualTo: Timestamp.fromDate(filters.toInclusive),
        );
    if (filters.salesRepId.isNotEmpty) {
      query = query.where('salesRepId', isEqualTo: filters.salesRepId);
    }
    return query;
  }

  Future<FinancialLedgerPage> _fetchSearchPage({
    required String companyId,
    required FinancialLedgerFilters filters,
    required FinancialLedgerCursor? after,
    required int pageSize,
  }) async {
    final payload = _filterPayload(companyId, filters)
      ..['pageSize'] = pageSize
      ..['cursor'] = after == null
          ? null
          : {
              'occurredAt': after.occurredAt.millisecondsSinceEpoch,
              'id': after.id,
            };
    final result = await _trustedCallableClient
        .callAuthenticated<Map<String, dynamic>>(
          'searchFinancialLedger',
          payload,
        );
    final data = result.data;
    final rawEntries = data['entries'];
    if (rawEntries is! List) {
      throw const FormatException(
        'Financial ledger search entries are invalid.',
      );
    }
    final entries = rawEntries
        .map((value) {
          if (value is! Map) {
            throw const FormatException(
              'A financial ledger search row is invalid.',
            );
          }
          return FinancialLedgerEntry.fromMap(Map<String, dynamic>.from(value));
        })
        .toList(growable: false);
    return FinancialLedgerPage(
      entries: entries,
      cursor: _cursorFromCallable(data['cursor']),
      hasMore: data['hasMore'] == true,
    );
  }

  Map<String, dynamic> _filterPayload(
    String companyId,
    FinancialLedgerFilters filters,
  ) {
    return {
      'companyId': companyId,
      'from': filters.fromInclusive.millisecondsSinceEpoch,
      'to': filters.toInclusive.millisecondsSinceEpoch,
      'type': filters.type,
      'accountKey': filters.accountKey,
      'customerId': filters.customerId,
      'salesRepId': filters.salesRepId,
      'paymentMethod': filters.paymentMethod,
      'search': filters.search,
    };
  }

  FinancialLedgerCursor _cursorFromDocument(
    QueryDocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final occurredAt = document.data()['occurredAt'];
    if (occurredAt is! Timestamp) {
      throw const FormatException('Financial ledger cursor date is invalid.');
    }
    return FinancialLedgerCursor(
      occurredAt: occurredAt.toDate(),
      id: document.id,
    );
  }

  FinancialLedgerCursor? _cursorFromCallable(Object? value) {
    if (value == null) return null;
    if (value is! Map) {
      throw const FormatException('Financial ledger search cursor is invalid.');
    }
    final data = Map<String, dynamic>.from(value);
    final id = data['id'];
    final occurredAt = data['occurredAt'];
    if (id is! String || id.isEmpty || occurredAt is! num) {
      throw const FormatException('Financial ledger search cursor is invalid.');
    }
    return FinancialLedgerCursor(
      occurredAt: DateTime.fromMillisecondsSinceEpoch(occurredAt.toInt()),
      id: id,
    );
  }

  static double _number(Object? value) {
    if (value is num && value.isFinite) return value.toDouble();
    throw const FormatException('Financial ledger summary value is invalid.');
  }

  static int _integer(Object? value) {
    if (value is num && value.isFinite) return value.toInt();
    throw const FormatException('Financial ledger summary count is invalid.');
  }

  static String _string(Object? value) => value is String ? value.trim() : '';
}

class FinancialLedgerPage {
  const FinancialLedgerPage({
    required this.entries,
    required this.cursor,
    required this.hasMore,
  });

  final List<FinancialLedgerEntry> entries;
  final FinancialLedgerCursor? cursor;
  final bool hasMore;
}

class FinancialLedgerCursor {
  const FinancialLedgerCursor({required this.occurredAt, required this.id});

  final DateTime occurredAt;
  final String id;
}

class FinancialLedgerLookups {
  const FinancialLedgerLookups({
    required this.representatives,
    required this.customers,
  });

  final List<AppUserModel> representatives;
  final List<CustomerModel> customers;
}

class FinancialLedgerProjectionNotReadyException implements Exception {
  const FinancialLedgerProjectionNotReadyException();

  static bool matches(Object error) {
    if (error is FirebaseFunctionsException) {
      return error.code == 'failed-precondition';
    }
    if (error is! PlatformException) return false;
    if (error.code == 'failed-precondition') return true;
    final details = error.details;
    if (details is Map && details['code'] == 'failed-precondition') {
      return true;
    }
    return error.message?.contains('failed-precondition') == true;
  }
}
