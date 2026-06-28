import 'package:fatoora/app/routes/app_routes.dart';
import 'package:fatoora/core/class/handilingdataview.dart';
import 'package:fatoora/core/class/statusrequest.dart';
import 'package:fatoora/core/constants/color.dart';
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
    setState(() {
      _statusRequest = StatusRequest.loading;
      _errorMessageKey = 'customers_load_error';
    });
    try {
      final values = await Future.wait<Object>([
        _repository.fetchCustomers(
          companyId: _companyId,
          searchText: _searchText,
        ),
        _permissionResolver.resolve(_companyId),
      ]);
      final customers = values[0] as List<CustomerModel>;
      final permissions = values[1] as EffectiveBusinessPermissions;
      if (!mounted) return;
      setState(() {
        _customers = customers;
        _permissions = permissions;
        _statusRequest = StatusRequest.success;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _statusRequest = CustomerErrorMapper.status(error);
        _errorMessageKey = CustomerErrorMapper.messageKey(
          error,
          fallback: 'customers_load_error',
        );
      });
    }
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
    return Material(
      color: AppColor.surface,
      borderRadius: BorderRadius.circular(18),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            18,
            18,
            18,
            MediaQuery.viewInsetsOf(context).bottom + 18,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
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
              const SizedBox(height: 12),
              TextField(
                controller: _searchController,
                onChanged: (value) {
                  _searchText = value;
                  _loadCustomers();
                },
                decoration: InputDecoration(
                  hintText: 'customers_search_hint'.tr,
                  prefixIcon: const Icon(Icons.search_rounded),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(context).height * 0.58,
                ),
                child: HandilingDataView(
                  statusrequest: _statusRequest,
                  errorMessage: _errorMessageKey.tr,
                  retryLabel: 'items_retry'.tr,
                  onRetry: _loadCustomers,
                  widget: _customers.isEmpty
                      ? _EmptyPicker(
                          onAdd: _permissions.createCustomers
                              ? _addCustomer
                              : null,
                        )
                      : ListView.separated(
                          shrinkWrap: true,
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
                              onTap: () =>
                                  Get.back<CustomerModel>(result: customer),
                            );
                          },
                          separatorBuilder: (_, _) => const Divider(height: 1),
                          itemCount: _customers.length,
                        ),
                ),
              ),
              if (_permissions.createCustomers) ...[
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _addCustomer,
                  icon: const Icon(Icons.person_add_alt_1_outlined),
                  label: Text('customers_add'.tr),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
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
