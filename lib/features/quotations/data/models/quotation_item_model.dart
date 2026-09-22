import 'package:fatoora/features/invoices/data/models/invoice_item_snapshot.dart';

class QuotationItemModel {
  const QuotationItemModel({
    this.lineId = '',
    this.lineType = InvoiceLineType.catalog,
    this.isLegacyManual = false,
    required this.itemId,
    required this.itemName,
    this.description = '',
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

  final String lineId;
  final InvoiceLineType lineType;
  final bool isLegacyManual;
  final String? itemId;
  final String itemName;
  final String description;
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
      lineId: item.lineId,
      lineType: item.lineType,
      isLegacyManual: item.isLegacyManual,
      itemId: item.itemId,
      itemName: item.itemName,
      description: item.description,
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
    final invoiceItem = InvoiceItemSnapshot.fromMap(data);
    return QuotationItemModel(
      lineId: invoiceItem.lineId,
      lineType: invoiceItem.lineType,
      isLegacyManual: invoiceItem.isLegacyManual,
      itemId: invoiceItem.itemId,
      itemName: invoiceItem.itemName,
      description: invoiceItem.description,
      itemCode: invoiceItem.itemCode,
      unit: invoiceItem.unit,
      quantity: invoiceItem.quantity,
      unitPrice: invoiceItem.unitPrice,
      discount: invoiceItem.discount,
      taxPercent: invoiceItem.taxPercent,
      subtotal: invoiceItem.subtotal,
      taxAmount: invoiceItem.taxAmount,
      total: invoiceItem.total,
    );
  }

  Map<String, dynamic> toMap() => {
    'lineId': lineId,
    if (!isLegacyManual) 'lineType': lineType.value,
    'itemId': itemId,
    'itemName': itemName,
    'description': description,
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
      lineId: lineId,
      lineType: lineType,
      isLegacyManual: isLegacyManual,
      itemId: itemId,
      itemName: itemName,
      description: description,
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
    String? lineId,
    InvoiceLineType? lineType,
    bool? isLegacyManual,
    String? itemId,
    bool clearItemId = false,
    String? itemName,
    String? description,
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
      lineId: lineId ?? this.lineId,
      lineType: lineType ?? this.lineType,
      isLegacyManual: isLegacyManual ?? this.isLegacyManual,
      itemId: clearItemId ? null : itemId ?? this.itemId,
      itemName: itemName ?? this.itemName,
      description: description ?? this.description,
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
}
