import 'package:cloud_firestore/cloud_firestore.dart';

class AppUserModel {
  const AppUserModel({
    required this.uid,
    required this.name,
    required this.email,
    required this.role,
    required this.active,
    required this.createdAt,
    this.age,
    this.phone,
    this.phoneVerified = false,
  });

  final String uid;
  final String name;
  final String email;
  final String role;
  final bool active;
  final DateTime createdAt;
  final int? age;
  final String? phone;
  final bool phoneVerified;

  factory AppUserModel.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data();
    if (data == null) {
      throw const FormatException('User document has no data.');
    }

    final name = data['name'];
    final email = data['email'];
    final role = data['role'];
    final active = data['active'];
    final createdAt = data['createdAt'];
    final age = data['age'];
    final phone = data['phone'];
    final phoneVerified = data['phoneVerified'];

    if (name is! String ||
        name.trim().isEmpty ||
        email is! String ||
        email.trim().isEmpty ||
        role is! String ||
        role.trim().isEmpty ||
        active is! bool ||
        (age != null && age is! num) ||
        (phone != null && phone is! String) ||
        (phoneVerified != null && phoneVerified is! bool) ||
        (createdAt is! Timestamp && createdAt is! DateTime)) {
      throw const FormatException('User document has invalid fields.');
    }

    return AppUserModel(
      uid: document.id,
      name: name.trim(),
      email: email.trim(),
      role: role.trim().toLowerCase(),
      active: active,
      createdAt: createdAt is Timestamp
          ? createdAt.toDate()
          : createdAt as DateTime,
      age: age is num ? age.toInt() : null,
      phone: phone is String ? phone.trim() : null,
      phoneVerified: phoneVerified is bool ? phoneVerified : false,
    );
  }
}
