// ignore_for_file: subtype_of_sealed_class

import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:excel/excel.dart';
import 'package:fatoora/core/data/firestore_query_pager.dart';
import 'package:fatoora/features/expenses/data/models/expense_model.dart';
import 'package:fatoora/features/invoices/data/models/invoice_customer_snapshot.dart';
import 'package:fatoora/features/invoices/data/models/invoice_enums.dart';
import 'package:fatoora/features/invoices/data/models/invoice_model.dart';
import 'package:fatoora/features/operational_report/data/models/operational_report_data.dart';
import 'package:fatoora/features/operational_report/data/models/operational_report_filters.dart';
import 'package:fatoora/features/operational_report/data/repositories/operational_report_repository.dart';
import 'package:fatoora/features/operational_report/data/services/operational_report_excel_service.dart';
import 'package:fatoora/features/receipts/data/models/receipt_model.dart';
import 'package:fatoora/features/sales_returns/data/models/sales_return_enums.dart';
import 'package:fatoora/features/sales_returns/data/models/sales_return_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Sales rows', () {
    test('creates one row per item and repeats invoice values', () {
      final invoice = _invoice(
        number: 'INV-100',
        status: InvoiceStatus.confirmed,
        itemNames: const ['Tea', 'Coffee'],
      );

      final rows = buildOperationalSalesRows([invoice]);

      expect(rows, hasLength(2));
      expect(rows.map((row) => row.invoice.invoiceNumber), [
        'INV-100',
        'INV-100',
      ]);
      expect(rows.map((row) => row.item.itemName), ['Tea', 'Coffee']);
      expect(rows.map((row) => row.lineNumber), [1, 2]);
    });

    test('includes confirmed and accepted but excludes non-sales statuses', () {
      final rows = buildOperationalSalesRows([
        _invoice(number: 'CONF', status: InvoiceStatus.confirmed),
        _invoice(number: 'ACCEPT', status: InvoiceStatus.accepted),
        _invoice(number: 'DRAFT', status: InvoiceStatus.draft),
        _invoice(number: 'CANCEL', status: InvoiceStatus.cancelled),
      ]);

      expect(rows.map((row) => row.invoice.invoiceNumber), ['CONF', 'ACCEPT']);
    });

    test('does not invent a row for an invoice without stored items', () {
      final rows = buildOperationalSalesRows([
        _invoice(
          number: 'LEGACY',
          status: InvoiceStatus.confirmed,
          itemNames: const [],
        ),
      ]);

      expect(rows, isEmpty);
    });
  });

  group('Sales return rows', () {
    test('exports confirmed returns with one row per returned item', () {
      final rows = buildOperationalSalesReturnRows([
        _salesReturn(number: 'RET-1', itemNames: const ['Tea', 'Coffee']),
        _salesReturn(number: 'RET-2'),
        _salesReturn(number: 'DRAFT', status: SalesReturnStatus.draft),
        _salesReturn(number: 'CANCEL', status: SalesReturnStatus.cancelled),
        _salesReturn(number: 'LEGACY', itemNames: const []),
      ]);

      expect(rows.map((row) => row.salesReturn.returnNumber), [
        'RET-1',
        'RET-1',
        'RET-2',
      ]);
      expect(rows.map((row) => row.item.itemName), ['Tea', 'Coffee', 'Item']);
      expect(rows.map((row) => row.item.returnedQuantity), [0.5, 1.5, 0.5]);
      expect(rows.map((row) => row.lineNumber), [1, 2, 1]);
    });
  });

  group('Expense categories', () {
    test('uses the custom name for other', () {
      final expense = _expense(
        category: ExpenseCategory.other,
        customCategoryName: 'Permit fee',
      );

      expect(operationalExpenseCategory(expense), 'Permit fee');
    });

    test('normal categories remain readable and bilingual', () {
      final expense = _expense(category: ExpenseCategory.fuel);

      expect(operationalExpenseCategory(expense), 'Fuel / وقود');
    });
  });

  group('Receipt rows', () {
    test('keeps one row and concatenates multiple invoice numbers', () {
      final receipt = _receipt(
        amount: 100,
        details: const [
          ReceiptInvoiceAllocation(
            invoiceId: 'i1',
            invoiceNumber: 'INV-1',
            amount: 60,
          ),
          ReceiptInvoiceAllocation(
            invoiceId: 'i2',
            invoiceNumber: 'INV-2',
            amount: 30,
          ),
        ],
      );

      final rows = buildOperationalReceiptRows([receipt], const {});

      expect(rows, hasLength(1));
      expect(rows.single.relatedInvoiceNumbers, 'INV-1, INV-2');
      expect(rows.single.totalAllocatedAmount, 90);
      expect(rows.single.unallocatedAmount, 10);
    });

    test('resolves missing legacy numbers without one-read-per-allocation', () {
      final receipt = _receipt(
        amount: 80,
        allocations: const {'legacy-1': 50, 'legacy-2': 30},
      );

      expect(legacyReceiptInvoiceIds([receipt]), {'legacy-1', 'legacy-2'});
      expect(
        operationalReceiptInvoiceNumbers(receipt, const {
          'legacy-1': 'INV-101',
          'legacy-2': 'INV-102',
        }),
        'INV-101, INV-102',
      );
      expect(
        chunkOperationalIds(
          List.generate(65, (index) => 'id-$index'),
        ).map((batch) => batch.length),
        [30, 30, 5],
      );
    });

    test('clamps unallocated amount to zero', () {
      final receipt = _receipt(amount: 50, allocations: const {'invoice': 60});

      expect(operationalReceiptAllocatedAmount(receipt), 60);
      expect(operationalReceiptUnallocatedAmount(receipt), 0);
    });

    test('cash destination requires a stored cash movement', () {
      expect(
        operationalCashDestination(_receipt(amount: 10)),
        'Representative cash / نقد المندوب',
      );
      expect(
        operationalCashDestination(
          _receipt(amount: 10, cashMovementIds: const []),
        ),
        'Not applicable / لا ينطبق',
      );
    });
  });

  group('Filters and repository query contract', () {
    test('uses a half-open inclusive-from/exclusive-to date range', () {
      final filters = OperationalReportFilters(
        fromDate: DateTime(2026, 3, 5, 18),
        toDate: DateTime(2026, 3, 12, 23, 59),
      );

      expect(filters.fromInclusive, DateTime(2026, 3, 5));
      expect(filters.toExclusive, DateTime(2026, 3, 13));
    });

    test('uses each collection date field and all-pages pagination', () {
      expect(OperationalReportRepository.invoiceDateField, 'invoiceDate');
      expect(OperationalReportRepository.expenseDateField, 'expenseDate');
      expect(OperationalReportRepository.receiptDateField, 'receiptDate');
      expect(OperationalReportRepository.returnDateField, 'returnDate');
      expect(OperationalReportRepository.pageSize, 200);

      final source = File(
        'lib/features/operational_report/data/repositories/'
        'operational_report_repository.dart',
      ).readAsStringSync();
      expect(
        RegExp(
          r'\.getAllPages\(pageSize: pageSize\)',
        ).allMatches(source).length,
        4,
      );
      expect(source, contains(".orderBy(FieldPath.documentId"));
      expect(source, contains('isLessThan: Timestamp.fromDate(to)'));
      expect(source, contains('batchSize: legacyInvoiceBatchSize'));
    });

    test('all-pages pager retrieves records beyond the first page', () async {
      final documents = await _PagedFakeQuery(450).getAllPages(pageSize: 200);

      expect(documents, hasLength(450));
      expect(documents.first.id, 'doc-0');
      expect(documents.last.id, 'doc-449');
    });
  });

  group('Workbook', () {
    test('contains exactly the four required formatted sheets', () {
      final data = OperationalReportData(
        companyId: 'company',
        invoices: [
          _invoice(
            number: 'INV-200',
            status: InvoiceStatus.accepted,
            itemNames: const ['Item A', 'Item B'],
          ),
        ],
        expenses: [_expense(category: ExpenseCategory.parking)],
        receipts: [
          _receipt(amount: 25, allocations: const {'legacy': 20}),
        ],
        salesReturns: [
          _salesReturn(
            number: 'RET-200',
            itemNames: const ['Item A', 'Item B'],
          ),
        ],
        legacyInvoiceNumbers: const {'legacy': 'INV-200'},
      );

      final bytes = OperationalReportExcelService().buildWorkbook(data);
      final workbook = Excel.decodeBytes(bytes);

      expect(workbook.tables.keys.toList(), [
        'Sales',
        'Sales Returns',
        'Expenses',
        'Receipts',
      ]);
      expect(workbook['Sales'].maxRows, 3);
      expect(workbook['Sales Returns'].maxRows, 3);
      expect(workbook['Expenses'].maxRows, 2);
      expect(workbook['Receipts'].maxRows, 2);
      expect(
        workbook['Sales'].cell(CellIndex.indexByString('A1')).value.toString(),
        contains('رقم الفاتورة'),
      );

      final archive = ZipDecoder().decodeBytes(bytes);
      final expectedFilters = ['A1:AP3', 'A1:AK3', 'A1:S2', 'A1:V2'];
      for (var index = 0; index < expectedFilters.length; index += 1) {
        final file = archive.findFile('xl/worksheets/sheet${index + 1}.xml');
        expect(file, isNotNull);
        final xml = utf8.decode(file!.content as List<int>);
        expect(xml, contains('state="frozen"'));
        expect(xml, contains('ySplit="1"'));
        expect(xml, contains('autoFilter ref="${expectedFilters[index]}"'));
      }
    });

    test('exports monetary values as numeric cells', () {
      final data = OperationalReportData(
        companyId: 'company',
        invoices: [
          _invoice(number: 'INV-300', status: InvoiceStatus.confirmed),
        ],
        expenses: const [],
        receipts: const [],
      );
      final workbook = Excel.decodeBytes(
        OperationalReportExcelService().buildWorkbook(data),
      );

      final moneyValue = workbook['Sales']
          .cell(CellIndex.indexByString('R2'))
          .value;
      expect(
        moneyValue is DoubleCellValue || moneyValue is IntCellValue,
        isTrue,
      );
      expect(
        workbook['Sales'].cell(CellIndex.indexByString('B2')).value,
        isA<DateCellValue>(),
      );
    });

    test('exports return references, item amounts, and refund breakdowns', () {
      final data = OperationalReportData(
        companyId: 'company',
        invoices: const [],
        expenses: const [],
        receipts: const [],
        salesReturns: [
          _salesReturn(number: 'RET-CREDIT'),
          _salesReturn(number: 'RET-CASH', refundType: RefundType.cashRefund),
          _salesReturn(number: 'DRAFT', status: SalesReturnStatus.draft),
          _salesReturn(number: 'CANCEL', status: SalesReturnStatus.cancelled),
        ],
      );
      final sheet = Excel.decodeBytes(
        OperationalReportExcelService().buildWorkbook(data),
      )['Sales Returns'];

      String textAt(String address) =>
          sheet.cell(CellIndex.indexByString(address)).value.toString();
      double numberAt(String address) {
        final value = sheet.cell(CellIndex.indexByString(address)).value;
        expect(value is DoubleCellValue || value is IntCellValue, isTrue);
        return double.parse(value.toString());
      }

      expect(sheet.maxRows, 3);
      expect(textAt('A2'), 'RET-CREDIT');
      expect(textAt('C2'), 'INV-ORIGINAL');
      expect(textAt('E2'), 'Return Customer');
      expect(textAt('I2'), 'Representative');
      expect(textAt('M2'), 'original-line-0');
      expect(textAt('N2'), 'CODE-0');
      expect(textAt('O2'), 'Item');
      expect(textAt('P2'), 'Returned item description 0');
      expect(numberAt('R2'), 0.5);
      expect(numberAt('S2'), 10);
      expect(numberAt('T2'), 5);
      expect(numberAt('U2'), 0.5);
      expect(numberAt('V2'), 16);
      expect(numberAt('W2'), 0.72);
      expect(numberAt('X2'), 5.22);
      expect(numberAt('Y2'), 5);
      expect(numberAt('Z2'), 0.5);
      expect(numberAt('AA2'), 0.72);
      expect(numberAt('AB2'), 5.22);
      expect(textAt('AC2'), 'Customer credit / رصيد العميل');
      expect(numberAt('AD2'), 2);
      expect(numberAt('AE2'), closeTo(3.22, 0.000001));
      expect(numberAt('AF2'), 0);
      expect(textAt('AG2'), 'Damaged item');
      expect(textAt('AH2'), 'Confirmed / مؤكد');
      expect(textAt('AC3'), 'Cash refund / استرداد نقدي');
      expect(numberAt('AD3'), 2);
      expect(numberAt('AE3'), 0);
      expect(numberAt('AF3'), closeTo(3.22, 0.000001));
      expect(
        sheet.cell(CellIndex.indexByString('B2')).value,
        isA<DateCellValue>(),
      );
      expect(
        sheet.cell(CellIndex.indexByString('D2')).value,
        DateCellValue(year: 2025, month: 12, day: 20),
      );
      expect(
        sheet.cell(CellIndex.indexByString('AK2')).value,
        isA<DateTimeCellValue>(),
      );
    });

    test('keeps an empty returns sheet with headers and filters', () {
      final bytes = OperationalReportExcelService().buildWorkbook(
        OperationalReportData(
          companyId: 'company',
          invoices: const [],
          expenses: const [],
          receipts: const [],
        ),
      );
      final sheet = Excel.decodeBytes(bytes)['Sales Returns'];
      expect(sheet.maxRows, 1);
      expect(sheet.maxColumns, 37);
      final file = ZipDecoder()
          .decodeBytes(bytes)
          .findFile('xl/worksheets/sheet2.xml');
      expect(
        utf8.decode(file!.content as List<int>),
        contains('autoFilter ref="A1:AK1"'),
      );
    });

    test(
      'supports legacy returns without a customer snapshot or invoice date',
      () {
        final legacy = _salesReturn(number: 'LEGACY').toMap()
          ..remove('customerSnapshot')
          ..remove('originalInvoiceDate');
        final sheet = Excel.decodeBytes(
          OperationalReportExcelService().buildWorkbook(
            OperationalReportData(
              companyId: 'company',
              invoices: const [],
              expenses: const [],
              receipts: const [],
              salesReturns: [SalesReturnModel.fromMap(legacy)],
            ),
          ),
        )['Sales Returns'];
        expect(sheet.maxRows, 2);
        expect(
          sheet.cell(CellIndex.indexByString('A2')).value.toString(),
          'LEGACY',
        );
        for (final address in ['D2', 'E2', 'F2', 'G2', 'H2']) {
          expect(
            sheet.cell(CellIndex.indexByString(address)).value.toString(),
            '',
          );
        }
      },
    );

    test('headers contain both English and Arabic labels', () {
      expect(
        OperationalReportExcelService.salesHeaders.first,
        contains('Invoice Number'),
      );
      expect(
        OperationalReportExcelService.salesHeaders.first,
        contains('رقم الفاتورة'),
      );
      expect(
        OperationalReportExcelService.salesReturnsHeaders.first,
        contains('Return Number / رقم المرتجع'),
      );
      expect(
        OperationalReportExcelService.expensesHeaders.first,
        contains('تاريخ المصروف'),
      );
      expect(
        OperationalReportExcelService.receiptsHeaders.first,
        contains('رقم الإيصال'),
      );
    });
  });
}

SalesReturnModel _salesReturn({
  required String number,
  SalesReturnStatus status = SalesReturnStatus.confirmed,
  RefundType refundType = RefundType.creditCustomerBalance,
  List<String> itemNames = const ['Item'],
}) {
  final quantityFactor = itemNames.length * itemNames.length;
  final subtotal = quantityFactor * 5.0;
  final discount = quantityFactor * 0.5;
  final tax = quantityFactor * 0.72;
  final grandTotal = quantityFactor * 5.22;
  final receivableReduction = grandTotal == 0 ? 0.0 : 2.0;
  final refund = grandTotal - receivableReduction;
  return SalesReturnModel.fromMap({
    'id': number,
    'companyId': 'company',
    'returnNumber': number,
    'returnDate': DateTime(2026, 3, 12),
    'originalInvoiceId': 'invoice-original',
    'originalInvoiceNumber': 'INV-ORIGINAL',
    'originalInvoiceDate': DateTime(2025, 12, 20),
    'customerId': 'customer-1',
    'customerSnapshot': const InvoiceCustomerSnapshot(
      id: 'customer-1',
      name: 'Return Customer',
      phone: '0790000000',
      address: 'Amman Street',
      taxNumber: '',
      nationalNumber: '',
      city: 'Amman',
    ).toMap(),
    'salesRepId': 'rep-1',
    'salesRepName': 'Representative',
    'createdByUid': 'admin-1',
    'createdByName': 'Admin',
    'createdByRole': 'admin',
    'items': [
      for (var index = 0; index < itemNames.length; index += 1)
        {
          'lineId': 'return-line-$index',
          'originalInvoiceItemId': 'original-line-$index',
          'itemId': 'item-$index',
          'itemName': itemNames[index],
          'itemCode': 'CODE-$index',
          'description': 'Returned item description $index',
          'unit': 'piece',
          'returnedQuantity': index + 0.5,
          'unitPrice': 10.0,
          'discountPerUnit': 1.0,
          'discountAmount': index + 0.5,
          'taxPercent': 16.0,
          'subtotal': (index + 0.5) * 10.0,
          'taxAmount': (index * 2 + 1) * 0.72,
          'total': (index * 2 + 1) * 5.22,
        },
    ],
    'subtotal': subtotal,
    'totalDiscount': discount,
    'totalTax': tax,
    'grandTotal': grandTotal,
    'receivableReduction': receivableReduction,
    'customerCreditAmount': refundType == RefundType.creditCustomerBalance
        ? refund
        : 0.0,
    'cashRefundAmount': refundType == RefundType.cashRefund ? refund : 0.0,
    'refundType': refundType.value,
    'reason': 'Damaged item',
    'status': status.value,
    'financialPosted': status == SalesReturnStatus.confirmed,
    'inventoryPosted': status == SalesReturnStatus.confirmed,
    'createdAt': DateTime(2026, 3, 12, 10),
    'updatedAt': DateTime(2026, 3, 12, 10),
  });
}

InvoiceModel _invoice({
  required String number,
  required InvoiceStatus status,
  List<String> itemNames = const ['Item'],
}) {
  return InvoiceModel.fromMap({
    'id': number,
    'companyId': 'company',
    'invoiceNumber': number,
    'invoiceType': 'regular',
    'invoiceStatus': status.name,
    'paymentType': 'partial',
    'paymentStatus': 'partiallyPaid',
    'invoiceDate': DateTime(2026, 3, 10),
    'dueDate': DateTime(2026, 3, 20),
    'createdAt': DateTime(2026, 3, 9, 14, 30),
    'updatedAt': DateTime(2026, 3, 10),
    'createdByUid': 'admin-1',
    'createdByName': 'Admin',
    'createdByRole': 'admin',
    'salesRepId': 'rep-1',
    'salesRepName': 'Representative',
    'customerId': 'customer-1',
    'customerSnapshot': const InvoiceCustomerSnapshot(
      id: 'customer-1',
      name: 'Customer',
      phone: '0790000000',
      address: 'Amman Street',
      taxNumber: '',
      nationalNumber: '',
      city: 'Amman',
    ).toMap(),
    'items': [
      for (var index = 0; index < itemNames.length; index += 1)
        {
          'lineId': 'line-$index',
          'itemId': 'item-$index',
          'itemName': itemNames[index],
          'itemCode': 'CODE-$index',
          'description': 'Description $index',
          'unit': 'piece',
          'quantity': index + 1,
          'unitPrice': 10.0,
          'discount': 1.0,
          'taxPercent': 16.0,
          'subtotal': 10.0,
          'taxAmount': 1.44,
          'total': 10.44,
        },
    ],
    'subtotal': 20.0,
    'totalDiscount': 2.0,
    'totalTax': 2.88,
    'grandTotal': 20.88,
    'paidAmount': 5.0,
    'remainingAmount': 15.88,
    'returnedReceivableAmount': 2.0,
    'returnedTotal': 2.0,
    'customerCreditAmount': 1.0,
    'cashRefundAmount': 1.0,
    'returnStatus': 'partiallyReturned',
    'notes': 'Invoice note',
    'paymentMethod': 'cash',
    'stockSourceType': 'companyWarehouse',
    'government': {
      'governmentInvoiceId': 'GOV-1',
      'joFotaraStatus': 'accepted',
    },
  });
}

ExpenseModel _expense({
  required ExpenseCategory category,
  String customCategoryName = '',
}) {
  return ExpenseModel(
    id: 'expense-1',
    companyId: 'company',
    amount: 12.5,
    expenseDate: DateTime(2026, 3, 11),
    category: category,
    customCategoryName: customCategoryName,
    description: 'Expense note',
    paidByUid: 'admin-1',
    paidByName: 'Admin',
    paidByRole: 'admin',
    salesRepId: '',
    salesRepName: '',
    paymentMethod: 'cash',
    fundingSource: ExpenseFundingSource.companyCash,
    status: ExpenseStatus.posted,
    cashMovementId: 'cash-1',
    reimbursementStatus: ExpenseReimbursementStatus.none,
    approvedByUid: '',
    approvedByName: '',
    approvedAt: null,
    rejectedByUid: '',
    rejectedByName: '',
    rejectedAt: null,
    rejectionReason: '',
    createdByUid: 'admin-1',
    createdByName: 'Admin',
    createdByRole: 'admin',
    createdAt: DateTime(2026, 3, 11, 12),
    updatedAt: DateTime(2026, 3, 11, 12),
  );
}

ReceiptModel _receipt({
  required double amount,
  Map<String, double> allocations = const {},
  List<ReceiptInvoiceAllocation> details = const [],
  List<String> cashMovementIds = const ['cash-1'],
}) {
  return ReceiptModel(
    id: 'receipt-1',
    companyId: 'company',
    receiptNumber: 'REC-1',
    receiptDate: DateTime(2026, 3, 12),
    customerId: 'customer-1',
    customerSnapshot: const InvoiceCustomerSnapshot(
      id: 'customer-1',
      name: 'Customer',
      phone: '0790000000',
      address: 'Amman',
      taxNumber: '',
      nationalNumber: '',
      city: 'Amman',
    ),
    amount: amount,
    paymentMethod: 'cash',
    notes: 'Receipt note',
    salesRepId: 'rep-1',
    salesRepName: 'Representative',
    createdByUid: 'rep-1',
    createdByName: 'Representative',
    createdByRole: 'sales_rep',
    customerTransactionIds: const ['transaction-1'],
    cashMovementIds: cashMovementIds,
    invoiceAllocations: allocations,
    invoiceAllocationDetails: details,
    payFullBalance: false,
    resultingCustomerBalance: 25,
    createdAt: DateTime(2026, 3, 12, 9),
    updatedAt: DateTime(2026, 3, 12, 9),
  );
}

class _PagedFakeQuery implements Query<Map<String, dynamic>> {
  _PagedFakeQuery(this.total, {this.start = 0, this.pageLimit});

  final int total;
  final int start;
  final int? pageLimit;

  @override
  Future<QuerySnapshot<Map<String, dynamic>>> get([GetOptions? options]) async {
    final end = (start + (pageLimit ?? total)).clamp(0, total).toInt();
    return _FakeQuerySnapshot([
      for (var index = start; index < end; index += 1)
        _FakeQueryDocument(index),
    ]);
  }

  @override
  Query<Map<String, dynamic>> limit(int limit) =>
      _PagedFakeQuery(total, start: start, pageLimit: limit);

  @override
  Query<Map<String, dynamic>> startAfterDocument(
    DocumentSnapshot documentSnapshot,
  ) => _PagedFakeQuery(
    total,
    start: (documentSnapshot as _FakeQueryDocument).index + 1,
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeQuerySnapshot implements QuerySnapshot<Map<String, dynamic>> {
  const _FakeQuerySnapshot(this.docs);

  @override
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs;

  @override
  int get size => docs.length;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeQueryDocument
    implements QueryDocumentSnapshot<Map<String, dynamic>> {
  const _FakeQueryDocument(this.index);

  final int index;

  @override
  String get id => 'doc-$index';

  @override
  bool get exists => true;

  @override
  Map<String, dynamic> data() => {'index': index};

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
