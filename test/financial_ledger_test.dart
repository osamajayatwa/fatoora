import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:excel/excel.dart';
import 'package:fatoora/features/financial_ledger/data/models/financial_ledger_entry.dart';
import 'package:fatoora/features/financial_ledger/data/models/financial_ledger_export_data.dart';
import 'package:fatoora/features/financial_ledger/data/models/financial_ledger_filters.dart';
import 'package:fatoora/features/financial_ledger/data/repositories/financial_ledger_repository.dart';
import 'package:fatoora/features/financial_ledger/data/services/financial_ledger_excel_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('model preserves stable source, representative, and account IDs', () {
    final entry = FinancialLedgerEntry.fromMap({
      'id': 'invoice_i1_sales_cash',
      'occurredAt': Timestamp.fromDate(DateTime(2026, 8, 5, 10)),
      'type': 'invoice_sale',
      'component': 'cash_sale',
      'description': 'Invoice INV-1',
      'amount': 25,
      'debitAccountType': 'cash',
      'debitAccountKey': 'rep_cash:rep-laith',
      'debitAccountName': 'Laith',
      'creditAccountType': 'sales',
      'creditAccountKey': 'sales',
      'creditAccountName': 'Sales',
      'salesRepId': 'rep-laith',
      'salesRepName': 'Laith',
      'referenceType': 'invoice',
      'referenceId': 'i1',
      'referenceNumber': 'INV-1',
      'sourceCollection': 'invoices',
      'sourceId': 'i1',
    });

    expect(entry.salesRepId, 'rep-laith');
    expect(entry.debitAccountKey, 'rep_cash:rep-laith');
    expect(entry.sourceCollection, 'invoices');
    expect(entry.sourceId, 'i1');
    expect(entry.amount, 25);
  });

  test('combined base filters and search use separate server hashes', () {
    final filters = FinancialLedgerFilters(
      fromDate: DateTime(2026, 8),
      toDate: DateTime(2026, 8, 31),
      type: 'invoice_sale',
      accountKey: 'rep_cash:rep-laith',
      customerId: 'customer-1',
      salesRepId: 'rep-laith',
      paymentMethod: 'cash',
      search: 'INV',
    );

    expect(
      filters.queryKey,
      'type=invoice_sale|account=rep_cash%3Arep-laith|customer=customer-1|payment=cash',
    );
    expect(
      filters.indexedQueryKey,
      'v3:0_40QribO6XScU3frayH3EdACMI-LVY3ffGyvPPmGRA',
    );
    expect(
      filters.indexedSearchToken,
      'v3s:iScKUDQbuOg3NO4GJgPGPCGTIO1KQPufuMJ5I1hUjoo',
    );
  });

  test('SHA-256 query hashes match the Functions cross-platform vectors', () {
    expect(financialLedgerSchemaVersion, 3);
    expect(financialLedgerQueryKeyHashBytes, 46);
    expect(financialLedgerSearchTokenHashBytes, 47);
    expect(
      ledgerQueryKeyHash('all'),
      'v3:XvXvA2S2k5xMph80s5P3s2jRvoYZZHqvg9WzlZGatik',
    );
    expect(
      ledgerSearchTokenHash('inv'),
      'v3s:iScKUDQbuOg3NO4GJgPGPCGTIO1KQPufuMJ5I1hUjoo',
    );
  });

  test('ledger manifest has four main and two search composites only', () {
    final manifest =
        jsonDecode(File('firestore.indexes.json').readAsStringSync())
            as Map<String, dynamic>;
    final ledgerIndexes = (manifest['indexes'] as List<dynamic>)
        .cast<Map<String, dynamic>>()
        .where(
          (index) => index['collectionGroup'] == 'financial_ledger_entries',
        )
        .map(_indexSignature)
        .toSet();
    expect(ledgerIndexes, {
      'queryKeys:CONTAINS|occurredAt:ASCENDING',
      'queryKeys:CONTAINS|occurredAt:DESCENDING',
      'queryKeys:CONTAINS|salesRepId:ASCENDING|occurredAt:ASCENDING',
      'queryKeys:CONTAINS|salesRepId:ASCENDING|occurredAt:DESCENDING',
    });
    final searchIndexes = (manifest['indexes'] as List<dynamic>)
        .cast<Map<String, dynamic>>()
        .where(
          (index) =>
              index['collectionGroup'] == 'financial_ledger_search_entries',
        )
        .map(_indexSignature)
        .toSet();
    expect(searchIndexes, {
      'searchTokens:CONTAINS|occurredAt:DESCENDING',
      'searchTokens:CONTAINS|salesRepId:ASCENDING|occurredAt:DESCENDING',
    });
  });

  test(
    'immutable invoice items are emitted once for partial invoice entries',
    () {
      final entries = [
        _entry(id: 'invoice_i1_cash', amount: 40),
        _entry(id: 'invoice_i1_receivable', amount: 60),
      ];
      final result = assembleFinancialLedgerSalesDetails(
        entries: entries,
        invoices: {
          'i1': _invoiceSource(
            items: [
              _invoiceItem(id: 'p1', name: 'Pump', total: 40),
              _invoiceItem(id: 'p2', name: 'Valve', total: 60),
            ],
          ),
        },
        salesReturns: const {},
      );

      expect(result.details, hasLength(2));
      expect(result.details.map((line) => line.itemName), ['Pump', 'Valve']);
      expect(result.details.map((line) => line.sourceId).toSet(), {'i1'});
      expect(
        result.details.fold<double>(
          0,
          (total, line) => total + line.signedTotal,
        ),
        100,
      );
      expect(result.warnings, isEmpty);
    },
  );

  test(
    'return and refund components do not duplicate immutable return items',
    () {
      final returnEntry = _entry(
        id: 'return_r1_sales',
        amount: 25,
        type: 'sales_return',
        sourceCollection: 'sales_returns',
        sourceId: 'r1',
        referenceNumber: 'RET-1',
      );
      final refundEntry = _entry(
        id: 'return_r1_refund',
        amount: 25,
        type: 'refund',
        sourceCollection: 'sales_returns',
        sourceId: 'r1',
        referenceNumber: 'RET-1',
      );
      final result = assembleFinancialLedgerSalesDetails(
        entries: [returnEntry, refundEntry],
        invoices: const {},
        salesReturns: {
          'r1': {
            'status': 'confirmed',
            'financialPosted': true,
            'returnNumber': 'RET-1',
            'originalInvoiceNumber': 'INV-1',
            'returnDate': DateTime(2026, 8, 7),
            'customerId': 'c1',
            'customerSnapshot': {'name': 'Customer'},
            'salesRepId': 'rep-1',
            'salesRepName': 'Rep',
            'grandTotal': 25,
            'items': [
              {
                'itemId': 'p1',
                'itemName': 'Pump',
                'itemCode': 'P-1',
                'unit': 'pcs',
                'returnedQuantity': 1,
                'unitPrice': 25,
                'discountAmount': 0,
                'taxPercent': 0,
                'taxAmount': 0,
                'total': 25,
                'originalInvoiceItemId': 'i1:0',
              },
            ],
          },
        },
      );

      expect(result.details, hasLength(1));
      expect(result.details.single.signedQuantity, -1);
      expect(result.details.single.signedTotal, -25);
      expect(result.details.single.originalInvoiceNumber, 'INV-1');
    },
  );

  test('legacy incomplete immutable snapshots produce explicit warnings', () {
    final result = assembleFinancialLedgerSalesDetails(
      entries: [_entry(id: 'invoice_legacy', sourceId: 'legacy')],
      invoices: {
        'legacy': {
          'invoiceStatus': 'confirmed',
          'financialPosted': true,
          'invoiceNumber': 'LEGACY',
          'grandTotal': 10,
          'items': <Map<String, dynamic>>[],
        },
      },
      salesReturns: const {},
    );

    expect(result.details, isEmpty);
    expect(result.warnings.single, contains('Legacy source'));
  });

  test(
    'accounting workbook contains four sheets and balanced Journal totals',
    () {
      final filters = _filters();
      final entry = _entry(id: 'invoice_i1_cash', amount: 25);
      final sales = assembleFinancialLedgerSalesDetails(
        entries: [entry],
        invoices: {
          'i1': _invoiceSource(items: [_invoiceItem(total: 25)]),
        },
        salesReturns: const {},
      );
      final data = _exportData(
        entries: [entry],
        salesDetails: sales.details,
        openings: const {
          'company_cash': FinancialLedgerOpeningBalance(
            accountKey: 'company_cash',
            accountType: 'cash',
            accountName: 'Cash',
            debit: 10,
            credit: 0,
            balance: 10,
          ),
          'sales': FinancialLedgerOpeningBalance(
            accountKey: 'sales',
            accountType: 'revenue',
            accountName: 'Sales',
            debit: 0,
            credit: 5,
            balance: -5,
          ),
        },
      );
      final service = FinancialLedgerExcelService();
      final workbook = Excel.decodeBytes(
        service.buildAccountingReport(data: data, filters: filters),
      );

      expect(workbook.tables.keys.toList(), [
        'الملخص Summary',
        'القيود Journal',
        'تفاصيل المبيعات',
        'الأستاذ العام GL',
      ]);
      final journal = workbook['القيود Journal'];
      expect(_cellNumber(journal, 'O5'), 25);
      expect(_cellNumber(journal, 'R5'), 25);
      expect(_cellNumber(journal, 'O6'), _cellNumber(journal, 'R6'));
      expect(
        workbook['الملخص Summary'].cell(CellIndex.indexByString('B17')).value,
        TextCellValue('Balanced / متوازن'),
      );
      expect(workbook['تفاصيل المبيعات'].maxRows, greaterThanOrEqualTo(6));
    },
  );

  test(
    'GL uses brought-forward balances, running balances, and reconciles',
    () {
      final entries = [
        _entry(id: 'e1', amount: 25),
        _entry(id: 'e2', amount: 5, occurredAt: DateTime(2026, 8, 6)),
      ];
      final data = _exportData(
        entries: entries,
        openings: const {
          'company_cash': FinancialLedgerOpeningBalance(
            accountKey: 'company_cash',
            accountType: 'cash',
            accountName: 'Cash',
            debit: 10,
            credit: 0,
            balance: 10,
          ),
          'sales': FinancialLedgerOpeningBalance(
            accountKey: 'sales',
            accountType: 'revenue',
            accountName: 'Sales',
            debit: 0,
            credit: 3,
            balance: -3,
          ),
        },
      );
      final rows = FinancialLedgerExcelService().buildGeneralLedgerRows(
        data: data,
        filters: _filters(),
      );
      final cash = rows
          .where((row) => row.accountKey == 'company_cash')
          .toList();
      final sales = rows.where((row) => row.accountKey == 'sales').toList();

      expect(cash.first.isOpening, isTrue);
      expect(cash.first.runningBalance, 10);
      expect(cash.map((row) => row.runningBalance), [10, 35, 40]);
      expect(sales.map((row) => row.runningBalance), [-3, -28, -33]);
      final postings = rows.where((row) => !row.isOpening).toList();
      expect(postings, hasLength(entries.length * 2));
      expect(
        postings.fold<double>(0, (total, row) => total + row.debit),
        postings.fold<double>(0, (total, row) => total + row.credit),
      );
    },
  );

  test(
    'save failure is propagated and cannot be reported as success',
    () async {
      var saveAttempts = 0;
      final service = FinancialLedgerExcelService(
        fileSaver: (bytes, fileName) async {
          saveAttempts += 1;
          throw StateError('disk full');
        },
      );

      await expectLater(
        service.saveAccountingReport(
          data: _exportData(entries: [_entry()]),
          filters: _filters(),
        ),
        throwsA(isA<StateError>()),
      );
      expect(saveAttempts, 1);
    },
  );

  test('non-throwing platform save failure is treated as a failure', () async {
    final service = FinancialLedgerExcelService(
      fileSaver: (bytes, fileName) async => false,
    );

    await expectLater(
      service.saveAccountingReport(
        data: _exportData(entries: [_entry()]),
        filters: _filters(),
      ),
      throwsA(isA<StateError>()),
    );
  });

  test(
    'Android callable readiness errors map to the friendly export error',
    () {
      final error = PlatformException(
        code: 'firebase_functions',
        message:
            'FirebaseFunctionsException: Financial ledger account activity '
            'projection is not ready.',
        details: const {
          'code': 'failed-precondition',
          'message':
              'Financial ledger account activity projection is not ready.',
        },
      );

      expect(FinancialLedgerProjectionNotReadyException.matches(error), isTrue);
    },
  );
}

FinancialLedgerEntry _entry({
  String id = 'invoice_i1_sales_cash',
  double amount = 25,
  String type = 'invoice_sale',
  String sourceCollection = 'invoices',
  String sourceId = 'i1',
  String referenceNumber = 'INV-1',
  DateTime? occurredAt,
}) {
  return FinancialLedgerEntry.fromMap({
    'id': id,
    'occurredAt': occurredAt ?? DateTime(2026, 8, 5, 10),
    'type': type,
    'component': 'posting',
    'description': referenceNumber,
    'amount': amount,
    'quantity': 1,
    'unitPrice': amount,
    'debitAccountType': 'cash',
    'debitAccountKey': 'company_cash',
    'debitAccountName': 'Cash',
    'creditAccountType': 'revenue',
    'creditAccountKey': 'sales',
    'creditAccountName': 'Sales',
    'customerId': 'c1',
    'customerName': 'Customer',
    'salesRepId': 'rep-1',
    'salesRepName': 'Rep',
    'referenceType': type == 'sales_return' ? 'sales_return' : 'invoice',
    'referenceId': sourceId,
    'referenceNumber': referenceNumber,
    'sourceCollection': sourceCollection,
    'sourceId': sourceId,
  });
}

Map<String, dynamic> _invoiceSource({
  required List<Map<String, dynamic>> items,
}) {
  return {
    'invoiceStatus': 'confirmed',
    'financialPosted': true,
    'invoiceNumber': 'INV-1',
    'invoiceDate': DateTime(2026, 8, 5),
    'customerId': 'c1',
    'customerSnapshot': {'name': 'Customer'},
    'salesRepId': 'rep-1',
    'salesRepName': 'Rep',
    'grandTotal': items.fold<double>(
      0,
      (total, item) => total + (item['total'] as num).toDouble(),
    ),
    'items': items,
  };
}

Map<String, dynamic> _invoiceItem({
  String id = 'p1',
  String name = 'Pump',
  double total = 25,
}) {
  return {
    'itemId': id,
    'itemName': name,
    'itemCode': 'CODE-$id',
    'unit': 'pcs',
    'quantity': 1,
    'unitPrice': total,
    'discount': 0,
    'taxPercent': 0,
    'taxAmount': 0,
    'total': total,
  };
}

FinancialLedgerFilters _filters() => FinancialLedgerFilters(
  fromDate: DateTime(2026, 8),
  toDate: DateTime(2026, 8, 31),
  salesRepId: 'rep-1',
);

FinancialLedgerExportData _exportData({
  List<FinancialLedgerEntry> entries = const [],
  List<FinancialLedgerSalesDetail> salesDetails = const [],
  Map<String, FinancialLedgerOpeningBalance> openings = const {},
  List<String> warnings = const [],
}) {
  return FinancialLedgerExportData(
    companyId: 'company',
    companyName: 'Test Company',
    representativeName: 'Rep',
    generatedAt: DateTime(2026, 8, 31, 12),
    entries: entries,
    salesDetails: salesDetails,
    openingBalances: openings,
    warnings: warnings,
  );
}

double _cellNumber(Sheet sheet, String address) {
  final value = sheet.cell(CellIndex.indexByString(address)).value;
  return switch (value) {
    IntCellValue() => value.value.toDouble(),
    DoubleCellValue() => value.value,
    _ => throw StateError('$address is not numeric: $value'),
  };
}

String _indexSignature(Map<String, dynamic> index) {
  return (index['fields'] as List<dynamic>)
      .map((field) {
        final value = field as Map<String, dynamic>;
        return '${value['fieldPath']}:${value['arrayConfig'] ?? value['order']}';
      })
      .join('|');
}
