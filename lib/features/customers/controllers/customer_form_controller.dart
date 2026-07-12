import 'package:fatoora/core/class/statusrequest.dart';
import 'package:fatoora/core/constants/color.dart';
import 'package:fatoora/core/services/services.dart';
import 'package:fatoora/app/routes/app_routes.dart';
import 'package:fatoora/features/auth/data/repositories/auth_repository.dart';
import 'package:fatoora/features/customers/controllers/customer_error_mapper.dart';
import 'package:fatoora/features/customers/data/models/customer_model.dart';
import 'package:fatoora/features/customers/data/repositories/customer_repository.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class CustomerFormController extends GetxController {
  CustomerFormController({
    required CustomerRepository repository,
    required MyServices myServices,
  }) : _repository = repository,
       _myServices = myServices;

  final CustomerRepository _repository;
  final MyServices _myServices;
  final GlobalKey<FormState> formKey = GlobalKey<FormState>();
  final TextEditingController nameController = TextEditingController();
  final TextEditingController phoneController = TextEditingController();
  final TextEditingController addressController = TextEditingController();
  final TextEditingController cityController = TextEditingController();
  final TextEditingController areaController = TextEditingController();
  final TextEditingController notesController = TextEditingController();

  StatusRequest statusRequest = StatusRequest.success;
  String loadErrorMessageKey = 'customers_load_error';
  String companyId = AuthRepository.defaultCompanyId;
  String customerId = '';
  bool active = true;
  bool isSaving = false;
  bool returningCustomer = false;
  CustomerModel? loadedCustomer;

  bool get isEditMode => customerId.isNotEmpty;

  @override
  void onReady() {
    super.onReady();
    initialize();
  }

  Future<void> initialize() async {
    final args = Get.arguments;
    if (args is Map) {
      companyId =
          (args['companyId'] as String?) ??
          _myServices.sharedPreferences.getString('companyId') ??
          AuthRepository.defaultCompanyId;
      customerId = (args['customerId'] as String?)?.trim() ?? '';
      returningCustomer = args['returnCustomer'] == true;
    } else {
      companyId =
          _myServices.sharedPreferences.getString('companyId') ??
          AuthRepository.defaultCompanyId;
    }
    if (customerId.isEmpty) {
      statusRequest = StatusRequest.success;
      update();
      return;
    }
    await loadCustomer();
  }

  Future<void> loadCustomer() async {
    statusRequest = StatusRequest.loading;
    loadErrorMessageKey = 'customers_load_error';
    update();
    try {
      loadedCustomer = await _repository.getCustomer(
        companyId: companyId,
        customerId: customerId,
      );
      _applyCustomer(loadedCustomer!);
      statusRequest = StatusRequest.success;
    } catch (error) {
      statusRequest = CustomerErrorMapper.status(error);
      loadErrorMessageKey = CustomerErrorMapper.messageKey(
        error,
        fallback: 'customers_load_error',
      );
      _showError(loadErrorMessageKey);
    }
    if (!isClosed) update();
  }

  void _applyCustomer(CustomerModel customer) {
    nameController.text = customer.name;
    phoneController.text = customer.phone;
    addressController.text = customer.addressText;
    cityController.text = customer.city;
    areaController.text = customer.area;
    notesController.text = customer.notes;
    active = customer.active;
  }

  void setActive(bool value) {
    active = value;
    update();
  }

  Future<void> saveCustomer() async {
    if (isSaving) return;
    if (!(formKey.currentState?.validate() ?? false)) return;
    isSaving = true;
    update();
    try {
      final customer = isEditMode
          ? await _repository.updateCustomer(
              companyId: companyId,
              customerId: customerId,
              name: nameController.text,
              phone: phoneController.text,
              addressText: addressController.text,
              city: cityController.text,
              area: areaController.text,
              notes: notesController.text,
              active: active,
            )
          : await _repository.addCustomer(
              companyId: companyId,
              name: nameController.text,
              phone: phoneController.text,
              addressText: addressController.text,
              city: cityController.text,
              area: areaController.text,
              notes: notesController.text,
            );
      _showSuccess(
        isEditMode
            ? 'customers_updated_successfully'
            : 'customers_created_successfully',
      );
      await _navigateAfterSave(customer);
    } catch (error) {
      _showError(CustomerErrorMapper.messageKey(error));
    } finally {
      isSaving = false;
      if (!isClosed) update();
    }
  }

  Future<void> requestBack() async {
    Get.back<void>();
  }

  Future<void> _navigateAfterSave(CustomerModel customer) async {
    if (returningCustomer) {
      Get.back(result: customer);
      return;
    }
    if (isEditMode) {
      Get.back(result: true);
      return;
    }
    await Get.offNamed(
      AppRoute.customerDetails,
      arguments: {'companyId': customer.companyId, 'customerId': customer.id},
    );
  }

  String? validateName(String? value) {
    final name = value?.trim() ?? '';
    if (name.isEmpty || name.toLowerCase() == 'undefined') {
      return 'customers_name_required'.tr;
    }
    return null;
  }

  void _showSuccess(String messageKey) {
    Get.snackbar(
      'customers'.tr,
      messageKey.tr,
      snackPosition: SnackPosition.BOTTOM,
      backgroundColor: AppColor.success,
      colorText: AppColor.surface,
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
    nameController.dispose();
    phoneController.dispose();
    addressController.dispose();
    cityController.dispose();
    areaController.dispose();
    notesController.dispose();
    super.onClose();
  }
}
