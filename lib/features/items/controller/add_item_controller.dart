import 'package:fatoora/core/class/statusrequest.dart';
import 'package:fatoora/core/constants/color.dart';
import 'package:fatoora/app/routes/app_routes.dart';
import 'package:fatoora/core/services/services.dart';
import 'package:fatoora/core/settings/business_settings_defaults.dart';
import 'package:fatoora/core/settings/business_settings_resolver.dart';
import 'package:fatoora/features/auth/data/repositories/auth_repository.dart';
import 'package:fatoora/features/items/data/repositories/item_repository.dart';
import 'package:fatoora/features/items/controller/item_error_mapper.dart';
import 'package:fatoora/features/items/controller/item_page_navigation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class AddItemController extends GetxController with ItemPageNavigation {
  AddItemController({
    required ItemRepository repository,
    required BusinessSettingsResolver settingsResolver,
    required MyServices myServices,
  }) : _repository = repository,
       _settingsResolver = settingsResolver,
       _myServices = myServices;

  final ItemRepository _repository;
  final BusinessSettingsResolver _settingsResolver;
  final MyServices _myServices;
  final GlobalKey<FormState> formKey = GlobalKey<FormState>();
  final TextEditingController nameController = TextEditingController();
  final TextEditingController codeController = TextEditingController();
  final TextEditingController descriptionController = TextEditingController();
  final TextEditingController unitController = TextEditingController();
  final TextEditingController priceController = TextEditingController();
  final TextEditingController taxRateController = TextEditingController();
  final TextEditingController currentStockController = TextEditingController(
    text: '0',
  );
  final TextEditingController openingStockController = TextEditingController(
    text: '0',
  );
  final TextEditingController minStockController = TextEditingController(
    text: '0',
  );
  final TextEditingController costPriceController = TextEditingController(
    text: '0',
  );
  final TextEditingController barcodeController = TextEditingController();
  final TextEditingController categoryController = TextEditingController();
  final TextEditingController warehouseController = TextEditingController(
    text: 'default_warehouse',
  );

  StatusRequest statusRequest = StatusRequest.none;
  bool active = true;
  bool trackStock = true;
  bool isDirty = false;
  bool _applyingDefaults = false;

  bool get isLoading => statusRequest == StatusRequest.loading;

  @override
  void onInit() {
    super.onInit();
    statusRequest = StatusRequest.loading;
    for (final controller in _textControllers) {
      controller.addListener(_markDirty);
    }
    _loadDefaults();
  }

  List<TextEditingController> get _textControllers => [
    nameController,
    codeController,
    descriptionController,
    unitController,
    priceController,
    taxRateController,
    currentStockController,
    openingStockController,
    minStockController,
    costPriceController,
    barcodeController,
    categoryController,
    warehouseController,
  ];

  void _markDirty() {
    if (_applyingDefaults) return;
    if (!isDirty) {
      isDirty = true;
      update();
    }
  }

  Future<void> _loadDefaults() async {
    final companyId =
        _myServices.sharedPreferences.getString('companyId') ??
        AuthRepository.defaultCompanyId;
    final settings = await _settingsResolver.loadAppSettings(companyId);
    if (isClosed) return;
    final documents = settings.documentSettings;
    final inventory = settings.inventorySettings;
    _applyingDefaults = true;
    taxRateController.text = BusinessSettingsDefaults.inputNumber(
      BusinessSettingsDefaults.taxPercent(
        existingTaxPercent: null,
        defaultTaxPercent: documents.defaultTaxPercent,
      ),
    );
    minStockController.text = BusinessSettingsDefaults.inputNumber(
      BusinessSettingsDefaults.minimumStock(inventory.defaultMinStock),
    );
    warehouseController.text = BusinessSettingsDefaults.warehouseId(
      inventory.defaultWarehouseId,
    );
    trackStock = inventory.trackStockByDefault;
    _applyingDefaults = false;
    isDirty = false;
    statusRequest = StatusRequest.success;
    update();
  }

  void setActive(bool value) {
    active = value;
    isDirty = true;
    update();
  }

  void setTrackStock(bool value) {
    trackStock = value;
    isDirty = true;
    update();
  }

  Future<void> submit() async {
    if (isLoading || !(formKey.currentState?.validate() ?? false)) return;
    statusRequest = StatusRequest.loading;
    update();
    try {
      await _repository.addItem(
        name: nameController.text,
        code: codeController.text,
        description: descriptionController.text,
        unit: unitController.text,
        price: double.parse(priceController.text.trim()),
        taxRate: double.parse(taxRateController.text.trim()),
        active: active,
        currentStock: double.parse(currentStockController.text.trim()),
        openingStock: double.parse(openingStockController.text.trim()),
        minStock: double.parse(minStockController.text.trim()),
        trackStock: trackStock,
        costPrice: double.parse(costPriceController.text.trim()),
        barcode: barcodeController.text,
        category: categoryController.text,
        warehouseId: warehouseController.text,
      );
      statusRequest = StatusRequest.success;
      isDirty = false;
      update();
      await leavePage(fallbackRoute: AppRoute.adminItems, result: true);
      Get.snackbar(
        'items_title'.tr,
        'items_added_success'.tr,
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: AppColor.success,
        colorText: Colors.white,
      );
    } catch (error) {
      statusRequest = StatusRequest.failure;
      update();
      Get.snackbar(
        'items_title'.tr,
        ItemErrorMapper.messageKey(error).tr,
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: AppColor.error,
        colorText: Colors.white,
      );
    }
  }

  Future<void> requestBack() async {
    if (isLoading) return;
    if (!isDirty) {
      await leavePage(fallbackRoute: AppRoute.adminItems);
      return;
    }
    final discard = await _confirmDiscard();
    if (discard) {
      isDirty = false;
      update();
      await leavePage(fallbackRoute: AppRoute.adminItems);
    }
  }

  Future<bool> _confirmDiscard() async =>
      await Get.dialog<bool>(
        AlertDialog(
          title: Text('items_unsaved_title'.tr),
          content: Text('items_unsaved_message'.tr),
          actions: [
            TextButton(
              onPressed: () => Get.back(result: false),
              child: Text('items_cancel'.tr),
            ),
            FilledButton(
              onPressed: () => Get.back(result: true),
              style: FilledButton.styleFrom(backgroundColor: AppColor.error),
              child: Text('items_discard'.tr),
            ),
          ],
        ),
      ) ??
      false;

  @override
  void onClose() {
    for (final controller in _textControllers) {
      controller.dispose();
    }
    super.onClose();
  }
}
