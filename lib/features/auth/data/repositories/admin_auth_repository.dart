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

  Future<List<AppUserModel>> fetchAdmins() async {
    final snapshot = await _users
        .where('role', isEqualTo: AuthRepository.adminRole)
        .get()
        .timeout(const Duration(seconds: 20));
    final users = _filterDefaultCompany(
      snapshot.docs.map(AppUserModel.fromFirestore),
    ).toList(growable: false);
    users.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return users;
  }

  Future<void> approveSalesRep(String uid) {
    return _setApprovedRole(uid, AuthRepository.salesRepRole);
  }

  Future<void> approveAdmin(String uid) {
    return _setApprovedRole(uid, AuthRepository.adminRole);
  }

  Future<void> promoteToAdmin(String uid) {
    return _setApprovedRole(uid, AuthRepository.adminRole);
  }

  Future<void> demoteToSalesRep(String uid) {
    return _setApprovedRole(uid, AuthRepository.salesRepRole);
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

  Future<void> updateManagedUser({
    required String uid,
    required String name,
    required String phone,
  }) {
    final safeName = name.trim();
    if (safeName.isEmpty || safeName.toLowerCase() == 'undefined') {
      throw const FormatException('A valid sales rep name is required.');
    }
    _requireCanManage(uid);
    return _users
        .doc(uid)
        .update({
          'name': safeName,
          'phone': phone.trim(),
          'updatedAt': FieldValue.serverTimestamp(),
        })
        .timeout(const Duration(seconds: 20));
  }

  Future<void> deactivateUser(String uid) {
    _requireCanManage(uid);
    return _users
        .doc(uid)
        .update({'active': false, 'updatedAt': FieldValue.serverTimestamp()})
        .timeout(const Duration(seconds: 20));
  }

  Future<void> activateUser(String uid) {
    _requireCanManage(uid);
    final userRef = _users.doc(uid);
    return _firestore
        .runTransaction((transaction) async {
          final snapshot = await transaction.get(userRef);
          if (!snapshot.exists) throw StateError('User was not found.');
          final user = AppUserModel.fromFirestore(snapshot);
          if (!user.isAdmin && !user.isSalesRep) {
            throw StateError('Only approved user roles can be activated.');
          }
          transaction.update(userRef, {
            'active': true,
            'approvalStatus': AuthRepository.approvalApproved,
            'companyId': AuthRepository.defaultCompanyId,
            'updatedAt': FieldValue.serverTimestamp(),
          });
        })
        .timeout(const Duration(seconds: 20));
  }

  Future<void> _setApprovedRole(String uid, String role) {
    if (role != AuthRepository.adminRole &&
        role != AuthRepository.salesRepRole) {
      throw ArgumentError.value(role, 'role', 'Unsupported user role.');
    }
    final adminUid = _requireCanManage(uid);
    final userRef = _users.doc(uid);
    return _firestore
        .runTransaction((transaction) async {
          final snapshot = await transaction.get(userRef);
          if (!snapshot.exists) throw StateError('User was not found.');
          final user = AppUserModel.fromFirestore(snapshot);
          if (user.companyId != AuthRepository.defaultCompanyId) {
            throw StateError('User belongs to another company.');
          }
          transaction.update(userRef, {
            'role': role,
            'active': true,
            'approvalStatus': AuthRepository.approvalApproved,
            'companyId': AuthRepository.defaultCompanyId,
            'approvedAt': FieldValue.serverTimestamp(),
            'approvedByUid': adminUid,
            'updatedAt': FieldValue.serverTimestamp(),
          });
        })
        .timeout(const Duration(seconds: 20));
  }

  String _requireCanManage(String uid) {
    final adminUid = _requireAdminUid();
    if (uid.trim().isEmpty) throw ArgumentError.value(uid, 'uid');
    if (uid == adminUid) {
      throw StateError('Admins cannot change their own managed role.');
    }
    return adminUid;
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
