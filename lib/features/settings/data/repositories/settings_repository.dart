import 'dart:async';
import 'package:fatoora/core/firebase/pending_posting_keys.dart';
import 'package:fatoora/core/firebase/trusted_callable_client.dart';
import 'package:fatoora/features/settings/data/models/accounting_configuration_model.dart';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fatoora/features/auth/data/models/app_user_model.dart';
import 'package:fatoora/features/settings/data/models/app_settings_model.dart';
import 'package:fatoora/features/settings/data/models/user_preferences_model.dart';
import 'package:fatoora/features/shared/business/business_user_context.dart';
import 'package:firebase_auth/firebase_auth.dart';

enum SettingsRepositoryError {
  unauthenticated,
  permissionDenied,
  profileMissing,
  invalidData,
  timeout,
  unavailable,
  unknown,
}

class SettingsRepositoryException implements Exception {
  const SettingsRepositoryException(this.error, [this.cause]);

  final SettingsRepositoryError error;
  final Object? cause;
}

class SettingsRepository {
  static const accountingConfigurationEnabled = bool.fromEnvironment(
    'FATOORA_ACCOUNTING_CONFIGURATION',
  );

  Future<AccountingConfigurationSnapshot> accountingConfiguration(
    String bookId, {
    required String companyId,
    Map<String, dynamic>? configuration,
    int? expectedRevision,
  }) async {
    if (!accountingConfigurationEnabled) {
      throw const SettingsRepositoryException(
        SettingsRepositoryError.unavailable,
      );
    }
    final user = await _contextReader.requireApprovedUser();
    if (!user.isAdmin ||
        !user.canUseBusinessData ||
        companyId.isEmpty ||
        companyId != user.companyId ||
        _firestore.app.name != _firebaseAuth.app.name) {
      throw const SettingsRepositoryException(
        SettingsRepositoryError.permissionDenied,
      );
    }
    final payload = <String, dynamic>{
      'action': configuration == null ? 'read' : 'save',
      'companyId': companyId,
      'bookId': bookId,
      if (configuration != null) ...{
        'configuration': configuration,
        'expectedRevision': expectedRevision,
      },
    };
    final key = configuration == null
        ? null
        : await PendingPostingKeys.acquire(
            'accounting_configuration',
            user.uid,
            payload,
          );
    final response =
        await TrustedCallableClient.forDefaultApp(
          firebaseAuth: _firebaseAuth,
        ).callAuthenticated<Map<String, dynamic>>(
          'manageAccountingConfiguration',
          {...payload, if (key != null) 'requestId': key},
        );
    final result = AccountingConfigurationSnapshot.fromMap(
      Map<String, dynamic>.from(response.data),
      companyId: companyId,
      bookId: bookId,
    );
    if (key != null) {
      await PendingPostingKeys.complete(
        'accounting_configuration',
        user.uid,
        payload,
        key,
      );
    }
    return result;
  }

  SettingsRepository({
    FirebaseFirestore? firestore,
    FirebaseAuth? firebaseAuth,
    BusinessUserContextReader? contextReader,
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _firebaseAuth = firebaseAuth ?? FirebaseAuth.instance,
       _contextReader =
           contextReader ??
           BusinessUserContextReader(
             firestore: firestore,
             firebaseAuth: firebaseAuth,
           );

  final FirebaseFirestore _firestore;
  final FirebaseAuth _firebaseAuth;
  final BusinessUserContextReader _contextReader;

  DocumentReference<Map<String, dynamic>> _appSettings(String companyId) {
    return _firestore
        .collection('companies')
        .doc(companyId)
        .collection('settings')
        .doc('app');
  }

  DocumentReference<Map<String, dynamic>> _userPreferences(String uid) {
    return _firestore
        .collection('users')
        .doc(uid)
        .collection('preferences')
        .doc('app');
  }

  DocumentReference<Map<String, dynamic>> _userProfile(String uid) =>
      _firestore.collection('users').doc(uid);

  Future<AppSettingsModel> getAppSettings(String companyId) {
    return _run(() async {
      final user = await _contextReader.requireApprovedUser();
      final resolvedCompanyId = _requireCompany(companyId, user);
      final snapshot = await _appSettings(
        resolvedCompanyId,
      ).get().timeout(const Duration(seconds: 20));
      return AppSettingsModel.fromMap(snapshot.data());
    });
  }

  Stream<AppSettingsModel> watchAppSettings(String companyId) async* {
    final user = await _requireApprovedUser();
    final resolvedCompanyId = _requireCompany(companyId, user);
    yield* _appSettings(
      resolvedCompanyId,
    ).snapshots().map((snapshot) => AppSettingsModel.fromMap(snapshot.data()));
  }

  Future<void> updateAppSettings(AppSettingsModel settings) {
    return _run(() async {
      final user = await _contextReader.requireApprovedUser();
      if (!user.isAdmin) {
        throw const SettingsRepositoryException(
          SettingsRepositoryError.permissionDenied,
        );
      }
      final companyId = _requireCompany(user.companyId, user);
      final normalized = settings.copyWith(
        schemaVersion: settings.schemaVersion < 1 ? 1 : settings.schemaVersion,
        updatedAt: DateTime.now(),
        updatedByUid: user.uid,
        updatedByName: user.name,
      );
      await _appSettings(companyId)
          .set({
            ...normalized.toMap(),
            'updatedAt': FieldValue.serverTimestamp(),
            'updatedByUid': user.uid,
            'updatedByName': user.name,
          })
          .timeout(const Duration(seconds: 20));
    });
  }

  Future<UserPreferencesModel> getUserPreferences(String uid) {
    return _run(() async {
      await _requireOwnUser(uid);
      final snapshot = await _userPreferences(
        uid,
      ).get().timeout(const Duration(seconds: 20));
      return UserPreferencesModel.fromMap(snapshot.data());
    });
  }

  Stream<UserPreferencesModel> watchUserPreferences(String uid) async* {
    await _requireOwnUser(uid);
    yield* _userPreferences(uid).snapshots().map(
      (snapshot) => UserPreferencesModel.fromMap(snapshot.data()),
    );
  }

  Future<void> updateUserPreferences(
    String uid,
    UserPreferencesModel preferences,
  ) {
    return _run(() async {
      await _requireOwnUser(uid);
      final normalized = preferences.copyWith(updatedAt: DateTime.now());
      await _userPreferences(uid)
          .set({
            ...normalized.toMap(),
            'updatedAt': FieldValue.serverTimestamp(),
          })
          .timeout(const Duration(seconds: 20));
    });
  }

  Future<AppUserModel> getCurrentUserProfile() {
    return _run(() async {
      final user = await _contextReader.requireApprovedUser();
      final snapshot = await _userProfile(
        user.uid,
      ).get().timeout(const Duration(seconds: 20));
      if (!snapshot.exists) {
        throw const SettingsRepositoryException(
          SettingsRepositoryError.profileMissing,
        );
      }
      return AppUserModel.fromFirestore(snapshot);
    });
  }

  Future<void> updateSafeUserProfileFields({
    required String uid,
    required String name,
    required String phone,
    required String photoUrl,
  }) {
    return _run(() async {
      await _requireOwnUser(uid);
      final safeName = name.trim();
      if (safeName.length < 2 || safeName.toLowerCase() == 'undefined') {
        throw const SettingsRepositoryException(
          SettingsRepositoryError.invalidData,
        );
      }
      await _userProfile(uid)
          .update({
            'name': safeName,
            'phone': phone.trim(),
            'photoUrl': photoUrl.trim(),
            'updatedAt': FieldValue.serverTimestamp(),
          })
          .timeout(const Duration(seconds: 20));
    });
  }

  Future<BusinessUserContext> _requireApprovedUser() async {
    try {
      return await _contextReader.requireApprovedUser();
    } on BusinessUserContextException catch (error) {
      throw SettingsRepositoryException(_mapContextError(error.error), error);
    }
  }

  Future<BusinessUserContext> _requireOwnUser(String uid) async {
    final user = await _requireApprovedUser();
    final authUid = _firebaseAuth.currentUser?.uid ?? '';
    if (uid.trim().isEmpty || uid != user.uid || uid != authUid) {
      throw const SettingsRepositoryException(
        SettingsRepositoryError.permissionDenied,
      );
    }
    return user;
  }

  String _requireCompany(String requested, BusinessUserContext user) {
    final companyId = requested.trim().isEmpty ? user.companyId : requested;
    if (companyId != user.companyId) {
      throw const SettingsRepositoryException(
        SettingsRepositoryError.permissionDenied,
      );
    }
    return companyId;
  }

  Future<T> _run<T>(Future<T> Function() operation) async {
    try {
      return await operation();
    } on SettingsRepositoryException {
      rethrow;
    } on BusinessUserContextException catch (error) {
      throw SettingsRepositoryException(_mapContextError(error.error), error);
    } on TimeoutException catch (error) {
      throw SettingsRepositoryException(SettingsRepositoryError.timeout, error);
    } on FirebaseAuthException catch (error) {
      throw SettingsRepositoryException(
        error.code == 'permission-denied'
            ? SettingsRepositoryError.permissionDenied
            : SettingsRepositoryError.unauthenticated,
        error,
      );
    } on FirebaseException catch (error) {
      final mapped = switch (error.code) {
        'permission-denied' => SettingsRepositoryError.permissionDenied,
        'unauthenticated' => SettingsRepositoryError.unauthenticated,
        'unavailable' => SettingsRepositoryError.unavailable,
        'deadline-exceeded' => SettingsRepositoryError.timeout,
        _ => SettingsRepositoryError.unknown,
      };
      throw SettingsRepositoryException(mapped, error);
    } catch (error) {
      throw SettingsRepositoryException(SettingsRepositoryError.unknown, error);
    }
  }

  static SettingsRepositoryError _mapContextError(
    BusinessUserContextError error,
  ) {
    return switch (error) {
      BusinessUserContextError.unauthenticated =>
        SettingsRepositoryError.unauthenticated,
      BusinessUserContextError.profileMissing =>
        SettingsRepositoryError.profileMissing,
      BusinessUserContextError.permissionDenied =>
        SettingsRepositoryError.permissionDenied,
      BusinessUserContextError.invalidProfile =>
        SettingsRepositoryError.invalidData,
      BusinessUserContextError.timeout => SettingsRepositoryError.timeout,
    };
  }
}
