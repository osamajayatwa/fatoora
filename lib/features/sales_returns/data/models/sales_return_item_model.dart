class SalesReturnItemModel {
  const SalesReturnItemModel({
    required this.itemId,
    required this.itemName,
    required this.itemCode,
    required this.unit,
    required this.returnedQuantity,
    required this.unitPrice,
    required this.taxPercent,
    required this.subtotal,
    required this.taxAmount,
    required this.total,
    required this.originalInvoiceItemId,
  });

  final String itemId;
  final String itemName;
  final String itemCode;
  final String unit;
  final double returnedQuantity;
  final double unitPrice;
  final double taxPercent;
  final double subtotal;
  final double taxAmount;
  final double total;
  final String originalInvoiceItemId;

  factory SalesReturnItemModel.fromMap(Object? value) {
    final data = _asMap(value);
    return SalesReturnItemModel(
      itemId: _readString(data, 'itemId'),
      itemName: _readString(data, 'itemName'),
      itemCode: _readString(data, 'itemCode'),
      unit: _readString(data, 'unit'),
      returnedQuantity: _readDouble(data, 'returnedQuantity'),
      unitPrice: _readDouble(data, 'unitPrice'),
      taxPercent: _readDouble(data, 'taxPercent'),
      subtotal: _readDouble(data, 'subtotal'),
      taxAmount: _readDouble(data, 'taxAmount'),
      total: _readDouble(data, 'total'),
      originalInvoiceItemId: _readString(data, 'originalInvoiceItemId'),
    );
  }

  Map<String, dynamic> toMap() => {
    'itemId': itemId,
    'itemName': itemName,
    'itemCode': itemCode,
    'unit': unit,
    'returnedQuantity': returnedQuantity,
    'unitPrice': unitPrice,
    'taxPercent': taxPercent,
    'subtotal': subtotal,
    'taxAmount': taxAmount,
    'total': total,
    'originalInvoiceItemId': originalInvoiceItemId,
  };

  SalesReturnItemModel copyWith({
    String? itemId,
    String? itemName,
    String? itemCode,
    String? unit,
    double? returnedQuantity,
    double? unitPrice,
    double? taxPercent,
    double? subtotal,
    double? taxAmount,
    double? total,
    String? originalInvoiceItemId,
  }) {
    return SalesReturnItemModel(
      itemId: itemId ?? this.itemId,
      itemName: itemName ?? this.itemName,
      itemCode: itemCode ?? this.itemCode,
      unit: unit ?? this.unit,
      returnedQuantity: returnedQuantity ?? this.returnedQuantity,
      unitPrice: unitPrice ?? this.unitPrice,
      taxPercent: taxPercent ?? this.taxPercent,
      subtotal: subtotal ?? this.subtotal,
      taxAmount: taxAmount ?? this.taxAmount,
      total: total ?? this.total,
      originalInvoiceItemId:
          originalInvoiceItemId ?? this.originalInvoiceItemId,
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
