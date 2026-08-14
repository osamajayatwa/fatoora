import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:fatoora/core/data/firestore_query_pager.dart';
import 'package:fatoora/core/firebase/trusted_callable_client.dart';
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
    FirebaseFunctions? functions,
    FirebaseAuth? firebaseAuth,
    BusinessUserContextReader? contextReader,
    TrustedCallableClient? trustedCallableClient,
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _functions = functions ?? FirebaseFunctions.instance,
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
  final FirebaseFunctions _functions;
  final TrustedCallableClient _trustedCallableClient;
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
    int pageSize = 150,
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
      final documents = await query
          .orderBy('nameLower')
          .orderBy(FieldPath.documentId)
          .getAllPages(pageSize: pageSize);
      return documents.map(CustomerModel.fromFirestore).toList();
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
      final idempotencyKey = _customers(resolvedCompanyId).doc().id;
      final result = await _functions
          .httpsCallable('createCustomer')
          .call<Map<String, dynamic>>({
            'companyId': resolvedCompanyId,
            'idempotencyKey': idempotencyKey,
            'name': name,
            'phone': phone,
            'addressText': addressText,
            'city': city,
            'area': area,
            'notes': notes,
            'active': true,
          })
          .timeout(const Duration(seconds: 30));
      return _readCallableCustomer(
        resolvedCompanyId,
        result.data['customerId'],
      );
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
      final result = await _functions
          .httpsCallable('updateCustomer')
          .call<Map<String, dynamic>>({
            'companyId': resolvedCompanyId,
            'customerId': customerId,
            'name': name,
            'phone': phone,
            'addressText': addressText,
            'city': city,
            'area': area,
            'notes': notes,
            if (active != null) 'active': active,
          })
          .timeout(const Duration(seconds: 30));
      return _readCallableCustomer(
        resolvedCompanyId,
        result.data['customerId'],
      );
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
      final result = await _functions
          .httpsCallable('postCustomerOpeningBalance')
          .call<Map<String, dynamic>>({
            'companyId': resolvedCompanyId,
            'customerId': customerId,
            'openingBalanceType': balanceType.value,
            'amount': amount,
            'transactionDate': transactionDate.millisecondsSinceEpoch,
            'notes': notes,
          })
          .timeout(const Duration(seconds: 30));
      final transactionId = result.data['transactionId'] as String?;
      if (transactionId == null || transactionId.isEmpty) {
        throw const CustomerRepositoryException(
          CustomerRepositoryError.invalidData,
        );
      }
      final snapshot = await _transactions(
        resolvedCompanyId,
      ).doc(transactionId).get().timeout(const Duration(seconds: 20));
      if (!snapshot.exists) {
        throw const CustomerRepositoryException(
          CustomerRepositoryError.notFound,
        );
      }
      return CustomerTransactionModel.fromFirestore(snapshot);
    });
  }

  Future<CustomerTransactionModel> updateOpeningBalance({
    String companyId = AuthRepository.defaultCompanyId,
    required String customerId,
    required CustomerOpeningBalanceType balanceType,
    required double amount,
    required String reason,
  }) {
    return _run(() async {
      final user = await _contextReader.requireApprovedUser();
      final resolvedCompanyId = _resolveCompanyId(companyId, user);
      final idempotencyKey = _transactions(resolvedCompanyId).doc().id;
      final result = await _trustedCallableClient
          .callAuthenticated<Map<String, dynamic>>(
            'updateCustomerOpeningBalance',
            {
              'companyId': resolvedCompanyId,
              'customerId': customerId,
              'idempotencyKey': idempotencyKey,
              'openingBalanceType': balanceType.value,
              'amount': amount,
              'reason': reason.trim(),
            },
          )
          .timeout(const Duration(seconds: 30));
      final transactionId = result.data['transactionId'] as String?;
      final adjustmentId = result.data['adjustmentTransactionId'] as String?;
      if (transactionId == null ||
          transactionId.isEmpty ||
          adjustmentId == null ||
          adjustmentId.isEmpty) {
        throw const CustomerRepositoryException(
          CustomerRepositoryError.invalidData,
        );
      }
      final snapshot = await _transactions(resolvedCompanyId)
          .doc(transactionId)
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 20));
      if (!snapshot.exists) {
        throw const CustomerRepositoryException(
          CustomerRepositoryError.notFound,
        );
      }
      return CustomerTransactionModel.fromFirestore(snapshot);
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
          .orderBy(FieldPath.documentId)
          .getAllPages();
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
      final documents =
          results[0] as List<QueryDocumentSnapshot<Map<String, dynamic>>>;
      final transactions = documents
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
    final documents = await _transactions(companyId)
        .where('customerId', isEqualTo: customerId)
        .where(
          'transactionDate',
          isLessThan: Timestamp.fromDate(_startOfDay(beforeDate)),
        )
        .orderBy('transactionDate')
        .orderBy(FieldPath.documentId)
        .getAllPages();
    return documents.fold<double>(0, (balance, document) {
      final transaction = CustomerTransactionModel.fromFirestore(document);
      return balance + transaction.debitAmount - transaction.creditAmount;
    });
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

  Future<CustomerModel> _readCallableCustomer(
    String companyId,
    Object? customerIdValue,
  ) async {
    final customerId = customerIdValue is String ? customerIdValue.trim() : '';
    if (customerId.isEmpty) {
      throw const CustomerRepositoryException(
        CustomerRepositoryError.invalidData,
      );
    }
    final snapshot = await _customers(
      companyId,
    ).doc(customerId).get().timeout(const Duration(seconds: 20));
    if (!snapshot.exists) {
      throw const CustomerRepositoryException(CustomerRepositoryError.notFound);
    }
    return CustomerModel.fromFirestore(snapshot);
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
    } on FirebaseFunctionsException catch (error) {
      final details = error.details;
      final reason = details is Map ? details['reason']?.toString() : null;
      final mapped = reason == 'idempotency-conflict'
          ? CustomerRepositoryError.invalidData
          : _mapFirebaseError(error.code);
      throw CustomerRepositoryException(mapped, error);
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
      'already-exists' => CustomerRepositoryError.duplicatePhone,
      'invalid-argument' ||
      'failed-precondition' ||
      'data-loss' => CustomerRepositoryError.invalidData,
      'unavailable' ||
      'deadline-exceeded' => CustomerRepositoryError.unavailable,
      'not-found' => CustomerRepositoryError.notFound,
      _ => CustomerRepositoryError.unknown,
    };
  }
}
