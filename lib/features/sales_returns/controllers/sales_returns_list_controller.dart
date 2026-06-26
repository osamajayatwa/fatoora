import 'dart:async';

import 'package:fatoora/app/routes/app_routes.dart';
import 'package:fatoora/core/class/statusrequest.dart';
import 'package:fatoora/core/constants/color.dart';
import 'package:fatoora/core/services/services.dart';
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
  Timer? _searchDebounce;

  String get companyId =>
      _myServices.sharedPreferences.getString('companyId') ?? 'default_company';

  bool get hasFilters => searchText.trim().isNotEmpty || statusFilter != null;

  @override
  void onReady() {
    super.onReady();
    loadSalesReturns();
  }

  Future<void> loadSalesReturns() async {
    statusRequest = StatusRequest.loading;
    loadErrorMessageKey = 'sales_returns_load_error';
    update();
    try {
      salesReturns = await _repository.fetchSalesReturns(
        companyId: companyId,
        status: statusFilter,
        searchText: searchText,
      );
      statusRequest = StatusRequest.success;
    } catch (error) {
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

  void onSearchChanged(String value) {
    searchText = value;
    _searchDebounce?.cancel();
    _searchDebounce = Timer(
      const Duration(milliseconds: 350),
      loadSalesReturns,
    );
    update();
  }

  void setStatusFilter(SalesReturnStatus? value) {
    statusFilter = value;
    loadSalesReturns();
  }

  void clearFilters() {
    statusFilter = null;
    searchText = '';
    searchController.clear();
    loadSalesReturns();
  }

  Future<void> openDetails(SalesReturnModel salesReturn) async {
    final changed = await Get.toNamed(
      AppRoute.salesReturnDetails,
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
