import 'package:fatoora/core/class/statusrequest.dart';
import 'package:fatoora/core/constants/color.dart';
import 'package:fatoora/app/routes/app_routes.dart';
import 'package:fatoora/features/items/data/models/item_model.dart';
import 'package:fatoora/features/items/data/repositories/item_repository.dart';
import 'package:fatoora/features/items/controller/item_error_mapper.dart';
import 'package:fatoora/features/items/controller/item_page_navigation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class EditItemController extends GetxController with ItemPageNavigation {
  EditItemController({required ItemRepository repository})
    : _repository = repository;

  final ItemRepository _repository;
  final GlobalKey<FormState> formKey = GlobalKey<FormState>();
  final TextEditingController nameController = TextEditingController();
  final TextEditingController codeController = TextEditingController();
  final TextEditingController descriptionController = TextEditingController();
  final TextEditingController unitController = TextEditingController();
  final TextEditingController priceController = TextEditingController();
  final TextEditingController taxRateController = TextEditingController();
  final TextEditingController currentStockController = TextEditingController();
  final TextEditingController openingStockController = TextEditingController();
  final TextEditingController minStockController = TextEditingController();
  final TextEditingController costPriceController = TextEditingController();
  final TextEditingController barcodeController = TextEditingController();
  final TextEditingController categoryController = TextEditingController();
  final TextEditingController warehouseController = TextEditingController();

  ItemModel? item;
  StatusRequest statusRequest = StatusRequest.none;
  bool active = true;
  bool trackStock = true;
  bool isDirty = false;

  bool get isLoading => statusRequest == StatusRequest.loading;

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

  @override
  void onInit() {
    super.onInit();
    final argument = Get.arguments;
    if (argument is! ItemModel) {
      statusRequest = StatusRequest.failure;
      return;
    }
    item = argument;
    nameController.text = argument.name;
    codeController.text = argument.code;
    descriptionController.text = argument.description;
    unitController.text = argument.unit;
    priceController.text = _formatNumber(argument.price);
    taxRateController.text = _formatNumber(argument.taxRate);
    currentStockController.text = _formatNumber(argument.currentStock);
    openingStockController.text = _formatNumber(argument.openingStock);
    minStockController.text = _formatNumber(argument.minStock);
    costPriceController.text = _formatNumber(argument.costPrice);
    barcodeController.text = argument.barcode ?? '';
    categoryController.text = argument.category ?? '';
    warehouseController.text = argument.warehouseId;
    active = argument.active;
    trackStock = argument.trackStock;
    for (final controller in _textControllers) {
      controller.addListener(_markDirty);
    }
    statusRequest = StatusRequest.success;
  }

  String _formatNumber(double value) => value == value.roundToDouble()
      ? value.toInt().toString()
      : value.toString();

  void _markDirty() {
    if (!isDirty) {
      isDirty = true;
      update();
    }
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
    final current = item;
    if (current == null ||
        isLoading ||
        !(formKey.currentState?.validate() ?? false)) {
      return;
    }
    statusRequest = StatusRequest.loading;
    update();
    try {
      await _repository.updateItem(
        itemId: current.id,
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
      await leavePage(
        fallbackRoute: AppRoute.adminItemDetails,
        fallbackArguments: current,
        result: true,
      );
      Get.snackbar(
        'items_title'.tr,
        'items_updated_success'.tr,
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
      await _leaveEditPage();
      return;
    }
    final discard = await Get.dialog<bool>(
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
    );
    if (discard == true) {
      isDirty = false;
      update();
      await _leaveEditPage();
    }
  }

  Future<void> _leaveEditPage() => leavePage(
    fallbackRoute: item == null
        ? AppRoute.adminItems
        : AppRoute.adminItemDetails,
    fallbackArguments: item,
  );

  @override
  void onClose() {
    for (final controller in _textControllers) {
      controller.dispose();
    }
    super.onClose();
  }
}
