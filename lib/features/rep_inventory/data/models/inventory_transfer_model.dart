import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fatoora/features/rep_inventory/data/models/rep_inventory_enums.dart';

class InventoryTransferLine {
  const InventoryTransferLine({
    required this.itemId,
    required this.modelSnapshot,
    required this.itemNameSnapshot,
    required this.unitSnapshot,
    required this.quantity,
    this.warehouseQuantityBefore,
    this.warehouseQuantityAfter,
    this.repQuantityBefore,
    this.repQuantityAfter,
    this.companyMovementId = '',
    this.repMovementId = '',
  });

  final String itemId;
  final String modelSnapshot;
  final String itemNameSnapshot;
  final String unitSnapshot;
  final double quantity;
  final double? warehouseQuantityBefore;
  final double? warehouseQuantityAfter;
  final double? repQuantityBefore;
  final double? repQuantityAfter;
  final String companyMovementId;
  final String repMovementId;

  factory InventoryTransferLine.fromMap(Object? value) {
    final data = value is Map ? Map<String, dynamic>.from(value) : const {};
    return InventoryTransferLine(
      itemId: _string(data['itemId']),
      modelSnapshot: _string(data['modelSnapshot']),
      itemNameSnapshot: _string(data['itemNameSnapshot']),
      unitSnapshot: _string(data['unitSnapshot']),
      quantity: _number(data['quantity']),
      warehouseQuantityBefore: _nullableNumber(data['warehouseQuantityBefore']),
      warehouseQuantityAfter: _nullableNumber(data['warehouseQuantityAfter']),
      repQuantityBefore: _nullableNumber(data['repQuantityBefore']),
      repQuantityAfter: _nullableNumber(data['repQuantityAfter']),
      companyMovementId: _string(data['companyMovementId']),
      repMovementId: _string(data['repMovementId']),
    );
  }

  Map<String, dynamic> toMap() => {
    'itemId': itemId,
    'modelSnapshot': modelSnapshot,
    'itemNameSnapshot': itemNameSnapshot,
    'unitSnapshot': unitSnapshot,
    'quantity': quantity,
    'warehouseQuantityBefore': warehouseQuantityBefore,
    'warehouseQuantityAfter': warehouseQuantityAfter,
    'repQuantityBefore': repQuantityBefore,
    'repQuantityAfter': repQuantityAfter,
    'companyMovementId': companyMovementId,
    'repMovementId': repMovementId,
  };

  InventoryTransferLine copyWith({
    String? itemId,
    String? modelSnapshot,
    String? itemNameSnapshot,
    String? unitSnapshot,
    double? quantity,
    double? warehouseQuantityBefore,
    double? warehouseQuantityAfter,
    double? repQuantityBefore,
    double? repQuantityAfter,
    String? companyMovementId,
    String? repMovementId,
  }) {
    return InventoryTransferLine(
      itemId: itemId ?? this.itemId,
      modelSnapshot: modelSnapshot ?? this.modelSnapshot,
      itemNameSnapshot: itemNameSnapshot ?? this.itemNameSnapshot,
      unitSnapshot: unitSnapshot ?? this.unitSnapshot,
      quantity: quantity ?? this.quantity,
      warehouseQuantityBefore:
          warehouseQuantityBefore ?? this.warehouseQuantityBefore,
      warehouseQuantityAfter:
          warehouseQuantityAfter ?? this.warehouseQuantityAfter,
      repQuantityBefore: repQuantityBefore ?? this.repQuantityBefore,
      repQuantityAfter: repQuantityAfter ?? this.repQuantityAfter,
      companyMovementId: companyMovementId ?? this.companyMovementId,
      repMovementId: repMovementId ?? this.repMovementId,
    );
  }
}

class InventoryTransferModel {
  const InventoryTransferModel({
    required this.id,
    required this.companyId,
    required this.transferNumber,
    required this.year,
    required this.type,
    required this.status,
    required this.salesRepId,
    required this.salesRepNameSnapshot,
    required this.lines,
    required this.totalQuantity,
    required this.notes,
    required this.createdByUid,
    required this.createdByName,
    required this.createdAt,
    required this.updatedAt,
    this.confirmedByUid = '',
    this.confirmedByName = '',
    this.confirmedAt,
    this.cancelledByUid = '',
    this.cancelledAt,
    this.effectsVersion = 1,
  });

  final String id;
  final String companyId;
  final String transferNumber;
  final int year;
  final InventoryTransferType type;
  final InventoryTransferStatus status;
  final String salesRepId;
  final String salesRepNameSnapshot;
  final List<InventoryTransferLine> lines;
  final double totalQuantity;
  final String notes;
  final String createdByUid;
  final String createdByName;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String confirmedByUid;
  final String confirmedByName;
  final DateTime? confirmedAt;
  final String cancelledByUid;
  final DateTime? cancelledAt;
  final int effectsVersion;

  bool get isDraft => status == InventoryTransferStatus.draft;
  bool get isConfirmed => status == InventoryTransferStatus.confirmed;
  bool get isCancelled => status == InventoryTransferStatus.cancelled;

  factory InventoryTransferModel.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) {
    return InventoryTransferModel.fromMap(
      document.data() ?? const {},
      id: document.id,
    );
  }

  factory InventoryTransferModel.fromMap(
    Map<String, dynamic> data, {
    String? id,
  }) {
    final rawLines = data['lines'];
    final lines = rawLines is List
        ? rawLines.map(InventoryTransferLine.fromMap).toList(growable: false)
        : const <InventoryTransferLine>[];
    return InventoryTransferModel(
      id: id ?? _string(data['id']),
      companyId: _string(data['companyId']),
      transferNumber: _string(data['transferNumber']),
      year: _integer(data['year']),
      type: inventoryTransferTypeFromValue(data['type']),
      status: inventoryTransferStatusFromValue(data['status']),
      salesRepId: _string(data['salesRepId']),
      salesRepNameSnapshot: _string(data['salesRepNameSnapshot']),
      lines: lines,
      totalQuantity: _number(data['totalQuantity']),
      notes: _string(data['notes']),
      createdByUid: _string(data['createdByUid']),
      createdByName: _string(data['createdByName']),
      createdAt: _date(data['createdAt']) ?? DateTime.now(),
      updatedAt: _date(data['updatedAt']) ?? DateTime.now(),
      confirmedByUid: _string(data['confirmedByUid']),
      confirmedByName: _string(data['confirmedByName']),
      confirmedAt: _date(data['confirmedAt']),
      cancelledByUid: _string(data['cancelledByUid']),
      cancelledAt: _date(data['cancelledAt']),
      effectsVersion: _integer(data['effectsVersion'], fallback: 1),
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'companyId': companyId,
    'transferNumber': transferNumber,
    'year': year,
    'type': type.value,
    'status': status.value,
    'salesRepId': salesRepId,
    'salesRepNameSnapshot': salesRepNameSnapshot,
    'lines': lines.map((line) => line.toMap()).toList(growable: false),
    'totalQuantity': totalQuantity,
    'notes': notes,
    'createdByUid': createdByUid,
    'createdByName': createdByName,
    'createdAt': Timestamp.fromDate(createdAt),
    'updatedAt': Timestamp.fromDate(updatedAt),
    'confirmedByUid': confirmedByUid,
    'confirmedByName': confirmedByName,
    'confirmedAt': confirmedAt == null
        ? null
        : Timestamp.fromDate(confirmedAt!),
    'cancelledByUid': cancelledByUid,
    'cancelledAt': cancelledAt == null
        ? null
        : Timestamp.fromDate(cancelledAt!),
    'effectsVersion': effectsVersion,
  };

  InventoryTransferModel copyWith({
    String? id,
    String? companyId,
    String? transferNumber,
    int? year,
    InventoryTransferType? type,
    InventoryTransferStatus? status,
    String? salesRepId,
    String? salesRepNameSnapshot,
    List<InventoryTransferLine>? lines,
    double? totalQuantity,
    String? notes,
    String? createdByUid,
    String? createdByName,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? confirmedByUid,
    String? confirmedByName,
    DateTime? confirmedAt,
    String? cancelledByUid,
    DateTime? cancelledAt,
    int? effectsVersion,
  }) {
    return InventoryTransferModel(
      id: id ?? this.id,
      companyId: companyId ?? this.companyId,
      transferNumber: transferNumber ?? this.transferNumber,
      year: year ?? this.year,
      type: type ?? this.type,
      status: status ?? this.status,
      salesRepId: salesRepId ?? this.salesRepId,
      salesRepNameSnapshot: salesRepNameSnapshot ?? this.salesRepNameSnapshot,
      lines: lines ?? this.lines,
      totalQuantity: totalQuantity ?? this.totalQuantity,
      notes: notes ?? this.notes,
      createdByUid: createdByUid ?? this.createdByUid,
      createdByName: createdByName ?? this.createdByName,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      confirmedByUid: confirmedByUid ?? this.confirmedByUid,
      confirmedByName: confirmedByName ?? this.confirmedByName,
      confirmedAt: confirmedAt ?? this.confirmedAt,
      cancelledByUid: cancelledByUid ?? this.cancelledByUid,
      cancelledAt: cancelledAt ?? this.cancelledAt,
      effectsVersion: effectsVersion ?? this.effectsVersion,
    );
  }
}

String _string(Object? value) => value is String ? value.trim() : '';
double _number(Object? value) =>
    value is num && value.isFinite ? value.toDouble() : 0;
double? _nullableNumber(Object? value) =>
    value is num && value.isFinite ? value.toDouble() : null;
int _integer(Object? value, {int fallback = 0}) =>
    value is num ? value.toInt() : fallback;
DateTime? _date(Object? value) {
  if (value is Timestamp) return value.toDate();
  if (value is DateTime) return value;
  if (value is String) return DateTime.tryParse(value);
  return null;
}
