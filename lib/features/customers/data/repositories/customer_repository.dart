import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fatoora/core/settings/business_permission_resolver.dart';
import 'package:fatoora/features/auth/data/repositories/auth_repository.dart';
import 'package:fatoora/features/customers/data/models/customer_model.dart';
import 'package:fatoora/features/customers/data/models/customer_opening_balance.dart';
import 'package:fatoora/features/customers/data/models/customer_statement_snapshot.dart';
import 'package:fatoora/features/customers/data/models/customer_transaction_model.dart';
import 'package:fatoora/features/settings/data/models/app_settings_model.dart';
import 'package:fatoora/features/shared/business/business_user_context.dart';
import 'package:firebase_auth/firebase_auth.dart';

enum CustomerRepositoryError {
  unauthenticated,
  profileMissing,
  permissionDenied,
  createDisabled,
  unavailable,
  timeout,
  notFound,
  duplicatePhone,
  openingBalanceExists,
  inactiveCustomer,
  invalidData,
  unknown,
}

class CustomerRepositoryException implements Exception {
  const CustomerRepositoryException(this.error, [this.cause]);

  final CustomerRepositoryError error;
  final Object? cause;
}

class OpeningBalanceAlreadyExistsException extends CustomerRepositoryException {
  const OpeningBalanceAlreadyExistsException([this.openingBalance])
    : super(CustomerRepositoryError.openingBalanceExists);

  final CustomerTransactionModel? openingBalance;
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

  DocumentReference<Map<String, dynamic>> _appSettings(String companyId) {
    return _firestore
        .collection('companies')
        .doc(companyId)
        .collection('settings')
        .doc('app');
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
      final permissions = await _loadPermissions(resolvedCompanyId, user);
      if (!permissions.createCustomers) {
        throw const CustomerRepositoryException(
          CustomerRepositoryError.createDisabled,
        );
      }
      final normalizedPhone = CustomerModel.normalizePhone(phone);
      await _ensurePhoneIsUnique(
        companyId: resolvedCompanyId,
        phoneNormalized: normalizedPhone,
        user: user,
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
          user: user,
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

  Future<CustomerTransactionModel> addOpeningBalance({
    String companyId = AuthRepository.defaultCompanyId,
    required String customerId,
    required CustomerOpeningBalanceType balanceType,
    required double amount,
    required DateTime transactionDate,
    String notes = '',
  }) {
    return _run(() async {
      final user = await _contextReader.requireApprovedUser();
      final resolvedCompanyId = _resolveCompanyId(companyId, user);
      if (!amount.isFinite || amount <= 0) {
        throw const CustomerRepositoryException(
          CustomerRepositoryError.invalidData,
        );
      }

      final roundedAmount = _round(amount);
      if (roundedAmount <= 0 ||
          roundedAmount > 999999999 ||
          (amount - roundedAmount).abs() > 0.0000001 ||
          transactionDate.isAfter(DateTime.now()) ||
          notes.trim().length > 500) {
        throw const CustomerRepositoryException(
          CustomerRepositoryError.invalidData,
        );
      }

      final transactionRef = _transactions(
        resolvedCompanyId,
      ).doc('${customerId}_opening_balance');
      late CustomerTransactionModel openingBalance;
      try {
        await _firestore
            .runTransaction((transaction) async {
              final customerRef = _customers(resolvedCompanyId).doc(customerId);
              final customerSnapshot = await transaction.get(customerRef);
              final existingOpening = await transaction.get(transactionRef);
              if (!customerSnapshot.exists) {
                throw const CustomerRepositoryException(
                  CustomerRepositoryError.notFound,
                );
              }
              if (existingOpening.exists) {
                throw OpeningBalanceAlreadyExistsException(
                  CustomerTransactionModel.fromFirestore(existingOpening),
                );
              }

              final customer = CustomerModel.fromFirestore(customerSnapshot);
              _requireCanAccessCustomer(user, customer);
              if (!customer.active) {
                throw const CustomerRepositoryException(
                  CustomerRepositoryError.inactiveCustomer,
                );
              }

              final balanceBefore = _round(customer.currentBalance);
              final signedAmount = balanceType.balanceEffect(roundedAmount);
              final balanceAfter = _round(balanceBefore + signedAmount);
              final now = DateTime.now();
              openingBalance = CustomerTransactionModel(
                id: transactionRef.id,
                companyId: resolvedCompanyId,
                customerId: customer.id,
                customerName: customer.name,
                transactionType: 'opening_balance',
                type: 'opening_balance',
                sourceCollection: 'customer_transactions',
                sourceId: transactionRef.id,
                sourceNumber: 'OPENING',
                transactionDate: transactionDate,
                debitAmount: signedAmount > 0 ? roundedAmount : 0,
                creditAmount: signedAmount < 0 ? roundedAmount : 0,
                balanceBefore: balanceBefore,
                balanceAfter: balanceAfter,
                openingBalanceType: balanceType.value,
                amount: roundedAmount,
                signedAmount: signedAmount,
                notes: notes.trim(),
                createdByUid: user.uid,
                createdByName: user.name,
                createdByRole: user.role,
                salesRepId: user.isSalesRep ? user.uid : '',
                salesRepName: user.isSalesRep ? user.name : '',
                createdAt: now,
              );

              transaction.update(customerRef, {
                'currentBalance': balanceAfter,
                'lastOpeningBalanceTransactionId': transactionRef.id,
                'updatedAt': FieldValue.serverTimestamp(),
              });
              transaction.set(transactionRef, {
                ...openingBalance.toMap(),
                'referenceId': transactionRef.id,
                'createdAt': FieldValue.serverTimestamp(),
              });
            })
            .timeout(const Duration(seconds: 20));
      } on TimeoutException {
        final committed = await _readOpeningBalanceAfterAmbiguousFailure(
          transactionRef,
        );
        if (committed != null) return committed;
        rethrow;
      } on FirebaseException catch (error) {
        if (_isAmbiguousCommitError(error.code)) {
          final committed = await _readOpeningBalanceAfterAmbiguousFailure(
            transactionRef,
          );
          if (committed != null) return committed;
        }
        rethrow;
      }
      return openingBalance;
    });
  }

  Future<CustomerTransactionModel?> getOpeningBalance({
    String companyId = AuthRepository.defaultCompanyId,
    required String customerId,
  }) {
    return _run(() async {
      final user = await _contextReader.requireApprovedUser();
      final resolvedCompanyId = _resolveCompanyId(companyId, user);
      final customerSnapshot = await _customers(
        resolvedCompanyId,
      ).doc(customerId).get().timeout(const Duration(seconds: 20));
      if (!customerSnapshot.exists) {
        throw const CustomerRepositoryException(
          CustomerRepositoryError.notFound,
        );
      }
      _requireCanAccessCustomer(
        user,
        CustomerModel.fromFirestore(customerSnapshot),
      );

      final openingSnapshot = await _transactions(resolvedCompanyId)
          .doc('${customerId}_opening_balance')
          .get()
          .timeout(const Duration(seconds: 20));
      if (!openingSnapshot.exists) return null;
      return CustomerTransactionModel.fromFirestore(openingSnapshot);
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

  Future<CustomerStatementSnapshot> fetchStatement({
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
      final periodFuture = query
          .orderBy('transactionDate')
          .limit(500)
          .get()
          .timeout(const Duration(seconds: 20));
      final openingBalanceFuture = fromDate == null
          ? Future<double>.value(0)
          : _fetchOpeningBalance(
              companyId: resolvedCompanyId,
              customerId: customerId,
              beforeDate: fromDate,
            );
      final results = await Future.wait<Object>([
        periodFuture,
        openingBalanceFuture,
      ]);
      final snapshot = results[0] as QuerySnapshot<Map<String, dynamic>>;
      final transactions = snapshot.docs
          .map(CustomerTransactionModel.fromFirestore)
          .toList(growable: false);
      return CustomerStatementSnapshot.fromTransactions(
        transactions: transactions,
        openingBalance: results[1] as double,
      );
    });
  }

  Future<double> _fetchOpeningBalance({
    required String companyId,
    required String customerId,
    required DateTime beforeDate,
  }) async {
    final snapshot = await _transactions(companyId)
        .where('customerId', isEqualTo: customerId)
        .where(
          'transactionDate',
          isLessThan: Timestamp.fromDate(_startOfDay(beforeDate)),
        )
        .orderBy('transactionDate')
        .limit(500)
        .get()
        .timeout(const Duration(seconds: 20));
    return snapshot.docs.fold<double>(0, (balance, document) {
      final transaction = CustomerTransactionModel.fromFirestore(document);
      return balance + transaction.debitAmount - transaction.creditAmount;
    });
  }

  Future<void> _ensurePhoneIsUnique({
    required String companyId,
    required String phoneNormalized,
    required BusinessUserContext user,
    String? exceptCustomerId,
  }) async {
    if (phoneNormalized.isEmpty) return;
    Query<Map<String, dynamic>> query = _customers(companyId)
        .where('active', isEqualTo: true)
        .where('phoneNormalized', isEqualTo: phoneNormalized);
    if (user.isSalesRep) {
      query = query.where('createdByUid', isEqualTo: user.uid);
    }
    final snapshot = await query
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

  Future<EffectiveBusinessPermissions> _loadPermissions(
    String companyId,
    BusinessUserContext user,
  ) async {
    final snapshot = await _appSettings(
      companyId,
    ).get().timeout(const Duration(seconds: 20));
    final settings = AppSettingsModel.fromMap(snapshot.data());
    return EffectiveBusinessPermissions.fromUser(
      user,
      settings.permissionSettings,
    );
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

  double _round(double value) => (value * 1000).roundToDouble() / 1000;

  bool _isAmbiguousCommitError(String code) {
    return code == 'aborted' ||
        code == 'cancelled' ||
        code == 'deadline-exceeded' ||
        code == 'internal' ||
        code == 'unknown' ||
        code == 'unavailable';
  }

  Future<CustomerTransactionModel?> _readOpeningBalanceAfterAmbiguousFailure(
    DocumentReference<Map<String, dynamic>> transactionRef,
  ) async {
    try {
      final snapshot = await transactionRef.get().timeout(
        const Duration(seconds: 5),
      );
      return snapshot.exists
          ? CustomerTransactionModel.fromFirestore(snapshot)
          : null;
    } catch (_) {
      return null;
    }
  }

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
