import 'package:fatoora/core/class/statusrequest.dart';
import 'package:fatoora/core/constants/color.dart';
import 'package:fatoora/app/routes/app_routes.dart';
import 'package:fatoora/features/items/data/models/item_model.dart';
import 'package:fatoora/features/items/data/repositories/item_repository.dart';
import 'package:fatoora/features/items/controller/item_error_mapper.dart';
import 'package:fatoora/features/items/controller/item_page_navigation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

enum ItemFilter { all, active, inactive }

enum ItemSort { newest, oldest, priceHigh, priceLow }

class ItemsController extends GetxController with ItemPageNavigation {
  ItemsController({required ItemRepository repository})
    : _repository = repository;

  final ItemRepository _repository;
  final TextEditingController searchController = TextEditingController();

  StatusRequest statusRequest = StatusRequest.loading;
  List<ItemModel> items = const [];
  ItemFilter filter = ItemFilter.all;
  ItemSort sort = ItemSort.newest;
  String searchQuery = '';
  String loadErrorMessageKey = 'items_load_error';

  List<ItemModel> get visibleItems {
    final query = searchQuery.trim().toLowerCase();
    final result = items.where((item) {
      final matchesFilter = switch (filter) {
        ItemFilter.all => true,
        ItemFilter.active => item.active,
        ItemFilter.inactive => !item.active,
      };
      final matchesSearch =
          query.isEmpty ||
          item.name.toLowerCase().contains(query) ||
          item.code.toLowerCase().contains(query);
      return matchesFilter && matchesSearch;
    }).toList();

    result.sort(
      (a, b) => switch (sort) {
        ItemSort.newest => b.createdAt.compareTo(a.createdAt),
        ItemSort.oldest => a.createdAt.compareTo(b.createdAt),
        ItemSort.priceHigh => b.price.compareTo(a.price),
        ItemSort.priceLow => a.price.compareTo(b.price),
      },
    );
    return result;
  }

  @override
  void onReady() {
    super.onReady();
    loadItems();
  }

  Future<void> loadItems() async {
    statusRequest = StatusRequest.loading;
    loadErrorMessageKey = 'items_load_error';
    update();
    try {
      items = await _repository.fetchItems();
      statusRequest = StatusRequest.success;
    } catch (error) {
      statusRequest = ItemErrorMapper.status(error);
      loadErrorMessageKey = ItemErrorMapper.messageKey(
        error,
        fallback: 'items_load_error',
      );
      Get.snackbar(
        'items_title'.tr,
        loadErrorMessageKey.tr,
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: AppColor.error,
        colorText: Colors.white,
      );
    }
    if (!isClosed) update();
  }

  void setFilter(ItemFilter value) {
    filter = value;
    update();
  }

  void setSort(ItemSort value) {
    sort = value;
    update();
  }

  void onSearchChanged(String value) {
    searchQuery = value;
    update();
  }

  Future<void> openAddItem() async {
    final changed = await Get.toNamed(AppRoute.adminAddItem);
    if (changed == true) await loadItems();
  }

  Future<void> openItemDetails(ItemModel item) async {
    final changed = await Get.toNamed(
      AppRoute.adminItemDetails,
      arguments: item,
    );
    if (changed == true) await loadItems();
  }

  Future<void> goBack() => leavePage(fallbackRoute: AppRoute.adminHome);

  @override
  void onClose() {
    searchController.dispose();
    super.onClose();
  }
}
