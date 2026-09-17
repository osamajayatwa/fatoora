import 'dart:async';

import 'package:fatoora/app/routes/app_routes.dart';
import 'package:fatoora/core/class/statusrequest.dart';
import 'package:fatoora/core/constants/color.dart';
import 'package:fatoora/core/data/firestore_query_pager.dart';
import 'package:fatoora/core/services/services.dart';
import 'package:fatoora/core/search/server_search_policy.dart';
import 'package:fatoora/features/auth/data/repositories/auth_repository.dart';
import 'package:fatoora/features/expenses/controllers/expense_error_mapper.dart';
import 'package:fatoora/features/expenses/data/models/expense_model.dart';
import 'package:fatoora/features/expenses/data/repositories/expense_repository.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class ExpensesListController extends GetxController {
  ExpensesListController({
    required ExpenseRepository repository,
    required MyServices myServices,
  }) : _repository = repository,
       _myServices = myServices;

  final ExpenseRepository _repository;
  final MyServices _myServices;
  final TextEditingController searchController = TextEditingController();

  StatusRequest statusRequest = StatusRequest.loading;
  String loadErrorMessageKey = 'expenses_load_error';
  List<ExpenseModel> expenses = const [];
  String searchText = '';
  ExpenseStatus? statusFilter;
  ExpenseCategory? categoryFilter;
  DateTime? fromDate;
  DateTime? toDate;
  Timer? _searchDebounce;
  int _loadGeneration = 0;
  String _appliedSearchText = '';
  bool isLoadingMore = false;
  bool hasMore = false;
  FirestorePageCursor? _pageCursor;
  double _postedExpenseTotal = 0;
  int _pendingExpenseCount = 0;
  double _payableReimbursements = 0;

  String get companyId =>
      _myServices.sharedPreferences.getString('companyId') ??
      AuthRepository.defaultCompanyId;

  bool get isAdmin =>
      _myServices.sharedPreferences.getString('role') ==
      AuthRepository.adminRole;

  bool get hasFilters =>
      searchText.trim().isNotEmpty ||
      statusFilter != null ||
      categoryFilter != null ||
      fromDate != null ||
      toDate != null;

  double get postedExpenseTotal => _postedExpenseTotal;
  int get pendingExpenseCount => _pendingExpenseCount;
  double get payableReimbursements => _payableReimbursements;

  @override
  void onReady() {
    super.onReady();
    loadExpenses();
  }

  Future<void> loadExpenses() async {
    _searchDebounce?.cancel();
    final generation = ++_loadGeneration;
    final requestedSearch = serverSearchTerm(searchText);
    statusRequest = StatusRequest.loading;
    _pageCursor = null;
    hasMore = false;
    loadErrorMessageKey = 'expenses_load_error';
    update();
    try {
      final page = await _repository.fetchExpensesPage(
        companyId: companyId,
        searchText: requestedSearch,
        status: statusFilter,
        category: categoryFilter,
        fromDate: fromDate,
        toDate: toDate,
      );
      if (generation != _loadGeneration) return;
      expenses = page.items;
      _pageCursor = page.cursor;
      hasMore = page.hasMore;
      _postedExpenseTotal = page.postedTotal;
      _pendingExpenseCount = page.pendingCount;
      _payableReimbursements = page.payableReimbursements;
      _appliedSearchText = requestedSearch;
      statusRequest = StatusRequest.success;
    } catch (error) {
      if (generation != _loadGeneration) return;
      statusRequest = ExpenseErrorMapper.status(error);
      loadErrorMessageKey = ExpenseErrorMapper.messageKey(
        error,
        fallback: 'expenses_load_error',
      );
      _showError(loadErrorMessageKey);
    }
    if (!isClosed) update();
  }

  Future<void> refreshExpenses() => loadExpenses();

  Future<void> loadMoreExpenses() async {
    if (isLoadingMore || !hasMore || _pageCursor == null) return;
    isLoadingMore = true;
    final generation = _loadGeneration;
    update();
    try {
      final page = await _repository.fetchExpensesPage(
        companyId: companyId,
        searchText: serverSearchTerm(searchText),
        status: statusFilter,
        category: categoryFilter,
        fromDate: fromDate,
        toDate: toDate,
        after: _pageCursor,
      );
      if (generation != _loadGeneration) return;
      expenses = [...expenses, ...page.items];
      _pageCursor = page.cursor;
      hasMore = page.hasMore;
    } catch (error) {
      if (generation == _loadGeneration) {
        _showError(ExpenseErrorMapper.messageKey(error));
      }
    } finally {
      isLoadingMore = false;
      if (!isClosed) update();
    }
  }

  void onSearchChanged(String value) {
    searchText = value;
    _searchDebounce?.cancel();
    _loadGeneration++;
    update();
    if (serverSearchTerm(value).isEmpty) {
      if (_appliedSearchText.isNotEmpty ||
          statusRequest != StatusRequest.success) {
        loadExpenses();
      }
      return;
    }
    _searchDebounce = Timer(serverSearchDebounce, loadExpenses);
  }

  void submitSearch() {
    _searchDebounce?.cancel();
    if (serverSearchTerm(searchText).isEmpty &&
        _appliedSearchText.isEmpty &&
        statusRequest == StatusRequest.success) {
      return;
    }
    loadExpenses();
  }

  void clearSearch() {
    _searchDebounce?.cancel();
    searchText = '';
    searchController.clear();
    loadExpenses();
  }

  void setStatusFilter(ExpenseStatus? value) {
    statusFilter = value;
    loadExpenses();
  }

  void setCategoryFilter(ExpenseCategory? value) {
    categoryFilter = value;
    loadExpenses();
  }

  void setDateRange(DateTimeRange? range) {
    fromDate = range?.start;
    toDate = range?.end;
    loadExpenses();
  }

  void clearFilters() {
    _searchDebounce?.cancel();
    searchText = '';
    searchController.clear();
    statusFilter = null;
    categoryFilter = null;
    fromDate = null;
    toDate = null;
    loadExpenses();
  }

  Future<void> openCreateExpense() async {
    final changed = await Get.toNamed(
      AppRoute.createExpense,
      arguments: {'companyId': companyId},
    );
    if (changed == true) await loadExpenses();
  }

  Future<void> openDetails(ExpenseModel expense) async {
    final changed = await Get.toNamed(
      AppRoute.expenseDetailsPath(expense.id),
      arguments: {'companyId': expense.companyId, 'expenseId': expense.id},
    );
    if (changed == true) await loadExpenses();
  }

  void _showError(String messageKey) {
    Get.snackbar(
      'expenses'.tr,
      messageKey.tr,
      snackPosition: SnackPosition.BOTTOM,
      backgroundColor: AppColor.error,
      colorText: AppColor.surface,
    );
  }

  @override
  void onClose() {
    _searchDebounce?.cancel();
    searchController.dispose();
    super.onClose();
  }
}
