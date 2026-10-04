import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:excel/excel.dart';
import 'package:fatoora/features/expenses/data/models/expense_model.dart';
import 'package:fatoora/features/operational_report/data/models/operational_report_data.dart';
import 'package:fatoora/features/operational_report/data/models/operational_report_filters.dart';
import 'package:fatoora/features/receipts/data/models/receipt_model.dart';
import 'package:file_saver/file_saver.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:xml/xml.dart';

typedef OperationalReportFileSaver =
    Future<bool> Function(Uint8List bytes, String fileName);

class _OperationalReportBuildRequest {
  const _OperationalReportBuildRequest(this.data);

  final OperationalReportData data;
}

List<int> _buildOperationalReportInIsolate(
  _OperationalReportBuildRequest request,
) => OperationalReportExcelService().buildWorkbook(request.data);

class OperationalReportExcelService {
  OperationalReportExcelService({OperationalReportFileSaver? fileSaver})
    : _fileSaver = fileSaver ?? _saveWithFileSaver;

  static const salesSheetName = 'Sales';
  static const expensesSheetName = 'Expenses';
  static const receiptsSheetName = 'Receipts';

  static const salesHeaders = <String>[
    'Invoice Number / رقم الفاتورة',
    'Invoice Date / تاريخ الفاتورة',
    'Due Date / تاريخ الاستحقاق',
    'Invoice Type / نوع الفاتورة',
    'Customer Name / اسم العميل',
    'Customer Phone / هاتف العميل',
    'Customer Address / عنوان العميل',
    'Customer City / مدينة العميل',
    'Sales Rep Name / اسم المندوب',
    'Created By Name / أنشئت بواسطة',
    'Created By Role / دور المنشئ',
    'Line Number / رقم السطر',
    'Item Code / رمز الصنف',
    'Item Name / اسم الصنف',
    'Description / الوصف',
    'Unit / الوحدة',
    'Quantity / الكمية',
    'Unit Price / سعر الوحدة',
    'Line Subtotal / المجموع قبل الخصم والضريبة',
    'Line Discount / خصم السطر',
    'Tax Percent / نسبة الضريبة',
    'Tax Amount / مبلغ الضريبة',
    'Line Total / إجمالي السطر',
    'Invoice Subtotal / مجموع الفاتورة الفرعي',
    'Invoice Discount / خصم الفاتورة',
    'Invoice Tax / ضريبة الفاتورة',
    'Invoice Grand Total / إجمالي الفاتورة',
    'Payment Type / نوع الدفع',
    'Payment Status / حالة الدفع',
    'Payment Method / طريقة الدفع',
    'Paid Amount / المبلغ المدفوع',
    'Remaining Amount / المبلغ المتبقي',
    'Effective Outstanding Amount / المستحق الفعلي',
    'Return Status / حالة المرتجع',
    'Returned Total / إجمالي المرتجع',
    'Customer Credit Amount / رصيد العميل',
    'Cash Refund Amount / المبلغ المسترد نقداً',
    'Invoice Notes / ملاحظات الفاتورة',
    'Stock Source Type / مصدر المخزون',
    'Government Invoice ID / رقم الفاتورة الحكومي',
    'Government Status / الحالة الحكومية',
    'Created At / تاريخ الإنشاء',
  ];

  static const expensesHeaders = <String>[
    'Expense Date / تاريخ المصروف',
    'Category / الفئة',
    'Amount / المبلغ',
    'Description / Notes / الوصف والملاحظات',
    'Payment Method / طريقة الدفع',
    'Funding Source / مصدر التمويل',
    'Status / الحالة',
    'Reimbursement Status / حالة التعويض',
    'Paid By Name / اسم الدافع',
    'Paid By Role / دور الدافع',
    'Sales Rep Name / اسم المندوب',
    'Created By Name / أنشئ بواسطة',
    'Created By Role / دور المنشئ',
    'Approved By Name / اعتمد بواسطة',
    'Approved At / تاريخ الاعتماد',
    'Rejected By Name / رفض بواسطة',
    'Rejected At / تاريخ الرفض',
    'Rejection Reason / سبب الرفض',
    'Created At / تاريخ الإنشاء',
  ];

  static const receiptsHeaders = <String>[
    'Receipt Number / رقم الإيصال',
    'Receipt Date / تاريخ الإيصال',
    'Customer Name / اسم العميل',
    'Customer Phone / هاتف العميل',
    'Receipt Amount / مبلغ الإيصال',
    'Payment Method / طريقة الدفع',
    'Cash Destination / وجهة النقد',
    'Pay Full Balance / دفع كامل الرصيد',
    'Resulting Customer Balance / رصيد العميل الناتج',
    'Related Invoice Numbers / أرقام الفواتير المرتبطة',
    'Total Allocated Amount / إجمالي المبلغ المخصص',
    'Unallocated Amount / المبلغ غير المخصص',
    'Sales Rep Name / اسم المندوب',
    'Created By Name / أنشئ بواسطة',
    'Created By Role / دور المنشئ',
    'Notes / الملاحظات',
    'Created At / تاريخ الإنشاء',
  ];

  final OperationalReportFileSaver _fileSaver;

  Future<void> saveReport({
    required OperationalReportData data,
    required OperationalReportFilters filters,
  }) async {
    final bytes = kIsWeb
        ? buildWorkbook(data)
        : await compute(
            _buildOperationalReportInIsolate,
            _OperationalReportBuildRequest(data),
          );
    if (bytes.isEmpty) {
      throw StateError('Operational Excel generation returned no bytes.');
    }
    final saved = await _fileSaver(
      Uint8List.fromList(bytes),
      'operational-report-${_dateSuffix(filters)}',
    );
    if (!saved) {
      throw StateError('The operational report could not be saved.');
    }
  }

  List<int> buildWorkbook(OperationalReportData data) {
    final salesRows = buildOperationalSalesRows(data.invoices);
    final receiptRows = buildOperationalReceiptRows(
      data.receipts,
      data.legacyInvoiceNumbers,
    );
    final excel = Excel.createExcel();
    excel.rename('Sheet1', salesSheetName);
    _buildSales(excel[salesSheetName], salesRows);
    _buildExpenses(excel[expensesSheetName], data.expenses);
    _buildReceipts(excel[receiptsSheetName], receiptRows);
    final bytes = excel.save() ?? const <int>[];
    if (bytes.isEmpty) return bytes;
    return _addWorksheetFeatures(
      bytes,
      [
        _SheetLayout(columns: salesHeaders.length),
        _SheetLayout(columns: expensesHeaders.length),
        _SheetLayout(columns: receiptsHeaders.length),
      ],
      [salesRows.length, data.expenses.length, receiptRows.length],
    );
  }

  void _buildSales(Sheet sheet, List<OperationalSalesRow> rows) {
    _writeHeaders(sheet, salesHeaders);
    for (var index = 0; index < rows.length; index += 1) {
      final row = rows[index];
      final invoice = row.invoice;
      final customer = invoice.customerSnapshot;
      final item = row.item;
      final values = <CellValue>[
        TextCellValue(invoice.invoiceNumber),
        DateCellValue.fromDateTime(invoice.invoiceDate),
        DateCellValue.fromDateTime(invoice.dueDate),
        TextCellValue(_invoiceType(invoice.invoiceType.name)),
        TextCellValue(customer?.name ?? ''),
        TextCellValue(customer?.phone ?? ''),
        TextCellValue(customer?.address ?? ''),
        TextCellValue(customer?.city ?? ''),
        TextCellValue(invoice.salesRepName),
        TextCellValue(invoice.createdByName),
        TextCellValue(_role(invoice.createdByRole)),
        IntCellValue(row.lineNumber),
        TextCellValue(item.itemCode),
        TextCellValue(item.itemName),
        TextCellValue(item.description),
        TextCellValue(item.unit),
        DoubleCellValue(item.quantity),
        DoubleCellValue(item.unitPrice),
        DoubleCellValue(item.subtotal),
        DoubleCellValue(item.discount),
        DoubleCellValue(item.taxPercent),
        DoubleCellValue(item.taxAmount),
        DoubleCellValue(item.total),
        DoubleCellValue(invoice.subtotal),
        DoubleCellValue(invoice.totalDiscount),
        DoubleCellValue(invoice.totalTax),
        DoubleCellValue(invoice.grandTotal),
        TextCellValue(_paymentType(invoice.paymentType.name)),
        TextCellValue(_paymentStatus(invoice.paymentStatus.name)),
        TextCellValue(_paymentMethod(invoice.paymentMethod)),
        DoubleCellValue(invoice.paidAmount),
        DoubleCellValue(invoice.remainingAmount),
        DoubleCellValue(invoice.effectiveOutstandingAmount),
        TextCellValue(_returnStatus(invoice.returnStatus.name)),
        DoubleCellValue(invoice.returnedTotal),
        DoubleCellValue(invoice.customerCreditAmount),
        DoubleCellValue(invoice.cashRefundAmount),
        TextCellValue(invoice.notes),
        TextCellValue(_stockSource(invoice.stockSourceType.name)),
        TextCellValue(invoice.government?.governmentInvoiceId ?? ''),
        TextCellValue(invoice.government?.joFotaraStatus ?? ''),
        DateTimeCellValue.fromDateTime(invoice.createdAt),
      ];
      _writeRow(
        sheet,
        index + 1,
        values,
        moneyColumns: const {
          17,
          18,
          19,
          21,
          22,
          23,
          24,
          25,
          26,
          30,
          31,
          32,
          34,
          35,
          36,
        },
        quantityColumns: const {16},
        percentColumns: const {20},
        dateColumns: const {1, 2},
        dateTimeColumns: const {41},
      );
    }
    _setWidths(sheet, const [
      20,
      16,
      16,
      19,
      26,
      19,
      30,
      18,
      24,
      24,
      18,
      12,
      18,
      27,
      30,
      14,
      14,
      16,
      18,
      16,
      14,
      16,
      17,
      19,
      18,
      16,
      19,
      17,
      19,
      18,
      17,
      18,
      23,
      18,
      18,
      20,
      18,
      34,
      22,
      25,
      22,
      21,
    ]);
  }

  void _buildExpenses(Sheet sheet, List<ExpenseModel> expenses) {
    _writeHeaders(sheet, expensesHeaders);
    for (var index = 0; index < expenses.length; index += 1) {
      final expense = expenses[index];
      final values = <CellValue>[
        DateCellValue.fromDateTime(expense.expenseDate),
        TextCellValue(operationalExpenseCategory(expense)),
        DoubleCellValue(expense.amount),
        TextCellValue(expense.description),
        TextCellValue(_paymentMethod(expense.paymentMethod)),
        TextCellValue(_fundingSource(expense.fundingSource.value)),
        TextCellValue(_expenseStatus(expense.status.value)),
        TextCellValue(_reimbursementStatus(expense.reimbursementStatus.value)),
        TextCellValue(expense.paidByName),
        TextCellValue(_role(expense.paidByRole)),
        TextCellValue(expense.salesRepName),
        TextCellValue(expense.createdByName),
        TextCellValue(_role(expense.createdByRole)),
        TextCellValue(expense.approvedByName),
        _nullableDateTime(expense.approvedAt),
        TextCellValue(expense.rejectedByName),
        _nullableDateTime(expense.rejectedAt),
        TextCellValue(expense.rejectionReason),
        DateTimeCellValue.fromDateTime(expense.createdAt),
      ];
      _writeRow(
        sheet,
        index + 1,
        values,
        moneyColumns: const {2},
        dateColumns: const {0},
        dateTimeColumns: const {14, 16, 18},
      );
    }
    _setWidths(sheet, const [
      17,
      24,
      16,
      36,
      20,
      23,
      18,
      23,
      24,
      18,
      24,
      24,
      18,
      24,
      21,
      24,
      21,
      32,
      21,
    ]);
  }

  void _buildReceipts(Sheet sheet, List<OperationalReceiptRow> rows) {
    _writeHeaders(sheet, receiptsHeaders);
    for (var index = 0; index < rows.length; index += 1) {
      final row = rows[index];
      final receipt = row.receipt;
      final values = <CellValue>[
        TextCellValue(receipt.receiptNumber),
        DateCellValue.fromDateTime(receipt.receiptDate),
        TextCellValue(receipt.customerSnapshot.name),
        TextCellValue(receipt.customerSnapshot.phone),
        DoubleCellValue(receipt.amount),
        TextCellValue(_paymentMethod(receipt.paymentMethod)),
        TextCellValue(operationalCashDestination(receipt)),
        TextCellValue(receipt.payFullBalance ? 'Yes / نعم' : 'No / لا'),
        receipt.resultingCustomerBalance == null
            ? TextCellValue('')
            : DoubleCellValue(receipt.resultingCustomerBalance!),
        TextCellValue(row.relatedInvoiceNumbers),
        DoubleCellValue(row.totalAllocatedAmount),
        DoubleCellValue(row.unallocatedAmount),
        TextCellValue(receipt.salesRepName),
        TextCellValue(receipt.createdByName),
        TextCellValue(_role(receipt.createdByRole)),
        TextCellValue(receipt.notes),
        DateTimeCellValue.fromDateTime(receipt.createdAt),
      ];
      _writeRow(
        sheet,
        index + 1,
        values,
        moneyColumns: const {4, 8, 10, 11},
        dateColumns: const {1},
        dateTimeColumns: const {16},
      );
    }
    _setWidths(sheet, const [
      21,
      17,
      27,
      19,
      17,
      20,
      24,
      19,
      24,
      39,
      21,
      20,
      24,
      24,
      18,
      34,
      21,
    ]);
  }

  static void _writeHeaders(Sheet sheet, List<String> headers) {
    sheet.setRowHeight(0, 42);
    for (var column = 0; column < headers.length; column += 1) {
      _set(sheet, column, 0, TextCellValue(headers[column]), _headerStyle);
    }
  }

  static void _writeRow(
    Sheet sheet,
    int row,
    List<CellValue> values, {
    Set<int> moneyColumns = const {},
    Set<int> quantityColumns = const {},
    Set<int> percentColumns = const {},
    Set<int> dateColumns = const {},
    Set<int> dateTimeColumns = const {},
  }) {
    for (var column = 0; column < values.length; column += 1) {
      final style = moneyColumns.contains(column)
          ? _moneyStyle
          : quantityColumns.contains(column)
          ? _quantityStyle
          : percentColumns.contains(column)
          ? _percentStyle
          : dateColumns.contains(column)
          ? _dateStyle
          : dateTimeColumns.contains(column)
          ? _dateTimeStyle
          : _bodyStyle;
      _set(sheet, column, row, values[column], style);
    }
  }

  static void _set(
    Sheet sheet,
    int column,
    int row,
    CellValue value,
    CellStyle style,
  ) {
    final cell = sheet.cell(
      CellIndex.indexByColumnRow(columnIndex: column, rowIndex: row),
    );
    cell.value = value;
    cell.cellStyle = style;
  }

  static void _setWidths(Sheet sheet, List<double> widths) {
    for (var column = 0; column < widths.length; column += 1) {
      sheet.setColumnWidth(column, widths[column]);
    }
  }

  static CellValue _nullableDateTime(DateTime? value) =>
      value == null ? TextCellValue('') : DateTimeCellValue.fromDateTime(value);

  static List<int> _addWorksheetFeatures(
    List<int> bytes,
    List<_SheetLayout> layouts,
    List<int> dataRowCounts,
  ) {
    final archive = ZipDecoder().decodeBytes(bytes);
    final worksheetFiles =
        archive.files
            .where(
              (file) =>
                  RegExp(r'^xl/worksheets/sheet\d+\.xml$').hasMatch(file.name),
            )
            .toList()
          ..sort(
            (left, right) =>
                _sheetNumber(left.name).compareTo(_sheetNumber(right.name)),
          );
    if (worksheetFiles.length != layouts.length ||
        dataRowCounts.length != layouts.length) {
      throw StateError('Unexpected worksheet layout while finalizing report.');
    }

    for (var index = 0; index < worksheetFiles.length; index += 1) {
      final file = worksheetFiles[index];
      final document = XmlDocument.parse(
        utf8.decode((file.content as List<int>)),
      );
      final sheetView = document.findAllElements('sheetView').first;
      sheetView.children.removeWhere(
        (node) => node is XmlElement && node.name.local == 'pane',
      );
      sheetView.children.insert(
        0,
        XmlElement(XmlName('pane'), [
          XmlAttribute(XmlName('ySplit'), '1'),
          XmlAttribute(XmlName('topLeftCell'), 'A2'),
          XmlAttribute(XmlName('activePane'), 'bottomLeft'),
          XmlAttribute(XmlName('state'), 'frozen'),
        ]),
      );

      final worksheet = document.findAllElements('worksheet').first;
      worksheet.children.removeWhere(
        (node) => node is XmlElement && node.name.local == 'autoFilter',
      );
      final sheetData = document.findAllElements('sheetData').first;
      final sheetDataIndex = worksheet.children.indexOf(sheetData);
      final lastColumn = _columnName(layouts[index].columns);
      final lastRow = dataRowCounts[index] + 1;
      worksheet.children.insert(
        sheetDataIndex + 1,
        XmlElement(XmlName('autoFilter'), [
          XmlAttribute(XmlName('ref'), 'A1:$lastColumn$lastRow'),
        ]),
      );

      final content = utf8.encode(document.toXmlString());
      final replacement = ArchiveFile(file.name, content.length, content)
        ..lastModTime = file.lastModTime
        ..mode = file.mode;
      archive.addFile(replacement);
    }
    return ZipEncoder().encode(archive) ?? const <int>[];
  }

  static int _sheetNumber(String path) =>
      int.parse(RegExp(r'sheet(\d+)\.xml$').firstMatch(path)!.group(1)!);

  static String _columnName(int columnCount) {
    var number = columnCount;
    var result = '';
    while (number > 0) {
      final remainder = (number - 1) % 26;
      result = String.fromCharCode(65 + remainder) + result;
      number = (number - 1) ~/ 26;
    }
    return result;
  }

  static Future<bool> _saveWithFileSaver(
    Uint8List bytes,
    String fileName,
  ) async {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      final result = await FileSaver.instance.saveAs(
        name: fileName,
        bytes: bytes,
        fileExtension: 'xlsx',
        mimeType: MimeType.microsoftExcel,
      );
      return result?.trim().isNotEmpty == true;
    }
    final result = await FileSaver.instance.saveFile(
      name: fileName,
      bytes: bytes,
      fileExtension: 'xlsx',
      mimeType: MimeType.microsoftExcel,
    );
    final normalized = result.trim().toLowerCase();
    return normalized.isNotEmpty &&
        !normalized.startsWith('something went wrong');
  }

  static String _dateSuffix(OperationalReportFilters filters) {
    final formatter = DateFormat('yyyyMMdd');
    final from = filters.fromDate;
    final to = filters.toDate;
    if (from == null && to == null) return 'all-periods';
    return '${from == null ? 'start' : formatter.format(from)}-'
        '${to == null ? 'present' : formatter.format(to)}';
  }

  static String _invoiceType(String value) => switch (value) {
    'electronic' => 'Electronic / إلكترونية',
    _ => 'Regular / عادية',
  };

  static String _paymentType(String value) => switch (value) {
    'credit' => 'Credit / آجل',
    'partial' => 'Partial / جزئي',
    _ => 'Cash / نقدي',
  };

  static String _paymentStatus(String value) => switch (value) {
    'unpaid' => 'Unpaid / غير مدفوعة',
    'partiallyPaid' => 'Partially paid / مدفوعة جزئياً',
    'overdue' => 'Overdue / متأخرة',
    _ => 'Paid / مدفوعة',
  };

  static String _returnStatus(String value) => switch (value) {
    'partiallyReturned' => 'Partially returned / مرتجعة جزئياً',
    'returned' => 'Returned / مرتجعة',
    _ => 'None / لا يوجد',
  };

  static String _stockSource(String value) => switch (value) {
    'representative' || 'salesRep' => 'Representative / المندوب',
    _ => 'Company warehouse / مستودع الشركة',
  };

  static String _role(String value) => switch (value.trim().toLowerCase()) {
    'admin' => 'Admin / مدير',
    'sales_rep' || 'salesrep' => 'Sales representative / مندوب مبيعات',
    _ => value,
  };

  static String _paymentMethod(String value) =>
      switch (value.trim().toLowerCase()) {
        'cash' => 'Cash / نقدي',
        'bank' => 'Bank / بنك',
        'check' || 'cheque' => 'Check / شيك',
        'cliq' => 'CliQ / كليك',
        _ => value,
      };

  static String _fundingSource(String value) => switch (value) {
    'company_cash' => 'Company cash / نقد الشركة',
    'rep_collected_cash' => 'Rep collected cash / نقد محصل لدى المندوب',
    'personal_cash' => 'Personal cash / نقد شخصي',
    _ => value,
  };

  static String _expenseStatus(String value) => switch (value) {
    'posted' => 'Posted / مرحّل',
    'pending' => 'Pending / معلّق',
    'approved' => 'Approved / معتمد',
    'rejected' => 'Rejected / مرفوض',
    'cancelled' => 'Cancelled / ملغى',
    _ => value,
  };

  static String _reimbursementStatus(String value) => switch (value) {
    'payable' => 'Payable / مستحق الدفع',
    'paid' => 'Paid / مدفوع',
    _ => 'None / لا يوجد',
  };

  static final _thinBorder = Border(
    borderStyle: BorderStyle.Thin,
    borderColorHex: ExcelColor.fromHexString('FFD1D9E2'),
  );
  static final _headerStyle = CellStyle(
    bold: true,
    fontColorHex: ExcelColor.white,
    backgroundColorHex: ExcelColor.fromHexString('FF176B78'),
    horizontalAlign: HorizontalAlign.Center,
    verticalAlign: VerticalAlign.Center,
    textWrapping: TextWrapping.WrapText,
    leftBorder: _thinBorder,
    rightBorder: _thinBorder,
    topBorder: _thinBorder,
    bottomBorder: _thinBorder,
  );
  static final _bodyStyle = CellStyle(
    verticalAlign: VerticalAlign.Center,
    textWrapping: TextWrapping.WrapText,
    leftBorder: _thinBorder,
    rightBorder: _thinBorder,
    topBorder: _thinBorder,
    bottomBorder: _thinBorder,
  );
  static final _moneyStyle = _bodyStyle.copyWith(
    horizontalAlignVal: HorizontalAlign.Right,
    numberFormat: NumFormat.custom(formatCode: '#,##0.000;[Red](#,##0.000);-'),
  );
  static final _quantityStyle = _bodyStyle.copyWith(
    horizontalAlignVal: HorizontalAlign.Right,
    numberFormat: NumFormat.custom(formatCode: '#,##0.###'),
  );
  static final _percentStyle = _bodyStyle.copyWith(
    horizontalAlignVal: HorizontalAlign.Right,
    numberFormat: NumFormat.custom(formatCode: '0.###'),
  );
  static final _dateStyle = _bodyStyle.copyWith(
    horizontalAlignVal: HorizontalAlign.Center,
    numberFormat: NumFormat.custom(formatCode: 'yyyy-mm-dd'),
  );
  static final _dateTimeStyle = _bodyStyle.copyWith(
    horizontalAlignVal: HorizontalAlign.Center,
    numberFormat: NumFormat.custom(formatCode: 'yyyy-mm-dd hh:mm'),
  );
}

String operationalExpenseCategory(ExpenseModel expense) {
  if (expense.category == ExpenseCategory.other &&
      expense.customCategoryName.trim().isNotEmpty) {
    return expense.customCategoryName.trim();
  }
  return switch (expense.category) {
    ExpenseCategory.fuel => 'Fuel / وقود',
    ExpenseCategory.parking => 'Parking / مواقف',
    ExpenseCategory.maintenance => 'Maintenance / صيانة',
    ExpenseCategory.delivery => 'Delivery / توصيل',
    ExpenseCategory.meals => 'Meals / وجبات',
    ExpenseCategory.office => 'Office / مكتبية',
    ExpenseCategory.utilities => 'Utilities / خدمات',
    ExpenseCategory.salary => 'Salary / رواتب',
    ExpenseCategory.rent => 'Rent / إيجار',
    ExpenseCategory.other => 'Other / أخرى',
  };
}

String operationalCashDestination(ReceiptModel receipt) {
  if (receipt.paymentMethod.trim().toLowerCase() != 'cash' ||
      receipt.cashMovementIds.isEmpty) {
    return 'Not applicable / لا ينطبق';
  }
  return receipt.createdByRole.trim().toLowerCase() == 'admin'
      ? 'Company cash / نقد الشركة'
      : 'Representative cash / نقد المندوب';
}

class _SheetLayout {
  const _SheetLayout({required this.columns});

  final int columns;
}
