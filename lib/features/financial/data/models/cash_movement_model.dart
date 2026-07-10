import 'package:cloud_firestore/cloud_firestore.dart';

class CashMovementModel {
  const CashMovementModel({
    required this.id,
    required this.companyId,
    required this.salesRepId,
    required this.salesRepName,
    required this.type,
    required this.movementType,
    required this.direction,
    required this.amount,
    required this.referenceId,
    required this.referenceNumber,
    required this.sourceCollection,
    required this.sourceId,
    required this.sourceNumber,
    required this.customerId,
    required this.customerName,
    required this.date,
    required this.notes,
    this.cashAccount = '',
    this.settlementId = '',
    required this.createdByUid,
    required this.createdByName,
    required this.createdByRole,
    required this.createdAt,
  });

  final String id;
  final String companyId;
  final String salesRepId;
  final String salesRepName;
  final String type;
  final String movementType;
  final String direction;
  final double amount;
  final String referenceId;
  final String referenceNumber;
  final String sourceCollection;
  final String sourceId;
  final String sourceNumber;
  final String customerId;
  final String customerName;
  final DateTime date;
  final String notes;
  final String cashAccount;
  final String settlementId;
  final String createdByUid;
  final String createdByName;
  final String createdByRole;
  final DateTime createdAt;

  bool get isIn => direction == 'in';
  bool get isOut => direction == 'out';
  double get signedAmount => isOut ? -amount : amount;
  bool get isCompanyCashAccount => cashAccount == companyCashAccount;
  bool get isRepCashAccount => cashAccount == repCashAccount;
  bool get hasCashAccount => cashAccount.isNotEmpty;

  static const String companyCashAccount = 'company_cash';
  static const String repCashAccount = 'rep_cash';

  String get effectiveType {
    if (type.isNotEmpty) return type;
    return switch (movementType) {
      'invoice_payment' => 'invoice_cash',
      'receipt' => 'receipt_cash',
      _ => movementType,
    };
  }

  String get effectiveReferenceNumber {
    if (referenceNumber.isNotEmpty) return referenceNumber;
    return sourceNumber;
  }

  factory CashMovementModel.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data() ?? const {};
    final sourceId = _readString(data, 'sourceId');
    final sourceNumber = _readString(data, 'sourceNumber');
    return CashMovementModel(
      id: _readString(data, 'id').isEmpty
          ? document.id
          : _readString(data, 'id'),
      companyId: _readString(data, 'companyId'),
      salesRepId: _readString(data, 'salesRepId'),
      salesRepName: _readString(data, 'salesRepName'),
      type: _readString(data, 'type'),
      movementType: _readString(data, 'movementType'),
      direction: _readString(data, 'direction').toLowerCase() == 'out'
          ? 'out'
          : 'in',
      amount: _readDouble(data, 'amount'),
      referenceId: _readString(data, 'referenceId').isEmpty
          ? sourceId
          : _readString(data, 'referenceId'),
      referenceNumber: _readString(data, 'referenceNumber').isEmpty
          ? sourceNumber
          : _readString(data, 'referenceNumber'),
      sourceCollection: _readString(data, 'sourceCollection'),
      sourceId: sourceId,
      sourceNumber: sourceNumber,
      customerId: _readString(data, 'customerId'),
      customerName: _readString(data, 'customerName'),
      date:
          _readDate(data, 'date') ??
          _readDate(data, 'movementDate') ??
          _readDate(data, 'createdAt') ??
          DateTime.now(),
      notes: _readString(data, 'notes'),
      cashAccount: _readString(data, 'cashAccount'),
      settlementId: _readString(data, 'settlementId'),
      createdByUid: _readString(data, 'createdByUid'),
      createdByName: _readString(data, 'createdByName'),
      createdByRole: _readString(data, 'createdByRole'),
      createdAt: _readDate(data, 'createdAt') ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'companyId': companyId,
    'salesRepId': salesRepId,
    'salesRepName': salesRepName,
    'type': type,
    'movementType': movementType,
    'direction': direction,
    'amount': amount,
    'referenceId': referenceId,
    'referenceNumber': referenceNumber,
    'sourceCollection': sourceCollection,
    'sourceId': sourceId,
    'sourceNumber': sourceNumber,
    'customerId': customerId,
    'customerName': customerName,
    'date': Timestamp.fromDate(date),
    'movementDate': Timestamp.fromDate(date),
    'notes': notes,
    if (cashAccount.isNotEmpty) 'cashAccount': cashAccount,
    if (settlementId.isNotEmpty) 'settlementId': settlementId,
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
