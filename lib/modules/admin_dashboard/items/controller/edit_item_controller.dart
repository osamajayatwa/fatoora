import 'package:fatoora/core/class/statusrequest.dart';
import 'package:fatoora/core/constant/color.dart';
import 'package:fatoora/core/constant/routes.dart';
import 'package:fatoora/data/models/item_model.dart';
import 'package:fatoora/data/repositories/item_repository.dart';
import 'package:fatoora/modules/admin_dashboard/items/controller/item_error_mapper.dart';
import 'package:fatoora/modules/admin_dashboard/items/controller/item_page_navigation.dart';
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

  ItemModel? item;
  StatusRequest statusRequest = StatusRequest.none;
  bool active = true;
  bool isDirty = false;

  bool get isLoading => statusRequest == StatusRequest.loading;

  List<TextEditingController> get _textControllers => [
    nameController,
    codeController,
    descriptionController,
    unitController,
    priceController,
    taxRateController,
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
    active = argument.active;
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
