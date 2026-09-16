import 'dart:async';

import 'package:fatoora/app/routes/app_routes.dart';
import 'package:fatoora/core/class/statusrequest.dart';
import 'package:fatoora/core/constants/color.dart';
import 'package:fatoora/core/data/firestore_query_pager.dart';
import 'package:fatoora/core/services/services.dart';
import 'package:fatoora/core/search/server_search_policy.dart';
import 'package:fatoora/core/settings/business_permission_resolver.dart';
import 'package:fatoora/features/auth/data/repositories/auth_repository.dart';
import 'package:fatoora/features/quotations/controllers/quotation_error_mapper.dart';
import 'package:fatoora/features/quotations/data/models/quotation_model.dart';
import 'package:fatoora/features/quotations/data/models/quotation_status.dart';
import 'package:fatoora/features/quotations/data/repositories/quotation_repository.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class QuotationsListController extends GetxController {
  QuotationsListController({
    required QuotationRepository repository,
    required MyServices myServices,
    required BusinessPermissionResolver permissionResolver,
  }) : _repository = repository,
       _myServices = myServices,
       _permissionResolver = permissionResolver;

  final QuotationRepository _repository;
  final MyServices _myServices;
  final BusinessPermissionResolver _permissionResolver;
  final TextEditingController searchController = TextEditingController();

  StatusRequest statusRequest = StatusRequest.loading;
  String loadErrorMessageKey = 'quotations_load_error';
  List<QuotationModel> quotations = const [];
  String searchText = '';
  QuotationStatus? statusFilter;
  Timer? _searchDebounce;
  bool isLoadingMore = false;
  bool hasMore = false;
  FirestorePageCursor? _pageCursor;
  int _loadGeneration = 0;
  String _appliedSearchText = '';
  EffectiveBusinessPermissions permissions =
      EffectiveBusinessPermissions.denied;

  String get companyId =>
      _myServices.sharedPreferences.getString('companyId') ??
      AuthRepository.defaultCompanyId;

  bool get hasFilters => searchText.trim().isNotEmpty || statusFilter != null;
  bool get canCreateQuotation => permissions.createQuotations;

  @override
  void onReady() {
    super.onReady();
    loadQuotations();
  }

  Future<void> loadQuotations() async {
    _searchDebounce?.cancel();
    final generation = ++_loadGeneration;
    final requestedSearch = serverSearchTerm(searchText);
    statusRequest = StatusRequest.loading;
    _pageCursor = null;
    hasMore = false;
    loadErrorMessageKey = 'quotations_load_error';
    update();
    try {
      permissions = await _permissionResolver.resolve(companyId);
      final page = await _repository.fetchQuotationsPage(
        companyId: companyId,
        status: statusFilter,
        searchText: requestedSearch,
      );
      if (generation != _loadGeneration) return;
      quotations = page.items;
      _appliedSearchText = requestedSearch;
      _pageCursor = page.cursor;
      hasMore = page.hasMore;
      statusRequest = StatusRequest.success;
    } catch (error) {
      if (generation != _loadGeneration) return;
      statusRequest = QuotationErrorMapper.status(error);
      loadErrorMessageKey = QuotationErrorMapper.messageKey(
        error,
        fallback: 'quotations_load_error',
      );
      _showError(loadErrorMessageKey);
    }
    if (!isClosed) update();
  }

  Future<void> refreshQuotations() => loadQuotations();

  Future<void> loadMoreQuotations() async {
    if (isLoadingMore || !hasMore || _pageCursor == null) return;
    isLoadingMore = true;
    final generation = _loadGeneration;
    update();
    try {
      final page = await _repository.fetchQuotationsPage(
        companyId: companyId,
        status: statusFilter,
        searchText: serverSearchTerm(searchText),
        after: _pageCursor,
      );
      if (generation != _loadGeneration) return;
      quotations = [...quotations, ...page.items];
      _pageCursor = page.cursor;
      hasMore = page.hasMore;
    } catch (error) {
      if (generation != _loadGeneration) return;
      _showError(QuotationErrorMapper.messageKey(error));
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
        loadQuotations();
      }
      return;
    }
    _searchDebounce = Timer(serverSearchDebounce, loadQuotations);
  }

  void submitSearch() {
    _searchDebounce?.cancel();
    if (serverSearchTerm(searchText).isEmpty &&
        _appliedSearchText.isEmpty &&
        statusRequest == StatusRequest.success) {
      return;
    }
    loadQuotations();
  }

  void clearSearch() {
    _searchDebounce?.cancel();
    searchText = '';
    searchController.clear();
    loadQuotations();
  }

  void setStatusFilter(QuotationStatus? value) {
    statusFilter = value;
    loadQuotations();
  }

  void clearFilters() {
    _searchDebounce?.cancel();
    statusFilter = null;
    searchText = '';
    searchController.clear();
    loadQuotations();
  }

  Future<void> openCreateQuotation() async {
    if (!canCreateQuotation) {
      _showError('sales_rep_quotation_create_disabled');
      return;
    }
    final changed = await Get.toNamed(
      AppRoute.createQuotation,
      arguments: {'companyId': companyId},
    );
    if (changed == true) await loadQuotations();
  }

  Future<void> openDetails(QuotationModel quotation) async {
    final changed = await Get.toNamed(
      AppRoute.quotationDetailsPath(quotation.id),
      arguments: {
        'companyId': quotation.companyId,
        'quotationId': quotation.id,
      },
    );
    if (changed == true) await loadQuotations();
  }

  void _showError(String messageKey) {
    Get.snackbar(
      'quotations'.tr,
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
