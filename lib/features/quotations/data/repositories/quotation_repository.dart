import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fatoora/features/auth/data/repositories/auth_repository.dart';
import 'package:fatoora/features/customers/data/models/customer_model.dart';
import 'package:fatoora/features/invoices/data/models/invoice_enums.dart';
import 'package:fatoora/features/invoices/data/models/invoice_model.dart';
import 'package:fatoora/features/quotations/data/models/quotation_model.dart';
import 'package:fatoora/features/quotations/data/models/quotation_status.dart';
import 'package:fatoora/features/shared/business/business_user_context.dart';
import 'package:firebase_auth/firebase_auth.dart';

enum QuotationRepositoryError {
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

class QuotationRepositoryException implements Exception {
  const QuotationRepositoryException(this.error, [this.cause]);

  final QuotationRepositoryError error;
  final Object? cause;
}

class QuotationConversionResult {
  const QuotationConversionResult({
    required this.invoiceId,
    required this.invoiceNumber,
  });

  final String invoiceId;
  final String invoiceNumber;
}

class QuotationRepository {
  QuotationRepository({
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

  CollectionReference<Map<String, dynamic>> _quotations(String companyId) {
    return _firestore
        .collection('companies')
        .doc(companyId)
        .collection('quotations');
  }

  CollectionReference<Map<String, dynamic>> _customers(String companyId) {
    return _firestore
        .collection('companies')
        .doc(companyId)
        .collection('customers');
  }

  CollectionReference<Map<String, dynamic>> _invoices(String companyId) {
    return _firestore
        .collection('companies')
        .doc(companyId)
        .collection('invoices');
  }

  DocumentReference<Map<String, dynamic>> _quotationCounter(
    String companyId,
    int year,
  ) {
    return _firestore
        .collection('companies')
        .doc(companyId)
        .collection('counters')
        .doc('quotations_$year');
  }

  DocumentReference<Map<String, dynamic>> _invoiceCounter(
    String companyId,
    int year,
  ) {
    return _firestore
        .collection('companies')
        .doc(companyId)
        .collection('counters')
        .doc('invoices_$year');
  }

  Future<List<QuotationModel>> fetchQuotations({
    required String companyId,
    QuotationStatus? status,
    String? searchText,
  }) {
    return _run(() async {
      final user = await _contextReader.requireApprovedUser();
      final resolvedCompanyId = _resolveCompanyId(companyId, user);
      Query<Map<String, dynamic>> query = _quotations(resolvedCompanyId);
      if (user.isSalesRep) {
        query = query.where('salesRepId', isEqualTo: user.uid);
      }
      if (status != null) {
        query = query.where('status', isEqualTo: status.value);
      }
      final normalizedSearch = _normalize(searchText ?? '');
      if (normalizedSearch.isNotEmpty) {
        query = query.where('searchKeywords', arrayContains: normalizedSearch);
      }
      final snapshot = await query
          .orderBy('quotationDate', descending: true)
          .limit(150)
          .get()
          .timeout(const Duration(seconds: 20));
      return snapshot.docs.map(QuotationModel.fromFirestore).toList();
    });
  }

  Future<QuotationModel?> getQuotationById({
    required String companyId,
    required String quotationId,
  }) {
    return _run(() async {
      final user = await _contextReader.requireApprovedUser();
      final resolvedCompanyId = _resolveCompanyId(companyId, user);
      final document = await _quotations(
        resolvedCompanyId,
      ).doc(quotationId).get().timeout(const Duration(seconds: 20));
      if (!document.exists) return null;
      final quotation = QuotationModel.fromFirestore(document);
      _requireCanAccessQuotation(user, quotation);
      return quotation;
    });
  }

  Future<String> saveQuotation({required QuotationModel quotation}) {
    return _run(() async {
      final user = await _contextReader.requireApprovedUser();
      final companyId = _resolveCompanyId(quotation.companyId, user);
      final document = quotation.id.trim().isEmpty
          ? _quotations(companyId).doc()
          : _quotations(companyId).doc(quotation.id.trim());

      await _firestore
          .runTransaction((transaction) async {
            final now = DateTime.now();
            final isCreate = quotation.id.trim().isEmpty;
            QuotationModel? existing;
            if (!isCreate) {
              final snapshot = await transaction.get(document);
              if (!snapshot.exists) {
                throw const QuotationRepositoryException(
                  QuotationRepositoryError.notFound,
                );
              }
              existing = QuotationModel.fromFirestore(snapshot);
              _requireCanAccessQuotation(user, existing);
              if (!existing.canEdit) {
                throw const QuotationRepositoryException(
                  QuotationRepositoryError.locked,
                );
              }
            }

            final customer = await _readCustomerForQuotation(
              transaction: transaction,
              companyId: companyId,
              customerId: quotation.customerSnapshot?.id ?? '',
              user: user,
            );
            final numberAllocation = isCreate
                ? await _allocateQuotationNumber(
                    transaction: transaction,
                    companyId: companyId,
                    quotationDate: quotation.quotationDate,
                  )
                : null;
            final normalized = _normalizeQuotation(
              quotation: quotation,
              user: user,
              customer: customer,
              id: document.id,
              companyId: companyId,
              quotationNumber:
                  existing?.quotationNumber ?? numberAllocation!.number,
              createdAt: existing?.createdAt ?? now,
              updatedAt: now,
              existing: existing,
            );

            if (numberAllocation != null) {
              transaction.set(
                numberAllocation.counterRef,
                numberAllocation.counterData,
                SetOptions(merge: true),
              );
            }

            final data = {
              ...normalized.toMap(),
              'createdAt': isCreate
                  ? FieldValue.serverTimestamp()
                  : Timestamp.fromDate(normalized.createdAt),
              'updatedAt': FieldValue.serverTimestamp(),
            };
            if (isCreate) {
              transaction.set(document, data);
            } else {
              transaction.update(document, data);
            }
          })
          .timeout(const Duration(seconds: 20));
      return document.id;
    });
  }

  Future<void> updateStatus({
    required String companyId,
    required String quotationId,
    required QuotationStatus status,
  }) {
    return _run(() async {
      if (status == QuotationStatus.converted) {
        throw const QuotationRepositoryException(
          QuotationRepositoryError.invalidState,
        );
      }
      final user = await _contextReader.requireApprovedUser();
      final resolvedCompanyId = _resolveCompanyId(companyId, user);
      final document = _quotations(resolvedCompanyId).doc(quotationId);
      await _firestore
          .runTransaction((transaction) async {
            final snapshot = await transaction.get(document);
            if (!snapshot.exists) {
              throw const QuotationRepositoryException(
                QuotationRepositoryError.notFound,
              );
            }
            final quotation = QuotationModel.fromFirestore(snapshot);
            _requireCanAccessQuotation(user, quotation);
            if (quotation.status == QuotationStatus.converted) {
              throw const QuotationRepositoryException(
                QuotationRepositoryError.locked,
              );
            }
            transaction.update(document, {
              'status': status.value,
              'updatedAt': FieldValue.serverTimestamp(),
            });
          })
          .timeout(const Duration(seconds: 20));
    });
  }

  Future<QuotationConversionResult> convertToInvoiceDraft({
    required String companyId,
    required String quotationId,
  }) {
    return _run(() async {
      final user = await _contextReader.requireApprovedUser();
      final resolvedCompanyId = _resolveCompanyId(companyId, user);
      final quotationRef = _quotations(resolvedCompanyId).doc(quotationId);
      late QuotationConversionResult result;

      await _firestore
          .runTransaction((transaction) async {
            final quotationSnapshot = await transaction.get(quotationRef);
            if (!quotationSnapshot.exists) {
              throw const QuotationRepositoryException(
                QuotationRepositoryError.notFound,
              );
            }
            final quotation = QuotationModel.fromFirestore(quotationSnapshot);
            _requireCanAccessQuotation(user, quotation);
            if (!quotation.canConvert ||
                quotation.convertedInvoiceId.isNotEmpty) {
              throw const QuotationRepositoryException(
                QuotationRepositoryError.invalidState,
              );
            }
            final customer = await _readCustomerForQuotation(
              transaction: transaction,
              companyId: resolvedCompanyId,
              customerId: quotation.customerId,
              user: user,
            );
            final invoiceRef = _invoices(resolvedCompanyId).doc();
            final numberAllocation = await _allocateInvoiceNumber(
              transaction: transaction,
              companyId: resolvedCompanyId,
              invoiceDate: DateTime.now(),
            );
            final now = DateTime.now();
            final invoice = InvoiceModel(
              id: invoiceRef.id,
              companyId: resolvedCompanyId,
              invoiceNumber: numberAllocation.number,
              invoiceType: InvoiceType.regular,
              invoiceStatus: InvoiceStatus.draft,
              paymentType: PaymentType.credit,
              paymentStatus: PaymentStatus.unpaid,
              hasReceivedPayment: false,
              invoiceDate: now,
              dueDate: now,
              createdAt: now,
              updatedAt: now,
              createdByUid: user.uid,
              createdByName: user.name,
              createdByRole: user.role,
              salesRepId: quotation.salesRepId,
              salesRepName: quotation.salesRepName,
              customerId: customer.id,
              customerSnapshot: quotation.customerSnapshot,
              items: quotation.items
                  .map((item) => item.toInvoiceItem())
                  .toList(growable: false),
              subtotal: quotation.subtotal,
              totalDiscount: quotation.totalDiscount,
              totalTax: quotation.totalTax,
              grandTotal: quotation.grandTotal,
              paidAmount: 0,
              remainingAmount: quotation.grandTotal,
              notes: quotation.notes,
              paymentMethod: PaymentType.credit.value,
              isLocked: false,
              financialPosted: false,
              financialPostedByUid: '',
              financialPostedByName: '',
              customerTransactionIds: const [],
              cashMovementIds: const [],
              inventoryPosted: false,
              inventoryPostedByUid: '',
              inventoryPostedByName: '',
              inventoryMovementIds: const [],
              searchKeywords: const [],
              customerNameLower: '',
              itemNamesLower: const [],
              invoiceNumberLower: '',
              dateString: InvoiceModel.formatDateForSearch(now),
            ).withSearchFields();

            transaction.set(
              numberAllocation.counterRef,
              numberAllocation.counterData,
              SetOptions(merge: true),
            );
            transaction.set(invoiceRef, {
              ...invoice.toMap(),
              'createdAt': FieldValue.serverTimestamp(),
              'updatedAt': FieldValue.serverTimestamp(),
            });
            transaction.update(quotationRef, {
              'status': QuotationStatus.converted.value,
              'convertedInvoiceId': invoiceRef.id,
              'convertedInvoiceNumber': numberAllocation.number,
              'updatedAt': FieldValue.serverTimestamp(),
            });
            result = QuotationConversionResult(
              invoiceId: invoiceRef.id,
              invoiceNumber: numberAllocation.number,
            );
          })
          .timeout(const Duration(seconds: 20));

      return result;
    });
  }

  Future<CustomerModel> _readCustomerForQuotation({
    required Transaction transaction,
    required String companyId,
    required String customerId,
    required BusinessUserContext user,
  }) async {
    if (customerId.trim().isEmpty) {
      throw const QuotationRepositoryException(
        QuotationRepositoryError.invalidData,
      );
    }
    final customerRef = _customers(companyId).doc(customerId.trim());
    final snapshot = await transaction.get(customerRef);
    if (!snapshot.exists) {
      throw const QuotationRepositoryException(
        QuotationRepositoryError.notFound,
      );
    }
    final customer = CustomerModel.fromFirestore(snapshot);
    if (!customer.active) {
      throw const QuotationRepositoryException(
        QuotationRepositoryError.invalidState,
      );
    }
    _requireCanAccessCustomer(user, customer);
    return customer;
  }

  QuotationModel _normalizeQuotation({
    required QuotationModel quotation,
    required BusinessUserContext user,
    required CustomerModel customer,
    required String id,
    required String companyId,
    required String quotationNumber,
    required DateTime createdAt,
    required DateTime updatedAt,
    required QuotationModel? existing,
  }) {
    if (quotation.customerSnapshot == null ||
        quotation.customerSnapshot!.id.trim().isEmpty ||
        quotation.customerSnapshot!.name.trim().isEmpty ||
        quotation.items.isEmpty ||
        quotation.grandTotal < 0) {
      throw const QuotationRepositoryException(
        QuotationRepositoryError.invalidData,
      );
    }
    if (_dateOnly(
      quotation.validUntil,
    ).isBefore(_dateOnly(quotation.quotationDate))) {
      throw const QuotationRepositoryException(
        QuotationRepositoryError.invalidData,
      );
    }
    for (final item in quotation.items) {
      if (item.quantity <= 0 || item.unitPrice < 0) {
        throw const QuotationRepositoryException(
          QuotationRepositoryError.invalidData,
        );
      }
    }

    final createdByUid = existing?.createdByUid ?? user.uid;
    final createdByName = existing?.createdByName ?? user.name;
    final createdByRole = existing?.createdByRole ?? user.role;
    final salesRepId = existing?.salesRepId ?? user.uid;
    final salesRepName = existing?.salesRepName ?? user.name;

    return quotation
        .copyWith(
          id: id,
          companyId: companyId,
          quotationNumber: quotationNumber,
          customerId: customer.id,
          customerSnapshot: customer.toInvoiceSnapshot(),
          status: existing?.status == QuotationStatus.converted
              ? QuotationStatus.converted
              : QuotationStatus.draft,
          salesRepId: salesRepId,
          salesRepName: salesRepName,
          createdByUid: createdByUid,
          createdByName: createdByName,
          createdByRole: createdByRole,
          convertedInvoiceId: existing?.convertedInvoiceId ?? '',
          convertedInvoiceNumber: existing?.convertedInvoiceNumber ?? '',
          createdAt: createdAt,
          updatedAt: updatedAt,
        )
        .withSearchFields();
  }

  Future<_NumberAllocation> _allocateQuotationNumber({
    required Transaction transaction,
    required String companyId,
    required DateTime quotationDate,
  }) async {
    final year = quotationDate.year;
    final counterRef = _quotationCounter(companyId, year);
    final counter = await transaction.get(counterRef);
    final current = counter.data()?['lastNumber'];
    final next = current is num ? current.toInt() + 1 : 1;
    return _NumberAllocation(
      number: 'QUO-$year-${next.toString().padLeft(6, '0')}',
      counterRef: counterRef,
      counterData: {
        'id': counterRef.id,
        'companyId': companyId,
        'year': year,
        'lastNumber': next,
        'prefix': 'QUO',
        'updatedAt': FieldValue.serverTimestamp(),
      },
    );
  }

  Future<_NumberAllocation> _allocateInvoiceNumber({
    required Transaction transaction,
    required String companyId,
    required DateTime invoiceDate,
  }) async {
    final year = invoiceDate.year;
    final counterRef = _invoiceCounter(companyId, year);
    final counter = await transaction.get(counterRef);
    final current = counter.data()?['lastNumber'];
    final next = current is num ? current.toInt() + 1 : 1;
    return _NumberAllocation(
      number: 'INV-$year-${next.toString().padLeft(6, '0')}',
      counterRef: counterRef,
      counterData: {
        'id': counterRef.id,
        'companyId': companyId,
        'year': year,
        'lastNumber': next,
        'prefix': 'INV',
        'updatedAt': FieldValue.serverTimestamp(),
      },
    );
  }

  void _requireCanAccessQuotation(
    BusinessUserContext user,
    QuotationModel quotation,
  ) {
    if (user.isAdmin) return;
    if (user.isSalesRep &&
        (quotation.createdByUid == user.uid ||
            quotation.salesRepId == user.uid)) {
      return;
    }
    throw const QuotationRepositoryException(
      QuotationRepositoryError.permissionDenied,
    );
  }

  void _requireCanAccessCustomer(
    BusinessUserContext user,
    CustomerModel customer,
  ) {
    if (user.isAdmin) return;
    if (user.isSalesRep && customer.createdByUid == user.uid) return;
    throw const QuotationRepositoryException(
      QuotationRepositoryError.permissionDenied,
    );
  }

  String _resolveCompanyId(String requested, BusinessUserContext user) {
    final companyId = requested.trim().isEmpty
        ? AuthRepository.defaultCompanyId
        : requested.trim();
    if (companyId != user.companyId) {
      throw const QuotationRepositoryException(
        QuotationRepositoryError.permissionDenied,
      );
    }
    return companyId;
  }

  DateTime _dateOnly(DateTime date) =>
      DateTime(date.year, date.month, date.day);

  String _normalize(String value) => value.trim().toLowerCase();

  Future<T> _run<T>(Future<T> Function() operation) async {
    try {
      return await operation();
    } on QuotationRepositoryException {
      rethrow;
    } on BusinessUserContextException catch (error) {
      throw QuotationRepositoryException(_mapContextError(error.error), error);
    } on TimeoutException catch (error) {
      throw QuotationRepositoryException(
        QuotationRepositoryError.timeout,
        error,
      );
    } on FirebaseException catch (error) {
      throw QuotationRepositoryException(_mapFirebaseError(error.code), error);
    } catch (error) {
      throw QuotationRepositoryException(
        QuotationRepositoryError.unknown,
        error,
      );
    }
  }

  QuotationRepositoryError _mapContextError(BusinessUserContextError error) {
    return switch (error) {
      BusinessUserContextError.unauthenticated =>
        QuotationRepositoryError.unauthenticated,
      BusinessUserContextError.profileMissing =>
        QuotationRepositoryError.unauthenticated,
      BusinessUserContextError.permissionDenied =>
        QuotationRepositoryError.permissionDenied,
      BusinessUserContextError.invalidProfile =>
        QuotationRepositoryError.invalidData,
      BusinessUserContextError.timeout => QuotationRepositoryError.timeout,
    };
  }

  QuotationRepositoryError _mapFirebaseError(String code) {
    return switch (code) {
      'permission-denied' => QuotationRepositoryError.permissionDenied,
      'unauthenticated' => QuotationRepositoryError.unauthenticated,
      'unavailable' ||
      'deadline-exceeded' => QuotationRepositoryError.unavailable,
      'not-found' => QuotationRepositoryError.notFound,
      'failed-precondition' ||
      'aborted' => QuotationRepositoryError.invalidState,
      _ => QuotationRepositoryError.unknown,
    };
  }
}

class _NumberAllocation {
  const _NumberAllocation({
    required this.number,
    required this.counterRef,
    required this.counterData,
  });

  final String number;
  final DocumentReference<Map<String, dynamic>> counterRef;
  final Map<String, dynamic> counterData;
}
