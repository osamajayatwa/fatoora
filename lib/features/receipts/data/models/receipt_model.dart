import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fatoora/features/invoices/data/models/invoice_customer_snapshot.dart';

class ReceiptModel {
  const ReceiptModel({
    required this.id,
    required this.companyId,
    required this.receiptNumber,
    required this.receiptDate,
    required this.customerId,
    required this.customerSnapshot,
    required this.amount,
    required this.paymentMethod,
    required this.notes,
    required this.salesRepId,
    required this.salesRepName,
    required this.createdByUid,
    required this.createdByName,
    required this.createdByRole,
    required this.customerTransactionIds,
    required this.cashMovementIds,
    this.invoiceAllocations = const {},
    this.payFullBalance = false,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String companyId;
  final String receiptNumber;
  final DateTime receiptDate;
  final String customerId;
  final InvoiceCustomerSnapshot customerSnapshot;
  final double amount;
  final String paymentMethod;
  final String notes;
  final String salesRepId;
  final String salesRepName;
  final String createdByUid;
  final String createdByName;
  final String createdByRole;
  final List<String> customerTransactionIds;
  final List<String> cashMovementIds;
  final Map<String, double> invoiceAllocations;
  final bool payFullBalance;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory ReceiptModel.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data() ?? const {};
    return ReceiptModel(
      id: document.id,
      companyId: _readString(data, 'companyId'),
      receiptNumber: _readString(data, 'receiptNumber'),
      receiptDate: _readDate(data, 'receiptDate'),
      customerId: _readString(data, 'customerId'),
      customerSnapshot: InvoiceCustomerSnapshot.fromMap(
        data['customerSnapshot'],
      ),
      amount: _readDouble(data, 'amount'),
      paymentMethod: _readString(data, 'paymentMethod'),
      notes: _readString(data, 'notes'),
      salesRepId: _readString(data, 'salesRepId'),
      salesRepName: _readString(data, 'salesRepName'),
      createdByUid: _readString(data, 'createdByUid'),
      createdByName: _readString(data, 'createdByName'),
      createdByRole: _readString(data, 'createdByRole'),
      customerTransactionIds: _readStringList(data['customerTransactionIds']),
      cashMovementIds: _readStringList(data['cashMovementIds']),
      invoiceAllocations: _readDoubleMap(data['invoiceAllocations']),
      payFullBalance: data['payFullBalance'] == true,
      createdAt: _readDate(data, 'createdAt'),
      updatedAt: _readDate(data, 'updatedAt'),
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'companyId': companyId,
    'receiptNumber': receiptNumber,
    'receiptDate': Timestamp.fromDate(receiptDate),
    'customerId': customerId,
    'customerSnapshot': customerSnapshot.toMap(),
    'amount': amount,
    'paymentMethod': paymentMethod,
    'notes': notes,
    'salesRepId': salesRepId,
    'salesRepName': salesRepName,
    'createdByUid': createdByUid,
    'createdByName': createdByName,
    'createdByRole': createdByRole,
    'customerTransactionIds': customerTransactionIds,
    'cashMovementIds': cashMovementIds,
    'invoiceAllocations': invoiceAllocations,
    'payFullBalance': payFullBalance,
    'createdAt': Timestamp.fromDate(createdAt),
    'updatedAt': Timestamp.fromDate(updatedAt),
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

  static List<String> _readStringList(Object? value) {
    if (value is! List) return const [];
    return value
        .whereType<Object>()
        .map((item) => item.toString().trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
  }

  static Map<String, double> _readDoubleMap(Object? value) {
    if (value is! Map) return const {};
    return value.map((key, amount) {
      final number = amount is num
          ? amount.toDouble()
          : double.tryParse(amount.toString()) ?? 0;
      return MapEntry(key.toString(), number);
    });
  }
}
