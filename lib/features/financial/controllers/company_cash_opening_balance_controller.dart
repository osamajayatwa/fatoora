import 'package:fatoora/core/class/statusrequest.dart';
import 'package:fatoora/core/services/services.dart';
import 'package:fatoora/features/auth/data/repositories/auth_repository.dart';
import 'package:fatoora/features/financial/controllers/financial_error_mapper.dart';
import 'package:fatoora/features/financial/data/models/company_cash_opening_balance_model.dart';
import 'package:fatoora/features/financial/data/repositories/financial_repository.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class CompanyCashOpeningBalanceController extends GetxController {
  CompanyCashOpeningBalanceController({
    required FinancialRepository repository,
    required MyServices myServices,
  }) : _repository = repository,
       _myServices = myServices;

  final FinancialRepository _repository;
  final MyServices _myServices;

  final formKey = GlobalKey<FormState>();
  final amountController = TextEditingController();
  final noteController = TextEditingController();

  StatusRequest statusRequest = StatusRequest.loading;
  String loadErrorMessageKey =
      'financial_company_cash_opening_balance_load_error';
  CompanyCashOpeningBalanceModel? openingBalance;
  bool isSaving = false;

  String get companyId =>
      _myServices.sharedPreferences.getString('companyId') ??
      AuthRepository.defaultCompanyId;

  bool get canCreate {
    final preferences = _myServices.sharedPreferences;
    return preferences.getString('role') == AuthRepository.adminRole &&
        preferences.getString('uid') ==
            CompanyCashOpeningBalanceModel.authorizedUid &&
        (preferences.getString('email') ?? '').trim().toLowerCase() ==
            CompanyCashOpeningBalanceModel.authorizedEmail;
  }

  bool get hasOpeningBalance => openingBalance != null;

  @override
  void onReady() {
    super.onReady();
    loadOpeningBalance();
  }

  Future<void> loadOpeningBalance() async {
    statusRequest = StatusRequest.loading;
    update();
    try {
      openingBalance = await _repository.getCompanyCashOpeningBalance(
        companyId: companyId,
      );
      statusRequest = StatusRequest.success;
    } catch (error) {
      statusRequest = FinancialErrorMapper.status(error);
      loadErrorMessageKey = FinancialErrorMapper.messageKey(
        error,
        fallback: 'financial_company_cash_opening_balance_load_error',
      );
    }
    if (!isClosed) update();
  }

  String? validateAmount(String? value) {
    final amount = _parseAmount(value ?? '');
    if (amount == null || amount <= 0) {
      return 'financial_company_cash_opening_balance_invalid_amount'.tr;
    }
    if (amount > 999999999) {
      return 'settings_number_too_large'.trParams({'max': '999,999,999'});
    }
    return null;
  }

  Future<bool> createOpeningBalance() async {
    if (isSaving || hasOpeningBalance || !canCreate) return false;
    if (!(formKey.currentState?.validate() ?? false)) return false;
    final amount = _parseAmount(amountController.text);
    if (amount == null) return false;

    isSaving = true;
    update();
    try {
      await _repository.postCompanyCashOpeningBalance(
        companyId: companyId,
        amount: amount,
        note: noteController.text.trim(),
      );
      await loadOpeningBalance();
      if (openingBalance == null) {
        throw const FinancialRepositoryException(
          FinancialRepositoryError.invalidData,
        );
      }
      amountController.clear();
      noteController.clear();
      Get.snackbar(
        'settings_opening_balances'.tr,
        'financial_company_cash_opening_balance_created'.tr,
      );
      return true;
    } catch (error) {
      if (error is FinancialRepositoryException &&
          error.error == FinancialRepositoryError.alreadyExists) {
        await loadOpeningBalance();
      }
      Get.snackbar(
        'settings_opening_balances'.tr,
        FinancialErrorMapper.messageKey(
          error,
          fallback: 'financial_company_cash_opening_balance_create_error',
        ).tr,
      );
      return false;
    } finally {
      isSaving = false;
      if (!isClosed) update();
    }
  }

  double? _parseAmount(String value) {
    final normalized = value.trim().replaceAll(',', '');
    final amount = double.tryParse(normalized);
    if (amount == null || !amount.isFinite) return null;
    return amount;
  }

  @override
  void onClose() {
    amountController.dispose();
    noteController.dispose();
    super.onClose();
  }
}
