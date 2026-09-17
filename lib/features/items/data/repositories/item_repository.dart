import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:fatoora/core/firebase/trusted_callable_client.dart';
import 'package:fatoora/core/data/firestore_query_pager.dart';
import 'package:fatoora/features/items/data/models/item_model.dart';
import 'package:fatoora/features/shared/business/business_user_context.dart';
import 'package:firebase_auth/firebase_auth.dart';

enum ItemRepositoryError {
  unauthenticated,
  permissionDenied,
  unavailable,
  timeout,
  notFound,
  invalidData,
  unknown,
}

class ItemRepositoryException implements Exception {
  const ItemRepositoryException(this.error, [this.cause]);

  final ItemRepositoryError error;
  final Object? cause;

  @override
  String toString() {
    final firebaseCode = cause is FirebaseException
        ? ', firebaseCode=${(cause as FirebaseException).code}'
        : '';
    return 'ItemRepositoryException(error: ${error.name}$firebaseCode)';
  }
}

class NewItemInventoryValues {
  const NewItemInventoryValues({
    required this.currentStock,
    required this.openingStock,
    required this.minStock,
  });

  final double currentStock;
  final double openingStock;
  final double minStock;
}

NewItemInventoryValues normalizeNewItemInventory({
  required bool trackStock,
  required double openingStock,
  required double minStock,
}) {
  final opening = _roundQuantity(openingStock);
  final minimum = _roundQuantity(minStock);
  if (opening < 0 || minimum < 0) {
    throw const ItemRepositoryException(ItemRepositoryError.invalidData);
  }
  if (!trackStock) {
    return const NewItemInventoryValues(
      currentStock: 0,
      openingStock: 0,
      minStock: 0,
    );
  }
  return NewItemInventoryValues(
    currentStock: opening,
    openingStock: opening,
    minStock: minimum,
  );
}

double _roundQuantity(double value) {
  if (!value.isFinite) {
    throw const ItemRepositoryException(ItemRepositoryError.invalidData);
  }
  return (value * 1000).roundToDouble() / 1000;
}

class ItemRepository {
  ItemRepository({
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

  Future<List<ItemModel>> fetchItems() async {
    return _run(() async {
      await _contextReader.requireApprovedUser();
      final snapshot = await _items
          .where('deleted', isEqualTo: false)
          .get()
          .timeout(const Duration(seconds: 20));
      return snapshot.docs.map(ItemModel.fromFirestore).toList();
    });
  }

  Future<FirestorePage<ItemModel>> fetchItemsPage({
    String searchText = '',
    bool? active,
    String orderField = 'createdAt',
    bool descending = true,
    FirestorePageCursor? after,
    int pageSize = 36,
  }) async {
    return _run(() async {
      await _contextReader.requireApprovedUser();
      Query<Map<String, dynamic>> query = _items.where(
        'deleted',
        isEqualTo: false,
      );
      if (active != null) query = query.where('active', isEqualTo: active);
      final search = ItemModel.normalizeSearch(searchText);
      if (search.isNotEmpty) {
        query = query.where('searchKeywords', arrayContains: search);
      }
      final safeOrderField = switch (orderField) {
        'price' => 'price',
        'nameLower' => 'nameLower',
        _ => 'createdAt',
      };
      return query
          .orderBy(safeOrderField, descending: descending)
          .orderBy(FieldPath.documentId, descending: descending)
          .getPage(
            decode: ItemModel.fromFirestore,
            after: after,
            pageSize: pageSize,
          );
    });
  }

  Future<ItemModel> getItem(String itemId) async {
    return _run(() async {
      await _contextReader.requireApprovedUser();
      final document = await _items
          .doc(itemId)
          .get()
          .timeout(const Duration(seconds: 20));
      if (!document.exists) {
        throw const ItemRepositoryException(ItemRepositoryError.notFound);
      }
      final item = ItemModel.fromFirestore(document);
      if (item.deleted) {
        throw const ItemRepositoryException(ItemRepositoryError.notFound);
      }
      return item;
    });
  }

  Future<String> addItem({
    required String name,
    required String code,
    required String description,
    required String unit,
    required double price,
    required double taxRate,
    required bool active,
    required double openingStock,
    required double minStock,
    required bool trackStock,
    required double costPrice,
    String? barcode,
    String? category,
    String warehouseId = ItemModel.defaultWarehouseId,
  }) async {
    return _run(() async {
      final user = await _requireAdmin();
      final inventory = normalizeNewItemInventory(
        trackStock: trackStock,
        openingStock: openingStock,
        minStock: minStock,
      );
      final cost = _round(costPrice);
      _validateInventoryNumbers(
        currentStock: inventory.currentStock,
        openingStock: inventory.openingStock,
        minStock: inventory.minStock,
        costPrice: cost,
      );
      final document = _items.doc();
      final result = await _trustedCallableClient
          .callAuthenticated<Map<String, dynamic>>('createItem', {
            'companyId': user.companyId,
            'idempotencyKey': document.id,
            'name': name,
            'code': code,
            'description': description,
            'unit': unit,
            'price': price,
            'taxRate': taxRate,
            'active': active,
            'currentStock': inventory.currentStock,
            'openingStock': inventory.openingStock,
            'minStock': inventory.minStock,
            'trackStock': trackStock,
            'costPrice': cost,
            'barcode': barcode,
            'category': category,
            'warehouseId': _warehouseId(warehouseId),
          })
          .timeout(const Duration(seconds: 30));
      final itemId = result.data['itemId'] as String?;
      if (itemId == null || itemId.isEmpty) {
        throw const ItemRepositoryException(ItemRepositoryError.invalidData);
      }
      return itemId;
    });
  }

  Future<void> updateItem({
    required String itemId,
    required String name,
    required String code,
    required String description,
    required String unit,
    required double price,
    required double taxRate,
    required bool active,
    required double currentStock,
    required double openingStock,
    required double minStock,
    required bool trackStock,
    required double costPrice,
    String? barcode,
    String? category,
    String warehouseId = ItemModel.defaultWarehouseId,
  }) => _run(() async {
    final user = await _requireAdmin();
    final stock = _round(currentStock);
    final opening = _round(openingStock);
    final minimum = _round(minStock);
    final cost = _round(costPrice);
    _validateInventoryNumbers(
      currentStock: stock,
      openingStock: opening,
      minStock: minimum,
      costPrice: cost,
    );
    final document = _items.doc(itemId);
    await _firestore
        .runTransaction((transaction) async {
          final snapshot = await transaction.get(document);
          if (!snapshot.exists) {
            throw const ItemRepositoryException(ItemRepositoryError.notFound);
          }
          final existing = ItemModel.fromFirestore(snapshot);
          if (existing.deleted) {
            throw const ItemRepositoryException(ItemRepositoryError.notFound);
          }
          final resolvedWarehouseId = _warehouseId(warehouseId);
          final beforeStock = existing.currentStock;
          final stockChanged = (stock - beforeStock).abs() >= 0.001;
          if (stockChanged && (!existing.trackStock || !trackStock)) {
            throw const ItemRepositoryException(
              ItemRepositoryError.invalidData,
            );
          }
          final movementRef = stockChanged
              ? _stockMovements(user.companyId).doc()
              : null;
          transaction.update(document, {
            'name': name.trim(),
            'code': code.trim(),
            'description': description.trim(),
            'unit': unit.trim(),
            'price': price,
            'taxRate': taxRate,
            'active': active,
            'updatedAt': FieldValue.serverTimestamp(),
            'currentStock': stock,
            'openingStock': opening,
            'minStock': minimum,
            'trackStock': trackStock,
            'costPrice': cost,
            'barcode': _optionalText(barcode),
            'category': _optionalText(category),
            'warehouseId': resolvedWarehouseId,
            if (stockChanged)
              'inventoryUpdatedAt': FieldValue.serverTimestamp(),
            if (movementRef != null) ...{
              'lastInventoryReferenceType': 'itemCorrection',
              'lastInventoryReferenceId': existing.id,
              'lastStockMovementId': movementRef.id,
            },
          });
          if (movementRef != null) {
            final diff = _round(stock - beforeStock);
            transaction.set(
              movementRef,
              _stockMovementData(
                id: movementRef.id,
                companyId: user.companyId,
                warehouseId: resolvedWarehouseId,
                itemId: existing.id,
                itemName: name.trim(),
                itemCode: code.trim(),
                movementType: 'correction',
                direction: diff >= 0 ? 'in' : 'out',
                quantity: diff.abs(),
                quantityBefore: beforeStock,
                quantityAfter: stock,
                referenceType: 'item',
                referenceId: existing.id,
                referenceNumber: code.trim(),
                movementDate: DateTime.now(),
                notes: 'Item stock correction',
                createdByUid: user.uid,
                createdByName: user.name,
                createdByRole: user.role,
              ),
            );
          }
        })
        .timeout(const Duration(seconds: 20));
  });

  Future<void> setActive(String itemId, {required bool active}) =>
      _run(() async {
        await _requireAdmin();
        await _items.doc(itemId).update({
          'active': active,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      });

  Future<void> softDelete(String itemId) => _run(() async {
    await _requireAdmin();
    await _items.doc(itemId).update({
      'deleted': true,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  });

  Future<BusinessUserContext> _requireAdmin() async {
    final user = await _contextReader.requireApprovedUser();
    if (!user.isAdmin) {
      throw const ItemRepositoryException(ItemRepositoryError.permissionDenied);
    }
    return user;
  }

  void _validateInventoryNumbers({
    required double currentStock,
    required double openingStock,
    required double minStock,
    required double costPrice,
  }) {
    if (currentStock < 0 || openingStock < 0 || minStock < 0 || costPrice < 0) {
      throw const ItemRepositoryException(ItemRepositoryError.invalidData);
    }
  }

  String _warehouseId(String value) =>
      value.trim().isEmpty ? ItemModel.defaultWarehouseId : value.trim();

  String? _optionalText(String? value) {
    final text = value?.trim() ?? '';
    return text.isEmpty ? null : text;
  }

  Map<String, dynamic> _stockMovementData({
    required String id,
    required String companyId,
    required String warehouseId,
    required String itemId,
    required String itemName,
    required String itemCode,
    required String movementType,
    required String direction,
    required double quantity,
    required double quantityBefore,
    required double quantityAfter,
    required String referenceType,
    required String referenceId,
    required String referenceNumber,
    required DateTime movementDate,
    required String notes,
    required String createdByUid,
    required String createdByName,
    required String createdByRole,
  }) {
    return {
      'id': id,
      'companyId': companyId,
      'warehouseId': warehouseId,
      'itemId': itemId,
      'itemName': itemName,
      'itemCode': itemCode,
      'movementType': movementType,
      'direction': direction,
      'quantity': quantity,
      'quantityBefore': quantityBefore,
      'quantityAfter': quantityAfter,
      'referenceType': referenceType,
      'referenceId': referenceId,
      'referenceNumber': referenceNumber,
      'movementDate': Timestamp.fromDate(movementDate),
      'notes': notes,
      'createdByUid': createdByUid,
      'createdByName': createdByName,
      'createdByRole': createdByRole,
      'createdAt': FieldValue.serverTimestamp(),
    };
  }

  double _round(double value) {
    if (!value.isFinite) return 0;
    return (value * 1000).roundToDouble() / 1000;
  }

  Future<T> _run<T>(Future<T> Function() operation) async {
    try {
      return await operation();
    } on ItemRepositoryException {
      rethrow;
    } on BusinessUserContextException catch (error) {
      throw ItemRepositoryException(_mapContextError(error.error), error);
    } on TimeoutException catch (error) {
      throw ItemRepositoryException(ItemRepositoryError.timeout, error);
    } on FirebaseException catch (error) {
      final type = switch (error.code) {
        'permission-denied' => ItemRepositoryError.permissionDenied,
        'unauthenticated' => ItemRepositoryError.unauthenticated,
        'unavailable' || 'deadline-exceeded' => ItemRepositoryError.unavailable,
        'not-found' => ItemRepositoryError.notFound,
        'invalid-argument' ||
        'failed-precondition' ||
        'already-exists' => ItemRepositoryError.invalidData,
        _ => ItemRepositoryError.unknown,
      };
      throw ItemRepositoryException(type, error);
    } on FormatException catch (error) {
      throw ItemRepositoryException(ItemRepositoryError.invalidData, error);
    } catch (error) {
      throw ItemRepositoryException(ItemRepositoryError.unknown, error);
    }
  }

  ItemRepositoryError _mapContextError(BusinessUserContextError error) {
    return switch (error) {
      BusinessUserContextError.unauthenticated ||
      BusinessUserContextError.profileMissing =>
        ItemRepositoryError.unauthenticated,
      BusinessUserContextError.permissionDenied =>
        ItemRepositoryError.permissionDenied,
      BusinessUserContextError.invalidProfile =>
        ItemRepositoryError.invalidData,
      BusinessUserContextError.timeout => ItemRepositoryError.timeout,
    };
  }
}
