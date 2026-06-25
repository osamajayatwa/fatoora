import 'dart:async';

import 'package:fatoora/app/routes/app_routes.dart';
import 'package:fatoora/core/class/statusrequest.dart';
import 'package:fatoora/core/constants/color.dart';
import 'package:fatoora/core/services/services.dart';
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
  }) : _repository = repository,
       _myServices = myServices;

  final ReceiptRepository _repository;
  final MyServices _myServices;
  final TextEditingController searchController = TextEditingController();

  StatusRequest statusRequest = StatusRequest.loading;
  String loadErrorMessageKey = 'receipts_load_error';
  List<ReceiptModel> receipts = const [];
  String searchText = '';
  DateTime? fromDate;
  DateTime? toDate;
  Timer? _searchDebounce;

  String get companyId =>
      _myServices.sharedPreferences.getString('companyId') ??
      AuthRepository.defaultCompanyId;

  bool get hasFilters =>
      searchText.trim().isNotEmpty || fromDate != null || toDate != null;

  @override
  void onReady() {
    super.onReady();
    loadReceipts();
  }

  Future<void> loadReceipts() async {
    statusRequest = StatusRequest.loading;
    loadErrorMessageKey = 'receipts_load_error';
    update();
    try {
      receipts = await _repository.fetchReceipts(
        companyId: companyId,
        searchText: searchText,
        fromDate: fromDate,
        toDate: toDate,
      );
      statusRequest = StatusRequest.success;
    } catch (error) {
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
    update();
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 350), loadReceipts);
  }

  void setDateRange(DateTimeRange? range) {
    fromDate = range?.start;
    toDate = range?.end;
    loadReceipts();
  }

  void clearFilters() {
    fromDate = null;
    toDate = null;
    searchText = '';
    searchController.clear();
    loadReceipts();
  }

  Future<void> openCreateReceipt() async {
    final changed = await Get.toNamed(
      AppRoute.createReceipt,
      arguments: {'companyId': companyId},
    );
    if (changed == true) await loadReceipts();
  }

  Future<void> openDetails(ReceiptModel receipt) async {
    await Get.toNamed(
      AppRoute.receiptDetails,
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
