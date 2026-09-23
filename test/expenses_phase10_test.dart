import 'dart:async';

import 'package:fatoora/core/data/firestore_query_pager.dart';
import 'package:fatoora/core/localization/translation.dart';
import 'package:fatoora/core/services/services.dart';
import 'package:fatoora/features/expenses/controllers/expense_form_controller.dart';
import 'package:fatoora/features/expenses/controllers/expenses_list_controller.dart';
import 'package:fatoora/features/expenses/data/models/expense_model.dart';
import 'package:fatoora/features/expenses/data/repositories/expense_repository.dart';
import 'package:fatoora/features/expenses/view/screens/expense_form_screen.dart';
import 'package:fatoora/features/expenses/view/screens/expenses_list_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(Get.reset);

  testWidgets('rep expense card distinguishes personal cash at 320px 2x', (
    tester,
  ) async {
    await _pumpList(tester, const Size(320, 640), textScale: 2);
    expect(find.byType(ExpenseListCard), findsOneWidget);
    expect(find.text('Personal cash'), findsOneWidget);
    expect(find.text('Representative One'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Admin desktop table shows rep and actual funding/status', (
    tester,
  ) async {
    await _pumpList(tester, const Size(1366, 900), role: 'admin');
    expect(find.byType(DataTable), findsOneWidget);
    expect(find.text('Representative One'), findsOneWidget);
    expect(find.text('Pending'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'filter sheet applies one server query and chips remove filters',
    (tester) async {
      final repo = _ExpenseRepositoryFake();
      final controller = await _pumpList(
        tester,
        const Size(390, 800),
        repo: repo,
      );
      await tester.tap(find.byKey(const ValueKey('expense-filter-button')));
      await tester.pumpAndSettle();
      expect(find.text('Status'), findsWidgets);
      await tester.tap(find.text('Apply filters'));
      await tester.pumpAndSettle();
      expect(repo.fetchCalls, 2);
      controller.setStatusFilter(ExpenseStatus.pending);
      await tester.pumpAndSettle();
      expect(repo.lastStatus, ExpenseStatus.pending);
      expect(find.byType(InputChip), findsWidgets);
    },
  );

  testWidgets('search and Load More retry preserve server paging', (
    tester,
  ) async {
    final repo = _ExpenseRepositoryFake(paged: true);
    final controller = await _pumpList(
      tester,
      const Size(390, 800),
      repo: repo,
    );
    controller.onSearchChanged('fuel');
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    expect(repo.lastSearch, 'fuel');
    repo.failNextPage = true;
    await controller.loadMoreExpenses();
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('expense-load-more-error')),
      findsOneWidget,
    );
    repo.failNextPage = false;
    await controller.loadMoreExpenses();
    await tester.pumpAndSettle();
    expect(controller.expenses, hasLength(2));
  });

  testWidgets('rep form explains personal cash and guards saving', (
    tester,
  ) async {
    final repo = _ExpenseRepositoryFake();
    final controller = await _pumpForm(
      tester,
      const Size(320, 640),
      repo: repo,
    );
    controller.setFundingSource(ExpenseFundingSource.personalCash);
    await tester.pumpAndSettle();
    expect(find.textContaining('does not reduce company'), findsOneWidget);
    controller.amountController.text = '12';
    repo.createCompleter = Completer<ExpenseModel>();
    final save = controller.saveExpense();
    await tester.pump();
    expect(controller.isSaving, isTrue);
    expect(find.text('Saving expense...'), findsOneWidget);
    controller.saveExpense();
    expect(repo.createCalls, 1);
    repo.createCompleter!.completeError(StateError('offline'));
    await save;
    await tester.pump(const Duration(seconds: 5));
    expect(tester.takeException(), isNull);
  });
}

Future<ExpensesListController> _pumpList(
  WidgetTester tester,
  Size size, {
  String role = 'sales_rep',
  double textScale = 1,
  _ExpenseRepositoryFake? repo,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final controller = ExpensesListController(
    repository: repo ?? _ExpenseRepositoryFake(),
    myServices: await _services(role),
  );
  Get.put<ExpensesListController>(controller);
  await tester.pumpWidget(
    GetMaterialApp(
      locale: const Locale('en'),
      translations: MyTranslation(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: const ExpensesListScreen(),
    ),
  );
  await tester.pumpAndSettle();
  return controller;
}

Future<ExpenseFormController> _pumpForm(
  WidgetTester tester,
  Size size, {
  _ExpenseRepositoryFake? repo,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final controller = ExpenseFormController(
    repository: repo ?? _ExpenseRepositoryFake(),
    myServices: await _services('sales_rep'),
  );
  Get.put<ExpenseFormController>(controller);
  await tester.pumpWidget(
    GetMaterialApp(
      locale: const Locale('en'),
      translations: MyTranslation(),
      home: const ExpenseFormScreen(),
    ),
  );
  await tester.pumpAndSettle();
  return controller;
}

Future<MyServices> _services(String role) async {
  SharedPreferences.setMockInitialValues({
    'companyId': 'default_company',
    'role': role,
    'uid': 'rep-1',
  });
  Get.reset();
  final services = await MyServices().init();
  Get.put<MyServices>(services);
  return services;
}

class _FakeCursor implements FirestorePageCursor {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ExpenseRepositoryFake implements ExpenseRepository {
  _ExpenseRepositoryFake({this.paged = false});
  final bool paged;
  int fetchCalls = 0;
  int createCalls = 0;
  String? lastSearch;
  ExpenseStatus? lastStatus;
  bool failNextPage = false;
  Completer<ExpenseModel>? createCompleter;

  @override
  Future<ExpensePage> fetchExpensesPage({
    String companyId = 'default_company',
    String searchText = '',
    ExpenseStatus? status,
    ExpenseCategory? category,
    DateTime? fromDate,
    DateTime? toDate,
    FirestorePageCursor? after,
    int pageSize = 50,
  }) async {
    fetchCalls++;
    lastSearch = searchText;
    lastStatus = status;
    if (after != null && failNextPage) throw StateError('Page unavailable');
    return ExpensePage(
      items: [_expense(id: after == null ? 'expense-1' : 'expense-2')],
      cursor: paged && after == null ? _FakeCursor() : null,
      hasMore: paged && after == null,
      postedTotal: 0,
      pendingCount: 1,
      payableReimbursements: 0,
    );
  }

  @override
  Future<ExpenseModel> createExpense({
    String companyId = 'default_company',
    required double amount,
    required DateTime expenseDate,
    required ExpenseCategory category,
    String customCategoryName = '',
    String description = '',
    String paymentMethod = 'cash',
    required ExpenseFundingSource fundingSource,
  }) {
    createCalls++;
    return createCompleter?.future ?? Future.value(_expense());
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

ExpenseModel _expense({String id = 'expense-1'}) {
  final now = DateTime(2026, 9, 23);
  return ExpenseModel(
    id: id,
    companyId: 'default_company',
    amount: 12,
    expenseDate: now,
    category: ExpenseCategory.fuel,
    customCategoryName: '',
    description: 'Parking near customer',
    paidByUid: 'rep-1',
    paidByName: 'Representative One',
    paidByRole: 'sales_rep',
    salesRepId: 'rep-1',
    salesRepName: 'Representative One',
    paymentMethod: 'cash',
    fundingSource: ExpenseFundingSource.personalCash,
    status: ExpenseStatus.pending,
    cashMovementId: '',
    reimbursementStatus: ExpenseReimbursementStatus.none,
    approvedByUid: '',
    approvedByName: '',
    approvedAt: null,
    rejectedByUid: '',
    rejectedByName: '',
    rejectedAt: null,
    rejectionReason: '',
    createdByUid: 'rep-1',
    createdByName: 'Representative One',
    createdByRole: 'sales_rep',
    createdAt: now,
    updatedAt: now,
  );
}
