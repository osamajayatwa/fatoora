import 'package:cloud_firestore/cloud_firestore.dart';

class RepInventoryBalanceModel {
  const RepInventoryBalanceModel({
    required this.id,
    required this.companyId,
    required this.salesRepId,
    required this.itemId,
    required this.quantity,
    required this.modelSnapshot,
    required this.itemNameSnapshot,
    required this.unitSnapshot,
    required this.createdAt,
    required this.updatedAt,
    this.lastMovementId = '',
    this.lastReferenceType = '',
    this.lastReferenceId = '',
  });

  final String id;
  final String companyId;
  final String salesRepId;
  final String itemId;
  final double quantity;
  final String modelSnapshot;
  final String itemNameSnapshot;
  final String unitSnapshot;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String lastMovementId;
  final String lastReferenceType;
  final String lastReferenceId;

  static String documentId(String salesRepId, String itemId) =>
      '${salesRepId.trim()}_${itemId.trim()}';

  factory RepInventoryBalanceModel.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data() ?? const {};
    return RepInventoryBalanceModel(
      id: document.id,
      companyId: _string(data['companyId']),
      salesRepId: _string(data['salesRepId']),
      itemId: _string(data['itemId']),
      quantity: _number(data['quantity']),
      modelSnapshot: _string(data['modelSnapshot']),
      itemNameSnapshot: _string(data['itemNameSnapshot']),
      unitSnapshot: _string(data['unitSnapshot']),
      createdAt: _date(data['createdAt']) ?? DateTime.now(),
      updatedAt: _date(data['updatedAt']) ?? DateTime.now(),
      lastMovementId: _string(data['lastMovementId']),
      lastReferenceType: _string(data['lastReferenceType']),
      lastReferenceId: _string(data['lastReferenceId']),
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'companyId': companyId,
    'salesRepId': salesRepId,
    'itemId': itemId,
    'quantity': quantity,
    'modelSnapshot': modelSnapshot,
    'itemNameSnapshot': itemNameSnapshot,
    'unitSnapshot': unitSnapshot,
    'createdAt': Timestamp.fromDate(createdAt),
    'updatedAt': Timestamp.fromDate(updatedAt),
    'lastMovementId': lastMovementId,
    'lastReferenceType': lastReferenceType,
    'lastReferenceId': lastReferenceId,
  };

  RepInventoryBalanceModel copyWith({
    double? quantity,
    String? modelSnapshot,
    String? itemNameSnapshot,
    String? unitSnapshot,
    DateTime? updatedAt,
    String? lastMovementId,
    String? lastReferenceType,
    String? lastReferenceId,
  }) {
    return RepInventoryBalanceModel(
      id: id,
      companyId: companyId,
      salesRepId: salesRepId,
      itemId: itemId,
      quantity: quantity ?? this.quantity,
      modelSnapshot: modelSnapshot ?? this.modelSnapshot,
      itemNameSnapshot: itemNameSnapshot ?? this.itemNameSnapshot,
      unitSnapshot: unitSnapshot ?? this.unitSnapshot,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      lastMovementId: lastMovementId ?? this.lastMovementId,
      lastReferenceType: lastReferenceType ?? this.lastReferenceType,
      lastReferenceId: lastReferenceId ?? this.lastReferenceId,
    );
  }
}

String _string(Object? value) => value is String ? value.trim() : '';
double _number(Object? value) =>
    value is num && value.isFinite ? value.toDouble() : 0;
DateTime? _date(Object? value) {
  if (value is Timestamp) return value.toDate();
  if (value is DateTime) return value;
  if (value is String) return DateTime.tryParse(value);
  return null;
}
