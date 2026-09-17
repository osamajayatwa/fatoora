import 'package:excel/excel.dart';
import 'package:fatoora/features/financial_ledger/data/models/financial_ledger_entry.dart';
import 'package:fatoora/features/financial_ledger/data/models/financial_ledger_export_data.dart';
import 'package:fatoora/features/financial_ledger/data/models/financial_ledger_filters.dart';
import 'package:file_saver/file_saver.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

typedef FinancialLedgerFileSaver =
    Future<bool> Function(Uint8List bytes, String fileName);

class _AccountingReportBuildRequest {
  const _AccountingReportBuildRequest(this.data, this.filters);

  final FinancialLedgerExportData data;
  final FinancialLedgerFilters filters;
}

List<int> _buildAccountingReportInIsolate(
  _AccountingReportBuildRequest request,
) => FinancialLedgerExcelService().buildAccountingReport(
  data: request.data,
  filters: request.filters,
);

class FinancialLedgerExcelService {
  FinancialLedgerExcelService({FinancialLedgerFileSaver? fileSaver})
    : _fileSaver = fileSaver ?? _saveWithFileSaver;

  final FinancialLedgerFileSaver _fileSaver;

  Future<void> saveAccountingReport({
    required FinancialLedgerExportData data,
    required FinancialLedgerFilters filters,
  }) async {
    final bytes = kIsWeb
        ? buildAccountingReport(data: data, filters: filters)
        : await compute(
            _buildAccountingReportInIsolate,
            _AccountingReportBuildRequest(data, filters),
          );
    if (bytes.isEmpty) {
      throw StateError('Excel generation returned no bytes.');
    }
    final saved = await _fileSaver(
      Uint8List.fromList(bytes),
      'accounting-report-${_dateSuffix(filters)}',
    );
    if (!saved) {
      throw StateError('The accounting report could not be saved.');
    }
  }

  List<int> buildAccountingReport({
    required FinancialLedgerExportData data,
    required FinancialLedgerFilters filters,
  }) {
    final excel = Excel.createExcel();
    excel.rename('Sheet1', 'الملخص Summary');
    _buildSummary(excel['الملخص Summary'], data, filters);
    _buildJournal(excel['القيود Journal'], data, filters);
    _buildSalesDetails(excel['تفاصيل المبيعات'], data, filters);
    _buildGeneralLedger(excel['الأستاذ العام GL'], data, filters);
    return excel.save() ?? <int>[];
  }

  List<FinancialLedgerGeneralLedgerRow> buildGeneralLedgerRows({
    required FinancialLedgerExportData data,
    required FinancialLedgerFilters filters,
  }) {
    final accounts = <String, _LedgerAccount>{};
    for (final entry in data.entries) {
      if (entry.debitAccountKey.isNotEmpty) {
        accounts.putIfAbsent(
          entry.debitAccountKey,
          () => _LedgerAccount(
            key: entry.debitAccountKey,
            type: entry.debitAccountType,
            name: _accountName(entry.debitAccountKey, entry.debitAccountName),
          ),
        );
      }
      if (entry.creditAccountKey.isNotEmpty) {
        accounts.putIfAbsent(
          entry.creditAccountKey,
          () => _LedgerAccount(
            key: entry.creditAccountKey,
            type: entry.creditAccountType,
            name: _accountName(entry.creditAccountKey, entry.creditAccountName),
          ),
        );
      }
    }
    for (final opening in data.openingBalances.values) {
      accounts.putIfAbsent(
        opening.accountKey,
        () => _LedgerAccount(
          key: opening.accountKey,
          type: opening.accountType,
          name: _accountName(opening.accountKey, opening.accountName),
        ),
      );
    }
    final orderedAccounts = accounts.values.toList()
      ..sort((left, right) {
        final name = left.name.compareTo(right.name);
        return name != 0 ? name : left.key.compareTo(right.key);
      });
    final rows = <FinancialLedgerGeneralLedgerRow>[];
    for (final account in orderedAccounts) {
      final opening = data.openingBalances[account.key];
      var balance = _round(opening?.balance ?? 0);
      rows.add(
        FinancialLedgerGeneralLedgerRow(
          accountKey: account.key,
          accountName: account.name,
          accountType: account.type,
          date: filters.fromInclusive,
          reference: '',
          entryId: '',
          description: 'Balance brought forward / الرصيد السابق',
          counterpartyAccount: '',
          debit: balance > 0 ? balance : 0,
          credit: balance < 0 ? -balance : 0,
          runningBalance: balance,
          side: _balanceSide(balance),
          isOpening: true,
        ),
      );
      final postings = <_Posting>[];
      for (final entry in data.entries) {
        if (entry.debitAccountKey == account.key) {
          postings.add(
            _Posting(
              entry: entry,
              sideOrder: 0,
              debit: entry.amount,
              credit: 0,
              counterparty: _accountName(
                entry.creditAccountKey,
                entry.creditAccountName,
              ),
            ),
          );
        }
        if (entry.creditAccountKey == account.key) {
          postings.add(
            _Posting(
              entry: entry,
              sideOrder: 1,
              debit: 0,
              credit: entry.amount,
              counterparty: _accountName(
                entry.debitAccountKey,
                entry.debitAccountName,
              ),
            ),
          );
        }
      }
      postings.sort((left, right) {
        final date = left.entry.occurredAt.compareTo(right.entry.occurredAt);
        if (date != 0) return date;
        final id = left.entry.id.compareTo(right.entry.id);
        return id != 0 ? id : left.sideOrder.compareTo(right.sideOrder);
      });
      for (final posting in postings) {
        balance = _round(balance + posting.debit - posting.credit);
        rows.add(
          FinancialLedgerGeneralLedgerRow(
            accountKey: account.key,
            accountName: account.name,
            accountType: account.type,
            date: posting.entry.occurredAt,
            reference: posting.entry.referenceNumber.isNotEmpty
                ? posting.entry.referenceNumber
                : posting.entry.referenceId,
            entryId: posting.entry.id,
            description: posting.entry.effectiveDescription,
            counterpartyAccount: posting.counterparty,
            debit: posting.debit,
            credit: posting.credit,
            runningBalance: balance,
            side: _balanceSide(balance),
            isOpening: false,
          ),
        );
      }
    }
    return List.unmodifiable(rows);
  }

  Future<void> copyAsTsv(List<FinancialLedgerEntry> entries) async {
    final rows = <String>[
      [
        'Date',
        'Type',
        'Description',
        'Debit account',
        'Credit account',
        'Amount JOD',
        'Customer',
        'Sales representative',
        'Payment method',
        'Reference',
        'Notes',
      ].join('\t'),
      for (final entry in entries)
        [
          DateFormat('yyyy-MM-dd HH:mm').format(entry.occurredAt),
          entry.type,
          entry.effectiveDescription,
          entry.debitAccountName,
          entry.creditAccountName,
          entry.amount.toStringAsFixed(3),
          entry.customerName,
          entry.salesRepName,
          entry.paymentMethod,
          entry.referenceNumber,
          entry.notes,
        ].map(_tsvCell).join('\t'),
    ];
    await Clipboard.setData(ClipboardData(text: rows.join('\n')));
  }

  void _buildSummary(
    Sheet sheet,
    FinancialLedgerExportData data,
    FinancialLedgerFilters filters,
  ) {
    sheet.isRTL = true;
    const columns = 6;
    _title(
      sheet,
      columns,
      'التقرير المحاسبي / Accounting Report',
      _filterDescription(filters),
    );
    final totalDebit = _round(
      data.entries.fold<double>(0, (sum, entry) => sum + entry.amount),
    );
    final totalCredit = _round(
      data.entries.fold<double>(0, (sum, entry) => sum + entry.amount),
    );
    final difference = _round(totalDebit - totalCredit);
    final balanced = difference.abs() < 0.001;
    final metadata = <(String, CellValue)>[
      ('Company / الشركة', TextCellValue(data.companyName)),
      ('Company ID / معرف الشركة', TextCellValue(data.companyId)),
      (
        'Date range / الفترة',
        TextCellValue('${_date(filters.fromDate)} — ${_date(filters.toDate)}'),
      ),
      ('Timezone / المنطقة الزمنية', TextCellValue('Asia/Amman')),
      (
        'Sort order / ترتيب القيود',
        TextCellValue('Oldest to newest / من الأقدم إلى الأحدث'),
      ),
      (
        'Generated / وقت الإنشاء',
        DateTimeCellValue.fromDateTime(data.generatedAt),
      ),
      (
        'Representative / المندوب',
        TextCellValue(
          data.representativeName.isEmpty
              ? 'All / الكل'
              : '${data.representativeName} (${filters.salesRepId})',
        ),
      ),
      ('Active filters / الفلاتر', TextCellValue(_activeFilters(filters))),
    ];
    var row = 3;
    for (final item in metadata) {
      _set(sheet, 0, row, TextCellValue(item.$1), _labelStyle);
      sheet.merge(
        CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: row),
        CellIndex.indexByColumnRow(columnIndex: columns - 1, rowIndex: row),
      );
      _set(
        sheet,
        1,
        row,
        item.$2,
        item.$2 is DateTimeCellValue ? _dateStyle : _bodyStyle,
      );
      row += 1;
    }
    row += 1;
    _sectionHeader(
      sheet,
      row,
      columns,
      'Validation & counts / التحقق والأعداد',
    );
    row += 1;
    const headers = [
      'Metric / البيان',
      'Value / القيمة',
      'Metric / البيان',
      'Value / القيمة',
      'Metric / البيان',
      'Value / القيمة',
    ];
    _headers(sheet, row, headers);
    row += 1;
    final metrics = <(String, CellValue)>[
      ('Journal entries / القيود', IntCellValue(data.entries.length)),
      (
        'Sales detail rows / تفاصيل المبيعات',
        IntCellValue(data.salesDetails.length),
      ),
      ('GL postings / ترحيلات الأستاذ', IntCellValue(data.entries.length * 2)),
      ('Total Debit JOD / المدين', DoubleCellValue(totalDebit)),
      ('Total Credit JOD / الدائن', DoubleCellValue(totalCredit)),
      ('Difference JOD / الفرق', DoubleCellValue(difference)),
      (
        'Validation / التوازن',
        TextCellValue(
          balanced ? 'Balanced / متوازن' : 'UNBALANCED / غير متوازن',
        ),
      ),
    ];
    for (var index = 0; index < metrics.length; index += 3) {
      for (var offset = 0; offset < 3; offset += 1) {
        if (index + offset >= metrics.length) break;
        final metric = metrics[index + offset];
        final column = offset * 2;
        _set(sheet, column, row, TextCellValue(metric.$1), _labelStyle);
        final isMoney = metric.$1.contains('JOD');
        final isValidation = metric.$1.startsWith('Validation');
        _set(
          sheet,
          column + 1,
          row,
          metric.$2,
          isValidation
              ? (balanced ? _validStyle : _invalidStyle)
              : isMoney
              ? _moneyStyle
              : _bodyStyle,
        );
      }
      row += 1;
    }
    row += 1;
    _sectionHeader(sheet, row, columns, 'Warnings / التحذيرات');
    row += 1;
    final warnings = <String>[
      if (!balanced)
        'Journal is unbalanced. Do not use this workbook for posting / '
            'القيود غير متوازنة ولا يجوز اعتماد التقرير.',
      ...data.warnings,
    ];
    if (warnings.isEmpty) {
      sheet.merge(
        CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row),
        CellIndex.indexByColumnRow(columnIndex: columns - 1, rowIndex: row),
      );
      _set(
        sheet,
        0,
        row,
        TextCellValue('No warnings / لا توجد تحذيرات'),
        _validStyle,
      );
    } else {
      for (final warning in warnings) {
        sheet.merge(
          CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row),
          CellIndex.indexByColumnRow(columnIndex: columns - 1, rowIndex: row),
        );
        _set(sheet, 0, row, TextCellValue('⚠ $warning'), _warningStyle);
        row += 1;
      }
    }
    for (var column = 0; column < columns; column += 1) {
      sheet.setColumnWidth(column, column.isEven ? 31 : 24);
    }
  }

  void _buildJournal(
    Sheet sheet,
    FinancialLedgerExportData data,
    FinancialLedgerFilters filters,
  ) {
    sheet.isRTL = true;
    const headers = [
      '#',
      'Entry ID / معرف القيد',
      'Date / التاريخ',
      'Type / النوع',
      'Component / المكون',
      'Reference / المرجع',
      'Reference ID / معرف المرجع',
      'Description / البيان',
      'Customer / العميل',
      'Customer ID / معرف العميل',
      'Representative / المندوب',
      'Rep ID / معرف المندوب',
      'Debit account / الحساب المدين',
      'Debit key / مفتاح المدين',
      'Debit JOD / مدين',
      'Credit account / الحساب الدائن',
      'Credit key / مفتاح الدائن',
      'Credit JOD / دائن',
      'Payment / الدفع',
      'Source / المصدر',
      'Source ID / معرف المصدر',
      'Notes / الملاحظات',
    ];
    _title(
      sheet,
      headers.length,
      'القيود اليومية / Journal Entries',
      _filterDescription(filters),
    );
    _headers(sheet, 3, headers);
    for (var index = 0; index < data.entries.length; index += 1) {
      final entry = data.entries[index];
      final row = index + 4;
      final values = <CellValue>[
        IntCellValue(index + 1),
        TextCellValue(entry.id),
        DateTimeCellValue.fromDateTime(entry.occurredAt),
        TextCellValue(entry.type),
        TextCellValue(entry.component),
        TextCellValue(entry.referenceNumber),
        TextCellValue(entry.referenceId),
        TextCellValue(entry.effectiveDescription),
        TextCellValue(entry.customerName),
        TextCellValue(entry.customerId),
        TextCellValue(entry.salesRepName),
        TextCellValue(entry.salesRepId),
        TextCellValue(
          _accountName(entry.debitAccountKey, entry.debitAccountName),
        ),
        TextCellValue(entry.debitAccountKey),
        DoubleCellValue(entry.amount),
        TextCellValue(
          _accountName(entry.creditAccountKey, entry.creditAccountName),
        ),
        TextCellValue(entry.creditAccountKey),
        DoubleCellValue(entry.amount),
        TextCellValue(entry.paymentMethod),
        TextCellValue(entry.sourceCollection),
        TextCellValue(entry.sourceId),
        TextCellValue(entry.notes),
      ];
      _writeRow(
        sheet,
        row,
        values,
        moneyColumns: const {14, 17},
        dateColumns: const {2},
      );
    }
    final totalRow = data.entries.length + 4;
    _set(sheet, 0, totalRow, TextCellValue('TOTAL / الإجمالي'), _totalStyle);
    sheet.merge(
      CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: totalRow),
      CellIndex.indexByColumnRow(columnIndex: 13, rowIndex: totalRow),
    );
    final total = _round(
      data.entries.fold<double>(0, (sum, row) => sum + row.amount),
    );
    _set(sheet, 14, totalRow, DoubleCellValue(total), _totalMoneyStyle);
    _set(sheet, 15, totalRow, TextCellValue(''), _totalStyle);
    _set(sheet, 16, totalRow, TextCellValue(''), _totalStyle);
    _set(sheet, 17, totalRow, DoubleCellValue(total), _totalMoneyStyle);
    for (var column = 18; column < headers.length; column += 1) {
      _set(sheet, column, totalRow, TextCellValue(''), _totalStyle);
    }
    _setWidths(sheet, const [
      8,
      30,
      20,
      18,
      20,
      18,
      27,
      38,
      25,
      25,
      24,
      25,
      28,
      31,
      16,
      28,
      31,
      16,
      16,
      18,
      27,
      36,
    ]);
  }

  void _buildSalesDetails(
    Sheet sheet,
    FinancialLedgerExportData data,
    FinancialLedgerFilters filters,
  ) {
    sheet.isRTL = true;
    const headers = [
      '#',
      'Movement / الحركة',
      'Date / التاريخ',
      'Invoice/Return No. / رقم المستند',
      'Original invoice / الفاتورة الأصلية',
      'Source ID / معرف المصدر',
      'Customer / العميل',
      'Customer ID / معرف العميل',
      'Representative / المندوب',
      'Rep ID / معرف المندوب',
      'Line ID / معرف السطر',
      'Item ID / معرف الصنف',
      'Item name / اسم الصنف',
      'Code/Model / الكود أو الموديل',
      'Unit / الوحدة',
      'Quantity / الكمية',
      'Unit price JOD / سعر الوحدة',
      'Discount JOD / الخصم',
      'Tax % / الضريبة %',
      'Tax JOD / الضريبة',
      'Line total JOD / إجمالي السطر',
      'Signed quantity / الكمية الموقعة',
      'Signed total JOD / الإجمالي الموقع',
    ];
    _title(
      sheet,
      headers.length,
      'تفاصيل المبيعات والمرتجعات / Sales & Returns Details',
      'Immutable confirmed document snapshots / لقطات المستندات المؤكدة والثابتة',
    );
    _headers(sheet, 3, headers);
    for (var index = 0; index < data.salesDetails.length; index += 1) {
      final line = data.salesDetails[index];
      final row = index + 4;
      final values = <CellValue>[
        IntCellValue(index + 1),
        TextCellValue(line.sourceType),
        DateTimeCellValue.fromDateTime(line.date),
        TextCellValue(line.documentNumber),
        TextCellValue(line.originalInvoiceNumber),
        TextCellValue(line.sourceId),
        TextCellValue(line.customerName),
        TextCellValue(line.customerId),
        TextCellValue(line.salesRepName),
        TextCellValue(line.salesRepId),
        TextCellValue(line.lineId),
        TextCellValue(line.itemId),
        TextCellValue(line.itemName),
        TextCellValue(line.itemCode),
        TextCellValue(line.unit),
        DoubleCellValue(line.quantity),
        DoubleCellValue(line.unitPrice),
        DoubleCellValue(line.discount),
        DoubleCellValue(line.taxPercent),
        DoubleCellValue(line.tax),
        DoubleCellValue(line.lineTotal),
        DoubleCellValue(line.signedQuantity),
        DoubleCellValue(line.signedTotal),
      ];
      _writeRow(
        sheet,
        row,
        values,
        moneyColumns: const {16, 17, 19, 20, 22},
        quantityColumns: const {15, 18, 21},
        dateColumns: const {2},
      );
    }
    final totalRow = data.salesDetails.length + 4;
    _set(sheet, 0, totalRow, TextCellValue('TOTAL / الإجمالي'), _totalStyle);
    sheet.merge(
      CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: totalRow),
      CellIndex.indexByColumnRow(columnIndex: 14, rowIndex: totalRow),
    );
    final sums = <int, double>{
      15: data.salesDetails.fold(0, (sum, line) => sum + line.quantity),
      17: data.salesDetails.fold(0, (sum, line) => sum + line.discount),
      19: data.salesDetails.fold(0, (sum, line) => sum + line.tax),
      20: data.salesDetails.fold(0, (sum, line) => sum + line.lineTotal),
      21: data.salesDetails.fold(0, (sum, line) => sum + line.signedQuantity),
      22: data.salesDetails.fold(0, (sum, line) => sum + line.signedTotal),
    };
    for (var column = 15; column < headers.length; column += 1) {
      final value = sums[column];
      _set(
        sheet,
        column,
        totalRow,
        value == null ? TextCellValue('') : DoubleCellValue(_round(value)),
        value == null ? _totalStyle : _totalMoneyStyle,
      );
    }
    _setWidths(sheet, const [
      8,
      20,
      20,
      23,
      22,
      27,
      25,
      25,
      24,
      25,
      27,
      25,
      32,
      22,
      14,
      14,
      17,
      16,
      13,
      15,
      18,
      17,
      19,
    ]);
  }

  void _buildGeneralLedger(
    Sheet sheet,
    FinancialLedgerExportData data,
    FinancialLedgerFilters filters,
  ) {
    sheet.isRTL = true;
    const headers = [
      'Account key / مفتاح الحساب',
      'Account / الحساب',
      'Type / النوع',
      'Date / التاريخ',
      'Reference / المرجع',
      'Entry ID / معرف القيد',
      'Description / البيان',
      'Counterparty / الحساب المقابل',
      'Debit JOD / مدين',
      'Credit JOD / دائن',
      'Running balance JOD / الرصيد',
      'Dr/Cr / طبيعة الرصيد',
    ];
    _title(
      sheet,
      headers.length,
      'الأستاذ العام / General Ledger',
      'Opening balances are strictly before ${_date(filters.fromInclusive)} / '
          'الأرصدة السابقة قبل بداية الفترة حصراً',
    );
    _headers(sheet, 3, headers);
    final rows = buildGeneralLedgerRows(data: data, filters: filters);
    for (var index = 0; index < rows.length; index += 1) {
      final item = rows[index];
      final row = index + 4;
      final values = <CellValue>[
        TextCellValue(item.accountKey),
        TextCellValue(item.accountName),
        TextCellValue(item.accountType),
        DateTimeCellValue.fromDateTime(item.date),
        TextCellValue(item.reference),
        TextCellValue(item.entryId),
        TextCellValue(item.description),
        TextCellValue(item.counterpartyAccount),
        DoubleCellValue(item.debit),
        DoubleCellValue(item.credit),
        DoubleCellValue(item.runningBalance),
        TextCellValue(item.side),
      ];
      _writeRow(
        sheet,
        row,
        values,
        moneyColumns: const {8, 9, 10},
        dateColumns: const {3},
        openingRow: item.isOpening,
      );
    }
    final periodRows = rows.where((row) => !row.isOpening);
    final totalRow = rows.length + 4;
    _set(
      sheet,
      0,
      totalRow,
      TextCellValue('PERIOD TOTAL / إجمالي الفترة'),
      _totalStyle,
    );
    sheet.merge(
      CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: totalRow),
      CellIndex.indexByColumnRow(columnIndex: 7, rowIndex: totalRow),
    );
    _set(
      sheet,
      8,
      totalRow,
      DoubleCellValue(
        _round(periodRows.fold<double>(0, (sum, row) => sum + row.debit)),
      ),
      _totalMoneyStyle,
    );
    _set(
      sheet,
      9,
      totalRow,
      DoubleCellValue(
        _round(periodRows.fold<double>(0, (sum, row) => sum + row.credit)),
      ),
      _totalMoneyStyle,
    );
    _set(sheet, 10, totalRow, TextCellValue(''), _totalStyle);
    _set(sheet, 11, totalRow, TextCellValue(''), _totalStyle);
    _setWidths(sheet, const [31, 29, 18, 20, 20, 30, 40, 29, 16, 16, 19, 17]);
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

  static void _title(Sheet sheet, int columns, String title, String subtitle) {
    sheet.merge(
      CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 0),
      CellIndex.indexByColumnRow(columnIndex: columns - 1, rowIndex: 0),
    );
    _set(sheet, 0, 0, TextCellValue(title), _titleStyle);
    _styleRow(sheet, 0, columns, _titleStyle);
    sheet.merge(
      CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 1),
      CellIndex.indexByColumnRow(columnIndex: columns - 1, rowIndex: 1),
    );
    _set(sheet, 0, 1, TextCellValue(subtitle), _subtitleStyle);
    _styleRow(sheet, 1, columns, _subtitleStyle);
  }

  static void _sectionHeader(Sheet sheet, int row, int columns, String text) {
    sheet.merge(
      CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row),
      CellIndex.indexByColumnRow(columnIndex: columns - 1, rowIndex: row),
    );
    _set(sheet, 0, row, TextCellValue(text), _sectionStyle);
    _styleRow(sheet, row, columns, _sectionStyle);
  }

  static void _headers(Sheet sheet, int row, List<String> headers) {
    for (var column = 0; column < headers.length; column += 1) {
      _set(sheet, column, row, TextCellValue(headers[column]), _headerStyle);
    }
  }

  static void _writeRow(
    Sheet sheet,
    int row,
    List<CellValue> values, {
    Set<int> moneyColumns = const {},
    Set<int> quantityColumns = const {},
    Set<int> dateColumns = const {},
    bool openingRow = false,
  }) {
    for (var column = 0; column < values.length; column += 1) {
      final isMoney = moneyColumns.contains(column);
      final isQuantity = quantityColumns.contains(column);
      final isDate = dateColumns.contains(column);
      final style = openingRow
          ? isMoney || isQuantity
                ? _openingMoneyStyle
                : isDate
                ? _openingDateStyle
                : _openingStyle
          : isMoney
          ? _moneyStyle
          : isQuantity
          ? _quantityStyle
          : isDate
          ? _dateStyle
          : _bodyStyle;
      _set(sheet, column, row, values[column], style);
    }
  }

  static void _setWidths(Sheet sheet, List<double> widths) {
    for (var column = 0; column < widths.length; column += 1) {
      sheet.setColumnWidth(column, widths[column]);
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

  static void _styleRow(Sheet sheet, int row, int columns, CellStyle style) {
    for (var column = 0; column < columns; column += 1) {
      sheet
              .cell(
                CellIndex.indexByColumnRow(columnIndex: column, rowIndex: row),
              )
              .cellStyle =
          style;
    }
  }

  static String _filterDescription(FinancialLedgerFilters filters) =>
      '${_date(filters.fromDate)} — ${_date(filters.toDate)} | '
      '${_activeFilters(filters)}';

  static String _activeFilters(FinancialLedgerFilters filters) {
    final values = <String>[
      if (filters.type.isNotEmpty) 'type=${filters.type}',
      if (filters.accountKey.isNotEmpty) 'account=${filters.accountKey}',
      if (filters.customerId.isNotEmpty) 'customer=${filters.customerId}',
      if (filters.salesRepId.isNotEmpty) 'representative=${filters.salesRepId}',
      if (filters.paymentMethod.isNotEmpty) 'payment=${filters.paymentMethod}',
      if (filters.search.trim().isNotEmpty) 'search=${filters.search.trim()}',
    ];
    return values.isEmpty
        ? 'All matching entries / جميع القيود'
        : values.join(' | ');
  }

  static String _date(DateTime value) => DateFormat('yyyy-MM-dd').format(value);

  static String _dateSuffix(FinancialLedgerFilters filters) =>
      '${DateFormat('yyyyMMdd').format(filters.fromDate)}-'
      '${DateFormat('yyyyMMdd').format(filters.toDate)}';

  static String _balanceSide(double balance) => balance > 0.0005
      ? 'Dr / مدين'
      : balance < -0.0005
      ? 'Cr / دائن'
      : '—';

  static String _accountName(String key, String fallback) => switch (key) {
    'company_cash' => 'Cash / الصندوق',
    'sales' => 'Sales / المبيعات',
    'expenses' => 'Expenses / المصاريف',
    'bank_unallocated' => 'Unallocated bank / بنك غير محدد',
    'check_clearing' => 'Checks receivable / شيكات برسم التحصيل',
    'cliq_clearing' => 'CliQ clearing / حساب CliQ',
    'opening_balance_equity' =>
      'Opening balance equity / حقوق الأرصدة الافتتاحية',
    _ => fallback.isEmpty ? key : fallback,
  };

  static String _tsvCell(String value) =>
      value.replaceAll('\t', ' ').replaceAll('\r', ' ').replaceAll('\n', ' ');

  static double _round(double value) => (value * 1000).roundToDouble() / 1000;

  static final _thinBorder = Border(
    borderStyle: BorderStyle.Thin,
    borderColorHex: ExcelColor.fromHexString('FFD1D9E2'),
  );
  static final _titleStyle = CellStyle(
    bold: true,
    fontSize: 17,
    fontColorHex: ExcelColor.white,
    backgroundColorHex: ExcelColor.fromHexString('FF123A52'),
    horizontalAlign: HorizontalAlign.Center,
    verticalAlign: VerticalAlign.Center,
  );
  static final _subtitleStyle = CellStyle(
    bold: true,
    fontColorHex: ExcelColor.fromHexString('FF123A52'),
    backgroundColorHex: ExcelColor.fromHexString('FFE8F0F5'),
    horizontalAlign: HorizontalAlign.Center,
    verticalAlign: VerticalAlign.Center,
  );
  static final _sectionStyle = CellStyle(
    bold: true,
    fontColorHex: ExcelColor.white,
    backgroundColorHex: ExcelColor.fromHexString('FF1E637C'),
    horizontalAlign: HorizontalAlign.Center,
    verticalAlign: VerticalAlign.Center,
  );
  static final _headerStyle = CellStyle(
    bold: true,
    fontColorHex: ExcelColor.white,
    backgroundColorHex: ExcelColor.fromHexString('FF246B84'),
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
  static final _labelStyle = _bodyStyle.copyWith(
    boldVal: true,
    fontColorHexVal: ExcelColor.fromHexString('FF123A52'),
    backgroundColorHexVal: ExcelColor.fromHexString('FFF1F5F8'),
  );
  static final _moneyStyle = _bodyStyle.copyWith(
    horizontalAlignVal: HorizontalAlign.Right,
    numberFormat: NumFormat.custom(formatCode: '#,##0.000;[Red](#,##0.000);-'),
  );
  static final _quantityStyle = _bodyStyle.copyWith(
    horizontalAlignVal: HorizontalAlign.Right,
    numberFormat: NumFormat.custom(formatCode: '#,##0.000;[Red](#,##0.000);-'),
  );
  static final _dateStyle = _bodyStyle.copyWith(
    numberFormat: NumFormat.custom(formatCode: 'yyyy-mm-dd hh:mm'),
  );
  static final _totalStyle = _bodyStyle.copyWith(
    boldVal: true,
    fontColorHexVal: ExcelColor.white,
    backgroundColorHexVal: ExcelColor.fromHexString('FF123A52'),
  );
  static final _totalMoneyStyle = _totalStyle.copyWith(
    horizontalAlignVal: HorizontalAlign.Right,
    numberFormat: NumFormat.custom(formatCode: '#,##0.000;[Red](#,##0.000);-'),
  );
  static final _openingStyle = _bodyStyle.copyWith(
    boldVal: true,
    fontColorHexVal: ExcelColor.fromHexString('FF704C00'),
    backgroundColorHexVal: ExcelColor.fromHexString('FFFFF3CD'),
  );
  static final _openingMoneyStyle = _openingStyle.copyWith(
    horizontalAlignVal: HorizontalAlign.Right,
    numberFormat: NumFormat.custom(formatCode: '#,##0.000;[Red](#,##0.000);-'),
  );
  static final _openingDateStyle = _openingStyle.copyWith(
    numberFormat: NumFormat.custom(formatCode: 'yyyy-mm-dd hh:mm'),
  );
  static final _validStyle = _bodyStyle.copyWith(
    boldVal: true,
    fontColorHexVal: ExcelColor.fromHexString('FF155724'),
    backgroundColorHexVal: ExcelColor.fromHexString('FFD4EDDA'),
  );
  static final _invalidStyle = _bodyStyle.copyWith(
    boldVal: true,
    fontColorHexVal: ExcelColor.fromHexString('FF721C24'),
    backgroundColorHexVal: ExcelColor.fromHexString('FFF8D7DA'),
  );
  static final _warningStyle = _bodyStyle.copyWith(
    fontColorHexVal: ExcelColor.fromHexString('FF704C00'),
    backgroundColorHexVal: ExcelColor.fromHexString('FFFFF3CD'),
  );
}

class FinancialLedgerGeneralLedgerRow {
  const FinancialLedgerGeneralLedgerRow({
    required this.accountKey,
    required this.accountName,
    required this.accountType,
    required this.date,
    required this.reference,
    required this.entryId,
    required this.description,
    required this.counterpartyAccount,
    required this.debit,
    required this.credit,
    required this.runningBalance,
    required this.side,
    required this.isOpening,
  });

  final String accountKey;
  final String accountName;
  final String accountType;
  final DateTime date;
  final String reference;
  final String entryId;
  final String description;
  final String counterpartyAccount;
  final double debit;
  final double credit;
  final double runningBalance;
  final String side;
  final bool isOpening;
}

class _LedgerAccount {
  const _LedgerAccount({
    required this.key,
    required this.type,
    required this.name,
  });

  final String key;
  final String type;
  final String name;
}

class _Posting {
  const _Posting({
    required this.entry,
    required this.sideOrder,
    required this.debit,
    required this.credit,
    required this.counterparty,
  });

  final FinancialLedgerEntry entry;
  final int sideOrder;
  final double debit;
  final double credit;
  final String counterparty;
}
