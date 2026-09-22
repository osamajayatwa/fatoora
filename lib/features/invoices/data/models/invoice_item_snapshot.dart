enum InvoiceLineType { catalog, custom }

extension InvoiceLineTypeValue on InvoiceLineType {
  String get value => name;
}

class InvoiceItemSnapshot {
  const InvoiceItemSnapshot({
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

  factory InvoiceItemSnapshot.fromMap(Object? value) {
    final data = _asMap(value);
    final itemId = _readOptionalString(data, 'itemId');
    final lineType = _readLineType(data['lineType'], itemId);
    final rawLineType = _readString(data, 'lineType');
    return InvoiceItemSnapshot(
      lineId: _readString(data, 'lineId'),
      lineType: lineType,
      isLegacyManual:
          rawLineType.isEmpty &&
          (itemId == null || itemId.startsWith('manual-')),
      itemId: lineType == InvoiceLineType.custom ? itemId : itemId,
      itemName: _readString(data, 'itemName'),
      description: _readString(data, 'description'),
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

  InvoiceItemSnapshot copyWith({
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
    return InvoiceItemSnapshot(
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

  static String _readString(Map<String, dynamic> data, String key) {
    final value = data[key];
    return value is String ? value.trim() : '';
  }

  static String? _readOptionalString(Map<String, dynamic> data, String key) {
    final value = _readString(data, key);
    return value.isEmpty ? null : value;
  }

  static InvoiceLineType _readLineType(Object? value, String? itemId) {
    final normalized = value?.toString().trim().toLowerCase();
    if (normalized == InvoiceLineType.custom.value) {
      return InvoiceLineType.custom;
    }
    if (normalized == InvoiceLineType.catalog.value) {
      return InvoiceLineType.catalog;
    }
    return itemId == null || itemId.startsWith('manual-')
        ? InvoiceLineType.custom
        : InvoiceLineType.catalog;
  }

  static double _readDouble(Map<String, dynamic> data, String key) {
    final value = data[key];
    if (value is num && value.isFinite) return value.toDouble();
    if (value is String) return double.tryParse(value.trim()) ?? 0;
    return 0;
  }
}
