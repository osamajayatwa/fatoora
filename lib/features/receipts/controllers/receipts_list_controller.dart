import 'dart:async';

import 'package:fatoora/app/routes/app_routes.dart';
import 'package:fatoora/core/class/statusrequest.dart';
import 'package:fatoora/core/constants/color.dart';
import 'package:fatoora/core/services/services.dart';
import 'package:fatoora/core/search/server_search_policy.dart';
import 'package:fatoora/core/settings/business_permission_resolver.dart';
import 'package:fatoora/features/auth/data/repositories/auth_repository.dart';
import 'package:fatoora/features/receipts/controllers/receipt_error_mapper.dart';
import 'package:fatoora/features/receipts/data/models/receipt_model.dart';
import 'package:fatoora/features/receipts/data/repositories/receipt_repository.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class ReceiptsListController extends GetxController {
  ReceiptsListController({
    required ReceiptRepository repository,
    required MyServices myServices,
    required BusinessPermissionResolver permissionResolver,
  }) : _repository = repository,
       _myServices = myServices,
       _permissionResolver = permissionResolver;

  final ReceiptRepository _repository;
  final MyServices _myServices;
  final BusinessPermissionResolver _permissionResolver;
  final TextEditingController searchController = TextEditingController();

  StatusRequest statusRequest = StatusRequest.loading;
  String loadErrorMessageKey = 'receipts_load_error';
  List<ReceiptModel> receipts = const [];
  String searchText = '';
  DateTime? fromDate;
  DateTime? toDate;
  Timer? _searchDebounce;
  int _loadGeneration = 0;
  String _appliedSearchText = '';
  EffectiveBusinessPermissions permissions =
      EffectiveBusinessPermissions.denied;

  String get companyId =>
      _myServices.sharedPreferences.getString('companyId') ??
      AuthRepository.defaultCompanyId;

  bool get hasFilters =>
      searchText.trim().isNotEmpty || fromDate != null || toDate != null;
  bool get canCreateReceipt => permissions.createReceipts;

  @override
  void onReady() {
    super.onReady();
    loadReceipts();
  }

  Future<void> loadReceipts() async {
    _searchDebounce?.cancel();
    final generation = ++_loadGeneration;
    final requestedSearch = serverSearchTerm(searchText);
    statusRequest = StatusRequest.loading;
    loadErrorMessageKey = 'receipts_load_error';
    update();
    try {
      final resolvedPermissions = await _permissionResolver.resolve(companyId);
      final loadedReceipts = await _repository.fetchReceipts(
        companyId: companyId,
        searchText: requestedSearch,
        fromDate: fromDate,
        toDate: toDate,
      );
      if (generation != _loadGeneration) return;
      permissions = resolvedPermissions;
      receipts = loadedReceipts;
      _appliedSearchText = requestedSearch;
      statusRequest = StatusRequest.success;
    } catch (error) {
      if (generation != _loadGeneration) return;
      statusRequest = ReceiptErrorMapper.status(error);
      loadErrorMessageKey = ReceiptErrorMapper.messageKey(
        error,
        fallback: 'receipts_load_error',
      );
      _showError(loadErrorMessageKey);
    }
    if (!isClosed) update();
  }

  Future<void> refreshReceipts() => loadReceipts();

  void onSearchChanged(String value) {
    searchText = value;
    _searchDebounce?.cancel();
    _loadGeneration++;
    update();
    if (serverSearchTerm(value).isEmpty) {
      if (_appliedSearchText.isNotEmpty ||
          statusRequest != StatusRequest.success) {
        loadReceipts();
      }
      return;
    }
    _searchDebounce = Timer(serverSearchDebounce, loadReceipts);
  }

  void submitSearch() {
    _searchDebounce?.cancel();
    if (serverSearchTerm(searchText).isEmpty &&
        _appliedSearchText.isEmpty &&
        statusRequest == StatusRequest.success) {
      return;
    }
    loadReceipts();
  }

  void clearSearch() {
    _searchDebounce?.cancel();
    searchText = '';
    searchController.clear();
    loadReceipts();
  }

  void setDateRange(DateTimeRange? range) {
    fromDate = range?.start;
    toDate = range?.end;
    loadReceipts();
  }

  void clearFilters() {
    _searchDebounce?.cancel();
    fromDate = null;
    toDate = null;
    searchText = '';
    searchController.clear();
    loadReceipts();
  }

  Future<void> openCreateReceipt() async {
    if (!canCreateReceipt) {
      _showError('sales_rep_receipt_create_disabled');
      return;
    }
    final changed = await Get.toNamed(
      AppRoute.createReceipt,
      arguments: {'companyId': companyId},
    );
    if (changed == true) await loadReceipts();
  }

  Future<void> openDetails(ReceiptModel receipt) async {
    await Get.toNamed(
      AppRoute.receiptDetailsPath(receipt.id),
      arguments: {'companyId': receipt.companyId, 'receiptId': receipt.id},
    );
  }

  void _showError(String messageKey) {
    Get.snackbar(
      'receipts'.tr,
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
