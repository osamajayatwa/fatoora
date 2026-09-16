import 'dart:async';

import 'package:fatoora/app/routes/app_routes.dart';
import 'package:fatoora/core/class/handilingdataview.dart';
import 'package:fatoora/core/class/statusrequest.dart';
import 'package:fatoora/core/constants/color.dart';
import 'package:fatoora/core/search/server_search_policy.dart';
import 'package:fatoora/core/widgets/responsive_picker_sheet.dart';
import 'package:fatoora/core/services/services.dart';
import 'package:fatoora/core/settings/business_permission_resolver.dart';
import 'package:fatoora/features/auth/data/repositories/auth_repository.dart';
import 'package:fatoora/features/customers/bindings/customers_binding.dart';
import 'package:fatoora/features/customers/controllers/customer_error_mapper.dart';
import 'package:fatoora/features/customers/data/models/customer_model.dart';
import 'package:fatoora/features/customers/data/repositories/customer_repository.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

Future<CustomerModel?> showCustomerPicker(BuildContext context) {
  registerCustomerDependencies();
  final content = const CustomerPickerSheet();
  final wide = MediaQuery.sizeOf(context).width >= 760;
  if (wide) {
    return Get.dialog<CustomerModel>(
      Dialog(
        insetPadding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720, maxHeight: 720),
          child: content,
        ),
      ),
    );
  }
  return Get.bottomSheet<CustomerModel>(
    content,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
  );
}

class CustomerPickerSheet extends StatefulWidget {
  const CustomerPickerSheet({super.key});

  @override
  State<CustomerPickerSheet> createState() => _CustomerPickerSheetState();
}

class _CustomerPickerSheetState extends State<CustomerPickerSheet> {
  final CustomerRepository _repository = Get.find<CustomerRepository>();
  final BusinessPermissionResolver _permissionResolver =
      Get.find<BusinessPermissionResolver>();
  final MyServices _myServices = Get.find<MyServices>();
  final TextEditingController _searchController = TextEditingController();

  StatusRequest _statusRequest = StatusRequest.loading;
  List<CustomerModel> _customers = const [];
  String _errorMessageKey = 'customers_load_error';
  String _searchText = '';
  String _appliedSearchText = '';
  int _requestGeneration = 0;
  Timer? _searchDebounce;
  EffectiveBusinessPermissions _permissions =
      EffectiveBusinessPermissions.denied;

  String get _companyId =>
      _myServices.sharedPreferences.getString('companyId') ??
      AuthRepository.defaultCompanyId;

  @override
  void initState() {
    super.initState();
    _loadCustomers();
  }

  Future<void> _loadCustomers() async {
    _searchDebounce?.cancel();
    final generation = ++_requestGeneration;
    final requestedSearch = serverSearchTerm(_searchText);
    setState(() {
      _statusRequest = StatusRequest.loading;
      _errorMessageKey = 'customers_load_error';
    });
    try {
      final values = await Future.wait<Object>([
        _repository.fetchCustomers(
          companyId: _companyId,
          searchText: requestedSearch,
        ),
        _permissionResolver.resolve(_companyId),
      ]);
      final customers = values[0] as List<CustomerModel>;
      final permissions = values[1] as EffectiveBusinessPermissions;
      if (!mounted || generation != _requestGeneration) return;
      setState(() {
        _customers = customers;
        _permissions = permissions;
        _appliedSearchText = requestedSearch;
        _statusRequest = StatusRequest.success;
      });
    } catch (error) {
      if (!mounted || generation != _requestGeneration) return;
      setState(() {
        _statusRequest = CustomerErrorMapper.status(error);
        _errorMessageKey = CustomerErrorMapper.messageKey(
          error,
          fallback: 'customers_load_error',
        );
      });
    }
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    _requestGeneration++;
    setState(() => _searchText = value);
    if (serverSearchTerm(value).isEmpty) {
      if (_appliedSearchText.isNotEmpty ||
          _statusRequest != StatusRequest.success) {
        _loadCustomers();
      }
      return;
    }
    _searchDebounce = Timer(serverSearchDebounce, _loadCustomers);
  }

  void _submitSearch() {
    _searchDebounce?.cancel();
    if (serverSearchTerm(_searchText).isEmpty &&
        _appliedSearchText.isEmpty &&
        _statusRequest == StatusRequest.success) {
      return;
    }
    _loadCustomers();
  }

  void _clearSearch() {
    _searchDebounce?.cancel();
    _requestGeneration++;
    _searchController.clear();
    setState(() => _searchText = '');
    _loadCustomers();
  }

  Future<void> _addCustomer() async {
    if (!_permissions.createCustomers) {
      Get.snackbar(
        'permission_denied'.tr,
        'sales_rep_customer_create_disabled'.tr,
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: AppColor.error,
        colorText: AppColor.surface,
      );
      return;
    }
    final created = await Get.toNamed(
      AppRoute.createCustomer,
      arguments: {'returnCustomer': true},
    );
    if (created is CustomerModel) {
      Get.back<CustomerModel>(result: created);
      return;
    }
    await _loadCustomers();
  }

  @override
  Widget build(BuildContext context) {
    return ResponsivePickerSheet(
      header: Row(
        children: [
          Expanded(
            child: Text(
              'select_customer'.tr,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: AppColor.secondaryColor,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          IconButton(
            onPressed: Get.back<void>,
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
      search: TextField(
        controller: _searchController,
        onChanged: _onSearchChanged,
        onSubmitted: (_) => _submitSearch(),
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: 'customers_search_hint'.tr,
          prefixIcon: const Icon(Icons.search_rounded),
          suffixIcon: _searchText.isEmpty
              ? null
              : IconButton(
                  onPressed: _clearSearch,
                  icon: const Icon(Icons.close_rounded),
                ),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
      body: HandilingDataView(
        statusrequest: _statusRequest,
        errorMessage: _errorMessageKey.tr,
        retryLabel: 'items_retry'.tr,
        onRetry: _loadCustomers,
        widget: _customers.isEmpty
            ? _EmptyPicker(
                onAdd: _permissions.createCustomers ? _addCustomer : null,
              )
            : ListView.separated(
                itemBuilder: (context, index) {
                  final customer = _customers[index];
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const CircleAvatar(
                      backgroundColor: Color(0xFFF4F6FA),
                      child: Icon(Icons.person_outline),
                    ),
                    title: Text(customer.name),
                    subtitle: Text(
                      [
                        customer.phone,
                        customer.city,
                        customer.area,
                      ].where((item) => item.isNotEmpty).join(' / '),
                    ),
                    trailing: const Icon(Icons.check_rounded),
                    onTap: () => Get.back<CustomerModel>(result: customer),
                  );
                },
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemCount: _customers.length,
              ),
      ),
      footer: _permissions.createCustomers
          ? OutlinedButton.icon(
              onPressed: _addCustomer,
              icon: const Icon(Icons.person_add_alt_1_outlined),
              label: Text('customers_add'.tr),
            )
          : null,
    );
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }
}

class _EmptyPicker extends StatelessWidget {
  const _EmptyPicker({required this.onAdd});

  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('customers_empty'.tr),
            if (onAdd != null) ...[
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: onAdd,
                icon: const Icon(Icons.person_add_alt_1_outlined),
                label: Text('customers_add'.tr),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
