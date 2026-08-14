import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fatoora/core/data/firestore_query_pager.dart';
import 'package:fatoora/core/firebase/trusted_callable_client.dart';
import 'package:fatoora/features/auth/data/repositories/auth_repository.dart';
import 'package:fatoora/features/inventory/data/models/inventory_dashboard_snapshot.dart';
import 'package:fatoora/features/inventory/data/models/stock_movement_model.dart';
import 'package:fatoora/features/items/data/models/item_model.dart';
import 'package:fatoora/features/shared/business/business_user_context.dart';
import 'package:firebase_auth/firebase_auth.dart';

enum InventoryRepositoryError {
  unauthenticated,
  permissionDenied,
  unavailable,
  timeout,
  notFound,
  invalidData,
  insufficientStock,
  unknown,
}

class InventoryRepositoryException implements Exception {
  const InventoryRepositoryException(this.error, [this.cause]);

  final InventoryRepositoryError error;
  final Object? cause;
}

class InventoryRepository {
  InventoryRepository({
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

  final FirebaseFirestore _firestore;
  final TrustedCallableClient _trustedCallableClient;
  final BusinessUserContextReader _contextReader;

  CollectionReference<Map<String, dynamic>> get _items =>
      _firestore.collection('items');

  CollectionReference<Map<String, dynamic>> _stockMovements(String companyId) {
    return _firestore
        .collection('companies')
        .doc(companyId)
        .collection('stock_movements');
  }

  Future<InventoryDashboardSnapshot> fetchDashboard({
    String companyId = AuthRepository.defaultCompanyId,
  }) {
    return _run(() async {
      final user = await _contextReader.requireApprovedUser();
      final resolvedCompanyId = _resolveCompanyId(companyId, user);
      final items = await _fetchItems();
      final trackedItems = items
          .where((item) => item.active && !item.deleted && item.trackStock)
          .toList(growable: false);
      final movements = await fetchStockMovements(
        companyId: resolvedCompanyId,
        pageSize: 20,
      );
      final lowStockItems =
          trackedItems
              .where(
                (item) =>
                    item.currentStock > 0 && item.currentStock <= item.minStock,
              )
              .toList(growable: false)
            ..sort((a, b) => a.currentStock.compareTo(b.currentStock));
      final outOfStockCount = trackedItems
          .where((item) => item.currentStock <= 0)
          .length;
      return InventoryDashboardSnapshot(
        trackedItemCount: trackedItems.length,
        totalStockQuantity: _round(
          trackedItems.fold<double>(
            0,
            (total, item) => total + item.currentStock,
          ),
        ),
        lowStockCount: lowStockItems.length,
        outOfStockCount: outOfStockCount,
        inventoryValue: _round(
          trackedItems.fold<double>(
            0,
            (total, item) => total + (item.currentStock * item.costPrice),
          ),
        ),
        recentMovements: movements.take(20).toList(growable: false),
        lowStockItems: lowStockItems.take(8).toList(growable: false),
      );
    });
  }

  Future<List<StockMovementModel>> fetchStockMovements({
    String companyId = AuthRepository.defaultCompanyId,
    String itemId = '',
    String movementType = '',
    String searchText = '',
    DateTime? fromDate,
    DateTime? toDate,
    int pageSize = 150,
  }) {
    return _run(() async {
      final user = await _contextReader.requireApprovedUser();
      final resolvedCompanyId = _resolveCompanyId(companyId, user);
      Query<Map<String, dynamic>> query = _stockMovements(resolvedCompanyId);
      if (itemId.trim().isNotEmpty) {
        query = query.where('itemId', isEqualTo: itemId.trim());
      }
      if (movementType.trim().isNotEmpty) {
        query = query.where('movementType', isEqualTo: movementType.trim());
      }
      if (fromDate != null) {
        query = query.where(
          'movementDate',
          isGreaterThanOrEqualTo: Timestamp.fromDate(_startOfDay(fromDate)),
        );
      }
      if (toDate != null) {
        query = query.where(
          'movementDate',
          isLessThanOrEqualTo: Timestamp.fromDate(_endOfDay(toDate)),
        );
      }
      final documents = await query
          .orderBy('movementDate', descending: true)
          .orderBy(FieldPath.documentId, descending: true)
          .getAllPages(pageSize: pageSize);
      final normalizedSearch = searchText.trim().toLowerCase();
      final movements = documents
          .map(StockMovementModel.fromFirestore)
          .where((movement) {
            final afterFrom =
                fromDate == null ||
                !movement.movementDate.isBefore(_startOfDay(fromDate));
            final beforeTo =
                toDate == null ||
                !movement.movementDate.isAfter(_endOfDay(toDate));
            if (!afterFrom || !beforeTo) return false;
            if (normalizedSearch.isEmpty) return true;
            return movement.itemName.toLowerCase().contains(normalizedSearch) ||
                movement.itemCode.toLowerCase().contains(normalizedSearch) ||
                movement.referenceNumber.toLowerCase().contains(
                  normalizedSearch,
                );
          })
          .toList(growable: false);
      movements.sort((a, b) => b.movementDate.compareTo(a.movementDate));
      return movements;
    });
  }

  Future<void> adjustStock({
    String companyId = AuthRepository.defaultCompanyId,
    required String itemId,
    required String adjustmentType,
    required double quantity,
    String notes = '',
  }) {
    return _run(() async {
      final user = await _contextReader.requireApprovedUser();
      if (!user.isAdmin) {
        throw const InventoryRepositoryException(
          InventoryRepositoryError.permissionDenied,
        );
      }
      final resolvedCompanyId = _resolveCompanyId(companyId, user);
      final roundedQuantity = _round(quantity);
      if (itemId.trim().isEmpty || roundedQuantity <= 0) {
        throw const InventoryRepositoryException(
          InventoryRepositoryError.invalidData,
        );
      }
      final movementType = _normalizeAdjustmentType(adjustmentType);
      final idempotencyKey = _stockMovements(resolvedCompanyId).doc().id;
      await _trustedCallableClient
          .callAuthenticated<Map<String, dynamic>>('adjustStock', {
            'companyId': resolvedCompanyId,
            'idempotencyKey': idempotencyKey,
            'itemId': itemId.trim(),
            'adjustmentType': movementType,
            'quantity': roundedQuantity,
            'notes': notes.trim(),
          })
          .timeout(const Duration(seconds: 30));
    });
  }

  Future<List<ItemModel>> _fetchItems() async {
    final documents = await _items
        .where('deleted', isEqualTo: false)
        .orderBy(FieldPath.documentId)
        .getAllPages();
    return documents.map(ItemModel.fromFirestore).toList(growable: false);
  }

  String _normalizeAdjustmentType(String value) {
    return switch (value.trim()) {
      'manual_adjustment_in' || 'increase_stock' => 'manual_adjustment_in',
      'manual_adjustment_out' || 'decrease_stock' => 'manual_adjustment_out',
      'damage' => 'damage',
      // TODO: Split correction into explicit in/out directions if needed.
      'correction' => 'correction',
      _ => throw const InventoryRepositoryException(
        InventoryRepositoryError.invalidData,
      ),
    };
  }

  String _resolveCompanyId(String requested, BusinessUserContext user) {
    final companyId = requested.trim().isEmpty
        ? AuthRepository.defaultCompanyId
        : requested.trim();
    if (companyId != user.companyId) {
      throw const InventoryRepositoryException(
        InventoryRepositoryError.permissionDenied,
      );
    }
    return companyId;
  }

  DateTime _startOfDay(DateTime date) =>
      DateTime(date.year, date.month, date.day);

  DateTime _endOfDay(DateTime date) =>
      DateTime(date.year, date.month, date.day, 23, 59, 59, 999);

  double _round(double value) {
    if (!value.isFinite) return 0;
    return (value * 1000).roundToDouble() / 1000;
  }

  Future<T> _run<T>(Future<T> Function() operation) async {
    try {
      return await operation();
    } on InventoryRepositoryException {
      rethrow;
    } on BusinessUserContextException catch (error) {
      throw InventoryRepositoryException(_mapContextError(error.error), error);
    } on TimeoutException catch (error) {
      throw InventoryRepositoryException(
        InventoryRepositoryError.timeout,
        error,
      );
    } on FirebaseFunctionsException catch (error) {
      final details = error.details;
      final reason = details is Map ? details['reason']?.toString() : null;
      final mapped = reason == 'insufficient-stock'
          ? InventoryRepositoryError.insufficientStock
          : _mapFirebaseError(error.code);
      throw InventoryRepositoryException(mapped, error);
    } on FirebaseException catch (error) {
      throw InventoryRepositoryException(_mapFirebaseError(error.code), error);
    } on FormatException catch (error) {
      throw InventoryRepositoryException(
        InventoryRepositoryError.invalidData,
        error,
      );
    } catch (error) {
      throw InventoryRepositoryException(
        InventoryRepositoryError.unknown,
        error,
      );
    }
  }

  InventoryRepositoryError _mapContextError(BusinessUserContextError error) {
    return switch (error) {
      BusinessUserContextError.unauthenticated ||
      BusinessUserContextError.profileMissing =>
        InventoryRepositoryError.unauthenticated,
      BusinessUserContextError.permissionDenied =>
        InventoryRepositoryError.permissionDenied,
      BusinessUserContextError.invalidProfile =>
        InventoryRepositoryError.invalidData,
      BusinessUserContextError.timeout => InventoryRepositoryError.timeout,
    };
  }

  InventoryRepositoryError _mapFirebaseError(String code) {
    return switch (code) {
      'permission-denied' => InventoryRepositoryError.permissionDenied,
      'unauthenticated' => InventoryRepositoryError.unauthenticated,
      'unavailable' ||
      'deadline-exceeded' => InventoryRepositoryError.unavailable,
      'not-found' => InventoryRepositoryError.notFound,
      'invalid-argument' ||
      'failed-precondition' ||
      'already-exists' ||
      'aborted' => InventoryRepositoryError.invalidData,
      _ => InventoryRepositoryError.unknown,
    };
  }
}
