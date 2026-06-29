import 'package:fatoora/app/routes/app_routes.dart';
import 'package:fatoora/core/class/statusrequest.dart';
import 'package:fatoora/core/constants/color.dart';
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
  List<CustomerModel> _allCustomers = const [];
  String searchText = '';

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
    statusRequest = StatusRequest.loading;
    loadErrorMessageKey = 'statements_load_error';
    update();
    try {
      _allCustomers = await _repository.fetchCustomers(companyId: companyId);
      _applySearch();
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
    _applySearch();
    update();
  }

  void clearSearch() {
    searchText = '';
    searchController.clear();
    _applySearch();
    update();
  }

  void _applySearch() {
    final query = CustomerModel.normalizeText(searchText);
    if (query.isEmpty) {
      customers = _allCustomers;
      return;
    }
    customers = _allCustomers
        .where((customer) {
          final values = [
            customer.name,
            customer.phone,
            customer.city,
            customer.area,
            customer.addressText,
          ];
          return values.any(
            (value) => CustomerModel.normalizeText(value).contains(query),
          );
        })
        .toList(growable: false);
  }

  void openStatement(CustomerModel customer) {
    Get.toNamed(
      AppRoute.customerStatement,
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
    searchController.dispose();
    super.onClose();
  }
}
