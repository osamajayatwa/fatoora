import 'package:fatoora/app/routes/app_routes.dart';
import 'package:fatoora/core/constants/color.dart';
import 'package:fatoora/core/services/services.dart';
import 'package:fatoora/features/auth/data/repositories/auth_repository.dart';
import 'package:fatoora/features/expenses/controllers/expense_error_mapper.dart';
import 'package:fatoora/features/expenses/data/models/expense_model.dart';
import 'package:fatoora/features/expenses/data/repositories/expense_repository.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class ExpenseFormController extends GetxController {
  ExpenseFormController({
    required ExpenseRepository repository,
    required MyServices myServices,
  }) : _repository = repository,
       _myServices = myServices;

  final ExpenseRepository _repository;
  final MyServices _myServices;
  final TextEditingController amountController = TextEditingController();
  final TextEditingController customCategoryController =
      TextEditingController();
  final TextEditingController descriptionController = TextEditingController();

  ExpenseCategory category = ExpenseCategory.fuel;
  ExpenseFundingSource fundingSource = ExpenseFundingSource.repCollectedCash;
  DateTime expenseDate = DateTime.now();
  bool isSaving = false;

  String get companyId =>
      _myServices.sharedPreferences.getString('companyId') ??
      AuthRepository.defaultCompanyId;

  bool get isAdmin =>
      _myServices.sharedPreferences.getString('role') ==
      AuthRepository.adminRole;

  bool get isSalesRep =>
      _myServices.sharedPreferences.getString('role') ==
      AuthRepository.salesRepRole;

  List<ExpenseFundingSource> get availableFundingSources => isAdmin
      ? const [ExpenseFundingSource.companyCash]
      : const [
          ExpenseFundingSource.repCollectedCash,
          ExpenseFundingSource.personalCash,
        ];

  @override
  void onInit() {
    super.onInit();
    fundingSource = isAdmin
        ? ExpenseFundingSource.companyCash
        : ExpenseFundingSource.repCollectedCash;
  }

  void setCategory(ExpenseCategory? value) {
    if (value == null) return;
    category = value;
    update();
  }

  void setFundingSource(ExpenseFundingSource value) {
    if (!availableFundingSources.contains(value)) return;
    fundingSource = value;
    update();
  }

  void setExpenseDate(DateTime value) {
    expenseDate = value;
    update();
  }

  Future<void> saveExpense() async {
    if (isSaving) return;
    final amount = _parseAmount(amountController.text);
    if (amount <= 0) {
      _showError('expense_amount_required');
      return;
    }
    if (category == ExpenseCategory.other &&
        customCategoryController.text.trim().length < 2) {
      _showError('expense_custom_category_required');
      return;
    }

    isSaving = true;
    update();
    try {
      final expense = await _repository.createExpense(
        companyId: companyId,
        amount: amount,
        expenseDate: expenseDate,
        category: category,
        customCategoryName: customCategoryController.text,
        description: descriptionController.text,
        paymentMethod: 'cash',
        fundingSource: fundingSource,
      );
      Get.snackbar(
        'expenses'.tr,
        isAdmin ? 'expense_posted_successfully'.tr : 'expense_submitted'.tr,
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: AppColor.success,
        colorText: AppColor.surface,
      );
      await Get.offNamed(
        AppRoute.expenseDetailsPath(expense.id),
        arguments: {'companyId': expense.companyId, 'expenseId': expense.id},
      );
    } catch (error) {
      _showError(ExpenseErrorMapper.messageKey(error));
    } finally {
      isSaving = false;
      if (!isClosed) update();
    }
  }

  double _parseAmount(String value) {
    return double.tryParse(value.replaceAll(',', '').trim()) ?? 0;
  }

  void _showError(String messageKey) {
    Get.snackbar(
      'expenses'.tr,
      messageKey.tr,
      snackPosition: SnackPosition.BOTTOM,
      backgroundColor: AppColor.error,
      colorText: AppColor.surface,
    );
  }

  @override
  void onClose() {
    amountController.dispose();
    customCategoryController.dispose();
    descriptionController.dispose();
    super.onClose();
  }
}
