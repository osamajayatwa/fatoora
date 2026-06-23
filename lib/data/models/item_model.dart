import 'package:cloud_firestore/cloud_firestore.dart';

class ItemModel {
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

  static bool _requiredBool(Map<String, dynamic> data, String key) {
    final value = data[key];
    if (value is! bool) {
      throw FormatException('Item field "$key" is invalid.');
    }
    return value;
  }

  static DateTime _requiredDate(Map<String, dynamic> data, String key) {
    final value = data[key];
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    throw FormatException('Item field "$key" is invalid.');
  }
}
