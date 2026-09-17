import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fatoora/features/auth/data/models/app_user_model.dart';
import 'package:fatoora/features/auth/data/repositories/auth_repository.dart';
import 'package:firebase_auth/firebase_auth.dart';

class BusinessUserContext {
  const BusinessUserContext({
    required this.uid,
    required this.name,
    required this.email,
    required this.phone,
    required this.role,
    required this.companyId,
    required this.active,
    required this.approvalStatus,
  });

  final String uid;
  final String name;
  final String email;
  final String phone;
  final String role;
  final String companyId;
  final bool active;
  final String approvalStatus;

  bool get isAdmin => role == AuthRepository.adminRole;
  bool get isSalesRep => role == AuthRepository.salesRepRole;
  bool get isApproved => approvalStatus == AuthRepository.approvalApproved;
  bool get canUseBusinessData =>
      active && isApproved && (isAdmin || isSalesRep);
  bool get hasValidName =>
      name.trim().isNotEmpty && name.trim().toLowerCase() != 'undefined';

  factory BusinessUserContext.fromUser(AppUserModel user) {
    return BusinessUserContext(
      uid: user.uid,
      name: user.name.trim(),
      email: user.email,
      phone: user.phone,
      role: user.role,
      companyId: user.companyId.trim().isEmpty
          ? AuthRepository.defaultCompanyId
          : user.companyId,
      active: user.active,
      approvalStatus: user.approvalStatus,
    );
  }
}

enum BusinessUserContextError {
  unauthenticated,
  profileMissing,
  permissionDenied,
  invalidProfile,
  timeout,
}

class BusinessUserContextException implements Exception {
  const BusinessUserContextException(this.error, [this.cause]);

  final BusinessUserContextError error;
  final Object? cause;
}

class BusinessUserContextReader {
  BusinessUserContextReader({
    FirebaseAuth? firebaseAuth,
    FirebaseFirestore? firestore,
    Duration cacheTtl = const Duration(seconds: 30),
  }) : _firebaseAuth = firebaseAuth ?? FirebaseAuth.instance,
       _firestore = firestore ?? FirebaseFirestore.instance,
       _cacheTtl = cacheTtl;

  final FirebaseAuth _firebaseAuth;
  final FirebaseFirestore _firestore;
  final Duration _cacheTtl;

  static final Map<_BusinessContextCacheKey, _CachedBusinessContext> _cache =
      {};
  static final Map<_BusinessContextCacheKey, Future<BusinessUserContext>>
  _inFlight = {};

  static void invalidateCache([String? uid]) {
    if (uid == null) {
      _cache.clear();
      _inFlight.clear();
      return;
    }
    _cache.removeWhere((key, _) => key.uid == uid);
    _inFlight.removeWhere((key, _) => key.uid == uid);
  }

  Future<BusinessUserContext> requireApprovedUser() async {
    try {
      final firebaseUser =
          _firebaseAuth.currentUser ??
          await _firebaseAuth.authStateChanges().first.timeout(
            const Duration(seconds: 10),
          );
      if (firebaseUser == null) {
        throw const BusinessUserContextException(
          BusinessUserContextError.unauthenticated,
        );
      }

      final cacheKey = _BusinessContextCacheKey(_firestore, firebaseUser.uid);
      final now = DateTime.now();
      final cached = _cache[cacheKey];
      if (cached != null && now.difference(cached.loadedAt) < _cacheTtl) {
        return cached.context;
      }
      final pending = _inFlight[cacheKey];
      if (pending != null) return await pending;

      final load = _loadApprovedUser(firebaseUser.uid);
      _inFlight[cacheKey] = load;
      try {
        final context = await load;
        _cache[cacheKey] = _CachedBusinessContext(context, DateTime.now());
        return context;
      } finally {
        _inFlight.remove(cacheKey);
      }
    } on BusinessUserContextException {
      rethrow;
    } on TimeoutException catch (error) {
      throw BusinessUserContextException(
        BusinessUserContextError.timeout,
        error,
      );
    }
  }

  Future<BusinessUserContext> _loadApprovedUser(String uid) async {
    final document = await _firestore
        .collection('users')
        .doc(uid)
        .get()
        .timeout(const Duration(seconds: 15));
    if (!document.exists) {
      throw const BusinessUserContextException(
        BusinessUserContextError.profileMissing,
      );
    }

    final context = BusinessUserContext.fromUser(
      AppUserModel.fromFirestore(document),
    );
    if (!context.canUseBusinessData) {
      throw const BusinessUserContextException(
        BusinessUserContextError.permissionDenied,
      );
    }
    if (!context.hasValidName) {
      throw const BusinessUserContextException(
        BusinessUserContextError.invalidProfile,
      );
    }
    return context;
  }
}

class _BusinessContextCacheKey {
  const _BusinessContextCacheKey(this.firestore, this.uid);

  final FirebaseFirestore firestore;
  final String uid;

  @override
  bool operator ==(Object other) =>
      other is _BusinessContextCacheKey &&
      identical(other.firestore, firestore) &&
      other.uid == uid;

  @override
  int get hashCode => Object.hash(identityHashCode(firestore), uid);
}

class _CachedBusinessContext {
  const _CachedBusinessContext(this.context, this.loadedAt);

  final BusinessUserContext context;
  final DateTime loadedAt;
}
