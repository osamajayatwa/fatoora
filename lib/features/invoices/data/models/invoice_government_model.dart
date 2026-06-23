import 'package:cloud_firestore/cloud_firestore.dart';

class InvoiceGovernmentModel {
  const InvoiceGovernmentModel({
    required this.governmentInvoiceId,
    required this.uuid,
    required this.qrCode,
    this.submittedAt,
    this.acceptedAt,
    required this.joFotaraStatus,
    required this.joFotaraErrorCode,
    required this.joFotaraErrorMessage,
    required this.rawResponse,
  });

  final String governmentInvoiceId;
  final String uuid;
  final String qrCode;
  final DateTime? submittedAt;
  final DateTime? acceptedAt;
  final String joFotaraStatus;
  final String joFotaraErrorCode;
  final String joFotaraErrorMessage;
  final Map<String, dynamic> rawResponse;

  factory InvoiceGovernmentModel.fromMap(Object? value) {
    final data = _asMap(value);
    return InvoiceGovernmentModel(
      governmentInvoiceId: _readString(data, 'governmentInvoiceId'),
      uuid: _readString(data, 'uuid'),
      qrCode: _readString(data, 'qrCode'),
      submittedAt: _readDate(data, 'submittedAt'),
      acceptedAt: _readDate(data, 'acceptedAt'),
      joFotaraStatus: _readString(data, 'joFotaraStatus'),
      joFotaraErrorCode: _readString(data, 'joFotaraErrorCode'),
      joFotaraErrorMessage: _readString(data, 'joFotaraErrorMessage'),
      rawResponse: _asMap(data['rawResponse']),
    );
  }

  Map<String, dynamic> toMap() => {
    'governmentInvoiceId': governmentInvoiceId,
    'uuid': uuid,
    'qrCode': qrCode,
    'submittedAt': submittedAt == null
        ? null
        : Timestamp.fromDate(submittedAt!),
    'acceptedAt': acceptedAt == null ? null : Timestamp.fromDate(acceptedAt!),
    'joFotaraStatus': joFotaraStatus,
    'joFotaraErrorCode': joFotaraErrorCode,
    'joFotaraErrorMessage': joFotaraErrorMessage,
    'rawResponse': rawResponse,
  };

  InvoiceGovernmentModel copyWith({
    String? governmentInvoiceId,
    String? uuid,
    String? qrCode,
    DateTime? submittedAt,
    DateTime? acceptedAt,
    String? joFotaraStatus,
    String? joFotaraErrorCode,
    String? joFotaraErrorMessage,
    Map<String, dynamic>? rawResponse,
  }) {
    return InvoiceGovernmentModel(
      governmentInvoiceId: governmentInvoiceId ?? this.governmentInvoiceId,
      uuid: uuid ?? this.uuid,
      qrCode: qrCode ?? this.qrCode,
      submittedAt: submittedAt ?? this.submittedAt,
      acceptedAt: acceptedAt ?? this.acceptedAt,
      joFotaraStatus: joFotaraStatus ?? this.joFotaraStatus,
      joFotaraErrorCode: joFotaraErrorCode ?? this.joFotaraErrorCode,
      joFotaraErrorMessage: joFotaraErrorMessage ?? this.joFotaraErrorMessage,
      rawResponse: rawResponse ?? this.rawResponse,
    );
  }

  static Map<String, dynamic> _asMap(Object? value) {
    if (value is! Map) return const {};
    return value.map((key, value) => MapEntry(key.toString(), value));
  }

  static String _readString(Map<String, dynamic> data, String key) {
    final value = data[key];
    return value is String ? value.trim() : '';
  }

  static DateTime? _readDate(Map<String, dynamic> data, String key) {
    final value = data[key];
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }
}
