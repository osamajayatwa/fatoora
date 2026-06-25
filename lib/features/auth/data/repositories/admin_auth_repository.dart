import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fatoora/features/auth/data/models/app_user_model.dart';
import 'package:fatoora/features/auth/data/repositories/auth_repository.dart';
import 'package:firebase_auth/firebase_auth.dart';

class AdminAuthRepository extends AuthRepository {
  AdminAuthRepository({super.firebaseAuth, super.firestore, super.googleSignIn})
    : _firebaseAuth = firebaseAuth ?? FirebaseAuth.instance,
      _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseAuth _firebaseAuth;
  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _users =>
      _firestore.collection('users');

  Stream<List<AppUserModel>> watchPendingUsers() {
    return _users
        .where('approvalStatus', isEqualTo: AuthRepository.approvalPending)
        .snapshots()
        .map(
          (snapshot) => _sortNewestFirst(
            _filterDefaultCompany(
              snapshot.docs.map(AppUserModel.fromFirestore),
            ).where((user) => user.isPending),
          ),
        );
  }

  Future<List<AppUserModel>> fetchPendingUsers() async {
    final snapshot = await _users
        .where('approvalStatus', isEqualTo: AuthRepository.approvalPending)
        .get()
        .timeout(const Duration(seconds: 20));
    return _sortNewestFirst(
      _filterDefaultCompany(
        snapshot.docs.map(AppUserModel.fromFirestore),
      ).where((user) => user.isPending),
    );
  }

  Future<List<AppUserModel>> fetchSalesReps() async {
    final snapshot = await _users
        .where('role', isEqualTo: AuthRepository.salesRepRole)
        .get()
        .timeout(const Duration(seconds: 20));
    final users = _filterDefaultCompany(
      snapshot.docs.map(AppUserModel.fromFirestore),
    ).toList(growable: false);
    users.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return users;
  }

  Future<void> approveSalesRep(String uid) {
    final adminUid = _requireAdminUid();
    return _users
        .doc(uid)
        .update({
          'role': AuthRepository.salesRepRole,
          'active': true,
          'approvalStatus': AuthRepository.approvalApproved,
          'companyId': AuthRepository.defaultCompanyId,
          'approvedAt': FieldValue.serverTimestamp(),
          'approvedByUid': adminUid,
          'updatedAt': FieldValue.serverTimestamp(),
        })
        .timeout(const Duration(seconds: 20));
  }

  Future<void> rejectSalesRep(String uid) {
    final adminUid = _requireAdminUid();
    return _users
        .doc(uid)
        .update({
          'role': AuthRepository.pendingSalesRepRole,
          'active': false,
          'approvalStatus': AuthRepository.approvalRejected,
          'companyId': AuthRepository.defaultCompanyId,
          'rejectedAt': FieldValue.serverTimestamp(),
          'rejectedByUid': adminUid,
          'updatedAt': FieldValue.serverTimestamp(),
        })
        .timeout(const Duration(seconds: 20));
  }

  Future<void> updateSalesRep({
    required String uid,
    required String name,
    required String phone,
  }) {
    final safeName = name.trim();
    if (safeName.isEmpty || safeName.toLowerCase() == 'undefined') {
      throw const FormatException('A valid sales rep name is required.');
    }
    return _users
        .doc(uid)
        .update({
          'name': safeName,
          'phone': phone.trim(),
          'updatedAt': FieldValue.serverTimestamp(),
        })
        .timeout(const Duration(seconds: 20));
  }

  Future<void> deactivateSalesRep(String uid) {
    return _users
        .doc(uid)
        .update({'active': false, 'updatedAt': FieldValue.serverTimestamp()})
        .timeout(const Duration(seconds: 20));
  }

  Future<void> activateSalesRep(String uid) {
    return _users
        .doc(uid)
        .update({
          'role': AuthRepository.salesRepRole,
          'active': true,
          'approvalStatus': AuthRepository.approvalApproved,
          'companyId': AuthRepository.defaultCompanyId,
          'updatedAt': FieldValue.serverTimestamp(),
        })
        .timeout(const Duration(seconds: 20));
  }

  String _requireAdminUid() {
    final uid = _firebaseAuth.currentUser?.uid;
    if (uid == null || uid.isEmpty) {
      throw FirebaseAuthException(code: 'unauthenticated');
    }
    return uid;
  }

  Iterable<AppUserModel> _filterDefaultCompany(Iterable<AppUserModel> users) {
    return users.where(
      (user) => user.companyId == AuthRepository.defaultCompanyId,
    );
  }

  List<AppUserModel> _sortNewestFirst(Iterable<AppUserModel> users) {
    final sorted = users.toList(growable: false)
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return sorted;
  }
}
