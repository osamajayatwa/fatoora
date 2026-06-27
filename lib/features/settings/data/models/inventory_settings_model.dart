class InventorySettingsModel {
  const InventorySettingsModel({
    required this.defaultWarehouseId,
    required this.allowNegativeStock,
    required this.lowStockAlertsEnabled,
    required this.defaultMinStock,
    required this.trackStockByDefault,
  });

  static const InventorySettingsModel defaults = InventorySettingsModel(
    defaultWarehouseId: 'default_warehouse',
    allowNegativeStock: false,
    lowStockAlertsEnabled: true,
    defaultMinStock: 0,
    trackStockByDefault: true,
  );

  final String defaultWarehouseId;
  final bool allowNegativeStock;
  final bool lowStockAlertsEnabled;
  final double defaultMinStock;
  final bool trackStockByDefault;

  factory InventorySettingsModel.fromMap(Map<String, dynamic>? data) {
    final map = data ?? const <String, dynamic>{};
    return InventorySettingsModel(
      defaultWarehouseId: _string(
        map['defaultWarehouseId'],
        defaults.defaultWarehouseId,
      ),
      allowNegativeStock: _bool(
        map['allowNegativeStock'],
        defaults.allowNegativeStock,
      ),
      lowStockAlertsEnabled: _bool(
        map['lowStockAlertsEnabled'],
        defaults.lowStockAlertsEnabled,
      ),
      defaultMinStock: _double(
        map['defaultMinStock'],
        defaults.defaultMinStock,
      ),
      trackStockByDefault: _bool(
        map['trackStockByDefault'],
        defaults.trackStockByDefault,
      ),
    );
  }

  Map<String, dynamic> toMap() => {
    'defaultWarehouseId': defaultWarehouseId.trim().isEmpty
        ? defaults.defaultWarehouseId
        : defaultWarehouseId.trim(),
    'allowNegativeStock': allowNegativeStock,
    'lowStockAlertsEnabled': lowStockAlertsEnabled,
    'defaultMinStock': defaultMinStock,
    'trackStockByDefault': trackStockByDefault,
  };

  InventorySettingsModel copyWith({
    String? defaultWarehouseId,
    bool? allowNegativeStock,
    bool? lowStockAlertsEnabled,
    double? defaultMinStock,
    bool? trackStockByDefault,
  }) {
    return InventorySettingsModel(
      defaultWarehouseId: defaultWarehouseId ?? this.defaultWarehouseId,
      allowNegativeStock: allowNegativeStock ?? this.allowNegativeStock,
      lowStockAlertsEnabled:
          lowStockAlertsEnabled ?? this.lowStockAlertsEnabled,
      defaultMinStock: defaultMinStock ?? this.defaultMinStock,
      trackStockByDefault: trackStockByDefault ?? this.trackStockByDefault,
    );
  }

  static String _string(Object? value, String fallback) {
    if (value is! String || value.trim().isEmpty) return fallback;
    return value.trim();
  }

  static double _double(Object? value, double fallback) {
    if (value is num && value.isFinite) return value.toDouble();
    if (value is String) return double.tryParse(value.trim()) ?? fallback;
    return fallback;
  }

  static bool _bool(Object? value, bool fallback) =>
      value is bool ? value : fallback;
}
