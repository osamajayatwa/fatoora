import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fatoora/features/financial_ledger/data/models/financial_ledger_entry.dart';

class FinancialLedgerExportData {
  const FinancialLedgerExportData({
    required this.companyId,
    required this.companyName,
    required this.representativeName,
    required this.generatedAt,
    required this.entries,
    required this.salesDetails,
    required this.openingBalances,
    required this.warnings,
  });

  final String companyId;
  final String companyName;
  final String representativeName;
  final DateTime generatedAt;
  final List<FinancialLedgerEntry> entries;
  final List<FinancialLedgerSalesDetail> salesDetails;
  final Map<String, FinancialLedgerOpeningBalance> openingBalances;
  final List<String> warnings;
}

class FinancialLedgerOpeningBalance {
  const FinancialLedgerOpeningBalance({
    required this.accountKey,
    required this.accountType,
    required this.accountName,
    required this.debit,
    required this.credit,
    required this.balance,
  });

  final String accountKey;
  final String accountType;
  final String accountName;
  final double debit;
  final double credit;
  final double balance;

  factory FinancialLedgerOpeningBalance.fromMap(Map<String, dynamic> data) {
    final accountKey = _string(data['accountKey']);
    if (accountKey.isEmpty) {
      throw const FormatException('Opening balance account key is invalid.');
    }
    return FinancialLedgerOpeningBalance(
      accountKey: accountKey,
      accountType: _string(data['accountType']),
      accountName: _string(data['accountName']),
      debit: _number(data['debit']),
      credit: _number(data['credit']),
      balance: _number(data['balance']),
    );
  }
}

class FinancialLedgerSalesDetail {
  const FinancialLedgerSalesDetail({
    required this.sourceType,
    required this.sourceId,
    required this.documentNumber,
    required this.originalInvoiceNumber,
    required this.date,
    required this.customerId,
    required this.customerName,
    required this.salesRepId,
    required this.salesRepName,
    required this.lineId,
    required this.lineType,
    required this.description,
    required this.itemId,
    required this.itemName,
    required this.itemCode,
    required this.unit,
    required this.quantity,
    required this.unitPrice,
    required this.discount,
    required this.taxPercent,
    required this.tax,
    required this.lineTotal,
    required this.signedQuantity,
    required this.signedTotal,
  });

  final String sourceType;
  final String sourceId;
  final String documentNumber;
  final String originalInvoiceNumber;
  final DateTime date;
  final String customerId;
  final String customerName;
  final String salesRepId;
  final String salesRepName;
  final String lineId;
  final String lineType;
  final String description;
  final String? itemId;
  final String itemName;
  final String itemCode;
  final String unit;
  final double quantity;
  final double unitPrice;
  final double discount;
  final double taxPercent;
  final double tax;
  final double lineTotal;
  final double signedQuantity;
  final double signedTotal;
}

class FinancialLedgerSalesAssembly {
  const FinancialLedgerSalesAssembly({
    required this.details,
    required this.warnings,
  });

  final List<FinancialLedgerSalesDetail> details;
  final List<String> warnings;
}

FinancialLedgerSalesAssembly assembleFinancialLedgerSalesDetails({
  required List<FinancialLedgerEntry> entries,
  required Map<String, Map<String, dynamic>> invoices,
  required Map<String, Map<String, dynamic>> salesReturns,
}) {
  final details = <FinancialLedgerSalesDetail>[];
  final warnings = <String>[];
  final includedSources = <String>{};
  for (final entry in entries) {
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
    final isInvoice =
        entry.type == 'invoice_sale' && sourceCollection == 'invoices';
    final isReturn =
        (entry.type == 'sales_return' || entry.type == 'refund') &&
        sourceCollection == 'sales_returns';
    if (sourceId.isEmpty || (!isInvoice && !isReturn)) continue;
    if (!includedSources.add('$sourceCollection/$sourceId')) continue;
    final source = isInvoice ? invoices[sourceId] : salesReturns[sourceId];
    if (source == null) {
      warnings.add(
        'Missing immutable source snapshot / لقطة المصدر غير موجودة: '
        '$sourceCollection/$sourceId',
      );
      continue;
    }
    final status = _string(source[isInvoice ? 'invoiceStatus' : 'status']);
    final validStatus = isInvoice
        ? status == 'confirmed' || status == 'accepted'
        : status == 'confirmed';
    if (source['financialPosted'] != true || !validStatus) {
      warnings.add(
        'Unconfirmed source omitted / تم استبعاد مصدر غير مؤكد: '
        '$sourceCollection/$sourceId',
      );
      continue;
    }
    final rawItems = source['items'];
    if (rawItems is! List || rawItems.isEmpty) {
      warnings.add(
        'Legacy source has no immutable items / مصدر قديم بلا تفاصيل ثابتة: '
        '$sourceCollection/$sourceId',
      );
      continue;
    }
    final customerSnapshot = _map(source['customerSnapshot']);
    final customerId = _string(source['customerId']).isNotEmpty
        ? _string(source['customerId'])
        : entry.customerId;
    final customerName = _string(customerSnapshot['name']).isNotEmpty
        ? _string(customerSnapshot['name'])
        : _string(source['customerName']).isNotEmpty
        ? _string(source['customerName'])
        : entry.customerName;
    final salesRepId = _string(source['salesRepId']).isNotEmpty
        ? _string(source['salesRepId'])
        : entry.salesRepId;
    final salesRepName = _string(source['salesRepName']).isNotEmpty
        ? _string(source['salesRepName'])
        : entry.salesRepName;
    final documentNumber = _string(
      source[isInvoice ? 'invoiceNumber' : 'returnNumber'],
    );
    final originalInvoiceNumber = isInvoice
        ? documentNumber
        : _string(source['originalInvoiceNumber']);
    final date = _date(
      source[isInvoice ? 'invoiceDate' : 'returnDate'],
      entry.occurredAt,
    );
    var sourceTotal = 0.0;
    for (var index = 0; index < rawItems.length; index += 1) {
      final item = _map(rawItems[index]);
      final rawItemId = _string(item['itemId']);
      final explicitLineType = _string(item['lineType']);
      final lineType = explicitLineType.isNotEmpty
          ? explicitLineType
          : rawItemId.isEmpty || rawItemId.startsWith('manual-')
          ? 'custom'
          : 'catalog';
      final itemName = _string(item['itemName']);
      final quantity = _number(
        item[isInvoice ? 'quantity' : 'returnedQuantity'],
      );
      final lineTotal = _number(item['total']);
      final sign = isInvoice ? 1.0 : -1.0;
      sourceTotal = _round(sourceTotal + lineTotal);
      if (itemName.isEmpty || quantity <= 0 || lineTotal < 0) {
        warnings.add(
          'Incomplete legacy item snapshot / تفاصيل صنف قديمة غير مكتملة: '
          '$sourceCollection/$sourceId item ${index + 1}',
        );
      }
      details.add(
        FinancialLedgerSalesDetail(
          sourceType: isInvoice ? 'Invoice / فاتورة' : 'Return / مرتجع',
          sourceId: sourceId,
          documentNumber: documentNumber.isEmpty ? sourceId : documentNumber,
          originalInvoiceNumber: originalInvoiceNumber,
          date: date,
          customerId: customerId,
          customerName: customerName,
          salesRepId: salesRepId,
          salesRepName: salesRepName,
          lineId: _string(item['originalInvoiceItemId']).isNotEmpty
              ? _string(item['originalInvoiceItemId'])
              : '$sourceId:$index',
          lineType: lineType,
          description: _string(item['description']),
          itemId: rawItemId.isEmpty ? null : rawItemId,
          itemName: itemName,
          itemCode: _string(item['itemCode']),
          unit: _string(item['unit']),
          quantity: quantity,
          unitPrice: _number(item['unitPrice']),
          discount: _number(item[isInvoice ? 'discount' : 'discountAmount']),
          taxPercent: _number(item['taxPercent']),
          tax: _number(item['taxAmount']),
          lineTotal: lineTotal,
          signedQuantity: _round(quantity * sign),
          signedTotal: _round(lineTotal * sign),
        ),
      );
    }
    final expectedTotal = _number(source['grandTotal']);
    if ((sourceTotal - expectedTotal).abs() > 0.001) {
      warnings.add(
        'Item snapshot total mismatch / مجموع التفاصيل لا يطابق الإجمالي: '
        '$sourceCollection/$sourceId '
        '(${sourceTotal.toStringAsFixed(3)} vs '
        '${expectedTotal.toStringAsFixed(3)})',
      );
    }
  }
  details.sort((left, right) {
    final date = left.date.compareTo(right.date);
    if (date != 0) return date;
    final source = left.sourceId.compareTo(right.sourceId);
    return source != 0 ? source : left.lineId.compareTo(right.lineId);
  });
  return FinancialLedgerSalesAssembly(
    details: List.unmodifiable(details),
    warnings: List.unmodifiable(warnings),
  );
}

Map<String, dynamic> _map(Object? value) {
  if (value is! Map) return const <String, dynamic>{};
  return value.map((key, value) => MapEntry(key.toString(), value));
}

String _string(Object? value) => value is String ? value.trim() : '';

double _number(Object? value) {
  if (value is num && value.isFinite) return value.toDouble();
  if (value is String) return double.tryParse(value.trim()) ?? 0;
  return 0;
}

DateTime _date(Object? value, DateTime fallback) {
  if (value is Timestamp) return value.toDate();
  if (value is DateTime) return value;
  if (value is num && value.isFinite) {
    return DateTime.fromMillisecondsSinceEpoch(value.toInt());
  }
  if (value is String) return DateTime.tryParse(value) ?? fallback;
  return fallback;
}

double _round(double value) => (value * 1000).roundToDouble() / 1000;
