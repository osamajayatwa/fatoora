import 'package:fatoora/app/routes/app_routes.dart';
import 'package:fatoora/core/class/statusrequest.dart';
import 'package:fatoora/core/constants/color.dart';
import 'package:fatoora/core/services/services.dart';
import 'package:fatoora/features/auth/data/repositories/auth_repository.dart';
import 'package:fatoora/features/customers/controllers/customer_error_mapper.dart';
import 'package:fatoora/features/customers/data/models/customer_model.dart';
import 'package:fatoora/features/customers/data/repositories/customer_repository.dart';
import 'package:get/get.dart';

class CustomerDetailsController extends GetxController {
  CustomerDetailsController({
    required CustomerRepository repository,
    required MyServices myServices,
  }) : _repository = repository,
       _myServices = myServices;

  final CustomerRepository _repository;
  final MyServices _myServices;

  StatusRequest statusRequest = StatusRequest.loading;
  String loadErrorMessageKey = 'customers_load_error';
  String companyId = AuthRepository.defaultCompanyId;
  String customerId = '';
  CustomerModel? customer;
  bool isUpdating = false;

  @override
  void onReady() {
    super.onReady();
    loadCustomer();
  }

  Future<void> loadCustomer() async {
    final args = Get.arguments;
    if (args is Map) {
      companyId =
          (args['companyId'] as String?) ??
          _myServices.sharedPreferences.getString('companyId') ??
          AuthRepository.defaultCompanyId;
      customerId = (args['customerId'] as String?)?.trim() ?? '';
    }
    if (customerId.isEmpty) {
      statusRequest = StatusRequest.failure;
      loadErrorMessageKey = 'customers_not_found';
      update();
      return;
    }

    statusRequest = StatusRequest.loading;
    loadErrorMessageKey = 'customers_load_error';
    update();
    try {
      customer = await _repository.getCustomer(
        companyId: companyId,
        customerId: customerId,
      );
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

  Future<void> editCustomer() async {
    final current = customer;
    if (current == null) return;
    final changed = await Get.toNamed(
      AppRoute.createCustomer,
      arguments: {'companyId': current.companyId, 'customerId': current.id},
    );
    if (changed == true) await loadCustomer();
  }

  Future<void> openStatement() async {
    final current = customer;
    if (current == null) return;
    await Get.toNamed(
      AppRoute.customerStatement,
      arguments: {'companyId': current.companyId, 'customerId': current.id},
    );
    await loadCustomer();
  }

  Future<void> setActive(bool active) async {
    final current = customer;
    if (current == null || isUpdating) return;
    isUpdating = true;
    update();
    try {
      await _repository.setActive(
        companyId: current.companyId,
        customerId: current.id,
        active: active,
      );
      _showSuccess(
        active
            ? 'customers_activated_successfully'
            : 'customers_deactivated_successfully',
      );
      await loadCustomer();
    } catch (error) {
      _showError(CustomerErrorMapper.messageKey(error));
    } finally {
      isUpdating = false;
      if (!isClosed) update();
    }
  }

  Future<void> requestBack() async {
    Get.back(result: true);
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
}
