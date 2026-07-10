import 'dart:async';

import 'package:fatoora/app/routes/app_routes.dart';
import 'package:fatoora/core/class/statusrequest.dart';
import 'package:fatoora/core/constants/color.dart';
import 'package:fatoora/core/services/services.dart';
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

  double get postedExpenseTotal => _round(
    expenses
        .where((expense) => expense.isPostedOrApproved)
        .fold<double>(0, (total, expense) => total + expense.amount),
  );

  int get pendingExpenseCount => expenses
      .where((expense) => expense.status == ExpenseStatus.pending)
      .length;

  double get payableReimbursements => _round(
    expenses
        .where(
          (expense) =>
              expense.reimbursementStatus == ExpenseReimbursementStatus.payable,
        )
        .fold<double>(0, (total, expense) => total + expense.amount),
  );

  @override
  void onReady() {
    super.onReady();
    loadExpenses();
  }

  Future<void> loadExpenses() async {
    statusRequest = StatusRequest.loading;
    loadErrorMessageKey = 'expenses_load_error';
    update();
    try {
      expenses = await _repository.fetchExpenses(
        companyId: companyId,
        searchText: searchText,
        status: statusFilter,
        category: categoryFilter,
        fromDate: fromDate,
        toDate: toDate,
      );
      statusRequest = StatusRequest.success;
    } catch (error) {
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

  void onSearchChanged(String value) {
    searchText = value;
    update();
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 350), loadExpenses);
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
      AppRoute.expenseDetails,
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

  double _round(double value) {
    if (!value.isFinite) return 0;
    return (value * 1000).roundToDouble() / 1000;
  }

  @override
  void onClose() {
    _searchDebounce?.cancel();
    searchController.dispose();
    super.onClose();
  }
}
