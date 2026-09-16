import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fatoora/app/routes/app_routes.dart';
import 'package:fatoora/core/class/statusrequest.dart';
import 'package:fatoora/core/data/firestore_query_pager.dart';
import 'package:fatoora/core/services/services.dart';
import 'package:fatoora/features/invoices/controllers/invoices_list_controller.dart';
import 'package:fatoora/features/invoices/data/models/invoice_enums.dart';
import 'package:fatoora/features/invoices/data/models/invoice_list_query.dart';
import 'package:fatoora/features/invoices/data/models/invoice_model.dart';
import 'package:fatoora/features/invoices/data/repositories/invoice_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    Get.reset();
  });

  test('sort fields map to stored Firestore fields', () {
    expect(
      {
        for (final field in InvoiceSortField.values)
          field: field.firestoreField,
      },
      {
        InvoiceSortField.invoiceNumber: 'invoiceNumberLower',
        InvoiceSortField.invoiceDate: 'invoiceDate',
        InvoiceSortField.customerName: 'customerNameLower',
        InvoiceSortField.salesRepresentativeName: 'salesRepName',
        InvoiceSortField.invoiceTotal: 'grandTotal',
        InvoiceSortField.remainingBalance: 'remainingAmount',
        InvoiceSortField.invoiceStatus: 'invoiceStatus',
        InvoiceSortField.createdDate: 'createdAt',
      },
    );
  });

  test('required invoice search fields contribute searchable prefixes', () {
    final keywords = InvoiceModel.buildSearchKeywords(
      invoiceNumber: 'inv-2026-0042',
      customerName: 'Acme Trading',
      customerPhone: '+962790000000',
      salesRepName: 'Rana Saleh',
      itemNames: const [],
      dateString: '',
    );

    expect(keywords, containsAll(['inv', 'acme', '+962', 'rana']));
  });

  test(
    'controller passes every visibility filter and sort to the repository',
    () async {
      SharedPreferences.setMockInitialValues({
        'companyId': 'default_company',
        'role': 'admin',
        'uid': 'admin-1',
        'name': 'Admin',
        'approvalStatus': 'approved',
        'active': true,
      });
      final services = await MyServices().init();
      final resultInvoice = InvoiceModel.fromMap(const {
        'companyId': 'default_company',
        'invoiceNumber': 'INV-RESULT',
        'paymentStatus': 'paid',
        'returnStatus': 'returned',
      }, id: 'result-invoice');
      final repository = _CapturingInvoiceRepository(resultInvoice);
      final controller = InvoicesListController(
        repository: repository,
        myServices: services,
      );
      addTearDown(controller.onClose);

      controller.typeFilter = InvoiceType.electronic;
      controller.statusFilter = InvoiceStatus.confirmed;
      controller.paymentStatusFilter = PaymentStatus.unpaid;
      controller.returnStatusFilter = InvoiceReturnStatus.none;
      controller.salesRepFilter = const InvoiceFilterOption(
        id: 'rep-1',
        label: 'Rep One',
      );
      controller.customerFilter = const InvoiceFilterOption(
        id: 'customer-1',
        label: 'Customer One',
      );
      controller.fromDate = DateTime(2026, 8, 1);
      controller.toDate = DateTime(2026, 8, 15);
      controller.searchText = 'acme';
      controller.sortField = InvoiceSortField.invoiceDate;
      controller.sortDirection = InvoiceSortDirection.ascending;

      await controller.loadInvoices();

      final call = repository.lastCall!;
      expect(call.companyId, 'default_company');
      expect(call.type, InvoiceType.electronic);
      expect(call.status, InvoiceStatus.confirmed);
      expect(call.paymentStatus, PaymentStatus.unpaid);
      expect(call.returnStatus, InvoiceReturnStatus.none);
      expect(call.salesRepId, 'rep-1');
      expect(call.customerId, 'customer-1');
      expect(call.fromDate, DateTime(2026, 8, 1));
      expect(call.toDate, DateTime(2026, 8, 15));
      expect(call.searchText, 'acme');
      expect(call.sortField, InvoiceSortField.invoiceDate);
      expect(call.sortDirection, InvoiceSortDirection.ascending);
      expect(controller.statusRequest, StatusRequest.success);
      expect(
        controller.invoices,
        [resultInvoice],
        reason: 'Repository pages must not be filtered again on the client.',
      );
    },
  );

  test('date range forces query-compatible invoice date sorting', () async {
    SharedPreferences.setMockInitialValues({
      'companyId': 'default_company',
      'role': 'admin',
      'uid': 'admin-1',
      'name': 'Admin',
      'approvalStatus': 'approved',
      'active': true,
    });
    final services = await MyServices().init();
    final controller = InvoicesListController(
      repository: _CapturingInvoiceRepository(
        InvoiceModel.fromMap(const {}, id: 'invoice'),
      ),
      myServices: services,
    );
    addTearDown(controller.onClose);
    controller.sortField = InvoiceSortField.customerName;

    controller.setDateRange(
      DateTimeRange(start: DateTime(2026, 8, 1), end: DateTime(2026, 8, 15)),
    );

    expect(controller.sortField, InvoiceSortField.invoiceDate);
  });

  testWidgets(
    'invoice server search follows debounce, minimum, Enter, and clear',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'companyId': 'default_company',
        'role': 'admin',
        'uid': 'admin-1',
        'name': 'Admin',
        'approvalStatus': 'approved',
        'active': true,
      });
      final services = await MyServices().init();
      final repository = _CapturingInvoiceRepository(
        InvoiceModel.fromMap(const {}, id: 'invoice'),
      );
      final controller = InvoicesListController(
        repository: repository,
        myServices: services,
      )..statusRequest = StatusRequest.success;
      addTearDown(controller.onClose);

      controller.onSearchChanged('a');
      await tester.pump(const Duration(milliseconds: 500));
      expect(repository.calls, isEmpty);

      controller.onSearchChanged('ac');
      await tester.pump(const Duration(milliseconds: 449));
      expect(repository.calls, isEmpty);
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump();
      expect(repository.calls.single.searchText, 'ac');

      controller.onSearchChanged('acme');
      controller.submitSearch();
      await tester.pump();
      expect(repository.calls.last.searchText, 'acme');
      expect(repository.calls, hasLength(2));

      controller.clearSearch();
      await tester.pump();
      expect(repository.calls.last.searchText, '');
      expect(controller.invoices, isNotEmpty);
    },
  );

  testWidgets('create invoice opens the form directly as a regular invoice', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'companyId': 'default_company',
      'role': 'admin',
      'uid': 'admin-1',
      'name': 'Admin',
      'approvalStatus': 'approved',
      'active': true,
    });
    final services = await MyServices().init();
    final controller = InvoicesListController(
      repository: _CapturingInvoiceRepository(
        InvoiceModel.fromMap(const {}, id: 'invoice'),
      ),
      myServices: services,
    );
    addTearDown(controller.onClose);
    Map<dynamic, dynamic>? receivedArguments;
    await tester.pumpWidget(
      GetMaterialApp(
        home: const SizedBox.shrink(),
        getPages: [
          GetPage(
            name: AppRoute.invoiceForm,
            page: () {
              receivedArguments = Get.arguments as Map<dynamic, dynamic>?;
              return const SizedBox.shrink();
            },
          ),
        ],
      ),
    );

    final navigation = controller.openCreateInvoice();
    await tester.pumpAndSettle();
    expect(Get.currentRoute, AppRoute.invoiceForm);
    expect(receivedArguments?['mode'], 'create');
    expect(receivedArguments?['invoiceType'], InvoiceType.regular.value);

    Get.back(result: false);
    await tester.pumpAndSettle();
    await navigation;
  });

  test('older invoice search response cannot replace a newer result', () async {
    SharedPreferences.setMockInitialValues({
      'companyId': 'default_company',
      'role': 'admin',
      'uid': 'admin-1',
      'name': 'Admin',
      'approvalStatus': 'approved',
      'active': true,
    });
    final services = await MyServices().init();
    final repository = _DelayedInvoiceRepository();
    final controller = InvoicesListController(
      repository: repository,
      myServices: services,
    );
    addTearDown(controller.onClose);

    controller.searchText = 'older';
    final olderLoad = controller.loadInvoices();
    controller.searchText = 'newer';
    final newerLoad = controller.loadInvoices();

    repository.complete('newer', 'newer-result');
    await newerLoad;
    expect(controller.invoices.single.id, 'newer-result');

    repository.complete('older', 'older-result');
    await olderLoad;
    expect(controller.invoices.single.id, 'newer-result');
  });

  test('index manifest covers every filter/sort direction and search sort', () {
    final manifest =
        jsonDecode(File('firestore.indexes.json').readAsStringSync())
            as Map<String, dynamic>;
    final indexes = (manifest['indexes'] as List<dynamic>)
        .cast<Map<String, dynamic>>()
        .where((index) => index['collectionGroup'] == 'invoices')
        .toList(growable: false);
    const filterFields = [
      'salesRepId',
      'customerId',
      'invoiceStatus',
      'paymentStatus',
      'returnStatus',
      'invoiceType',
    ];

    for (final sortField in InvoiceSortField.values) {
      for (final direction in const ['ASCENDING', 'DESCENDING']) {
        expect(
          _hasIndex(indexes, [
            const _IndexField('searchKeywords', array: true),
            _IndexField(sortField.firestoreField, order: direction),
          ]),
          isTrue,
          reason: 'Missing search/${sortField.firestoreField}/$direction',
        );
        for (final filterField in filterFields) {
          if (filterField == sortField.firestoreField) continue;
          expect(
            _hasIndex(indexes, [
              _IndexField(filterField, order: 'ASCENDING'),
              _IndexField(sortField.firestoreField, order: direction),
            ]),
            isTrue,
            reason:
                'Missing $filterField/${sortField.firestoreField}/$direction',
          );
        }
      }
    }
  });
}

bool _hasIndex(
  List<Map<String, dynamic>> indexes,
  List<_IndexField> requiredFields,
) {
  return indexes.any((index) {
    final fields = (index['fields'] as List<dynamic>)
        .cast<Map<String, dynamic>>();
    if (fields.length != requiredFields.length) return false;
    for (var index = 0; index < fields.length; index += 1) {
      final actual = fields[index];
      final required = requiredFields[index];
      if (actual['fieldPath'] != required.path) return false;
      if (required.array) {
        if (actual['arrayConfig'] != 'CONTAINS') return false;
      } else if (actual['order'] != required.order) {
        return false;
      }
    }
    return true;
  });
}

class _IndexField {
  const _IndexField(this.path, {this.order, this.array = false});

  final String path;
  final String? order;
  final bool array;
}

class _InvoicePageCall {
  const _InvoicePageCall({
    required this.companyId,
    required this.type,
    required this.status,
    required this.paymentStatus,
    required this.returnStatus,
    required this.salesRepId,
    required this.customerId,
    required this.fromDate,
    required this.toDate,
    required this.searchText,
    required this.sortField,
    required this.sortDirection,
  });

  final String companyId;
  final InvoiceType? type;
  final InvoiceStatus? status;
  final PaymentStatus? paymentStatus;
  final InvoiceReturnStatus? returnStatus;
  final String? salesRepId;
  final String? customerId;
  final DateTime? fromDate;
  final DateTime? toDate;
  final String? searchText;
  final InvoiceSortField sortField;
  final InvoiceSortDirection sortDirection;
}

class _CapturingInvoiceRepository implements InvoiceRepository {
  _CapturingInvoiceRepository(this.resultInvoice);

  final InvoiceModel resultInvoice;
  _InvoicePageCall? lastCall;
  final List<_InvoicePageCall> calls = [];

  @override
  Future<FirestorePage<InvoiceModel>> getInvoicesPage({
    required String companyId,
    InvoiceType? type,
    InvoiceStatus? status,
    PaymentStatus? paymentStatus,
    InvoiceReturnStatus? returnStatus,
    String? salesRepId,
    String? customerId,
    DateTime? fromDate,
    DateTime? toDate,
    String? searchText,
    InvoiceSortField sortField = InvoiceSortField.invoiceDate,
    InvoiceSortDirection sortDirection = InvoiceSortDirection.descending,
    FirestorePageCursor? after,
    int pageSize = 50,
  }) async {
    final call = _InvoicePageCall(
      companyId: companyId,
      type: type,
      status: status,
      paymentStatus: paymentStatus,
      returnStatus: returnStatus,
      salesRepId: salesRepId,
      customerId: customerId,
      fromDate: fromDate,
      toDate: toDate,
      searchText: searchText,
      sortField: sortField,
      sortDirection: sortDirection,
    );
    lastCall = call;
    calls.add(call);
    return FirestorePage(items: [resultInvoice], cursor: null, hasMore: false);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _DelayedInvoiceRepository implements InvoiceRepository {
  final Map<String, Completer<FirestorePage<InvoiceModel>>> _pending = {};

  void complete(String searchText, String invoiceId) {
    _pending[searchText]!.complete(
      FirestorePage(
        items: [InvoiceModel.fromMap(const {}, id: invoiceId)],
        cursor: null,
        hasMore: false,
      ),
    );
  }

  @override
  Future<FirestorePage<InvoiceModel>> getInvoicesPage({
    required String companyId,
    InvoiceType? type,
    InvoiceStatus? status,
    PaymentStatus? paymentStatus,
    InvoiceReturnStatus? returnStatus,
    String? salesRepId,
    String? customerId,
    DateTime? fromDate,
    DateTime? toDate,
    String? searchText,
    InvoiceSortField sortField = InvoiceSortField.invoiceDate,
    InvoiceSortDirection sortDirection = InvoiceSortDirection.descending,
    FirestorePageCursor? after,
    int pageSize = 50,
  }) {
    final completer = Completer<FirestorePage<InvoiceModel>>();
    _pending[searchText ?? ''] = completer;
    return completer.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
