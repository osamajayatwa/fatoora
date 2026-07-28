import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fatoora/features/rep_inventory/data/models/rep_inventory_enums.dart';

class RepInventoryMovementModel {
  const RepInventoryMovementModel({
    required this.id,
    required this.companyId,
    required this.salesRepId,
    required this.salesRepNameSnapshot,
    required this.itemId,
    required this.modelSnapshot,
    required this.itemNameSnapshot,
    required this.unitSnapshot,
    required this.direction,
    required this.quantity,
    required this.quantityBefore,
    required this.quantityAfter,
    required this.reason,
    required this.referenceType,
    required this.referenceId,
    required this.referenceNumber,
    required this.transferType,
    required this.createdByUid,
    required this.createdByName,
    required this.createdAt,
  });

  final String id;
  final String companyId;
  final String salesRepId;
  final String salesRepNameSnapshot;
  final String itemId;
  final String modelSnapshot;
  final String itemNameSnapshot;
  final String unitSnapshot;
  final RepInventoryDirection direction;
  final double quantity;
  final double quantityBefore;
  final double quantityAfter;
  final RepInventoryReason reason;
  final RepInventoryReferenceType referenceType;
  final String referenceId;
  final String referenceNumber;
  final String transferType;
  final String createdByUid;
  final String createdByName;
  final DateTime createdAt;

  factory RepInventoryMovementModel.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data() ?? const {};
    return RepInventoryMovementModel(
      id: document.id,
      companyId: _string(data['companyId']),
      salesRepId: _string(data['salesRepId']),
      salesRepNameSnapshot: _string(data['salesRepNameSnapshot']),
      itemId: _string(data['itemId']),
      modelSnapshot: _string(data['modelSnapshot']),
      itemNameSnapshot: _string(data['itemNameSnapshot']),
      unitSnapshot: _string(data['unitSnapshot']),
      direction: repInventoryDirectionFromValue(data['direction']),
      quantity: _number(data['quantity']),
      quantityBefore: _number(data['quantityBefore']),
      quantityAfter: _number(data['quantityAfter']),
      reason: repInventoryReasonFromValue(data['reason']),
      referenceType: repInventoryReferenceTypeFromValue(data['referenceType']),
      referenceId: _string(data['referenceId']),
      referenceNumber: _string(data['referenceNumber']),
      transferType: _string(data['transferType']),
      createdByUid: _string(data['createdByUid']),
      createdByName: _string(data['createdByName']),
      createdAt: _date(data['createdAt']) ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'companyId': companyId,
    'salesRepId': salesRepId,
    'salesRepNameSnapshot': salesRepNameSnapshot,
    'itemId': itemId,
    'modelSnapshot': modelSnapshot,
    'itemNameSnapshot': itemNameSnapshot,
    'unitSnapshot': unitSnapshot,
    'direction': direction.value,
    'quantity': quantity,
    'quantityBefore': quantityBefore,
    'quantityAfter': quantityAfter,
    'reason': reason.value,
    'referenceType': referenceType.value,
    'referenceId': referenceId,
    'referenceNumber': referenceNumber,
    'transferType': transferType,
    'createdByUid': createdByUid,
    'createdByName': createdByName,
    'createdAt': Timestamp.fromDate(createdAt),
  };
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
