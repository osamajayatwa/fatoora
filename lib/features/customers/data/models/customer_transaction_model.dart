import 'package:cloud_firestore/cloud_firestore.dart';

class CustomerTransactionModel {
  const CustomerTransactionModel({
    required this.id,
    required this.companyId,
    required this.customerId,
    required this.customerName,
    required this.transactionType,
    required this.sourceCollection,
    required this.sourceId,
    required this.sourceNumber,
    required this.transactionDate,
    required this.debitAmount,
    required this.creditAmount,
    required this.balanceAfter,
    required this.notes,
    required this.createdByUid,
    required this.createdByName,
    required this.createdByRole,
    required this.salesRepId,
    required this.salesRepName,
    required this.createdAt,
  });

  final String id;
  final String companyId;
  final String customerId;
  final String customerName;
  final String transactionType;
  final String sourceCollection;
  final String sourceId;
  final String sourceNumber;
  final DateTime transactionDate;
  final double debitAmount;
  final double creditAmount;
  final double balanceAfter;
  final String notes;
  final String createdByUid;
  final String createdByName;
  final String createdByRole;
  final String salesRepId;
  final String salesRepName;
  final DateTime createdAt;

  factory CustomerTransactionModel.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data() ?? const {};
    return CustomerTransactionModel(
      id: document.id,
      companyId: _readString(data, 'companyId'),
      customerId: _readString(data, 'customerId'),
      customerName: _readString(data, 'customerName'),
      transactionType: _readString(data, 'transactionType'),
      sourceCollection: _readString(data, 'sourceCollection'),
      sourceId: _readString(data, 'sourceId'),
      sourceNumber: _readString(data, 'sourceNumber'),
      transactionDate: _readDate(data, 'transactionDate'),
      debitAmount: _readDouble(data, 'debitAmount'),
      creditAmount: _readDouble(data, 'creditAmount'),
      balanceAfter: _readDouble(data, 'balanceAfter'),
      notes: _readString(data, 'notes'),
      createdByUid: _readString(data, 'createdByUid'),
      createdByName: _readString(data, 'createdByName'),
      createdByRole: _readString(data, 'createdByRole'),
      salesRepId: _readString(data, 'salesRepId'),
      salesRepName: _readString(data, 'salesRepName'),
      createdAt: _readDate(data, 'createdAt'),
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'companyId': companyId,
    'customerId': customerId,
    'customerName': customerName,
    'transactionType': transactionType,
    'sourceCollection': sourceCollection,
    'sourceId': sourceId,
    'sourceNumber': sourceNumber,
    'transactionDate': Timestamp.fromDate(transactionDate),
    'debitAmount': debitAmount,
    'creditAmount': creditAmount,
    'balanceAfter': balanceAfter,
    'notes': notes,
    'createdByUid': createdByUid,
    'createdByName': createdByName,
    'createdByRole': createdByRole,
    'salesRepId': salesRepId,
    'salesRepName': salesRepName,
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

  static DateTime _readDate(Map<String, dynamic> data, String key) {
    final value = data[key];
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value) ?? DateTime.now();
    return DateTime.now();
  }
}
