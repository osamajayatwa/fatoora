import 'dart:async';

import 'package:fatoora/app/routes/app_routes.dart';
import 'package:fatoora/core/class/statusrequest.dart';
import 'package:fatoora/core/data/firestore_query_pager.dart';
import 'package:fatoora/core/search/server_search_policy.dart';
import 'package:fatoora/core/services/services.dart';
import 'package:fatoora/features/auth/data/repositories/auth_repository.dart';
import 'package:fatoora/features/inventory/controllers/inventory_error_mapper.dart';
import 'package:fatoora/features/inventory/data/models/inventory_dashboard_snapshot.dart';
import 'package:fatoora/features/inventory/data/repositories/inventory_repository.dart';
import 'package:fatoora/features/items/controller/item_error_mapper.dart';
import 'package:fatoora/features/items/data/models/item_model.dart';
import 'package:fatoora/features/items/data/repositories/item_repository.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

enum InventoryItemSort { newest, oldest, priceHigh, priceLow }

class InventoryDashboardController extends GetxController {
  InventoryDashboardController({
    required InventoryRepository repository,
    required ItemRepository itemRepository,
    required MyServices myServices,
  }) : _repository = repository,
       _itemRepository = itemRepository,
       _myServices = myServices;

  final InventoryRepository _repository;
  final ItemRepository _itemRepository;
  final MyServices _myServices;
  static const int itemPageSize = 36;

  final TextEditingController itemSearchController = TextEditingController();

  StatusRequest statusRequest = StatusRequest.loading;
  String loadErrorMessageKey = 'inventory_load_error';
  InventoryDashboardSnapshot snapshot =
      const InventoryDashboardSnapshot.empty();
  StatusRequest itemStatusRequest = StatusRequest.loading;
  String itemLoadErrorMessageKey = 'items_load_error';
  List<ItemModel> items = const [];
  InventoryItemSort itemSort = InventoryItemSort.newest;
  String itemSearchQuery = '';
  bool isLoadingMoreItems = false;
  bool hasMoreItems = false;
  FirestorePageCursor? _itemPageCursor;
  Timer? _itemSearchDebounce;
  int _itemLoadGeneration = 0;
  String _appliedItemSearch = '';

  String get companyId {
    final cached =
        _myServices.sharedPreferences.getString('companyId')?.trim() ?? '';
    return cached.isEmpty ? AuthRepository.defaultCompanyId : cached;
  }

  @override
  void onReady() {
    super.onReady();
    loadDashboard();
  }

  Future<void> loadDashboard() async {
    statusRequest = StatusRequest.loading;
    loadErrorMessageKey = 'inventory_load_error';
    update();
    try {
      final results = await Future.wait([
        _repository.fetchDashboard(companyId: companyId),
        _fetchItemsPage(reset: true),
      ]);
      snapshot = results.first as InventoryDashboardSnapshot;
      statusRequest = StatusRequest.success;
    } catch (error) {
      statusRequest = InventoryErrorMapper.status(error);
      loadErrorMessageKey = InventoryErrorMapper.messageKey(
        error,
        fallback: 'inventory_load_error',
      );
    }
    if (!isClosed) update();
  }

  Future<void> refreshDashboard() async {
    try {
      final results = await Future.wait([
        _repository.fetchDashboard(companyId: companyId),
        _fetchItemsPage(reset: true),
      ]);
      snapshot = results.first as InventoryDashboardSnapshot;
      statusRequest = StatusRequest.success;
    } catch (error) {
      loadErrorMessageKey = InventoryErrorMapper.messageKey(
        error,
        fallback: 'inventory_load_error',
      );
    }
    if (!isClosed) update();
  }

  Future<void> loadItems() => _fetchItemsPage(reset: true);

  Future<void> _fetchItemsPage({required bool reset}) async {
    _itemSearchDebounce?.cancel();
    final generation = reset ? ++_itemLoadGeneration : _itemLoadGeneration;
    final requestedSearch = serverSearchTerm(itemSearchQuery);
    if (reset) {
      itemStatusRequest = StatusRequest.loading;
      itemLoadErrorMessageKey = 'items_load_error';
      _itemPageCursor = null;
      hasMoreItems = false;
      if (!isClosed) update();
    }
    try {
      final page = await _itemRepository.fetchItemsPage(
        searchText: requestedSearch,
        orderField: switch (itemSort) {
          InventoryItemSort.newest || InventoryItemSort.oldest => 'createdAt',
          InventoryItemSort.priceHigh || InventoryItemSort.priceLow => 'price',
        },
        descending:
            itemSort == InventoryItemSort.newest ||
            itemSort == InventoryItemSort.priceHigh,
        after: reset ? null : _itemPageCursor,
        pageSize: itemPageSize,
      );
      if (generation != _itemLoadGeneration) return;
      items = reset ? page.items : [...items, ...page.items];
      _itemPageCursor = page.cursor;
      hasMoreItems = page.hasMore;
      _appliedItemSearch = requestedSearch;
      itemStatusRequest = StatusRequest.success;
    } catch (error) {
      if (generation != _itemLoadGeneration) return;
      itemLoadErrorMessageKey = ItemErrorMapper.messageKey(
        error,
        fallback: 'items_load_error',
      );
      if (!reset) rethrow;
      itemStatusRequest = ItemErrorMapper.status(error);
    } finally {
      if (!isClosed) update();
    }
  }

  Future<void> loadMoreItems() async {
    if (isLoadingMoreItems || !hasMoreItems || _itemPageCursor == null) return;
    isLoadingMoreItems = true;
    update();
    try {
      await _fetchItemsPage(reset: false);
    } catch (error) {
      itemLoadErrorMessageKey = ItemErrorMapper.messageKey(
        error,
        fallback: 'items_load_error',
      );
      Get.snackbar(
        'inventory_items'.tr,
        itemLoadErrorMessageKey.tr,
        snackPosition: SnackPosition.BOTTOM,
      );
    } finally {
      isLoadingMoreItems = false;
      if (!isClosed) update();
    }
  }

  void onItemSearchChanged(String value) {
    itemSearchQuery = value;
    _itemSearchDebounce?.cancel();
    _itemLoadGeneration++;
    update();
    if (serverSearchTerm(value).isEmpty) {
      if (_appliedItemSearch.isNotEmpty ||
          itemStatusRequest != StatusRequest.success) {
        loadItems();
      }
      return;
    }
    _itemSearchDebounce = Timer(serverSearchDebounce, loadItems);
  }

  void submitItemSearch() {
    _itemSearchDebounce?.cancel();
    loadItems();
  }

  void clearItemSearch() {
    _itemSearchDebounce?.cancel();
    itemSearchQuery = '';
    itemSearchController.clear();
    loadItems();
  }

  void setItemSort(InventoryItemSort value) {
    if (itemSort == value) return;
    itemSort = value;
    loadItems();
  }

  Future<void> openItem(ItemModel item) async {
    final changed = await Get.toNamed(
      AppRoute.itemDetailsPath(item.id),
      arguments: item,
    );
    if (changed == true) await refreshDashboard();
  }

  void openMovements() => Get.toNamed(AppRoute.stockMovements);

  void openAdjustment() => Get.toNamed(AppRoute.inventoryAdjustment);

  @override
  void onClose() {
    _itemSearchDebounce?.cancel();
    itemSearchController.dispose();
    super.onClose();
  }
}
