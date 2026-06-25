import 'package:cloud_firestore/cloud_firestore.dart';

class AppUserModel {
  const AppUserModel({
    required this.uid,
    required this.name,
    required this.email,
    required this.phone,
    required this.photoUrl,
    required this.role,
    required this.active,
    required this.approvalStatus,
    required this.companyId,
    required this.createdAt,
    required this.updatedAt,
    this.age,
    this.phoneVerified = false,
  });

  final String uid;
  final String name;
  final String email;
  final String phone;
  final String photoUrl;
  final String role;
  final bool active;
  final String approvalStatus;
  final String companyId;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int? age;
  final bool phoneVerified;

  bool get isAdmin => role == 'admin';
  bool get isSalesRep => role == 'sales_rep';
  bool get isPending =>
      role == 'pending_sales_rep' || approvalStatus == 'pending';
  bool get isApproved => approvalStatus == 'approved';
  bool get isRejected => approvalStatus == 'rejected';
  bool get hasValidName =>
      name.trim().isNotEmpty && name.trim().toLowerCase() != 'undefined';
  bool get canAccessApp => active && isApproved && (isAdmin || isSalesRep);

  factory AppUserModel.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) {
    return AppUserModel.fromMap(
      document.data() ?? const {},
      fallbackUid: document.id,
    );
  }

  factory AppUserModel.fromMap(
    Map<String, dynamic> data, {
    String fallbackUid = '',
  }) {
    final rawUid = _readString(data, 'uid', fallback: fallbackUid);
    final uid = rawUid.isEmpty ? fallbackUid : rawUid;
    final role = _normalizeRole(_readString(data, 'role'));
    final active = _readBool(data, 'active');
    final approvalStatus = _normalizeApprovalStatus(
      _readString(data, 'approvalStatus'),
      role: role,
      active: active,
    );

    return AppUserModel(
      uid: uid,
      name: _cleanName(_readString(data, 'name')),
      email: _readString(data, 'email'),
      phone: _readString(data, 'phone'),
      photoUrl: _readString(data, 'photoUrl'),
      role: role,
      active: active,
      approvalStatus: approvalStatus,
      companyId: _readString(data, 'companyId', fallback: 'default_company'),
      createdAt: _readDate(data, 'createdAt'),
      updatedAt: _readDate(data, 'updatedAt'),
      age: _readInt(data, 'age'),
      phoneVerified: _readBool(data, 'phoneVerified'),
    );
  }

  Map<String, dynamic> toMap() => {
    'uid': uid,
    'name': name.trim(),
    'email': email.trim(),
    'phone': phone.trim(),
    'photoUrl': photoUrl.trim(),
    'role': role,
    'active': active,
    'approvalStatus': approvalStatus,
    'companyId': companyId.trim().isEmpty ? 'default_company' : companyId,
    'createdAt': Timestamp.fromDate(createdAt),
    'updatedAt': Timestamp.fromDate(updatedAt),
    if (age != null) 'age': age,
    'phoneVerified': phoneVerified,
  };

  AppUserModel copyWith({
    String? uid,
    String? name,
    String? email,
    String? phone,
    String? photoUrl,
    String? role,
    bool? active,
    String? approvalStatus,
    String? companyId,
    DateTime? createdAt,
    DateTime? updatedAt,
    int? age,
    bool? phoneVerified,
  }) {
    return AppUserModel(
      uid: uid ?? this.uid,
      name: name ?? this.name,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      photoUrl: photoUrl ?? this.photoUrl,
      role: role ?? this.role,
      active: active ?? this.active,
      approvalStatus: approvalStatus ?? this.approvalStatus,
      companyId: companyId ?? this.companyId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      age: age ?? this.age,
      phoneVerified: phoneVerified ?? this.phoneVerified,
    );
  }

  static String _readString(
    Map<String, dynamic> data,
    String key, {
    String fallback = '',
  }) {
    final value = data[key];
    return value is String ? value.trim() : fallback;
  }

  static bool _readBool(Map<String, dynamic> data, String key) {
    final value = data[key];
    return value is bool ? value : false;
  }

  static int? _readInt(Map<String, dynamic> data, String key) {
    final value = data[key];
    if (value is num && value.isFinite) return value.toInt();
    if (value is String) return int.tryParse(value.trim());
    return null;
  }

  static DateTime _readDate(Map<String, dynamic> data, String key) {
    final value = data[key];
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value) ?? DateTime.now();
    return DateTime.now();
  }

  static String _normalizeRole(String value) {
    final role = value.trim().toLowerCase();
    if (role == 'admin' || role == 'sales_rep') return role;
    return 'pending_sales_rep';
  }

  static String _normalizeApprovalStatus(
    String value, {
    required String role,
    required bool active,
  }) {
    final status = value.trim().toLowerCase();
    if (status == 'approved' || status == 'pending' || status == 'rejected') {
      return status;
    }
    if ((role == 'admin' || role == 'sales_rep') && active) return 'approved';
    return 'pending';
  }

  static String _cleanName(String value) {
    final name = value.trim();
    return name.toLowerCase() == 'undefined' ? '' : name;
  }
}
