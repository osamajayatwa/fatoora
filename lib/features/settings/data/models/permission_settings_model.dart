class PermissionSettingsModel {
  const PermissionSettingsModel({
    required this.allowSalesRepCreateCustomers,
    required this.allowSalesRepCreateReceipts,
    required this.allowSalesRepCreateReturns,
    required this.allowSalesRepCreateQuotations,
    required this.allowSalesRepPriceEdit,
    required this.allowSalesRepDiscount,
  });

  static const PermissionSettingsModel defaults = PermissionSettingsModel(
    allowSalesRepCreateCustomers: true,
    allowSalesRepCreateReceipts: true,
    allowSalesRepCreateReturns: true,
    allowSalesRepCreateQuotations: true,
    allowSalesRepPriceEdit: true,
    allowSalesRepDiscount: true,
  );

  final bool allowSalesRepCreateCustomers;
  final bool allowSalesRepCreateReceipts;
  final bool allowSalesRepCreateReturns;
  final bool allowSalesRepCreateQuotations;
  final bool allowSalesRepPriceEdit;
  final bool allowSalesRepDiscount;

  factory PermissionSettingsModel.fromMap(Map<String, dynamic>? data) {
    final map = data ?? const <String, dynamic>{};
    return PermissionSettingsModel(
      allowSalesRepCreateCustomers: _bool(
        map['allowSalesRepCreateCustomers'],
        defaults.allowSalesRepCreateCustomers,
      ),
      allowSalesRepCreateReceipts: _bool(
        map['allowSalesRepCreateReceipts'],
        defaults.allowSalesRepCreateReceipts,
      ),
      allowSalesRepCreateReturns: _bool(
        map['allowSalesRepCreateReturns'],
        defaults.allowSalesRepCreateReturns,
      ),
      allowSalesRepCreateQuotations: _bool(
        map['allowSalesRepCreateQuotations'],
        defaults.allowSalesRepCreateQuotations,
      ),
      allowSalesRepPriceEdit: _bool(
        map['allowSalesRepPriceEdit'],
        defaults.allowSalesRepPriceEdit,
      ),
      allowSalesRepDiscount: _bool(
        map['allowSalesRepDiscount'],
        defaults.allowSalesRepDiscount,
      ),
    );
  }

  Map<String, dynamic> toMap() => {
    'allowSalesRepCreateCustomers': allowSalesRepCreateCustomers,
    'allowSalesRepCreateReceipts': allowSalesRepCreateReceipts,
    'allowSalesRepCreateReturns': allowSalesRepCreateReturns,
    'allowSalesRepCreateQuotations': allowSalesRepCreateQuotations,
    'allowSalesRepPriceEdit': allowSalesRepPriceEdit,
    'allowSalesRepDiscount': allowSalesRepDiscount,
  };

  PermissionSettingsModel copyWith({
    bool? allowSalesRepCreateCustomers,
    bool? allowSalesRepCreateReceipts,
    bool? allowSalesRepCreateReturns,
    bool? allowSalesRepCreateQuotations,
    bool? allowSalesRepPriceEdit,
    bool? allowSalesRepDiscount,
  }) {
    return PermissionSettingsModel(
      allowSalesRepCreateCustomers:
          allowSalesRepCreateCustomers ?? this.allowSalesRepCreateCustomers,
      allowSalesRepCreateReceipts:
          allowSalesRepCreateReceipts ?? this.allowSalesRepCreateReceipts,
      allowSalesRepCreateReturns:
          allowSalesRepCreateReturns ?? this.allowSalesRepCreateReturns,
      allowSalesRepCreateQuotations:
          allowSalesRepCreateQuotations ?? this.allowSalesRepCreateQuotations,
      allowSalesRepPriceEdit:
          allowSalesRepPriceEdit ?? this.allowSalesRepPriceEdit,
      allowSalesRepDiscount:
          allowSalesRepDiscount ?? this.allowSalesRepDiscount,
    );
  }

  static bool _bool(Object? value, bool fallback) =>
      value is bool ? value : fallback;
}
