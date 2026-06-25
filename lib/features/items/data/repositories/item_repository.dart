import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fatoora/features/items/data/models/item_model.dart';
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
}

class ItemRepository {
  ItemRepository({FirebaseFirestore? firestore, FirebaseAuth? firebaseAuth})
    : _firestore = firestore ?? FirebaseFirestore.instance,
      _firebaseAuth = firebaseAuth ?? FirebaseAuth.instance;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _firebaseAuth;

  CollectionReference<Map<String, dynamic>> get _items =>
      _firestore.collection('items');

  Future<List<ItemModel>> fetchItems() async {
    return _run(() async {
      await _requireUserId();
      final snapshot = await _items
          .where('deleted', isEqualTo: false)
          .get()
          .timeout(const Duration(seconds: 20));
      return snapshot.docs.map(ItemModel.fromFirestore).toList();
    });
  }

  Future<ItemModel> getItem(String itemId) async {
    return _run(() async {
      await _requireUserId();
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
  }) async {
    return _run(() async {
      final userId = await _requireUserId();
      final document = _items.doc();
      await document.set({
        'id': document.id,
        'name': name.trim(),
        'code': code.trim(),
        'description': description.trim(),
        'unit': unit.trim(),
        'price': price,
        'taxRate': taxRate,
        'active': active,
        'deleted': false,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'createdBy': userId,
      });
      return document.id;
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
  }) => _run(() async {
    await _requireUserId();
    await _items.doc(itemId).update({
      'name': name.trim(),
      'code': code.trim(),
      'description': description.trim(),
      'unit': unit.trim(),
      'price': price,
      'taxRate': taxRate,
      'active': active,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  });

  Future<void> setActive(String itemId, {required bool active}) =>
      _run(() async {
        await _requireUserId();
        await _items.doc(itemId).update({
          'active': active,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      });

  Future<void> softDelete(String itemId) => _run(() async {
    await _requireUserId();
    await _items.doc(itemId).update({
      'deleted': true,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  });

  Future<String> _requireUserId() async {
    final user =
        _firebaseAuth.currentUser ??
        await _firebaseAuth.authStateChanges().first.timeout(
          const Duration(seconds: 10),
        );
    if (user == null) {
      throw const ItemRepositoryException(ItemRepositoryError.unauthenticated);
    }
    return user.uid;
  }

  Future<T> _run<T>(Future<T> Function() operation) async {
    try {
      return await operation();
    } on ItemRepositoryException {
      rethrow;
    } on TimeoutException catch (error) {
      throw ItemRepositoryException(ItemRepositoryError.timeout, error);
    } on FirebaseException catch (error) {
      final type = switch (error.code) {
        'permission-denied' => ItemRepositoryError.permissionDenied,
        'unauthenticated' => ItemRepositoryError.unauthenticated,
        'unavailable' || 'deadline-exceeded' => ItemRepositoryError.unavailable,
        'not-found' => ItemRepositoryError.notFound,
        _ => ItemRepositoryError.unknown,
      };
      throw ItemRepositoryException(type, error);
    } on FormatException catch (error) {
      throw ItemRepositoryException(ItemRepositoryError.invalidData, error);
    } catch (error) {
      throw ItemRepositoryException(ItemRepositoryError.unknown, error);
    }
  }
}
