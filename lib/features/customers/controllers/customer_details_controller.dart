import 'dart:async';

import 'package:fatoora/app/routes/app_routes.dart';
import 'package:fatoora/core/class/statusrequest.dart';
import 'package:fatoora/core/constants/color.dart';
import 'package:fatoora/core/services/services.dart';
import 'package:fatoora/features/auth/data/repositories/auth_repository.dart';
import 'package:fatoora/features/customers/controllers/customer_error_mapper.dart';
import 'package:fatoora/features/customers/data/models/customer_model.dart';
import 'package:fatoora/features/customers/data/models/customer_opening_balance.dart';
import 'package:fatoora/features/customers/data/models/customer_transaction_model.dart';
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
  bool isPostingOpeningBalance = false;
  bool isCheckingOpeningBalance = false;
  CustomerTransactionModel? openingBalance;

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
    }
    customerId =
        (Get.parameters['customerId'] ??
                (args is Map ? args['customerId'] as String? : null) ??
                '')
            .trim();
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
      final loadedCustomer = await _repository.getCustomer(
        companyId: companyId,
        customerId: customerId,
      );
      final loadedOpeningBalance = await _repository.getOpeningBalance(
        companyId: companyId,
        customerId: customerId,
      );
      customer = loadedCustomer;
      openingBalance = loadedOpeningBalance;
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
      AppRoute.customerEditPath(current.id),
      arguments: {'companyId': current.companyId, 'customerId': current.id},
    );
    if (changed == true) await loadCustomer();
  }

  Future<void> openStatement() async {
    final current = customer;
    if (current == null) return;
    await Get.toNamed(
      AppRoute.customerStatementPath(current.id),
      arguments: {'companyId': current.companyId, 'customerId': current.id},
    );
    await loadCustomer();
  }

  Future<bool> prepareOpeningBalance() async {
    final current = customer;
    if (current == null || isCheckingOpeningBalance) return false;
    isCheckingOpeningBalance = true;
    if (!isClosed) update();
    try {
      openingBalance = await _repository.getOpeningBalance(
        companyId: current.companyId,
        customerId: current.id,
      );
      return true;
    } catch (error) {
      if (!isClosed) {
        _showError(
          CustomerErrorMapper.messageKey(
            error,
            fallback: 'customers_opening_balance_check_error',
          ),
        );
      }
      return false;
    } finally {
      isCheckingOpeningBalance = false;
      if (!isClosed) update();
    }
  }

  Future<CustomerTransactionModel?> addOpeningBalance({
    required CustomerOpeningBalanceType balanceType,
    required double amount,
    required DateTime transactionDate,
    required String notes,
  }) async {
    final current = customer;
    if (current == null || isPostingOpeningBalance) return null;
    isPostingOpeningBalance = true;
    if (!isClosed) update();
    try {
      final transaction = await _repository.addOpeningBalance(
        companyId: current.companyId,
        customerId: current.id,
        balanceType: balanceType,
        amount: amount,
        transactionDate: transactionDate,
        notes: notes,
      );
      if (!isClosed) {
        openingBalance = transaction;
        customer = current.copyWith(
          currentBalance: transaction.balanceAfter,
          updatedAt: DateTime.now(),
        );
        update();
      }
      return transaction;
    } catch (error) {
      if (error is OpeningBalanceAlreadyExistsException &&
          error.openingBalance != null &&
          !isClosed) {
        openingBalance = error.openingBalance;
      }
      if (!isClosed) {
        _showError(
          CustomerErrorMapper.messageKey(
            error,
            fallback: 'customers_opening_balance_error',
          ),
        );
      }
      return null;
    } finally {
      isPostingOpeningBalance = false;
      if (!isClosed) update();
    }
  }

  Future<CustomerTransactionModel?> updateOpeningBalance({
    required CustomerOpeningBalanceType balanceType,
    required double amount,
    required String reason,
  }) async {
    final current = customer;
    final existing = openingBalance;
    if (current == null ||
        existing == null ||
        isPostingOpeningBalance ||
        reason.trim().isEmpty) {
      return null;
    }
    isPostingOpeningBalance = true;
    if (!isClosed) update();
    try {
      final transaction = await _repository.updateOpeningBalance(
        companyId: current.companyId,
        customerId: current.id,
        balanceType: balanceType,
        amount: amount,
        reason: reason,
      );
      if (!isClosed) {
        final difference = transaction.signedAmount - existing.signedAmount;
        openingBalance = transaction;
        customer = current.copyWith(
          currentBalance: _round(current.currentBalance + difference),
          updatedAt: DateTime.now(),
        );
        update();
      }
      return transaction;
    } catch (error) {
      if (!isClosed) {
        _showError(
          CustomerErrorMapper.messageKey(
            error,
            fallback: 'customers_opening_balance_update_error',
          ),
        );
      }
      return null;
    } finally {
      isPostingOpeningBalance = false;
      if (!isClosed) update();
    }
  }

  void openingBalanceDialogCompleted(CustomerTransactionModel transaction) {
    if (isClosed) return;
    openingBalance = transaction;
    _showSuccess('customers_opening_balance_created');
    unawaited(_refreshAfterOpeningBalance());
  }

  void openingBalanceUpdateDialogCompleted(
    CustomerTransactionModel transaction,
  ) {
    if (isClosed) return;
    openingBalance = transaction;
    _showSuccess('customers_opening_balance_updated');
    unawaited(_refreshAfterOpeningBalance());
  }

  Future<void> _refreshAfterOpeningBalance() async {
    final current = customer;
    if (current == null) return;
    try {
      final results = await Future.wait<Object?>([
        _repository.getCustomer(
          companyId: current.companyId,
          customerId: current.id,
        ),
        _repository.getOpeningBalance(
          companyId: current.companyId,
          customerId: current.id,
        ),
      ]);
      if (isClosed) return;
      customer = results[0] as CustomerModel;
      openingBalance = results[1] as CustomerTransactionModel?;
      update();
    } catch (_) {
      // The committed transaction is already reflected locally. A refresh
      // failure must not turn a successful financial posting into a failure.
    }
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

  double _round(double value) => (value * 1000).roundToDouble() / 1000;
}
