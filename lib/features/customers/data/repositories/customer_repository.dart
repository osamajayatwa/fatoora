import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fatoora/features/auth/data/repositories/auth_repository.dart';
import 'package:fatoora/features/customers/data/models/customer_model.dart';
import 'package:fatoora/features/customers/data/models/customer_transaction_model.dart';
import 'package:fatoora/features/shared/business/business_user_context.dart';
import 'package:firebase_auth/firebase_auth.dart';

enum CustomerRepositoryError {
  unauthenticated,
  profileMissing,
  permissionDenied,
  unavailable,
  timeout,
  notFound,
  duplicatePhone,
  invalidData,
  unknown,
}

class CustomerRepositoryException implements Exception {
  const CustomerRepositoryException(this.error, [this.cause]);

  final CustomerRepositoryError error;
  final Object? cause;
}

class CustomerRepository {
  CustomerRepository({
    FirebaseFirestore? firestore,
    FirebaseAuth? firebaseAuth,
    BusinessUserContextReader? contextReader,
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _contextReader =
           contextReader ??
           BusinessUserContextReader(
             firestore: firestore,
             firebaseAuth: firebaseAuth,
           );

  final FirebaseFirestore _firestore;
  final BusinessUserContextReader _contextReader;

  CollectionReference<Map<String, dynamic>> _customers(String companyId) {
    return _firestore
        .collection('companies')
        .doc(companyId)
        .collection('customers');
  }

  CollectionReference<Map<String, dynamic>> _transactions(String companyId) {
    return _firestore
        .collection('companies')
        .doc(companyId)
        .collection('customer_transactions');
  }

  Future<List<CustomerModel>> fetchCustomers({
    String companyId = AuthRepository.defaultCompanyId,
    String searchText = '',
    bool activeOnly = true,
    int maxResults = 150,
  }) {
    return _run(() async {
      final user = await _contextReader.requireApprovedUser();
      final resolvedCompanyId = _resolveCompanyId(companyId, user);
      Query<Map<String, dynamic>> query = _customers(resolvedCompanyId);
      if (activeOnly) query = query.where('active', isEqualTo: true);
      if (user.isSalesRep) {
        query = query.where('createdByUid', isEqualTo: user.uid);
      }
      final normalizedSearch = CustomerModel.normalizeText(searchText);
      if (normalizedSearch.isNotEmpty) {
        query = query.where('searchKeywords', arrayContains: normalizedSearch);
      }
      final snapshot = await query
          .orderBy('nameLower')
          .limit(maxResults)
          .get()
          .timeout(const Duration(seconds: 20));
      return snapshot.docs.map(CustomerModel.fromFirestore).toList();
    });
  }

  Future<CustomerModel> getCustomer({
    String companyId = AuthRepository.defaultCompanyId,
    required String customerId,
  }) {
    return _run(() async {
      final user = await _contextReader.requireApprovedUser();
      final resolvedCompanyId = _resolveCompanyId(companyId, user);
      final document = await _customers(
        resolvedCompanyId,
      ).doc(customerId).get().timeout(const Duration(seconds: 20));
      if (!document.exists) {
        throw const CustomerRepositoryException(
          CustomerRepositoryError.notFound,
        );
      }
      final customer = CustomerModel.fromFirestore(document);
      _requireCanAccessCustomer(user, customer);
      return customer;
    });
  }

  Future<CustomerModel> addCustomer({
    String companyId = AuthRepository.defaultCompanyId,
    required String name,
    required String phone,
    required String addressText,
    required String city,
    required String area,
    required String notes,
  }) {
    return _run(() async {
      final user = await _contextReader.requireApprovedUser();
      final resolvedCompanyId = _resolveCompanyId(companyId, user);
      final normalizedPhone = CustomerModel.normalizePhone(phone);
      await _ensurePhoneIsUnique(
        companyId: resolvedCompanyId,
        phoneNormalized: normalizedPhone,
      );

      final document = _customers(resolvedCompanyId).doc();
      final now = DateTime.now();
      final customer = CustomerModel(
        id: document.id,
        companyId: resolvedCompanyId,
        name: _requiredName(name),
        phone: phone.trim(),
        addressText: addressText.trim(),
        city: city.trim(),
        area: area.trim(),
        notes: notes.trim(),
        active: true,
        createdByUid: user.uid,
        createdByName: user.name,
        createdByRole: user.role,
        createdAt: now,
        updatedAt: now,
        currentBalance: 0,
        totalSales: 0,
        totalPaid: 0,
        searchKeywords: const [],
        nameLower: '',
        phoneNormalized: normalizedPhone,
        cityLower: '',
        areaLower: '',
      ).withSearchFields();

      await document
          .set({
            ...customer.toMap(),
            'createdAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          })
          .timeout(const Duration(seconds: 20));
      return customer;
    });
  }

  Future<CustomerModel> updateCustomer({
    String companyId = AuthRepository.defaultCompanyId,
    required String customerId,
    required String name,
    required String phone,
    required String addressText,
    required String city,
    required String area,
    required String notes,
    bool? active,
  }) {
    return _run(() async {
      final user = await _contextReader.requireApprovedUser();
      final resolvedCompanyId = _resolveCompanyId(companyId, user);
      final document = _customers(resolvedCompanyId).doc(customerId);
      final snapshot = await document.get().timeout(
        const Duration(seconds: 20),
      );
      if (!snapshot.exists) {
        throw const CustomerRepositoryException(
          CustomerRepositoryError.notFound,
        );
      }
      final existing = CustomerModel.fromFirestore(snapshot);
      _requireCanAccessCustomer(user, existing);

      final normalizedPhone = CustomerModel.normalizePhone(phone);
      if (normalizedPhone != existing.phoneNormalized) {
        await _ensurePhoneIsUnique(
          companyId: resolvedCompanyId,
          phoneNormalized: normalizedPhone,
          exceptCustomerId: customerId,
        );
      }

      final updated = existing
          .copyWith(
            name: _requiredName(name),
            phone: phone.trim(),
            addressText: addressText.trim(),
            city: city.trim(),
            area: area.trim(),
            notes: notes.trim(),
            active: active ?? existing.active,
            updatedAt: DateTime.now(),
          )
          .withSearchFields();

      await document
          .update({
            'name': updated.name,
            'phone': updated.phone,
            'addressText': updated.addressText,
            'city': updated.city,
            'area': updated.area,
            'notes': updated.notes,
            'active': updated.active,
            'updatedAt': FieldValue.serverTimestamp(),
            'searchKeywords': updated.searchKeywords,
            'nameLower': updated.nameLower,
            'phoneNormalized': updated.phoneNormalized,
            'cityLower': updated.cityLower,
            'areaLower': updated.areaLower,
          })
          .timeout(const Duration(seconds: 20));
      return updated;
    });
  }

  Future<void> setActive({
    String companyId = AuthRepository.defaultCompanyId,
    required String customerId,
    required bool active,
  }) {
    return _run(() async {
      final user = await _contextReader.requireApprovedUser();
      final resolvedCompanyId = _resolveCompanyId(companyId, user);
      final document = _customers(resolvedCompanyId).doc(customerId);
      final snapshot = await document.get().timeout(
        const Duration(seconds: 20),
      );
      if (!snapshot.exists) {
        throw const CustomerRepositoryException(
          CustomerRepositoryError.notFound,
        );
      }
      final existing = CustomerModel.fromFirestore(snapshot);
      _requireCanAccessCustomer(user, existing);
      await document
          .update({'active': active, 'updatedAt': FieldValue.serverTimestamp()})
          .timeout(const Duration(seconds: 20));
    });
  }

  Future<List<CustomerTransactionModel>> fetchStatement({
    String companyId = AuthRepository.defaultCompanyId,
    required String customerId,
    DateTime? fromDate,
    DateTime? toDate,
  }) {
    return _run(() async {
      final user = await _contextReader.requireApprovedUser();
      final resolvedCompanyId = _resolveCompanyId(companyId, user);
      final customer = await getCustomer(
        companyId: resolvedCompanyId,
        customerId: customerId,
      );
      _requireCanAccessCustomer(user, customer);

      Query<Map<String, dynamic>> query = _transactions(
        resolvedCompanyId,
      ).where('customerId', isEqualTo: customerId);
      if (fromDate != null) {
        query = query.where(
          'transactionDate',
          isGreaterThanOrEqualTo: Timestamp.fromDate(_startOfDay(fromDate)),
        );
      }
      if (toDate != null) {
        query = query.where(
          'transactionDate',
          isLessThanOrEqualTo: Timestamp.fromDate(_endOfDay(toDate)),
        );
      }
      final snapshot = await query
          .orderBy('transactionDate')
          .limit(500)
          .get()
          .timeout(const Duration(seconds: 20));
      return snapshot.docs
          .map(CustomerTransactionModel.fromFirestore)
          .toList(growable: false);
    });
  }

  Future<void> _ensurePhoneIsUnique({
    required String companyId,
    required String phoneNormalized,
    String? exceptCustomerId,
  }) async {
    if (phoneNormalized.isEmpty) return;
    final snapshot = await _customers(companyId)
        .where('active', isEqualTo: true)
        .where('phoneNormalized', isEqualTo: phoneNormalized)
        .limit(2)
        .get()
        .timeout(const Duration(seconds: 20));
    final duplicate = snapshot.docs
        .map(CustomerModel.fromFirestore)
        .where((customer) => customer.id != exceptCustomerId)
        .isNotEmpty;
    if (duplicate) {
      throw const CustomerRepositoryException(
        CustomerRepositoryError.duplicatePhone,
      );
    }
  }

  void _requireCanAccessCustomer(
    BusinessUserContext user,
    CustomerModel customer,
  ) {
    if (user.isAdmin) return;
    if (user.isSalesRep && customer.createdByUid == user.uid) return;
    throw const CustomerRepositoryException(
      CustomerRepositoryError.permissionDenied,
    );
  }

  String _resolveCompanyId(String requested, BusinessUserContext user) {
    final companyId = requested.trim().isEmpty
        ? AuthRepository.defaultCompanyId
        : requested.trim();
    if (companyId != user.companyId) {
      throw const CustomerRepositoryException(
        CustomerRepositoryError.permissionDenied,
      );
    }
    return companyId;
  }

  String _requiredName(String value) {
    final name = value.trim();
    if (name.isEmpty || name.toLowerCase() == 'undefined') {
      throw const CustomerRepositoryException(
        CustomerRepositoryError.invalidData,
      );
    }
    return name;
  }

  DateTime _startOfDay(DateTime date) =>
      DateTime(date.year, date.month, date.day);

  DateTime _endOfDay(DateTime date) =>
      DateTime(date.year, date.month, date.day, 23, 59, 59, 999);

  Future<T> _run<T>(Future<T> Function() operation) async {
    try {
      return await operation();
    } on CustomerRepositoryException {
      rethrow;
    } on BusinessUserContextException catch (error) {
      throw CustomerRepositoryException(_mapContextError(error.error), error);
    } on TimeoutException catch (error) {
      throw CustomerRepositoryException(CustomerRepositoryError.timeout, error);
    } on FirebaseException catch (error) {
      throw CustomerRepositoryException(_mapFirebaseError(error.code), error);
    } on FormatException catch (error) {
      throw CustomerRepositoryException(
        CustomerRepositoryError.invalidData,
        error,
      );
    } catch (error) {
      throw CustomerRepositoryException(CustomerRepositoryError.unknown, error);
    }
  }

  CustomerRepositoryError _mapContextError(BusinessUserContextError error) {
    return switch (error) {
      BusinessUserContextError.unauthenticated =>
        CustomerRepositoryError.unauthenticated,
      BusinessUserContextError.profileMissing =>
        CustomerRepositoryError.profileMissing,
      BusinessUserContextError.permissionDenied =>
        CustomerRepositoryError.permissionDenied,
      BusinessUserContextError.invalidProfile =>
        CustomerRepositoryError.invalidData,
      BusinessUserContextError.timeout => CustomerRepositoryError.timeout,
    };
  }

  CustomerRepositoryError _mapFirebaseError(String code) {
    return switch (code) {
      'permission-denied' => CustomerRepositoryError.permissionDenied,
      'unauthenticated' => CustomerRepositoryError.unauthenticated,
      'unavailable' ||
      'deadline-exceeded' => CustomerRepositoryError.unavailable,
      'not-found' => CustomerRepositoryError.notFound,
      _ => CustomerRepositoryError.unknown,
    };
  }
}
