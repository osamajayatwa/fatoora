import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:fatoora/core/data/firestore_query_pager.dart';
import 'package:fatoora/core/firebase/trusted_callable_client.dart';
import 'package:fatoora/core/settings/business_settings_defaults.dart';
import 'package:fatoora/features/auth/data/models/app_user_model.dart';
import 'package:fatoora/features/auth/data/repositories/auth_repository.dart';
import 'package:fatoora/features/items/data/models/item_model.dart';
import 'package:fatoora/features/rep_inventory/data/models/inventory_transfer_model.dart';
import 'package:fatoora/features/rep_inventory/data/models/rep_inventory_balance_model.dart';
import 'package:fatoora/features/rep_inventory/data/models/rep_inventory_enums.dart';
import 'package:fatoora/features/rep_inventory/data/models/rep_inventory_movement_model.dart';
import 'package:fatoora/features/shared/business/business_user_context.dart';
import 'package:firebase_auth/firebase_auth.dart';

enum RepInventoryRepositoryError {
  unauthenticated,
  permissionDenied,
  unavailable,
  timeout,
  notFound,
  invalidData,
  invalidRepresentative,
  inactiveRepresentative,
  untrackedItem,
  invalidQuantity,
  duplicateItem,
  emptyTransfer,
  tooManyLines,
  insufficientWarehouseStock,
  insufficientRepStock,
  alreadyConfirmed,
  notEditable,
  concurrentUpdate,
  unknown,
}

class RepInventoryRepositoryException implements Exception {
  const RepInventoryRepositoryException(this.error, [this.cause]);

  final RepInventoryRepositoryError error;
  final Object? cause;
}

class RepInventoryRepository {
  RepInventoryRepository({
    FirebaseFirestore? firestore,
    FirebaseFunctions? functions,
    FirebaseAuth? firebaseAuth,
    BusinessUserContextReader? contextReader,
    TrustedCallableClient? trustedCallableClient,
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _trustedCallableClient =
           trustedCallableClient ??
           TrustedCallableClient.forDefaultApp(
             firebaseAuth: firebaseAuth,
             functions: functions,
           ),
       _contextReader =
           contextReader ??
           BusinessUserContextReader(
             firestore: firestore,
             firebaseAuth: firebaseAuth,
           );

  static const int maxTransferLines = 100;
  static const String transferPrefix = 'TRN';

  final FirebaseFirestore _firestore;
  final TrustedCallableClient _trustedCallableClient;
  final BusinessUserContextReader _contextReader;

  CollectionReference<Map<String, dynamic>> get _items =>
      _firestore.collection('items');
  CollectionReference<Map<String, dynamic>> get _users =>
      _firestore.collection('users');

  CollectionReference<Map<String, dynamic>> _transfers(String companyId) =>
      _firestore
          .collection('companies')
          .doc(companyId)
          .collection('inventory_transfers');

  CollectionReference<Map<String, dynamic>> _balances(String companyId) =>
      _firestore
          .collection('companies')
          .doc(companyId)
          .collection('rep_inventory_balances');

  CollectionReference<Map<String, dynamic>> _repMovements(String companyId) =>
      _firestore
          .collection('companies')
          .doc(companyId)
          .collection('rep_inventory_movements');

  DocumentReference<Map<String, dynamic>> _counter(
    String companyId,
    int year,
  ) => _firestore
      .collection('companies')
      .doc(companyId)
      .collection('counters')
      .doc('inventory_transfers_$year');

  Future<List<AppUserModel>> fetchApprovedSalesReps({
    String companyId = AuthRepository.defaultCompanyId,
  }) {
    return _run(() async {
      final user = await _contextReader.requireApprovedUser();
      final resolvedCompanyId = _resolveCompanyId(companyId, user);
      if (!user.isAdmin) {
        throw const RepInventoryRepositoryException(
          RepInventoryRepositoryError.permissionDenied,
        );
      }
      final documents = await _users
          .where('role', isEqualTo: AuthRepository.salesRepRole)
          .orderBy(FieldPath.documentId)
          .getAllPages();
      final reps =
          documents
              .map(AppUserModel.fromFirestore)
              .where(
                (rep) =>
                    rep.companyId == resolvedCompanyId &&
                    rep.active &&
                    rep.isApproved,
              )
              .toList(growable: false)
            ..sort(
              (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
            );
      return reps;
    });
  }

  Future<List<ItemModel>> fetchTrackedItems() {
    return _run(() async {
      await _contextReader.requireApprovedUser();
      final documents = await _items
          .where('deleted', isEqualTo: false)
          .orderBy(FieldPath.documentId)
          .getAllPages();
      final items =
          documents
              .map(ItemModel.fromFirestore)
              .where((item) => item.active && item.trackStock)
              .toList(growable: false)
            ..sort(
              (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
            );
      return items;
    });
  }

  Future<List<InventoryTransferModel>> fetchTransfers({
    String companyId = AuthRepository.defaultCompanyId,
    String salesRepId = '',
    InventoryTransferType? type,
    InventoryTransferStatus? status,
    DateTime? fromDate,
    DateTime? toDate,
    String searchText = '',
    int pageSize = 200,
  }) {
    return _run(() async {
      final user = await _contextReader.requireApprovedUser();
      final resolvedCompanyId = _resolveCompanyId(companyId, user);
      final ownerId = user.isSalesRep ? user.uid : salesRepId.trim();
      Query<Map<String, dynamic>> query = _transfers(resolvedCompanyId);
      if (ownerId.isNotEmpty) {
        query = query.where('salesRepId', isEqualTo: ownerId);
      }
      if (type != null) query = query.where('type', isEqualTo: type.value);
      if (status != null) {
        query = query.where('status', isEqualTo: status.value);
      }
      if (fromDate != null) {
        query = query.where(
          'createdAt',
          isGreaterThanOrEqualTo: Timestamp.fromDate(_startOfDay(fromDate)),
        );
      }
      if (toDate != null) {
        query = query.where(
          'createdAt',
          isLessThanOrEqualTo: Timestamp.fromDate(_endOfDay(toDate)),
        );
      }
      final documents = await query
          .orderBy('createdAt', descending: true)
          .orderBy(FieldPath.documentId, descending: true)
          .getAllPages(pageSize: pageSize);
      final search = searchText.trim().toLowerCase();
      return documents
          .map(InventoryTransferModel.fromFirestore)
          .where((transfer) {
            if (!user.isAdmin && transfer.salesRepId != user.uid) return false;
            if (type != null && transfer.type != type) return false;
            if (status != null && transfer.status != status) return false;
            if (fromDate != null &&
                transfer.createdAt.isBefore(_startOfDay(fromDate))) {
              return false;
            }
            if (toDate != null &&
                transfer.createdAt.isAfter(_endOfDay(toDate))) {
              return false;
            }
            if (search.isEmpty) return true;
            return transfer.transferNumber.toLowerCase().contains(search) ||
                transfer.salesRepNameSnapshot.toLowerCase().contains(search) ||
                transfer.lines.any(
                  (line) =>
                      line.modelSnapshot.toLowerCase().contains(search) ||
                      line.itemNameSnapshot.toLowerCase().contains(search),
                );
          })
          .toList(growable: false);
    });
  }

  Future<InventoryTransferModel?> getTransfer({
    String companyId = AuthRepository.defaultCompanyId,
    required String transferId,
  }) {
    return _run(() async {
      final user = await _contextReader.requireApprovedUser();
      final resolvedCompanyId = _resolveCompanyId(companyId, user);
      final snapshot = await _transfers(
        resolvedCompanyId,
      ).doc(transferId).get().timeout(const Duration(seconds: 20));
      if (!snapshot.exists) return null;
      final transfer = InventoryTransferModel.fromFirestore(snapshot);
      if (!user.isAdmin && transfer.salesRepId != user.uid) {
        throw const RepInventoryRepositoryException(
          RepInventoryRepositoryError.permissionDenied,
        );
      }
      return transfer;
    });
  }

  Future<List<RepInventoryBalanceModel>> fetchBalances({
    String companyId = AuthRepository.defaultCompanyId,
    String salesRepId = '',
    int pageSize = 700,
  }) {
    return _run(() async {
      final user = await _contextReader.requireApprovedUser();
      final resolvedCompanyId = _resolveCompanyId(companyId, user);
      final ownerId = user.isSalesRep ? user.uid : salesRepId.trim();
      if (ownerId.isEmpty) {
        throw const RepInventoryRepositoryException(
          RepInventoryRepositoryError.invalidRepresentative,
        );
      }
      final documents = await _balances(resolvedCompanyId)
          .where('salesRepId', isEqualTo: ownerId)
          .orderBy('updatedAt', descending: true)
          .orderBy(FieldPath.documentId, descending: true)
          .getAllPages(pageSize: pageSize);
      return documents
          .map(RepInventoryBalanceModel.fromFirestore)
          .where((balance) => balance.quantity > 0)
          .toList(growable: false);
    });
  }

  Future<List<RepInventoryMovementModel>> fetchMovements({
    String companyId = AuthRepository.defaultCompanyId,
    String salesRepId = '',
    String itemId = '',
    int pageSize = 150,
  }) {
    return _run(() async {
      final user = await _contextReader.requireApprovedUser();
      final resolvedCompanyId = _resolveCompanyId(companyId, user);
      final ownerId = user.isSalesRep ? user.uid : salesRepId.trim();
      if (ownerId.isEmpty) {
        throw const RepInventoryRepositoryException(
          RepInventoryRepositoryError.invalidRepresentative,
        );
      }
      Query<Map<String, dynamic>> query = _repMovements(
        resolvedCompanyId,
      ).where('salesRepId', isEqualTo: ownerId);
      if (itemId.trim().isNotEmpty) {
        query = query.where('itemId', isEqualTo: itemId.trim());
      }
      final documents = await query
          .orderBy('createdAt', descending: true)
          .orderBy(FieldPath.documentId, descending: true)
          .getAllPages(pageSize: pageSize);
      return documents
          .map(RepInventoryMovementModel.fromFirestore)
          .where(
            (movement) => itemId.trim().isEmpty || movement.itemId == itemId,
          )
          .toList(growable: false);
    });
  }

  Future<InventoryTransferModel> saveDraft({
    String companyId = AuthRepository.defaultCompanyId,
    String transferId = '',
    required InventoryTransferType type,
    required String salesRepId,
    required List<InventoryTransferLine> lines,
    String notes = '',
  }) {
    return _run(() async {
      final user = await _requireAdmin(companyId);
      final resolvedCompanyId = _resolveCompanyId(companyId, user);
      _validateInputLines(lines);
      final validationSnapshots = await Future.wait([
        _users
            .doc(salesRepId.trim())
            .get(const GetOptions(source: Source.server)),
        ...lines.map(
          (line) => _items
              .doc(line.itemId.trim())
              .get(const GetOptions(source: Source.server)),
        ),
      ]).timeout(const Duration(seconds: 20));
      final rep = _validRep(validationSnapshots.first, resolvedCompanyId);
      final normalizedLines = <InventoryTransferLine>[];
      for (var index = 0; index < lines.length; index++) {
        final input = lines[index];
        final item = _trackedItem(validationSnapshots[index + 1]);
        normalizedLines.add(
          InventoryTransferLine(
            itemId: item.id,
            modelSnapshot: item.code,
            itemNameSnapshot: item.name,
            unitSnapshot: item.unit,
            quantity: _round(input.quantity),
          ),
        );
      }
      final transferRef = transferId.trim().isEmpty
          ? _transfers(resolvedCompanyId).doc()
          : _transfers(resolvedCompanyId).doc(transferId.trim());
      late InventoryTransferModel saved;
      await _firestore
          .runTransaction((transaction) async {
            final existingSnapshot = await transaction.get(transferRef);
            InventoryTransferModel? existing;
            if (existingSnapshot.exists) {
              existing = InventoryTransferModel.fromFirestore(existingSnapshot);
              if (!existing.isDraft) {
                throw const RepInventoryRepositoryException(
                  RepInventoryRepositoryError.notEditable,
                );
              }
            }
            final now = DateTime.now();
            DocumentReference<Map<String, dynamic>>? counterRef;
            Map<String, dynamic>? counterData;
            var transferNumber = existing?.transferNumber ?? '';
            if (transferNumber.isEmpty) {
              final year = now.year;
              counterRef = _counter(resolvedCompanyId, year);
              final counterSnapshot = await transaction.get(counterRef);
              final current = counterSnapshot.data()?['lastNumber'];
              final next = current is num ? current.toInt() + 1 : 1;
              transferNumber = BusinessSettingsDefaults.documentNumber(
                prefix: transferPrefix,
                year: year,
                sequence: next,
              );
              counterData = {
                'id': counterRef.id,
                'companyId': resolvedCompanyId,
                'year': year,
                'lastNumber': next,
                'prefix': transferPrefix,
                'updatedAt': FieldValue.serverTimestamp(),
              };
            }
            saved = InventoryTransferModel(
              id: transferRef.id,
              companyId: resolvedCompanyId,
              transferNumber: transferNumber,
              year: existing?.year ?? now.year,
              type: type,
              status: InventoryTransferStatus.draft,
              salesRepId: rep.uid,
              salesRepNameSnapshot: rep.name,
              lines: normalizedLines,
              totalQuantity: _round(
                normalizedLines.fold<double>(
                  0,
                  (total, line) => total + line.quantity,
                ),
              ),
              notes: notes.trim(),
              createdByUid: existing?.createdByUid ?? user.uid,
              createdByName: existing?.createdByName ?? user.name,
              createdAt: existing?.createdAt ?? now,
              updatedAt: now,
              effectsVersion: 1,
            );
            if (counterRef != null && counterData != null) {
              transaction.set(counterRef, counterData, SetOptions(merge: true));
            }
            transaction.set(transferRef, {
              ...saved.toMap(),
              'createdAt': existing == null
                  ? FieldValue.serverTimestamp()
                  : Timestamp.fromDate(existing.createdAt),
              'updatedAt': FieldValue.serverTimestamp(),
            });
          })
          .timeout(const Duration(seconds: 30));
      return saved;
    });
  }

  Future<InventoryTransferModel> confirmTransfer({
    String companyId = AuthRepository.defaultCompanyId,
    required String transferId,
  }) {
    return _run(() async {
      final user = await _requireAdmin(companyId);
      final resolvedCompanyId = _resolveCompanyId(companyId, user);
      final normalizedTransferId = transferId.trim();
      if (normalizedTransferId.isEmpty) {
        throw const RepInventoryRepositoryException(
          RepInventoryRepositoryError.notFound,
        );
      }
      final result = await _trustedCallableClient
          .callAuthenticated<Map<String, dynamic>>('confirmInventoryTransfer', {
            'companyId': resolvedCompanyId,
            'transferId': normalizedTransferId,
          })
          .timeout(const Duration(seconds: 30));
      final confirmedId = result.data['transferId'] as String?;
      if (confirmedId == null || confirmedId != normalizedTransferId) {
        throw const RepInventoryRepositoryException(
          RepInventoryRepositoryError.invalidData,
        );
      }
      final snapshot = await _transfers(resolvedCompanyId)
          .doc(confirmedId)
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 20));
      if (!snapshot.exists) {
        throw const RepInventoryRepositoryException(
          RepInventoryRepositoryError.notFound,
        );
      }
      final confirmed = InventoryTransferModel.fromFirestore(snapshot);
      if (!confirmed.isConfirmed) {
        throw const RepInventoryRepositoryException(
          RepInventoryRepositoryError.concurrentUpdate,
        );
      }
      return confirmed;
    });
  }

  Future<void> cancelDraft({
    String companyId = AuthRepository.defaultCompanyId,
    required String transferId,
  }) {
    return _run(() async {
      final user = await _requireAdmin(companyId);
      final resolvedCompanyId = _resolveCompanyId(companyId, user);
      final ref = _transfers(resolvedCompanyId).doc(transferId);
      await _firestore
          .runTransaction((transaction) async {
            final snapshot = await transaction.get(ref);
            if (!snapshot.exists) {
              throw const RepInventoryRepositoryException(
                RepInventoryRepositoryError.notFound,
              );
            }
            final transfer = InventoryTransferModel.fromFirestore(snapshot);
            if (!transfer.isDraft) {
              throw const RepInventoryRepositoryException(
                RepInventoryRepositoryError.notEditable,
              );
            }
            transaction.update(ref, {
              'status': InventoryTransferStatus.cancelled.value,
              'cancelledByUid': user.uid,
              'cancelledAt': FieldValue.serverTimestamp(),
              'updatedAt': FieldValue.serverTimestamp(),
            });
          })
          .timeout(const Duration(seconds: 20));
    });
  }

  Future<void> deleteDraft({
    String companyId = AuthRepository.defaultCompanyId,
    required String transferId,
  }) {
    return _run(() async {
      final user = await _requireAdmin(companyId);
      final resolvedCompanyId = _resolveCompanyId(companyId, user);
      final ref = _transfers(resolvedCompanyId).doc(transferId.trim());
      await _firestore
          .runTransaction((transaction) async {
            final snapshot = await transaction.get(ref);
            if (!snapshot.exists) {
              throw const RepInventoryRepositoryException(
                RepInventoryRepositoryError.notFound,
              );
            }
            if (!InventoryTransferModel.fromFirestore(snapshot).isDraft) {
              throw const RepInventoryRepositoryException(
                RepInventoryRepositoryError.notEditable,
              );
            }
            transaction.delete(ref);
          })
          .timeout(const Duration(seconds: 20));
    });
  }

  Future<BusinessUserContext> _requireAdmin(String companyId) async {
    final user = await _contextReader.requireApprovedUser();
    _resolveCompanyId(companyId, user);
    if (!user.isAdmin) {
      throw const RepInventoryRepositoryException(
        RepInventoryRepositoryError.permissionDenied,
      );
    }
    return user;
  }

  AppUserModel _validRep(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
    String companyId,
  ) {
    if (!snapshot.exists) {
      throw const RepInventoryRepositoryException(
        RepInventoryRepositoryError.invalidRepresentative,
      );
    }
    final rep = AppUserModel.fromFirestore(snapshot);
    if (!rep.isSalesRep || rep.companyId != companyId) {
      throw const RepInventoryRepositoryException(
        RepInventoryRepositoryError.invalidRepresentative,
      );
    }
    if (!rep.active || !rep.isApproved) {
      throw const RepInventoryRepositoryException(
        RepInventoryRepositoryError.inactiveRepresentative,
      );
    }
    return rep;
  }

  ItemModel _trackedItem(DocumentSnapshot<Map<String, dynamic>> snapshot) {
    if (!snapshot.exists) {
      throw const RepInventoryRepositoryException(
        RepInventoryRepositoryError.notFound,
      );
    }
    final item = ItemModel.fromFirestore(snapshot);
    if (item.deleted || !item.active || !item.trackStock) {
      throw const RepInventoryRepositoryException(
        RepInventoryRepositoryError.untrackedItem,
      );
    }
    return item;
  }

  void _validateInputLines(List<InventoryTransferLine> lines) {
    if (lines.isEmpty) {
      throw const RepInventoryRepositoryException(
        RepInventoryRepositoryError.emptyTransfer,
      );
    }
    if (lines.length > maxTransferLines) {
      throw const RepInventoryRepositoryException(
        RepInventoryRepositoryError.tooManyLines,
      );
    }
    final ids = <String>{};
    for (final line in lines) {
      if (line.itemId.trim().isEmpty) {
        throw const RepInventoryRepositoryException(
          RepInventoryRepositoryError.invalidData,
        );
      }
      if (!ids.add(line.itemId.trim())) {
        throw const RepInventoryRepositoryException(
          RepInventoryRepositoryError.duplicateItem,
        );
      }
      final quantity = _round(line.quantity);
      if (!quantity.isFinite || quantity <= 0) {
        throw const RepInventoryRepositoryException(
          RepInventoryRepositoryError.invalidQuantity,
        );
      }
    }
  }

  String _resolveCompanyId(String requested, BusinessUserContext user) {
    final companyId = requested.trim().isEmpty
        ? AuthRepository.defaultCompanyId
        : requested.trim();
    if (companyId != user.companyId) {
      throw const RepInventoryRepositoryException(
        RepInventoryRepositoryError.permissionDenied,
      );
    }
    return companyId;
  }

  DateTime _startOfDay(DateTime value) =>
      DateTime(value.year, value.month, value.day);
  DateTime _endOfDay(DateTime value) =>
      DateTime(value.year, value.month, value.day, 23, 59, 59, 999);
  double _round(double value) => (value * 1000).roundToDouble() / 1000;

  Future<T> _run<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on RepInventoryRepositoryException {
      rethrow;
    } on BusinessUserContextException catch (error) {
      throw RepInventoryRepositoryException(switch (error.error) {
        BusinessUserContextError.unauthenticated ||
        BusinessUserContextError.profileMissing =>
          RepInventoryRepositoryError.unauthenticated,
        BusinessUserContextError.permissionDenied =>
          RepInventoryRepositoryError.permissionDenied,
        BusinessUserContextError.invalidProfile =>
          RepInventoryRepositoryError.invalidData,
        BusinessUserContextError.timeout => RepInventoryRepositoryError.timeout,
      }, error);
    } on TimeoutException catch (error) {
      throw RepInventoryRepositoryException(
        RepInventoryRepositoryError.timeout,
        error,
      );
    } on FirebaseFunctionsException catch (error) {
      throw RepInventoryRepositoryException(_mapFunctionError(error), error);
    } on FirebaseException catch (error) {
      throw RepInventoryRepositoryException(switch (error.code) {
        'permission-denied' => RepInventoryRepositoryError.permissionDenied,
        'unauthenticated' => RepInventoryRepositoryError.unauthenticated,
        'unavailable' => RepInventoryRepositoryError.unavailable,
        'deadline-exceeded' => RepInventoryRepositoryError.timeout,
        'not-found' => RepInventoryRepositoryError.notFound,
        'aborted' => RepInventoryRepositoryError.concurrentUpdate,
        'failed-precondition' => RepInventoryRepositoryError.concurrentUpdate,
        _ => RepInventoryRepositoryError.unknown,
      }, error);
    } on FormatException catch (error) {
      throw RepInventoryRepositoryException(
        RepInventoryRepositoryError.invalidData,
        error,
      );
    } catch (error) {
      throw RepInventoryRepositoryException(
        RepInventoryRepositoryError.unknown,
        error,
      );
    }
  }

  RepInventoryRepositoryError _mapFunctionError(
    FirebaseFunctionsException error,
  ) {
    final details = error.details;
    final reason = details is Map ? details['reason']?.toString() : null;
    return switch (reason) {
      'insufficient-warehouse-stock' =>
        RepInventoryRepositoryError.insufficientWarehouseStock,
      'insufficient-rep-stock' =>
        RepInventoryRepositoryError.insufficientRepStock,
      'invalid-representative' =>
        RepInventoryRepositoryError.invalidRepresentative,
      'inactive-representative' =>
        RepInventoryRepositoryError.inactiveRepresentative,
      'untracked-item' => RepInventoryRepositoryError.untrackedItem,
      'invalid-quantity' => RepInventoryRepositoryError.invalidQuantity,
      'duplicate-item' => RepInventoryRepositoryError.duplicateItem,
      'not-editable' => RepInventoryRepositoryError.notEditable,
      'already-confirmed' => RepInventoryRepositoryError.alreadyConfirmed,
      'partial-posting' => RepInventoryRepositoryError.concurrentUpdate,
      _ => switch (error.code) {
        'permission-denied' => RepInventoryRepositoryError.permissionDenied,
        'unauthenticated' => RepInventoryRepositoryError.unauthenticated,
        'unavailable' => RepInventoryRepositoryError.unavailable,
        'deadline-exceeded' => RepInventoryRepositoryError.timeout,
        'not-found' => RepInventoryRepositoryError.notFound,
        'aborted' => RepInventoryRepositoryError.concurrentUpdate,
        'failed-precondition' => RepInventoryRepositoryError.notEditable,
        'invalid-argument' => RepInventoryRepositoryError.invalidData,
        _ => RepInventoryRepositoryError.unknown,
      },
    };
  }
}
