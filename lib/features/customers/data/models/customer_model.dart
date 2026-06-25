import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fatoora/features/invoices/data/models/invoice_customer_snapshot.dart';

class CustomerModel {
  const CustomerModel({
    required this.id,
    required this.companyId,
    required this.name,
    required this.phone,
    required this.addressText,
    required this.city,
    required this.area,
    required this.notes,
    required this.active,
    required this.createdByUid,
    required this.createdByName,
    required this.createdByRole,
    required this.createdAt,
    required this.updatedAt,
    required this.currentBalance,
    required this.totalSales,
    required this.totalPaid,
    required this.searchKeywords,
    required this.nameLower,
    required this.phoneNormalized,
    required this.cityLower,
    required this.areaLower,
  });

  final String id;
  final String companyId;
  final String name;
  final String phone;
  final String addressText;
  final String city;
  final String area;
  final String notes;
  final bool active;
  final String createdByUid;
  final String createdByName;
  final String createdByRole;
  final DateTime createdAt;
  final DateTime updatedAt;
  final double currentBalance;
  final double totalSales;
  final double totalPaid;
  final List<String> searchKeywords;
  final String nameLower;
  final String phoneNormalized;
  final String cityLower;
  final String areaLower;

  factory CustomerModel.empty({
    required String companyId,
    required String createdByUid,
    required String createdByName,
    required String createdByRole,
  }) {
    final now = DateTime.now();
    return CustomerModel(
      id: '',
      companyId: companyId,
      name: '',
      phone: '',
      addressText: '',
      city: '',
      area: '',
      notes: '',
      active: true,
      createdByUid: createdByUid,
      createdByName: createdByName,
      createdByRole: createdByRole,
      createdAt: now,
      updatedAt: now,
      currentBalance: 0,
      totalSales: 0,
      totalPaid: 0,
      searchKeywords: const [],
      nameLower: '',
      phoneNormalized: '',
      cityLower: '',
      areaLower: '',
    );
  }

  factory CustomerModel.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) {
    return CustomerModel.fromMap(document.data() ?? const {}, id: document.id);
  }

  factory CustomerModel.fromMap(Map<String, dynamic> data, {String? id}) {
    return CustomerModel(
      id: id ?? _readString(data, 'id'),
      companyId: _readString(data, 'companyId', fallback: 'default_company'),
      name: _readString(data, 'name'),
      phone: _readString(data, 'phone'),
      addressText: _readString(data, 'addressText'),
      city: _readString(data, 'city'),
      area: _readString(data, 'area'),
      notes: _readString(data, 'notes'),
      active: _readBool(data, 'active', fallback: true),
      createdByUid: _readString(data, 'createdByUid'),
      createdByName: _readString(data, 'createdByName'),
      createdByRole: _readString(data, 'createdByRole'),
      createdAt: _readDate(data, 'createdAt'),
      updatedAt: _readDate(data, 'updatedAt'),
      currentBalance: _readDouble(data, 'currentBalance'),
      totalSales: _readDouble(data, 'totalSales'),
      totalPaid: _readDouble(data, 'totalPaid'),
      searchKeywords: _readStringList(data['searchKeywords']),
      nameLower: _readString(data, 'nameLower'),
      phoneNormalized: _readString(data, 'phoneNormalized'),
      cityLower: _readString(data, 'cityLower'),
      areaLower: _readString(data, 'areaLower'),
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'companyId': companyId,
    'name': name.trim(),
    'phone': phone.trim(),
    'addressText': addressText.trim(),
    'city': city.trim(),
    'area': area.trim(),
    'notes': notes.trim(),
    'active': active,
    'createdByUid': createdByUid,
    'createdByName': createdByName,
    'createdByRole': createdByRole,
    'createdAt': Timestamp.fromDate(createdAt),
    'updatedAt': Timestamp.fromDate(updatedAt),
    'currentBalance': currentBalance,
    'totalSales': totalSales,
    'totalPaid': totalPaid,
    'searchKeywords': searchKeywords,
    'nameLower': nameLower,
    'phoneNormalized': phoneNormalized,
    'cityLower': cityLower,
    'areaLower': areaLower,
  };

  CustomerModel copyWith({
    String? id,
    String? companyId,
    String? name,
    String? phone,
    String? addressText,
    String? city,
    String? area,
    String? notes,
    bool? active,
    String? createdByUid,
    String? createdByName,
    String? createdByRole,
    DateTime? createdAt,
    DateTime? updatedAt,
    double? currentBalance,
    double? totalSales,
    double? totalPaid,
    List<String>? searchKeywords,
    String? nameLower,
    String? phoneNormalized,
    String? cityLower,
    String? areaLower,
  }) {
    return CustomerModel(
      id: id ?? this.id,
      companyId: companyId ?? this.companyId,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      addressText: addressText ?? this.addressText,
      city: city ?? this.city,
      area: area ?? this.area,
      notes: notes ?? this.notes,
      active: active ?? this.active,
      createdByUid: createdByUid ?? this.createdByUid,
      createdByName: createdByName ?? this.createdByName,
      createdByRole: createdByRole ?? this.createdByRole,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      currentBalance: currentBalance ?? this.currentBalance,
      totalSales: totalSales ?? this.totalSales,
      totalPaid: totalPaid ?? this.totalPaid,
      searchKeywords: searchKeywords ?? this.searchKeywords,
      nameLower: nameLower ?? this.nameLower,
      phoneNormalized: phoneNormalized ?? this.phoneNormalized,
      cityLower: cityLower ?? this.cityLower,
      areaLower: areaLower ?? this.areaLower,
    );
  }

  CustomerModel withSearchFields() {
    final normalizedName = normalizeText(name);
    final normalizedPhone = normalizePhone(phone);
    final normalizedCity = normalizeText(city);
    final normalizedArea = normalizeText(area);
    return copyWith(
      nameLower: normalizedName,
      phoneNormalized: normalizedPhone,
      cityLower: normalizedCity,
      areaLower: normalizedArea,
      searchKeywords: buildSearchKeywords([
        normalizedName,
        normalizedPhone,
        normalizedCity,
        normalizedArea,
        normalizeText(addressText),
      ]),
    );
  }

  InvoiceCustomerSnapshot toInvoiceSnapshot() {
    return InvoiceCustomerSnapshot(
      id: id,
      name: name,
      phone: phone,
      address: addressText,
      taxNumber: '',
      nationalNumber: '',
      city: city,
    );
  }

  static List<String> buildSearchKeywords(List<String> values) {
    final keywords = <String>{};
    for (final value in values) {
      final normalized = normalizeText(value);
      if (normalized.isEmpty) continue;
      keywords.add(normalized);
      for (final token in normalized.split(RegExp(r'[\s\-_/]+'))) {
        if (token.isEmpty) continue;
        keywords.add(token);
        for (var i = 1; i <= token.length && i <= 20; i++) {
          keywords.add(token.substring(0, i));
        }
      }
    }
    return keywords.toList(growable: false)..sort();
  }

  static String normalizeText(String value) => value.trim().toLowerCase();

  static String normalizePhone(String value) {
    final digits = value.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.startsWith('00962')) return '0${digits.substring(5)}';
    if (digits.startsWith('962')) return '0${digits.substring(3)}';
    return digits;
  }

  static String _readString(
    Map<String, dynamic> data,
    String key, {
    String fallback = '',
  }) {
    final value = data[key];
    return value is String ? value.trim() : fallback;
  }

  static bool _readBool(
    Map<String, dynamic> data,
    String key, {
    bool fallback = false,
  }) {
    final value = data[key];
    return value is bool ? value : fallback;
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
}
