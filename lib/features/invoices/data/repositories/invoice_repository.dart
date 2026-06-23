import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:fatoora/features/invoices/data/models/invoice_enums.dart';
import 'package:fatoora/features/invoices/data/models/invoice_model.dart';
import 'package:fatoora/features/invoices/data/services/jofotara_placeholder_service.dart';
import 'package:firebase_auth/firebase_auth.dart';

enum InvoiceRepositoryError {
  unauthenticated,
  permissionDenied,
  unavailable,
  timeout,
  notFound,
  invalidData,
  invalidState,
  locked,
  unknown,
}

class InvoiceRepositoryException implements Exception {
  const InvoiceRepositoryException(this.error, [this.cause]);

  final InvoiceRepositoryError error;
  final Object? cause;
}

class InvoiceRepository {
  InvoiceRepository({
    FirebaseFirestore? firestore,
    FirebaseAuth? firebaseAuth,
    JofotaraPlaceholderService? jofotaraService,
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _firebaseAuth = firebaseAuth ?? FirebaseAuth.instance,
       _jofotaraService = jofotaraService ?? JofotaraPlaceholderService();

  final FirebaseFirestore _firestore;
  final FirebaseAuth _firebaseAuth;
  final JofotaraPlaceholderService _jofotaraService;

  CollectionReference<Map<String, dynamic>> _invoices(String companyId) {
    return _firestore
        .collection('companies')
        .doc(companyId)
        .collection('invoices');
  }

  Future<List<InvoiceModel>> getInvoices({
    required String companyId,
    InvoiceType? type,
    InvoiceStatus? status,
    DateTime? fromDate,
    DateTime? toDate,
    String? searchText,
  }) {
    return _run(() async {
      await _requireUser();
      Query<Map<String, dynamic>> query = _invoices(companyId);
      if (type != null) {
        query = query.where('invoiceType', isEqualTo: type.value);
      }
      if (status != null) {
        query = query.where('invoiceStatus', isEqualTo: status.value);
      }
      if (fromDate != null) {
        query = query.where(
          'invoiceDate',
          isGreaterThanOrEqualTo: Timestamp.fromDate(_startOfDay(fromDate)),
        );
      }
      if (toDate != null) {
        query = query.where(
          'invoiceDate',
          isLessThanOrEqualTo: Timestamp.fromDate(_endOfDay(toDate)),
        );
      }
      final normalizedSearch = _normalize(searchText ?? '');
      if (normalizedSearch.isNotEmpty) {
        query = query.where('searchKeywords', arrayContains: normalizedSearch);
      }
      final snapshot = await query
          .orderBy('invoiceDate', descending: true)
          .limit(150)
          .get()
          .timeout(const Duration(seconds: 20));
      return snapshot.docs.map(InvoiceModel.fromFirestore).toList();
    });
  }

  Stream<List<InvoiceModel>> watchInvoices({
    required String companyId,
    InvoiceType? type,
    InvoiceStatus? status,
  }) {
    Query<Map<String, dynamic>> query = _invoices(companyId);
    if (type != null) query = query.where('invoiceType', isEqualTo: type.value);
    if (status != null) {
      query = query.where('invoiceStatus', isEqualTo: status.value);
    }
    return query
        .orderBy('invoiceDate', descending: true)
        .limit(150)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs.map(InvoiceModel.fromFirestore).toList(),
        );
  }

  Future<InvoiceModel?> getInvoiceById({
    required String companyId,
    required String invoiceId,
  }) {
    return _run(() async {
      await _requireUser();
      final document = await _invoices(
        companyId,
      ).doc(invoiceId).get().timeout(const Duration(seconds: 20));
      if (!document.exists) return null;
      return InvoiceModel.fromFirestore(document);
    });
  }

  Future<String> createInvoice({required InvoiceModel invoice}) {
    return _run(() async {
      final user = await _requireUser();
      final document = invoice.id.trim().isEmpty
          ? _invoices(invoice.companyId).doc()
          : _invoices(invoice.companyId).doc(invoice.id.trim());
      final now = DateTime.now();
      final normalized = invoice
          .copyWith(
            id: document.id,
            createdAt: now,
            updatedAt: now,
            createdByUid: invoice.createdByUid.trim().isEmpty
                ? user.uid
                : invoice.createdByUid,
            createdByName: invoice.createdByName.trim().isEmpty
                ? (user.displayName ?? user.email ?? user.uid)
                : invoice.createdByName,
          )
          .withSearchFields();
      await document
          .set({
            ...normalized.toMap(),
            'createdAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          })
          .timeout(const Duration(seconds: 20));
      return document.id;
    });
  }

  Future<void> updateInvoice({required InvoiceModel invoice}) {
    return _run(() async {
      await _requireUser();
      if (invoice.id.trim().isEmpty || invoice.companyId.trim().isEmpty) {
        throw const InvoiceRepositoryException(
          InvoiceRepositoryError.invalidData,
        );
      }
      final document = _invoices(invoice.companyId).doc(invoice.id);
      await _firestore
          .runTransaction((transaction) async {
            final snapshot = await transaction.get(document);
            if (!snapshot.exists) {
              throw const InvoiceRepositoryException(
                InvoiceRepositoryError.notFound,
              );
            }
            final existing = InvoiceModel.fromFirestore(snapshot);
            if (!existing.canEdit) {
              throw const InvoiceRepositoryException(
                InvoiceRepositoryError.locked,
              );
            }
            final normalized = invoice
                .copyWith(
                  createdAt: existing.createdAt,
                  createdByUid: existing.createdByUid,
                  createdByName: existing.createdByName,
                  updatedAt: DateTime.now(),
                )
                .withSearchFields();
            transaction.update(document, {
              ...normalized.toMap(),
              'createdAt': Timestamp.fromDate(existing.createdAt),
              'updatedAt': FieldValue.serverTimestamp(),
            });
          })
          .timeout(const Duration(seconds: 20));
    });
  }

  Future<void> deleteDraftInvoice({
    required String companyId,
    required String invoiceId,
  }) {
    return _run(() async {
      await _requireUser();
      final document = _invoices(companyId).doc(invoiceId);
      await _firestore
          .runTransaction((transaction) async {
            final snapshot = await transaction.get(document);
            if (!snapshot.exists) {
              throw const InvoiceRepositoryException(
                InvoiceRepositoryError.notFound,
              );
            }
            final invoice = InvoiceModel.fromFirestore(snapshot);
            if (!invoice.canDelete) {
              throw const InvoiceRepositoryException(
                InvoiceRepositoryError.invalidState,
              );
            }
            transaction.delete(document);
          })
          .timeout(const Duration(seconds: 20));
    });
  }

  Future<void> markPendingSubmit({
    required String companyId,
    required String invoiceId,
  }) {
    return _run(() async {
      await _requireUser();
      final document = _invoices(companyId).doc(invoiceId);
      await _firestore
          .runTransaction((transaction) async {
            final snapshot = await transaction.get(document);
            if (!snapshot.exists) {
              throw const InvoiceRepositoryException(
                InvoiceRepositoryError.notFound,
              );
            }
            final invoice = InvoiceModel.fromFirestore(snapshot);
            final canSubmit =
                invoice.invoiceType == InvoiceType.electronic &&
                (invoice.invoiceStatus == InvoiceStatus.draft ||
                    invoice.invoiceStatus == InvoiceStatus.rejected);
            if (!canSubmit) {
              throw const InvoiceRepositoryException(
                InvoiceRepositoryError.invalidState,
              );
            }
            transaction.update(document, {
              'invoiceStatus': InvoiceStatus.pendingSubmit.value,
              'updatedAt': FieldValue.serverTimestamp(),
            });
          })
          .timeout(const Duration(seconds: 20));
    });
  }

  Future<void> submitElectronicInvoicePlaceholder({
    required String companyId,
    required String invoiceId,
  }) {
    return _run(
      () => _jofotaraService
          .submitInvoice(companyId: companyId, invoiceId: invoiceId)
          .timeout(const Duration(seconds: 30)),
    );
  }

  Future<User> _requireUser() async {
    final user =
        _firebaseAuth.currentUser ??
        await _firebaseAuth.authStateChanges().first.timeout(
          const Duration(seconds: 10),
        );
    if (user == null) {
      throw const InvoiceRepositoryException(
        InvoiceRepositoryError.unauthenticated,
      );
    }
    return user;
  }

  Future<T> _run<T>(Future<T> Function() operation) async {
    try {
      return await operation();
    } on InvoiceRepositoryException {
      rethrow;
    } on TimeoutException catch (error) {
      throw InvoiceRepositoryException(InvoiceRepositoryError.timeout, error);
    } on FirebaseFunctionsException catch (error) {
      throw InvoiceRepositoryException(_mapFunctionError(error.code), error);
    } on FirebaseException catch (error) {
      throw InvoiceRepositoryException(_mapFirebaseError(error.code), error);
    } on FormatException catch (error) {
      throw InvoiceRepositoryException(
        InvoiceRepositoryError.invalidData,
        error,
      );
    } catch (error) {
      throw InvoiceRepositoryException(InvoiceRepositoryError.unknown, error);
    }
  }

  InvoiceRepositoryError _mapFirebaseError(String code) {
    return switch (code) {
      'permission-denied' => InvoiceRepositoryError.permissionDenied,
      'unauthenticated' => InvoiceRepositoryError.unauthenticated,
      'unavailable' ||
      'deadline-exceeded' => InvoiceRepositoryError.unavailable,
      'not-found' => InvoiceRepositoryError.notFound,
      'failed-precondition' || 'aborted' => InvoiceRepositoryError.invalidState,
      _ => InvoiceRepositoryError.unknown,
    };
  }

  InvoiceRepositoryError _mapFunctionError(String code) {
    return switch (code) {
      'unauthenticated' => InvoiceRepositoryError.unauthenticated,
      'permission-denied' => InvoiceRepositoryError.permissionDenied,
      'not-found' => InvoiceRepositoryError.notFound,
      'failed-precondition' ||
      'invalid-argument' => InvoiceRepositoryError.invalidState,
      'unavailable' ||
      'deadline-exceeded' => InvoiceRepositoryError.unavailable,
      _ => InvoiceRepositoryError.unknown,
    };
  }

  DateTime _startOfDay(DateTime date) =>
      DateTime(date.year, date.month, date.day);

  DateTime _endOfDay(DateTime date) {
    return DateTime(date.year, date.month, date.day, 23, 59, 59, 999);
  }

  String _normalize(String value) => value.trim().toLowerCase();
}
