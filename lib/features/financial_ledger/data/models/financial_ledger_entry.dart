import 'package:cloud_firestore/cloud_firestore.dart';

class FinancialLedgerEntry {
  const FinancialLedgerEntry({
    required this.id,
    required this.occurredAt,
    required this.type,
    required this.component,
    required this.description,
    required this.amount,
    required this.quantity,
    required this.unitPrice,
    required this.debitAccountType,
    required this.debitAccountKey,
    required this.debitAccountName,
    required this.creditAccountType,
    required this.creditAccountKey,
    required this.creditAccountName,
    required this.customerId,
    required this.customerName,
    required this.salesRepId,
    required this.salesRepName,
    required this.paymentMethod,
    required this.referenceType,
    required this.referenceId,
    required this.referenceNumber,
    required this.sourceCollection,
    required this.sourceId,
    required this.notes,
  });

  final String id;
  final DateTime occurredAt;
  final String type;
  final String component;
  final String description;
  final double amount;
  final double quantity;
  final double unitPrice;
  final String debitAccountType;
  final String debitAccountKey;
  final String debitAccountName;
  final String creditAccountType;
  final String creditAccountKey;
  final String creditAccountName;
  final String customerId;
  final String customerName;
  final String salesRepId;
  final String salesRepName;
  final String paymentMethod;
  final String referenceType;
  final String referenceId;
  final String referenceNumber;
  final String sourceCollection;
  final String sourceId;
  final String notes;

  factory FinancialLedgerEntry.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) {
    return FinancialLedgerEntry.fromMap(
      document.data() ?? const <String, dynamic>{},
      id: document.id,
    );
  }

  factory FinancialLedgerEntry.fromMap(
    Map<String, dynamic> data, {
    String id = '',
  }) {
    final amount = _number(data['amount']);
    if (amount <= 0) {
      throw const FormatException('Financial ledger amount is invalid.');
    }
    final debitAccountKey = _string(data['debitAccountKey']);
    final creditAccountKey = _string(data['creditAccountKey']);
    if (debitAccountKey.isEmpty || creditAccountKey.isEmpty) {
      throw const FormatException('Financial ledger account key is invalid.');
    }
    return FinancialLedgerEntry(
      id: id.isEmpty ? _string(data['id']) : id,
      occurredAt: _date(data['occurredAt']),
      type: _string(data['type']),
      component: _string(data['component']),
      description: _string(data['description']),
      amount: amount,
      quantity: _number(data['quantity']),
      unitPrice: _number(data['unitPrice']),
      debitAccountType: _string(data['debitAccountType']),
      debitAccountKey: debitAccountKey,
      debitAccountName: _string(data['debitAccountName']),
      creditAccountType: _string(data['creditAccountType']),
      creditAccountKey: creditAccountKey,
      creditAccountName: _string(data['creditAccountName']),
      customerId: _string(data['customerId']),
      customerName: _string(data['customerName']),
      salesRepId: _string(data['salesRepId']),
      salesRepName: _string(data['salesRepName']),
      paymentMethod: _string(data['paymentMethod']),
      referenceType: _string(data['referenceType']),
      referenceId: _string(data['referenceId']),
      referenceNumber: _string(data['referenceNumber']),
      sourceCollection: _string(data['sourceCollection']),
      sourceId: _string(data['sourceId']),
      notes: _string(data['notes']),
    );
  }

  String get effectiveDescription => description.isNotEmpty
      ? description
      : referenceNumber.isNotEmpty
      ? referenceNumber
      : type;

  static String _string(Object? value) => value is String ? value.trim() : '';

  static double _number(Object? value) {
    if (value is num && value.isFinite) return value.toDouble();
    if (value is String) return double.tryParse(value.trim()) ?? 0;
    return 0;
  }

  static DateTime _date(Object? value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is num && value.isFinite) {
      return DateTime.fromMillisecondsSinceEpoch(value.toInt());
    }
    if (value is String) {
      final parsed = DateTime.tryParse(value);
      if (parsed != null) return parsed;
    }
    throw const FormatException('Financial ledger date is invalid.');
  }
}
