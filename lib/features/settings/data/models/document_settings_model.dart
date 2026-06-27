class DocumentSettingsModel {
  const DocumentSettingsModel({
    required this.invoicePrefix,
    required this.receiptPrefix,
    required this.quotationPrefix,
    required this.salesReturnPrefix,
    required this.defaultDueDays,
    required this.defaultTaxPercent,
    required this.allowDiscount,
    required this.allowSalesRepPriceEdit,
  });

  static const DocumentSettingsModel defaults = DocumentSettingsModel(
    invoicePrefix: 'INV',
    receiptPrefix: 'REC',
    quotationPrefix: 'QUO',
    salesReturnPrefix: 'RET',
    defaultDueDays: 0,
    defaultTaxPercent: 0,
    allowDiscount: true,
    allowSalesRepPriceEdit: true,
  );

  final String invoicePrefix;
  final String receiptPrefix;
  final String quotationPrefix;
  final String salesReturnPrefix;
  final int defaultDueDays;
  final double defaultTaxPercent;
  final bool allowDiscount;
  final bool allowSalesRepPriceEdit;

  factory DocumentSettingsModel.fromMap(Map<String, dynamic>? data) {
    final map = data ?? const <String, dynamic>{};
    return DocumentSettingsModel(
      invoicePrefix: _prefix(map['invoicePrefix'], defaults.invoicePrefix),
      receiptPrefix: _prefix(map['receiptPrefix'], defaults.receiptPrefix),
      quotationPrefix: _prefix(
        map['quotationPrefix'],
        defaults.quotationPrefix,
      ),
      salesReturnPrefix: _prefix(
        map['salesReturnPrefix'],
        defaults.salesReturnPrefix,
      ),
      defaultDueDays: _int(map['defaultDueDays'], defaults.defaultDueDays),
      defaultTaxPercent: _double(
        map['defaultTaxPercent'],
        defaults.defaultTaxPercent,
      ),
      allowDiscount: _bool(map['allowDiscount'], defaults.allowDiscount),
      allowSalesRepPriceEdit: _bool(
        map['allowSalesRepPriceEdit'],
        defaults.allowSalesRepPriceEdit,
      ),
    );
  }

  Map<String, dynamic> toMap() => {
    'invoicePrefix': _normalizePrefix(invoicePrefix, defaults.invoicePrefix),
    'receiptPrefix': _normalizePrefix(receiptPrefix, defaults.receiptPrefix),
    'quotationPrefix': _normalizePrefix(
      quotationPrefix,
      defaults.quotationPrefix,
    ),
    'salesReturnPrefix': _normalizePrefix(
      salesReturnPrefix,
      defaults.salesReturnPrefix,
    ),
    'defaultDueDays': defaultDueDays,
    'defaultTaxPercent': defaultTaxPercent,
    'allowDiscount': allowDiscount,
    'allowSalesRepPriceEdit': allowSalesRepPriceEdit,
  };

  DocumentSettingsModel copyWith({
    String? invoicePrefix,
    String? receiptPrefix,
    String? quotationPrefix,
    String? salesReturnPrefix,
    int? defaultDueDays,
    double? defaultTaxPercent,
    bool? allowDiscount,
    bool? allowSalesRepPriceEdit,
  }) {
    return DocumentSettingsModel(
      invoicePrefix: invoicePrefix ?? this.invoicePrefix,
      receiptPrefix: receiptPrefix ?? this.receiptPrefix,
      quotationPrefix: quotationPrefix ?? this.quotationPrefix,
      salesReturnPrefix: salesReturnPrefix ?? this.salesReturnPrefix,
      defaultDueDays: defaultDueDays ?? this.defaultDueDays,
      defaultTaxPercent: defaultTaxPercent ?? this.defaultTaxPercent,
      allowDiscount: allowDiscount ?? this.allowDiscount,
      allowSalesRepPriceEdit:
          allowSalesRepPriceEdit ?? this.allowSalesRepPriceEdit,
    );
  }

  static String _prefix(Object? value, String fallback) =>
      value is String ? _normalizePrefix(value, fallback) : fallback;

  static String _normalizePrefix(String value, String fallback) {
    final normalized = value.trim().toUpperCase();
    return normalized.isEmpty ? fallback : normalized;
  }

  static int _int(Object? value, int fallback) {
    if (value is num && value.isFinite) return value.toInt();
    if (value is String) return int.tryParse(value.trim()) ?? fallback;
    return fallback;
  }

  static double _double(Object? value, double fallback) {
    if (value is num && value.isFinite) return value.toDouble();
    if (value is String) return double.tryParse(value.trim()) ?? fallback;
    return fallback;
  }

  static bool _bool(Object? value, bool fallback) =>
      value is bool ? value : fallback;
}
