import 'dart:async';

import 'package:fatoora/app/routes/app_routes.dart';
import 'package:fatoora/core/class/statusrequest.dart';
import 'package:fatoora/core/constants/color.dart';
import 'package:fatoora/core/data/firestore_query_pager.dart';
import 'package:fatoora/core/services/services.dart';
import 'package:fatoora/core/search/server_search_policy.dart';
import 'package:fatoora/features/sales_returns/controllers/sales_return_error_mapper.dart';
import 'package:fatoora/features/sales_returns/data/models/sales_return_enums.dart';
import 'package:fatoora/features/sales_returns/data/models/sales_return_model.dart';
import 'package:fatoora/features/sales_returns/data/repositories/sales_return_repository.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class SalesReturnsListController extends GetxController {
  SalesReturnsListController({
    required SalesReturnRepository repository,
    required MyServices myServices,
  }) : _repository = repository,
       _myServices = myServices;

  final SalesReturnRepository _repository;
  final MyServices _myServices;
  final searchController = TextEditingController();

  StatusRequest statusRequest = StatusRequest.loading;
  String loadErrorMessageKey = 'sales_returns_load_error';
  List<SalesReturnModel> salesReturns = const [];
  SalesReturnStatus? statusFilter;
  String searchText = '';
  bool isLoadingMore = false;
  bool hasMore = false;
  FirestorePageCursor? _pageCursor;
  Timer? _searchDebounce;
  int _loadGeneration = 0;
  String _appliedSearchText = '';

  String get companyId =>
      _myServices.sharedPreferences.getString('companyId') ?? 'default_company';

  bool get hasFilters => searchText.trim().isNotEmpty || statusFilter != null;

  @override
  void onReady() {
    super.onReady();
    loadSalesReturns();
  }

  Future<void> loadSalesReturns() async {
    _searchDebounce?.cancel();
    final generation = ++_loadGeneration;
    final requestedSearch = serverSearchTerm(searchText);
    statusRequest = StatusRequest.loading;
    _pageCursor = null;
    hasMore = false;
    loadErrorMessageKey = 'sales_returns_load_error';
    update();
    try {
      final page = await _repository.fetchSalesReturnsPage(
        companyId: companyId,
        status: statusFilter,
        searchText: requestedSearch,
      );
      if (generation != _loadGeneration) return;
      salesReturns = page.items;
      _pageCursor = page.cursor;
      hasMore = page.hasMore;
      _appliedSearchText = requestedSearch;
      statusRequest = StatusRequest.success;
    } catch (error) {
      if (generation != _loadGeneration) return;
      statusRequest = SalesReturnErrorMapper.status(error);
      loadErrorMessageKey = SalesReturnErrorMapper.messageKey(
        error,
        fallback: 'sales_returns_load_error',
      );
      _showError(loadErrorMessageKey);
    }
    if (!isClosed) update();
  }

  Future<void> refreshSalesReturns() => loadSalesReturns();

  Future<void> loadMoreSalesReturns() async {
    if (isLoadingMore || !hasMore || _pageCursor == null) return;
    isLoadingMore = true;
    final generation = _loadGeneration;
    update();
    try {
      final page = await _repository.fetchSalesReturnsPage(
        companyId: companyId,
        status: statusFilter,
        searchText: serverSearchTerm(searchText),
        after: _pageCursor,
      );
      if (generation != _loadGeneration) return;
      salesReturns = [...salesReturns, ...page.items];
      _pageCursor = page.cursor;
      hasMore = page.hasMore;
    } catch (error) {
      if (generation != _loadGeneration) return;
      _showError(SalesReturnErrorMapper.messageKey(error));
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
        loadSalesReturns();
      }
      return;
    }
    _searchDebounce = Timer(serverSearchDebounce, loadSalesReturns);
  }

  void submitSearch() {
    _searchDebounce?.cancel();
    if (serverSearchTerm(searchText).isEmpty &&
        _appliedSearchText.isEmpty &&
        statusRequest == StatusRequest.success) {
      return;
    }
    loadSalesReturns();
  }

  void clearSearch() {
    _searchDebounce?.cancel();
    searchText = '';
    searchController.clear();
    loadSalesReturns();
  }

  void setStatusFilter(SalesReturnStatus? value) {
    statusFilter = value;
    loadSalesReturns();
  }

  void clearFilters() {
    _searchDebounce?.cancel();
    statusFilter = null;
    searchText = '';
    searchController.clear();
    loadSalesReturns();
  }

  Future<void> openDetails(SalesReturnModel salesReturn) async {
    final changed = await Get.toNamed(
      AppRoute.salesReturnDetailsPath(salesReturn.id),
      arguments: {
        'companyId': salesReturn.companyId,
        'returnId': salesReturn.id,
      },
    );
    if (changed == true) await loadSalesReturns();
  }

  void _showError(String messageKey) {
    Get.snackbar(
      'sales_returns'.tr,
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
