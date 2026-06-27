import 'dart:async';

import 'package:fatoora/app/routes/app_routes.dart';
import 'package:fatoora/core/class/statusrequest.dart';
import 'package:fatoora/core/constants/color.dart';
import 'package:fatoora/core/services/services.dart';
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
  }) : _repository = repository,
       _myServices = myServices;

  final QuotationRepository _repository;
  final MyServices _myServices;
  final TextEditingController searchController = TextEditingController();

  StatusRequest statusRequest = StatusRequest.loading;
  String loadErrorMessageKey = 'quotations_load_error';
  List<QuotationModel> quotations = const [];
  String searchText = '';
  QuotationStatus? statusFilter;
  Timer? _searchDebounce;

  String get companyId =>
      _myServices.sharedPreferences.getString('companyId') ??
      AuthRepository.defaultCompanyId;

  bool get hasFilters => searchText.trim().isNotEmpty || statusFilter != null;

  @override
  void onReady() {
    super.onReady();
    loadQuotations();
  }

  Future<void> loadQuotations() async {
    statusRequest = StatusRequest.loading;
    loadErrorMessageKey = 'quotations_load_error';
    update();
    try {
      quotations = await _repository.fetchQuotations(
        companyId: companyId,
        status: statusFilter,
        searchText: searchText,
      );
      statusRequest = StatusRequest.success;
    } catch (error) {
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

  void onSearchChanged(String value) {
    searchText = value;
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 350), loadQuotations);
    update();
  }

  void setStatusFilter(QuotationStatus? value) {
    statusFilter = value;
    loadQuotations();
  }

  void clearFilters() {
    statusFilter = null;
    searchText = '';
    searchController.clear();
    loadQuotations();
  }

  Future<void> openCreateQuotation() async {
    final changed = await Get.toNamed(
      AppRoute.createQuotation,
      arguments: {'companyId': companyId},
    );
    if (changed == true) await loadQuotations();
  }

  Future<void> openDetails(QuotationModel quotation) async {
    final changed = await Get.toNamed(
      AppRoute.quotationDetails,
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
