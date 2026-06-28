import 'package:fatoora/core/constants/color.dart';
import 'package:fatoora/core/services/services.dart';
import 'package:fatoora/core/settings/business_settings_defaults.dart';
import 'package:fatoora/core/settings/business_settings_resolver.dart';
import 'package:fatoora/core/settings/business_permission_resolver.dart';
import 'package:fatoora/features/auth/data/repositories/auth_repository.dart';
import 'package:fatoora/features/customers/data/models/customer_model.dart';
import 'package:fatoora/features/customers/view/widgets/customer_picker_sheet.dart';
import 'package:fatoora/features/receipts/controllers/receipt_error_mapper.dart';
import 'package:fatoora/features/receipts/data/repositories/receipt_repository.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class ReceiptFormController extends GetxController {
  ReceiptFormController({
    required ReceiptRepository repository,
    required MyServices myServices,
    required BusinessSettingsResolver settingsResolver,
    required BusinessPermissionResolver permissionResolver,
  }) : _repository = repository,
       _myServices = myServices,
       _settingsResolver = settingsResolver,
       _permissionResolver = permissionResolver;

  final ReceiptRepository _repository;
  final MyServices _myServices;
  final BusinessSettingsResolver _settingsResolver;
  final BusinessPermissionResolver _permissionResolver;
  final TextEditingController amountController = TextEditingController();
  final TextEditingController notesController = TextEditingController();

  CustomerModel? customer;
  DateTime receiptDate = DateTime.now();
  String paymentMethod = 'cash';
  bool isSaving = false;
  EffectiveBusinessPermissions permissions =
      EffectiveBusinessPermissions.denied;

  static const paymentMethods = ['cash', 'bank', 'check', 'cliq'];

  String get companyId =>
      _myServices.sharedPreferences.getString('companyId') ??
      AuthRepository.defaultCompanyId;

  @override
  void onReady() {
    super.onReady();
    _loadDefaultNote();
    _loadPermissions();
  }

  Future<void> _loadPermissions() async {
    permissions = await _permissionResolver.resolve(companyId);
    if (!isClosed) update();
  }

  Future<void> _loadDefaultNote() async {
    final uid = _myServices.sharedPreferences.getString('uid') ?? '';
    final preferences = await _settingsResolver.loadUserPreferences(uid);
    if (isClosed) return;
    notesController.text = BusinessSettingsDefaults.prefilledNote(
      currentNote: notesController.text,
      defaultNote: preferences.defaultReceiptNote,
    );
    update();
  }

  Future<void> selectCustomer(BuildContext context) async {
    final selected = await showCustomerPicker(context);
    if (selected == null) return;
    customer = selected;
    update();
  }

  void setReceiptDate(DateTime value) {
    receiptDate = value;
    update();
  }

  void setPaymentMethod(String value) {
    if (!paymentMethods.contains(value)) return;
    paymentMethod = value;
    update();
  }

  Future<void> saveReceipt() async {
    if (isSaving) return;
    if (!permissions.createReceipts) {
      _showError('sales_rep_receipt_create_disabled');
      return;
    }
    final selectedCustomer = customer;
    final amount = _parseAmount(amountController.text);
    if (selectedCustomer == null) {
      _showError('receipts_customer_required');
      return;
    }
    if (amount <= 0) {
      _showError('receipts_amount_required');
      return;
    }

    isSaving = true;
    update();
    try {
      await _repository.createReceipt(
        companyId: companyId,
        customerId: selectedCustomer.id,
        amount: amount,
        paymentMethod: paymentMethod,
        receiptDate: receiptDate,
        notes: notesController.text,
      );
      Get.snackbar(
        'receipts'.tr,
        'receipts_created_successfully'.tr,
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: AppColor.success,
        colorText: AppColor.surface,
      );
      Get.back(result: true);
    } catch (error) {
      _showError(ReceiptErrorMapper.messageKey(error));
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
      'receipts'.tr,
      messageKey.tr,
      snackPosition: SnackPosition.BOTTOM,
      backgroundColor: AppColor.error,
      colorText: AppColor.surface,
    );
  }

  @override
  void onClose() {
    amountController.dispose();
    notesController.dispose();
    super.onClose();
  }
}
