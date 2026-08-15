import 'package:cloud_firestore/cloud_firestore.dart';

class CompanyCashOpeningBalanceModel {
  const CompanyCashOpeningBalanceModel({
    required this.id,
    required this.companyId,
    required this.amount,
    required this.note,
    required this.effectiveDate,
    required this.balanceBefore,
    required this.balanceAfter,
    required this.createdByUid,
    required this.createdByName,
    required this.createdAt,
  });

  static const String authorizedUid = 'Ku5x8xXv1BhJQ0yQkVXtYtYOjQn1';
  static const String authorizedEmail = 'osamahesham101@gmail.com';
  static const String movementId = 'company_cash_opening_balance';
  static final DateTime fixedEffectiveDate = DateTime.utc(2026, 7, 30);

  final String id;
  final String companyId;
  final double amount;
  final String note;
  final DateTime effectiveDate;
  final double balanceBefore;
  final double balanceAfter;
  final String createdByUid;
  final String createdByName;
  final DateTime createdAt;

  factory CompanyCashOpeningBalanceModel.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data() ?? const <String, dynamic>{};
    return CompanyCashOpeningBalanceModel(
      id: _string(data['id']).isEmpty ? document.id : _string(data['id']),
      companyId: _string(data['companyId']),
      amount: _number(data['amount']),
      note: _string(data['notes']),
      effectiveDate: _date(data['effectiveDate']),
      balanceBefore: _number(data['balanceBefore']),
      balanceAfter: _number(data['balanceAfter']),
      createdByUid: _string(data['createdByUid']),
      createdByName: _string(data['createdByName']),
      createdAt: _date(data['createdAt']),
    );
  }

  bool get isValidOpeningBalance =>
      id == movementId &&
      companyId.isNotEmpty &&
      amount > 0 &&
      effectiveDate.toUtc() == fixedEffectiveDate;

  static String _string(Object? value) => value is String ? value.trim() : '';

  static double _number(Object? value) {
    if (value is num && value.isFinite) return value.toDouble();
    return double.nan;
  }

  static DateTime _date(Object? value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
  }
}
