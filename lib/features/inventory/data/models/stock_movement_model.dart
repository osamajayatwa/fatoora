import 'package:cloud_firestore/cloud_firestore.dart';

class StockMovementModel {
  const StockMovementModel({
    required this.id,
    required this.companyId,
    required this.warehouseId,
    required this.itemId,
    required this.itemName,
    required this.itemCode,
    required this.movementType,
    required this.direction,
    required this.quantity,
    required this.quantityBefore,
    required this.quantityAfter,
    required this.referenceType,
    required this.referenceId,
    required this.referenceNumber,
    required this.movementDate,
    required this.notes,
    required this.createdByUid,
    required this.createdByName,
    required this.createdByRole,
    required this.createdAt,
  });

  final String id;
  final String companyId;
  final String warehouseId;
  final String itemId;
  final String itemName;
  final String itemCode;
  final String movementType;
  final String direction;
  final double quantity;
  final double quantityBefore;
  final double quantityAfter;
  final String referenceType;
  final String referenceId;
  final String referenceNumber;
  final DateTime movementDate;
  final String notes;
  final String createdByUid;
  final String createdByName;
  final String createdByRole;
  final DateTime createdAt;

  bool get isIn => direction == 'in';
  bool get isOut => direction == 'out';

  factory StockMovementModel.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data() ?? const {};
    return StockMovementModel(
      id: _readString(data, 'id').isEmpty
          ? document.id
          : _readString(data, 'id'),
      companyId: _readString(data, 'companyId'),
      warehouseId: _readString(data, 'warehouseId'),
      itemId: _readString(data, 'itemId'),
      itemName: _readString(data, 'itemName'),
      itemCode: _readString(data, 'itemCode'),
      movementType: _readString(data, 'movementType'),
      direction: _readString(data, 'direction').toLowerCase() == 'out'
          ? 'out'
          : 'in',
      quantity: _readDouble(data, 'quantity'),
      quantityBefore: _readDouble(data, 'quantityBefore'),
      quantityAfter: _readDouble(data, 'quantityAfter'),
      referenceType: _readString(data, 'referenceType'),
      referenceId: _readString(data, 'referenceId'),
      referenceNumber: _readString(data, 'referenceNumber'),
      movementDate:
          _readDate(data, 'movementDate') ??
          _readDate(data, 'createdAt') ??
          DateTime.now(),
      notes: _readString(data, 'notes'),
      createdByUid: _readString(data, 'createdByUid'),
      createdByName: _readString(data, 'createdByName'),
      createdByRole: _readString(data, 'createdByRole'),
      createdAt: _readDate(data, 'createdAt') ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'companyId': companyId,
    'warehouseId': warehouseId,
    'itemId': itemId,
    'itemName': itemName,
    'itemCode': itemCode,
    'movementType': movementType,
    'direction': direction,
    'quantity': quantity,
    'quantityBefore': quantityBefore,
    'quantityAfter': quantityAfter,
    'referenceType': referenceType,
    'referenceId': referenceId,
    'referenceNumber': referenceNumber,
    'movementDate': Timestamp.fromDate(movementDate),
    'notes': notes,
    'createdByUid': createdByUid,
    'createdByName': createdByName,
    'createdByRole': createdByRole,
    'createdAt': Timestamp.fromDate(createdAt),
  };

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

  static DateTime? _readDate(Map<String, dynamic> data, String key) {
    final value = data[key];
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }
}
