import 'package:fatoora/features/invoices/data/models/invoice_item_snapshot.dart';

class QuotationItemModel {
  const QuotationItemModel({
    required this.itemId,
    required this.itemName,
    required this.itemCode,
    required this.unit,
    required this.quantity,
    required this.unitPrice,
    required this.discount,
    required this.taxPercent,
    required this.subtotal,
    required this.taxAmount,
    required this.total,
  });

  final String itemId;
  final String itemName;
  final String itemCode;
  final String unit;
  final double quantity;
  final double unitPrice;
  final double discount;
  final double taxPercent;
  final double subtotal;
  final double taxAmount;
  final double total;

  factory QuotationItemModel.fromInvoiceItem(InvoiceItemSnapshot item) {
    return QuotationItemModel(
      itemId: item.itemId,
      itemName: item.itemName,
      itemCode: item.itemCode,
      unit: item.unit,
      quantity: item.quantity,
      unitPrice: item.unitPrice,
      discount: item.discount,
      taxPercent: item.taxPercent,
      subtotal: item.subtotal,
      taxAmount: item.taxAmount,
      total: item.total,
    );
  }

  factory QuotationItemModel.fromMap(Object? value) {
    final data = _asMap(value);
    return QuotationItemModel(
      itemId: _readString(data, 'itemId'),
      itemName: _readString(data, 'itemName'),
      itemCode: _readString(data, 'itemCode'),
      unit: _readString(data, 'unit'),
      quantity: _readDouble(data, 'quantity'),
      unitPrice: _readDouble(data, 'unitPrice'),
      discount: _readDouble(data, 'discount'),
      taxPercent: _readDouble(data, 'taxPercent'),
      subtotal: _readDouble(data, 'subtotal'),
      taxAmount: _readDouble(data, 'taxAmount'),
      total: _readDouble(data, 'total'),
    );
  }

  Map<String, dynamic> toMap() => {
    'itemId': itemId,
    'itemName': itemName,
    'itemCode': itemCode,
    'unit': unit,
    'quantity': quantity,
    'unitPrice': unitPrice,
    'discount': discount,
    'taxPercent': taxPercent,
    'subtotal': subtotal,
    'taxAmount': taxAmount,
    'total': total,
  };

  InvoiceItemSnapshot toInvoiceItem() {
    return InvoiceItemSnapshot(
      itemId: itemId,
      itemName: itemName,
      itemCode: itemCode,
      unit: unit,
      quantity: quantity,
      unitPrice: unitPrice,
      discount: discount,
      taxPercent: taxPercent,
      subtotal: subtotal,
      taxAmount: taxAmount,
      total: total,
    );
  }

  QuotationItemModel copyWith({
    String? itemId,
    String? itemName,
    String? itemCode,
    String? unit,
    double? quantity,
    double? unitPrice,
    double? discount,
    double? taxPercent,
    double? subtotal,
    double? taxAmount,
    double? total,
  }) {
    return QuotationItemModel(
      itemId: itemId ?? this.itemId,
      itemName: itemName ?? this.itemName,
      itemCode: itemCode ?? this.itemCode,
      unit: unit ?? this.unit,
      quantity: quantity ?? this.quantity,
      unitPrice: unitPrice ?? this.unitPrice,
      discount: discount ?? this.discount,
      taxPercent: taxPercent ?? this.taxPercent,
      subtotal: subtotal ?? this.subtotal,
      taxAmount: taxAmount ?? this.taxAmount,
      total: total ?? this.total,
    );
  }

  static Map<String, dynamic> _asMap(Object? value) {
    if (value is! Map) return const {};
    return value.map((key, value) => MapEntry(key.toString(), value));
  }

  static String _readString(Map<String, dynamic> data, String key) {
    final value = data[key];
    return value is String ? value.trim() : '';
  }

  static double _readDouble(Map<String, dynamic> data, String key) {
    final value = data[key];
    if (value is num && value.isFinite) return value.toDouble();
    if (value is String) return double.tryParse(value.trim()) ?? 0;
    return 0;
  }
}
