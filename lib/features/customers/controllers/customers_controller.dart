import 'dart:async';

import 'package:fatoora/app/routes/app_routes.dart';
import 'package:fatoora/core/class/statusrequest.dart';
import 'package:fatoora/core/constants/color.dart';
import 'package:fatoora/core/services/services.dart';
import 'package:fatoora/core/search/server_search_policy.dart';
import 'package:fatoora/core/settings/business_permission_resolver.dart';
import 'package:fatoora/features/auth/data/repositories/auth_repository.dart';
import 'package:fatoora/features/customers/controllers/customer_error_mapper.dart';
import 'package:fatoora/features/customers/data/models/customer_model.dart';
import 'package:fatoora/features/customers/data/repositories/customer_repository.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class CustomersController extends GetxController {
  CustomersController({
    required CustomerRepository repository,
    required MyServices myServices,
    required BusinessPermissionResolver permissionResolver,
  }) : _repository = repository,
       _myServices = myServices,
       _permissionResolver = permissionResolver;

  final CustomerRepository _repository;
  final MyServices _myServices;
  final BusinessPermissionResolver _permissionResolver;
  final TextEditingController searchController = TextEditingController();

  StatusRequest statusRequest = StatusRequest.loading;
  List<CustomerModel> customers = const [];
  String searchText = '';
  String loadErrorMessageKey = 'customers_load_error';
  Timer? _searchDebounce;
  int _loadGeneration = 0;
  String _appliedSearchText = '';
  EffectiveBusinessPermissions permissions =
      EffectiveBusinessPermissions.denied;

  String get companyId =>
      _myServices.sharedPreferences.getString('companyId') ??
      AuthRepository.defaultCompanyId;

  bool get hasSearch => searchText.trim().isNotEmpty;
  bool get canCreateCustomer => permissions.createCustomers;

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
    loadErrorMessageKey = 'customers_load_error';
    update();
    try {
      final resolvedPermissions = await _permissionResolver.resolve(companyId);
      final loadedCustomers = await _repository.fetchCustomers(
        companyId: companyId,
        searchText: requestedSearch,
      );
      if (generation != _loadGeneration) return;
      permissions = resolvedPermissions;
      customers = loadedCustomers;
      _appliedSearchText = requestedSearch;
      statusRequest = StatusRequest.success;
    } catch (error) {
      if (generation != _loadGeneration) return;
      statusRequest = CustomerErrorMapper.status(error);
      loadErrorMessageKey = CustomerErrorMapper.messageKey(
        error,
        fallback: 'customers_load_error',
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
      if (_appliedSearchText.isNotEmpty ||
          statusRequest != StatusRequest.success) {
        loadCustomers();
      }
      return;
    }
    _searchDebounce = Timer(serverSearchDebounce, loadCustomers);
  }

  void submitSearch() {
    _searchDebounce?.cancel();
    if (serverSearchTerm(searchText).isEmpty &&
        _appliedSearchText.isEmpty &&
        statusRequest == StatusRequest.success) {
      return;
    }
    loadCustomers();
  }

  void clearSearch() {
    _searchDebounce?.cancel();
    searchText = '';
    searchController.clear();
    loadCustomers();
  }

  Future<void> openCreateCustomer() async {
    if (!canCreateCustomer) {
      _showError('sales_rep_customer_create_disabled');
      return;
    }
    final result = await Get.toNamed(AppRoute.createCustomer);
    if (result == true || result is CustomerModel) await loadCustomers();
  }

  Future<void> openCustomerDetails(CustomerModel customer) async {
    final changed = await Get.toNamed(
      AppRoute.customerDetailsPath(customer.id),
      arguments: {'companyId': customer.companyId, 'customerId': customer.id},
    );
    if (changed == true) await loadCustomers();
  }

  Future<void> goBack() async {
    if (Get.key.currentState?.canPop() ?? false) {
      Get.back<void>();
      return;
    }
    final role = _myServices.sharedPreferences.getString('role') ?? '';
    await Get.offAllNamed(
      role == AuthRepository.adminRole ? AppRoute.adminHome : AppRoute.home,
    );
  }

  void _showError(String messageKey) {
    Get.snackbar(
      'customers'.tr,
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
