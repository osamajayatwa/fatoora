import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fatoora/data/models/app_user_model.dart';
import 'package:firebase_auth/firebase_auth.dart';

class AdminAuthRepository {
  AdminAuthRepository({
    FirebaseAuth? firebaseAuth,
    FirebaseFirestore? firestore,
  }) : _firebaseAuth = firebaseAuth ?? FirebaseAuth.instance,
       _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseAuth _firebaseAuth;
  final FirebaseFirestore _firestore;

  Future<UserCredential> signIn({
    required String email,
    required String password,
  }) {
    return _firebaseAuth.signInWithEmailAndPassword(
      email: email,
      password: password,
    );
  }

  Future<AppUserModel?> getUser(String uid) async {
    final document = await _firestore.collection('users').doc(uid).get();
    if (!document.exists) return null;
    return AppUserModel.fromFirestore(document);
  }

  Future<void> signOut() => _firebaseAuth.signOut();
}
