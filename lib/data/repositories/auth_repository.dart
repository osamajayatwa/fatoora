import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fatoora/data/models/app_user_model.dart';
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

  Future<UserCredential> signIn({
    required String email,
    required String password,
  }) => _firebaseAuth.signInWithEmailAndPassword(
    email: email,
    password: password,
  );

  Future<UserCredential> registerViewer({
    required String name,
    required String email,
    required int age,
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
      await _firestore.collection('users').doc(user.uid).set({
        'name': name,
        'email': email,
        'age': age,
        'phone': phone,
        'phoneVerified': false,
        'role': 'viewer',
        'active': true,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      return credential;
    } catch (_) {
      try {
        await user.delete();
      } catch (_) {}
      rethrow;
    }
  }

  Future<AppUserModel?> getUser(String uid) async {
    final document = await _firestore.collection('users').doc(uid).get();
    if (!document.exists) return null;
    return AppUserModel.fromFirestore(document);
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
