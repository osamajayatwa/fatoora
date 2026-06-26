import 'package:fatoora/core/class/statusrequest.dart';
import 'package:fatoora/core/constants/color.dart';
import 'package:fatoora/core/services/services.dart';
import 'package:fatoora/features/auth/data/repositories/auth_repository.dart';
import 'package:fatoora/features/inventory/controllers/inventory_error_mapper.dart';
import 'package:fatoora/features/inventory/data/repositories/inventory_repository.dart';
import 'package:fatoora/features/items/data/models/item_model.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class InventoryAdjustmentController extends GetxController {
  InventoryAdjustmentController({
    required InventoryRepository repository,
    required MyServices myServices,
  }) : _repository = repository,
       _myServices = myServices;

  final InventoryRepository _repository;
  final MyServices _myServices;
  final GlobalKey<FormState> formKey = GlobalKey<FormState>();
  final TextEditingController quantityController = TextEditingController();
  final TextEditingController notesController = TextEditingController();

  StatusRequest statusRequest = StatusRequest.none;
  ItemModel? selectedItem;
  String adjustmentType = 'manual_adjustment_in';

  bool get isLoading => statusRequest == StatusRequest.loading;

  String get companyId {
    final cached =
        _myServices.sharedPreferences.getString('companyId')?.trim() ?? '';
    return cached.isEmpty ? AuthRepository.defaultCompanyId : cached;
  }

  void selectItem(ItemModel? item) {
    selectedItem = item;
    update();
  }

  void setAdjustmentType(String value) {
    adjustmentType = value;
    update();
  }

  Future<void> submit() async {
    final item = selectedItem;
    if (isLoading || !(formKey.currentState?.validate() ?? false)) return;
    if (item == null) {
      _showError('select_item');
      return;
    }
    statusRequest = StatusRequest.loading;
    update();
    try {
      await _repository.adjustStock(
        companyId: companyId,
        itemId: item.id,
        adjustmentType: adjustmentType,
        quantity: double.parse(quantityController.text.trim()),
        notes: notesController.text,
      );
      statusRequest = StatusRequest.success;
      quantityController.clear();
      notesController.clear();
      _showSuccess('stock_adjusted_successfully');
    } catch (error) {
      statusRequest = InventoryErrorMapper.status(error);
      _showError(InventoryErrorMapper.messageKey(error));
    }
    if (!isClosed) update();
  }

  void _showSuccess(String messageKey) {
    Get.snackbar(
      'inventory'.tr,
      messageKey.tr,
      snackPosition: SnackPosition.BOTTOM,
      backgroundColor: AppColor.success,
      colorText: AppColor.surface,
    );
  }

  void _showError(String messageKey) {
    Get.snackbar(
      'inventory'.tr,
      messageKey.tr,
      snackPosition: SnackPosition.BOTTOM,
      backgroundColor: AppColor.error,
      colorText: AppColor.surface,
    );
  }

  @override
  void onClose() {
    quantityController.dispose();
    notesController.dispose();
    super.onClose();
  }
}
