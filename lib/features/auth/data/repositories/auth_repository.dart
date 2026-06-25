import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fatoora/features/auth/data/models/app_user_model.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';

class AuthRepository {
  AuthRepository({
    FirebaseAuth? firebaseAuth,
    FirebaseFirestore? firestore,
    GoogleSignIn? googleSignIn,
  }) : _firebaseAuth = firebaseAuth ?? FirebaseAuth.instance,
       _firestore = firestore ?? FirebaseFirestore.instance,
       _googleSignIn = googleSignIn ?? GoogleSignIn(scopes: const ['email']);

  final FirebaseAuth _firebaseAuth;
  final FirebaseFirestore _firestore;
  final GoogleSignIn _googleSignIn;

  static const String defaultCompanyId = 'default_company';
  static const String adminRole = 'admin';
  static const String salesRepRole = 'sales_rep';
  static const String pendingSalesRepRole = 'pending_sales_rep';
  static const String approvalPending = 'pending';
  static const String approvalApproved = 'approved';
  static const String approvalRejected = 'rejected';

  Future<UserCredential> signIn({
    required String email,
    required String password,
  }) => _firebaseAuth.signInWithEmailAndPassword(
    email: email,
    password: password,
  );

  Future<UserCredential> registerPendingSalesRep({
    required String name,
    required String email,
    required String phone,
    required String password,
  }) async {
    final credential = await _firebaseAuth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );

    final user = credential.user;
    if (user == null) {
      throw FirebaseAuthException(code: 'user-not-found');
    }

    try {
      await user.updateDisplayName(name);
      await createPendingSalesRepProfile(
        user,
        fallbackName: name,
        phone: phone,
      );
      return credential;
    } catch (_) {
      try {
        await user.delete();
      } catch (_) {}
      rethrow;
    }
  }

  Future<UserCredential> registerViewer({
    required String name,
    required String email,
    required int age,
    required String phone,
    required String password,
  }) {
    return registerPendingSalesRep(
      name: name,
      email: email,
      phone: phone,
      password: password,
    );
  }

  Future<AppUserModel?> getUser(String uid) async {
    final document = await _firestore.collection('users').doc(uid).get();
    if (!document.exists) return null;
    return AppUserModel.fromFirestore(document);
  }

  Future<AppUserModel> getOrCreatePendingProfile(
    User user, {
    String? fallbackName,
    String phone = '',
  }) async {
    final existing = await getUser(user.uid);
    if (existing != null) return existing;
    await createPendingSalesRepProfile(
      user,
      fallbackName: fallbackName,
      phone: phone,
    );
    final created = await getUser(user.uid);
    if (created == null) {
      throw const FormatException('Pending user profile was not created.');
    }
    return created;
  }

  Future<void> createPendingSalesRepProfile(
    User user, {
    String? fallbackName,
    String phone = '',
  }) {
    final email = user.email?.trim() ?? '';
    final safeName = safeUserName(
      fallbackName,
      displayName: user.displayName,
      email: email,
    );

    return _firestore.collection('users').doc(user.uid).set({
      'uid': user.uid,
      'name': safeName,
      'email': email,
      'phone': phone.trim(),
      'photoUrl': user.photoURL?.trim() ?? '',
      'role': pendingSalesRepRole,
      'active': false,
      'approvalStatus': approvalPending,
      'companyId': defaultCompanyId,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: false));
  }

  String safeUserName(
    String? value, {
    String? displayName,
    required String email,
  }) {
    for (final candidate in [value, displayName]) {
      final trimmed = candidate?.trim() ?? '';
      if (trimmed.isNotEmpty && trimmed.toLowerCase() != 'undefined') {
        return _minimumName(trimmed);
      }
    }

    final prefix = email.split('@').first.trim();
    if (prefix.isNotEmpty && prefix.toLowerCase() != 'undefined') {
      return _minimumName(prefix);
    }
    return 'User';
  }

  String _minimumName(String value) {
    return value.length >= 2 ? value : '$value User';
  }

  Future<UserCredential?> signInWithGoogle() async {
    if (kIsWeb) {
      final provider = GoogleAuthProvider()
        ..setCustomParameters(const {'prompt': 'select_account'});
      return _firebaseAuth.signInWithPopup(provider);
    }

    try {
      final googleUser = await _googleSignIn.signIn();
      if (googleUser == null) return null;
      final googleAuth = await googleUser.authentication;
      return _firebaseAuth.signInWithCredential(
        GoogleAuthProvider.credential(
          accessToken: googleAuth.accessToken,
          idToken: googleAuth.idToken,
        ),
      );
    } on PlatformException catch (error) {
      if (error.code == 'sign_in_canceled') return null;
      throw FirebaseAuthException(code: error.code, message: error.message);
    }
  }

  Future<void> signOut() async {
    await _firebaseAuth.signOut();
    if (!kIsWeb) {
      try {
        await _googleSignIn.signOut();
      } catch (_) {}
    }
  }
}
