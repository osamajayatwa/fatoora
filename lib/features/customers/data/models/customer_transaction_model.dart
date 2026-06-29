import 'package:cloud_firestore/cloud_firestore.dart';

class CustomerTransactionModel {
  const CustomerTransactionModel({
    required this.id,
    required this.companyId,
    required this.customerId,
    required this.customerName,
    required this.transactionType,
    this.type = '',
    required this.sourceCollection,
    required this.sourceId,
    required this.sourceNumber,
    required this.transactionDate,
    required this.debitAmount,
    required this.creditAmount,
    required this.balanceAfter,
    this.amount = 0,
    this.signedAmount = 0,
    this.invoiceId = '',
    this.invoiceNumber = '',
    this.returnInvoiceId = '',
    this.returnNumber = '',
    this.originalInvoiceId = '',
    this.originalInvoiceNumber = '',
    this.receiptId = '',
    this.receiptNumber = '',
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
  final String type;
  final String sourceCollection;
  final String sourceId;
  final String sourceNumber;
  final DateTime transactionDate;
  final double debitAmount;
  final double creditAmount;
  final double balanceAfter;
  final double amount;
  final double signedAmount;
  final String invoiceId;
  final String invoiceNumber;
  final String returnInvoiceId;
  final String returnNumber;
  final String originalInvoiceId;
  final String originalInvoiceNumber;
  final String receiptId;
  final String receiptNumber;
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
      type: _readString(data, 'type').isEmpty
          ? _readString(data, 'transactionType')
          : _readString(data, 'type'),
      sourceCollection: _readString(data, 'sourceCollection'),
      sourceId: _readString(data, 'sourceId'),
      sourceNumber: _readString(data, 'sourceNumber'),
      transactionDate: _readDate(data, 'transactionDate'),
      debitAmount: _readDouble(data, 'debitAmount'),
      creditAmount: _readDouble(data, 'creditAmount'),
      balanceAfter: _readDouble(data, 'balanceAfter'),
      amount: _readDouble(data, 'amount') == 0
          ? _readDouble(data, 'debitAmount') + _readDouble(data, 'creditAmount')
          : _readDouble(data, 'amount'),
      signedAmount: data.containsKey('signedAmount')
          ? _readDouble(data, 'signedAmount')
          : _readDouble(data, 'debitAmount') -
                _readDouble(data, 'creditAmount'),
      invoiceId: _readString(data, 'invoiceId'),
      invoiceNumber: _readString(data, 'invoiceNumber'),
      returnInvoiceId: _readString(data, 'returnInvoiceId'),
      returnNumber: _readString(data, 'returnNumber'),
      originalInvoiceId: _readString(data, 'originalInvoiceId'),
      originalInvoiceNumber: _readString(data, 'originalInvoiceNumber'),
      receiptId: _readString(data, 'receiptId'),
      receiptNumber: _readString(data, 'receiptNumber'),
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
    'type': type.isEmpty ? transactionType : type,
    'sourceCollection': sourceCollection,
    'sourceId': sourceId,
    'sourceNumber': sourceNumber,
    'transactionDate': Timestamp.fromDate(transactionDate),
    'debitAmount': debitAmount,
    'creditAmount': creditAmount,
    'balanceAfter': balanceAfter,
    'amount': amount,
    'signedAmount': signedAmount,
    'invoiceId': invoiceId,
    'invoiceNumber': invoiceNumber,
    'returnInvoiceId': returnInvoiceId,
    'returnNumber': returnNumber,
    'originalInvoiceId': originalInvoiceId,
    'originalInvoiceNumber': originalInvoiceNumber,
    'receiptId': receiptId,
    'receiptNumber': receiptNumber,
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
