import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fatoora/core/data/firestore_query_pager.dart';
import 'package:fatoora/features/expenses/data/models/expense_model.dart';
import 'package:fatoora/features/invoices/data/models/invoice_enums.dart';
import 'package:fatoora/features/invoices/data/models/invoice_model.dart';
import 'package:fatoora/features/operational_report/data/models/operational_report_data.dart';
import 'package:fatoora/features/operational_report/data/models/operational_report_filters.dart';
import 'package:fatoora/features/receipts/data/models/receipt_model.dart';
import 'package:fatoora/features/shared/business/business_user_context.dart';

enum OperationalReportRepositoryError {
  permissionDenied,
  invalidData,
  offline,
  timeout,
  unknown,
}

class OperationalReportRepositoryException implements Exception {
  const OperationalReportRepositoryException(this.error, [this.cause]);

  final OperationalReportRepositoryError error;
  final Object? cause;
}

class OperationalReportRepository {
  OperationalReportRepository({
    FirebaseFirestore? firestore,
    BusinessUserContextReader? contextReader,
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _contextReader = contextReader ?? BusinessUserContextReader();

  static const invoiceDateField = 'invoiceDate';
  static const expenseDateField = 'expenseDate';
  static const receiptDateField = 'receiptDate';
  static const pageSize = 200;
  static const legacyInvoiceBatchSize = 30;

  final FirebaseFirestore _firestore;
  final BusinessUserContextReader _contextReader;

  CollectionReference<Map<String, dynamic>> _collection(
    String companyId,
    String name,
  ) => _firestore.collection('companies').doc(companyId).collection(name);

  Future<OperationalReportData> fetchReport({
    required String companyId,
    required OperationalReportFilters filters,
  }) => _run(() async {
    if (!filters.isValid) {
      throw const OperationalReportRepositoryException(
        OperationalReportRepositoryError.invalidData,
      );
    }

    final user = await _contextReader.requireApprovedUser();
    final resolvedCompanyId = _requireAdminCompany(companyId, user);
    final results = await Future.wait<Object>([
      _fetchInvoices(resolvedCompanyId, filters),
      _fetchExpenses(resolvedCompanyId, filters),
      _fetchReceipts(resolvedCompanyId, filters),
    ]);
    final invoices = results[0] as List<InvoiceModel>;
    final expenses = results[1] as List<ExpenseModel>;
    final receipts = results[2] as List<ReceiptModel>;
    final legacyIds = legacyReceiptInvoiceIds(receipts);
    final legacyNumbers = await _resolveLegacyInvoiceNumbers(
      resolvedCompanyId,
      legacyIds,
    );

    final warnings = <String>[
      for (final invoice in invoices)
        if (invoice.items.isEmpty)
          'Invoice ${invoice.invoiceNumber.isEmpty ? invoice.id : invoice.invoiceNumber} has no stored item rows and was skipped in Sales.',
      for (final invoiceId in legacyIds)
        if ((legacyNumbers[invoiceId] ?? '').isEmpty)
          'Invoice number could not be resolved for legacy allocation $invoiceId.',
    ];

    return OperationalReportData(
      companyId: resolvedCompanyId,
      invoices: invoices,
      expenses: expenses,
      receipts: receipts,
      legacyInvoiceNumbers: legacyNumbers,
      warnings: warnings,
    );
  });

  Future<List<InvoiceModel>> _fetchInvoices(
    String companyId,
    OperationalReportFilters filters,
  ) async {
    Query<Map<String, dynamic>> query = _collection(companyId, 'invoices')
        .where(
          'invoiceStatus',
          whereIn: const [
            InvoiceStatus.confirmed,
            InvoiceStatus.accepted,
          ].map((status) => status.name).toList(),
        );
    query = _applyDateRange(query, invoiceDateField, filters);
    final documents = await query
        .orderBy(invoiceDateField, descending: true)
        .orderBy(FieldPath.documentId, descending: true)
        .getAllPages(pageSize: pageSize);
    return documents
        .map(InvoiceModel.fromFirestore)
        .where(isOperationalSale)
        .toList(growable: false);
  }

  Future<List<ExpenseModel>> _fetchExpenses(
    String companyId,
    OperationalReportFilters filters,
  ) async {
    Query<Map<String, dynamic>> query = _collection(companyId, 'expenses');
    query = _applyDateRange(query, expenseDateField, filters);
    final documents = await query
        .orderBy(expenseDateField, descending: true)
        .orderBy(FieldPath.documentId, descending: true)
        .getAllPages(pageSize: pageSize);
    return documents.map(ExpenseModel.fromFirestore).toList(growable: false);
  }

  Future<List<ReceiptModel>> _fetchReceipts(
    String companyId,
    OperationalReportFilters filters,
  ) async {
    Query<Map<String, dynamic>> query = _collection(companyId, 'receipts');
    query = _applyDateRange(query, receiptDateField, filters);
    final documents = await query
        .orderBy(receiptDateField, descending: true)
        .orderBy(FieldPath.documentId, descending: true)
        .getAllPages(pageSize: pageSize);
    return documents.map(ReceiptModel.fromFirestore).toList(growable: false);
  }

  Query<Map<String, dynamic>> _applyDateRange(
    Query<Map<String, dynamic>> query,
    String field,
    OperationalReportFilters filters,
  ) {
    final from = filters.fromInclusive;
    final to = filters.toExclusive;
    if (from != null) {
      query = query.where(
        field,
        isGreaterThanOrEqualTo: Timestamp.fromDate(from),
      );
    }
    if (to != null) {
      query = query.where(field, isLessThan: Timestamp.fromDate(to));
    }
    return query;
  }

  Future<Map<String, String>> _resolveLegacyInvoiceNumbers(
    String companyId,
    Set<String> invoiceIds,
  ) async {
    if (invoiceIds.isEmpty) return const {};
    final batches = chunkOperationalIds(
      invoiceIds,
      batchSize: legacyInvoiceBatchSize,
    );
    final snapshots = await Future.wait(
      batches.map(
        (ids) => _collection(companyId, 'invoices')
            .where(FieldPath.documentId, whereIn: ids)
            .get()
            .timeout(const Duration(seconds: 30)),
      ),
    );
    return {
      for (final snapshot in snapshots)
        for (final document in snapshot.docs)
          document.id:
              document.data()['invoiceNumber']?.toString().trim() ?? '',
    };
  }

  String _requireAdminCompany(
    String requestedCompanyId,
    BusinessUserContext user,
  ) {
    final companyId = requestedCompanyId.trim();
    if (!user.isAdmin || companyId.isEmpty || companyId != user.companyId) {
      throw const OperationalReportRepositoryException(
        OperationalReportRepositoryError.permissionDenied,
      );
    }
    return companyId;
  }

  Future<T> _run<T>(Future<T> Function() operation) async {
    try {
      return await operation();
    } on OperationalReportRepositoryException {
      rethrow;
    } on BusinessUserContextException catch (error) {
      final mapped = switch (error.error) {
        BusinessUserContextError.timeout =>
          OperationalReportRepositoryError.timeout,
        BusinessUserContextError.unauthenticated ||
        BusinessUserContextError.profileMissing ||
        BusinessUserContextError.permissionDenied ||
        BusinessUserContextError.invalidProfile =>
          OperationalReportRepositoryError.permissionDenied,
      };
      throw OperationalReportRepositoryException(mapped, error);
    } on TimeoutException catch (error) {
      throw OperationalReportRepositoryException(
        OperationalReportRepositoryError.timeout,
        error,
      );
    } on FirebaseException catch (error) {
      final mapped = switch (error.code) {
        'permission-denied' ||
        'unauthenticated' => OperationalReportRepositoryError.permissionDenied,
        'unavailable' ||
        'network-request-failed' => OperationalReportRepositoryError.offline,
        'deadline-exceeded' => OperationalReportRepositoryError.timeout,
        _ => OperationalReportRepositoryError.unknown,
      };
      throw OperationalReportRepositoryException(mapped, error);
    } catch (error) {
      throw OperationalReportRepositoryException(
        OperationalReportRepositoryError.unknown,
        error,
      );
    }
  }
}
