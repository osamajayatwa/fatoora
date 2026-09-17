import 'dart:async';

import 'package:fatoora/app/routes/app_routes.dart';
import 'package:fatoora/core/class/statusrequest.dart';
import 'package:fatoora/core/constants/color.dart';
import 'package:fatoora/core/data/firestore_query_pager.dart';
import 'package:fatoora/core/search/server_search_policy.dart';
import 'package:fatoora/core/services/services.dart';
import 'package:fatoora/features/auth/data/repositories/auth_repository.dart';
import 'package:fatoora/features/customers/controllers/customer_error_mapper.dart';
import 'package:fatoora/features/customers/data/models/customer_model.dart';
import 'package:fatoora/features/customers/data/repositories/customer_repository.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class StatementsController extends GetxController {
  StatementsController({
    required CustomerRepository repository,
    required MyServices myServices,
  }) : _repository = repository,
       _myServices = myServices;

  final CustomerRepository _repository;
  final MyServices _myServices;
  final TextEditingController searchController = TextEditingController();

  StatusRequest statusRequest = StatusRequest.loading;
  String loadErrorMessageKey = 'statements_load_error';
  List<CustomerModel> customers = const [];
  String searchText = '';
  FirestorePageCursor? _pageCursor;
  bool hasMore = false;
  bool isLoadingMore = false;
  Timer? _searchDebounce;
  int _loadGeneration = 0;
  String _appliedSearch = '';

  String get companyId =>
      _myServices.sharedPreferences.getString('companyId') ??
      AuthRepository.defaultCompanyId;
  bool get isAdmin =>
      _myServices.sharedPreferences.getString('role') ==
      AuthRepository.adminRole;
  bool get hasSearch => searchText.trim().isNotEmpty;

  @override
  void onReady() {
    super.onReady();
    loadCustomers();
  }

  Future<void> loadCustomers() async {
    _searchDebounce?.cancel();
    final generation = ++_loadGeneration;
    final requestedSearch = serverSearchTerm(searchText);
    statusRequest = StatusRequest.loading;
    _pageCursor = null;
    hasMore = false;
    loadErrorMessageKey = 'statements_load_error';
    update();
    try {
      final page = await _repository.fetchCustomersPage(
        companyId: companyId,
        searchText: requestedSearch,
      );
      if (generation != _loadGeneration) return;
      customers = page.items;
      _pageCursor = page.cursor;
      hasMore = page.hasMore;
      _appliedSearch = requestedSearch;
      statusRequest = StatusRequest.success;
    } catch (error) {
      statusRequest = CustomerErrorMapper.status(error);
      loadErrorMessageKey = CustomerErrorMapper.messageKey(
        error,
        fallback: 'statements_load_error',
      );
      _showError(loadErrorMessageKey);
    }
    if (!isClosed) update();
  }

  Future<void> refreshCustomers() => loadCustomers();

  void onSearchChanged(String value) {
    searchText = value;
    _searchDebounce?.cancel();
    _loadGeneration++;
    update();
    if (serverSearchTerm(value).isEmpty) {
      if (_appliedSearch.isNotEmpty || statusRequest != StatusRequest.success) {
        loadCustomers();
      }
      return;
    }
    _searchDebounce = Timer(serverSearchDebounce, loadCustomers);
  }

  void submitSearch() {
    _searchDebounce?.cancel();
    loadCustomers();
  }

  void clearSearch() {
    searchText = '';
    searchController.clear();
    loadCustomers();
  }

  Future<void> loadMore() async {
    if (isLoadingMore || !hasMore || _pageCursor == null) return;
    isLoadingMore = true;
    final generation = _loadGeneration;
    update();
    try {
      final page = await _repository.fetchCustomersPage(
        companyId: companyId,
        searchText: serverSearchTerm(searchText),
        after: _pageCursor,
      );
      if (generation != _loadGeneration) return;
      customers = [...customers, ...page.items];
      _pageCursor = page.cursor;
      hasMore = page.hasMore;
    } catch (error) {
      if (generation == _loadGeneration) {
        _showError(CustomerErrorMapper.messageKey(error));
      }
    } finally {
      isLoadingMore = false;
      if (!isClosed) update();
    }
  }

  void openStatement(CustomerModel customer) {
    Get.toNamed(
      AppRoute.customerStatementPath(customer.id),
      arguments: {'companyId': customer.companyId, 'customerId': customer.id},
    );
  }

  Future<void> goBack() async {
    if (Get.key.currentState?.canPop() ?? false) {
      Get.back<void>();
      return;
    }
    await Get.offAllNamed(isAdmin ? AppRoute.adminHome : AppRoute.home);
  }

  void _showError(String messageKey) {
    Get.snackbar(
      'dashboard_account_statement'.tr,
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
