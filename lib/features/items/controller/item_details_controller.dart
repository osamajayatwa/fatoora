import 'package:fatoora/core/class/statusrequest.dart';
import 'package:fatoora/core/constants/color.dart';
import 'package:fatoora/app/routes/app_routes.dart';
import 'package:fatoora/features/items/data/models/item_model.dart';
import 'package:fatoora/features/items/data/repositories/item_repository.dart';
import 'package:fatoora/features/items/controller/item_error_mapper.dart';
import 'package:fatoora/features/items/controller/item_page_navigation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class ItemDetailsController extends GetxController with ItemPageNavigation {
  ItemDetailsController({required ItemRepository repository})
    : _repository = repository;

  final ItemRepository _repository;
  StatusRequest statusRequest = StatusRequest.none;
  ItemModel? item;
  bool isActionLoading = false;
  bool changed = false;
  String loadErrorMessageKey = 'items_load_error';

  @override
  void onInit() {
    super.onInit();
    final argument = Get.arguments;
    if (argument is ItemModel) {
      item = argument;
      loadItem();
    } else if (argument is String && argument.isNotEmpty) {
      item = ItemModel(
        id: argument,
        code: '',
        name: '',
        description: '',
        unit: '',
        price: 0,
        taxRate: 0,
        active: true,
        deleted: false,
        createdAt: DateTime.fromMillisecondsSinceEpoch(0),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(0),
        createdBy: '',
        currentStock: 0,
        openingStock: 0,
        minStock: 0,
        trackStock: true,
        costPrice: 0,
        warehouseId: ItemModel.defaultWarehouseId,
      );
      loadItem();
    } else {
      statusRequest = StatusRequest.failure;
      loadErrorMessageKey = 'items_not_found_error';
    }
  }

  Future<void> loadItem() async {
    final id = item?.id;
    if (id == null) return;
    statusRequest = StatusRequest.loading;
    loadErrorMessageKey = 'items_load_error';
    update();
    try {
      item = await _repository.getItem(id);
      statusRequest = StatusRequest.success;
    } catch (error) {
      statusRequest = ItemErrorMapper.status(error);
      loadErrorMessageKey = ItemErrorMapper.messageKey(
        error,
        fallback: 'items_load_error',
      );
    }
    if (!isClosed) update();
  }

  Future<void> editItem() async {
    if (item == null || isActionLoading) return;
    final updated = await Get.toNamed(AppRoute.adminEditItem, arguments: item);
    if (updated == true) {
      changed = true;
      await loadItem();
    }
  }

  Future<void> openStockDetails() async {
    if (item == null || isActionLoading) return;
    await Get.toNamed(AppRoute.itemStockDetails, arguments: item);
    await loadItem();
  }

  Future<void> toggleActive() async {
    final current = item;
    if (current == null || isActionLoading) return;
    if (current.active) {
      final confirmed = await _confirm(
        title: 'items_deactivate'.tr,
        message: 'items_confirm_deactivate'.tr,
        danger: true,
      );
      if (!confirmed) return;
    }

    await _runAction(() async {
      await _repository.setActive(current.id, active: !current.active);
      item = current.copyWith(
        active: !current.active,
        updatedAt: DateTime.now(),
      );
      changed = true;
      _showSuccess(
        current.active
            ? 'items_deactivated_success'.tr
            : 'items_activated_success'.tr,
      );
    });
  }

  Future<void> deleteItem() async {
    final current = item;
    if (current == null || isActionLoading) return;
    final confirmed = await _confirm(
      title: 'items_delete'.tr,
      message: 'items_confirm_delete'.tr,
      danger: true,
    );
    if (!confirmed) return;

    isActionLoading = true;
    update();
    try {
      await _repository.softDelete(current.id);
      changed = true;
      isActionLoading = false;
      update();
      await leavePage(fallbackRoute: AppRoute.adminItems, result: true);
      _showSuccess('items_deleted_success'.tr);
    } catch (error) {
      isActionLoading = false;
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

  Future<void> _runAction(Future<void> Function() action) async {
    isActionLoading = true;
    update();
    try {
      await action();
    } catch (error) {
      Get.snackbar(
        'items_title'.tr,
        ItemErrorMapper.messageKey(error).tr,
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: AppColor.error,
        colorText: Colors.white,
      );
    } finally {
      isActionLoading = false;
      if (!isClosed) update();
    }
  }

  Future<bool> _confirm({
    required String title,
    required String message,
    required bool danger,
  }) async =>
      await Get.dialog<bool>(
        AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Get.back(result: false),
              child: Text('items_cancel'.tr),
            ),
            FilledButton(
              onPressed: () => Get.back(result: true),
              style: FilledButton.styleFrom(
                backgroundColor: danger
                    ? AppColor.error
                    : AppColor.primaryColor,
              ),
              child: Text(title),
            ),
          ],
        ),
      ) ??
      false;

  void _showSuccess(String message) {
    Get.snackbar(
      'items_title'.tr,
      message,
      snackPosition: SnackPosition.BOTTOM,
      backgroundColor: AppColor.success,
      colorText: Colors.white,
    );
  }

  Future<void> goBack() async {
    if (!isActionLoading) {
      await leavePage(fallbackRoute: AppRoute.adminItems, result: changed);
    }
  }
}
