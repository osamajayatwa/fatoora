import 'package:cloud_firestore/cloud_firestore.dart';

class ItemModel {
  static const String defaultWarehouseId = 'default_warehouse';

  const ItemModel({
    required this.id,
    required this.code,
    required this.name,
    required this.description,
    required this.unit,
    required this.price,
    required this.taxRate,
    required this.active,
    required this.deleted,
    required this.createdAt,
    required this.updatedAt,
    required this.createdBy,
    required this.currentStock,
    required this.openingStock,
    required this.minStock,
    required this.trackStock,
    required this.costPrice,
    this.barcode,
    this.category,
    required this.warehouseId,
    this.inventoryUpdatedAt,
  });

  final String id;
  final String code;
  final String name;
  final String description;
  final String unit;
  final double price;
  final double taxRate;
  final bool active;
  final bool deleted;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String createdBy;
  final double currentStock;
  final double openingStock;
  final double minStock;
  final bool trackStock;
  final double costPrice;
  final String? barcode;
  final String? category;
  final String warehouseId;
  final DateTime? inventoryUpdatedAt;

  bool get isOutOfStock => trackStock && currentStock <= 0;
  bool get isLowStock =>
      trackStock && currentStock > 0 && currentStock <= minStock;

  factory ItemModel.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data();
    if (data == null) {
      throw const FormatException('Item document has no data.');
    }

    final id = _requiredString(data, 'id');
    if (id != document.id) {
      throw const FormatException('Item id does not match its document id.');
    }

    return ItemModel(
      id: document.id,
      code: _requiredString(data, 'code'),
      name: _requiredString(data, 'name'),
      description: _requiredString(data, 'description'),
      unit: _requiredString(data, 'unit'),
      price: _requiredDouble(data, 'price'),
      taxRate: _requiredDouble(data, 'taxRate'),
      active: _requiredBool(data, 'active'),
      deleted: _requiredBool(data, 'deleted'),
      createdAt: _requiredDate(data, 'createdAt'),
      updatedAt: _requiredDate(data, 'updatedAt'),
      createdBy: _requiredString(data, 'createdBy'),
      currentStock: _readDouble(data, 'currentStock'),
      openingStock: _readDouble(data, 'openingStock'),
      minStock: _readDouble(data, 'minStock'),
      trackStock: _readBool(data, 'trackStock', fallback: true),
      costPrice: _readDouble(data, 'costPrice'),
      barcode: _readOptionalString(data, 'barcode'),
      category: _readOptionalString(data, 'category'),
      warehouseId:
          _readOptionalString(data, 'warehouseId') ?? defaultWarehouseId,
      inventoryUpdatedAt: _readDate(data, 'inventoryUpdatedAt'),
    );
  }

  Map<String, dynamic> toFirestore() => {
    'code': code.trim(),
    'name': name.trim(),
    'description': description.trim(),
    'unit': unit.trim(),
    'price': price,
    'taxRate': taxRate,
    'active': active,
    'deleted': deleted,
    'createdAt': Timestamp.fromDate(createdAt),
    'updatedAt': Timestamp.fromDate(updatedAt),
    'createdBy': createdBy,
    'currentStock': currentStock,
    'openingStock': openingStock,
    'minStock': minStock,
    'trackStock': trackStock,
    'costPrice': costPrice,
    'barcode': barcode,
    'category': category,
    'warehouseId': warehouseId.trim().isEmpty
        ? defaultWarehouseId
        : warehouseId.trim(),
    'inventoryUpdatedAt': inventoryUpdatedAt == null
        ? null
        : Timestamp.fromDate(inventoryUpdatedAt!),
  };

  ItemModel copyWith({
    String? id,
    String? code,
    String? name,
    String? description,
    String? unit,
    double? price,
    double? taxRate,
    bool? active,
    bool? deleted,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? createdBy,
    double? currentStock,
    double? openingStock,
    double? minStock,
    bool? trackStock,
    double? costPrice,
    String? barcode,
    bool clearBarcode = false,
    String? category,
    bool clearCategory = false,
    String? warehouseId,
    DateTime? inventoryUpdatedAt,
    bool clearInventoryUpdatedAt = false,
  }) => ItemModel(
    id: id ?? this.id,
    code: code ?? this.code,
    name: name ?? this.name,
    description: description ?? this.description,
    unit: unit ?? this.unit,
    price: price ?? this.price,
    taxRate: taxRate ?? this.taxRate,
    active: active ?? this.active,
    deleted: deleted ?? this.deleted,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    createdBy: createdBy ?? this.createdBy,
    currentStock: currentStock ?? this.currentStock,
    openingStock: openingStock ?? this.openingStock,
    minStock: minStock ?? this.minStock,
    trackStock: trackStock ?? this.trackStock,
    costPrice: costPrice ?? this.costPrice,
    barcode: clearBarcode ? null : barcode ?? this.barcode,
    category: clearCategory ? null : category ?? this.category,
    warehouseId: warehouseId ?? this.warehouseId,
    inventoryUpdatedAt: clearInventoryUpdatedAt
        ? null
        : inventoryUpdatedAt ?? this.inventoryUpdatedAt,
  );

  static String _requiredString(Map<String, dynamic> data, String key) {
    final value = data[key];
    if (value is! String || value.trim().isEmpty) {
      throw FormatException('Item field "$key" is invalid.');
    }
    return value.trim();
  }

  static double _requiredDouble(Map<String, dynamic> data, String key) {
    final value = data[key];
    if (value is! num || !value.isFinite) {
      throw FormatException('Item field "$key" is invalid.');
    }
    return value.toDouble();
  }

  static double _readDouble(Map<String, dynamic> data, String key) {
    final value = data[key];
    if (value is num && value.isFinite) return value.toDouble();
    if (value is String) return double.tryParse(value.trim()) ?? 0;
    return 0;
  }

  static bool _requiredBool(Map<String, dynamic> data, String key) {
    final value = data[key];
    if (value is! bool) {
      throw FormatException('Item field "$key" is invalid.');
    }
    return value;
  }

  static bool _readBool(
    Map<String, dynamic> data,
    String key, {
    required bool fallback,
  }) {
    final value = data[key];
    return value is bool ? value : fallback;
  }

  static DateTime _requiredDate(Map<String, dynamic> data, String key) {
    final value = data[key];
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    throw FormatException('Item field "$key" is invalid.');
  }

  static DateTime? _readDate(Map<String, dynamic> data, String key) {
    final value = data[key];
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  static String? _readOptionalString(Map<String, dynamic> data, String key) {
    final value = data[key];
    if (value is! String) return null;
    final text = value.trim();
    return text.isEmpty ? null : text;
  }
}
