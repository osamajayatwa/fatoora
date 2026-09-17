import 'dart:async';

import 'package:fatoora/core/class/statusrequest.dart';
import 'package:fatoora/core/constants/color.dart';
import 'package:fatoora/core/data/firestore_query_pager.dart';
import 'package:fatoora/core/search/server_search_policy.dart';
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
  final ScrollController scrollController = ScrollController();

  StatusRequest statusRequest = StatusRequest.loading;
  List<ItemModel> items = const [];
  ItemFilter filter = ItemFilter.all;
  ItemSort sort = ItemSort.newest;
  String searchQuery = '';
  String loadErrorMessageKey = 'items_load_error';
  bool isLoadingMore = false;
  bool hasMore = false;
  FirestorePageCursor? _pageCursor;
  Timer? _searchDebounce;
  int _loadGeneration = 0;
  String _appliedSearch = '';

  List<ItemModel> get visibleItems => items;

  @override
  void onReady() {
    super.onReady();
    scrollController.addListener(_onScroll);
    loadItems();
  }

  Future<void> loadItems() async {
    _searchDebounce?.cancel();
    final generation = ++_loadGeneration;
    final requestedSearch = serverSearchTerm(searchQuery);
    statusRequest = StatusRequest.loading;
    _pageCursor = null;
    hasMore = false;
    loadErrorMessageKey = 'items_load_error';
    update();
    try {
      final page = await _repository.fetchItemsPage(
        searchText: requestedSearch,
        active: switch (filter) {
          ItemFilter.all => null,
          ItemFilter.active => true,
          ItemFilter.inactive => false,
        },
        orderField: switch (sort) {
          ItemSort.newest || ItemSort.oldest => 'createdAt',
          ItemSort.priceHigh || ItemSort.priceLow => 'price',
        },
        descending: sort == ItemSort.newest || sort == ItemSort.priceHigh,
      );
      if (generation != _loadGeneration) return;
      items = page.items;
      _pageCursor = page.cursor;
      hasMore = page.hasMore;
      _appliedSearch = requestedSearch;
      statusRequest = StatusRequest.success;
    } catch (error) {
      if (generation != _loadGeneration) return;
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
    if (filter == value) return;
    filter = value;
    loadItems();
  }

  void setSort(ItemSort value) {
    if (sort == value) return;
    sort = value;
    loadItems();
  }

  void onSearchChanged(String value) {
    searchQuery = value;
    _searchDebounce?.cancel();
    _loadGeneration++;
    update();
    if (serverSearchTerm(value).isEmpty) {
      if (_appliedSearch.isNotEmpty || statusRequest != StatusRequest.success) {
        loadItems();
      }
      return;
    }
    _searchDebounce = Timer(serverSearchDebounce, loadItems);
  }

  void submitSearch() {
    _searchDebounce?.cancel();
    loadItems();
  }

  Future<void> loadMoreItems() async {
    if (isLoadingMore || !hasMore || _pageCursor == null) return;
    isLoadingMore = true;
    final generation = _loadGeneration;
    update();
    try {
      final page = await _repository.fetchItemsPage(
        searchText: serverSearchTerm(searchQuery),
        active: switch (filter) {
          ItemFilter.all => null,
          ItemFilter.active => true,
          ItemFilter.inactive => false,
        },
        orderField: switch (sort) {
          ItemSort.newest || ItemSort.oldest => 'createdAt',
          ItemSort.priceHigh || ItemSort.priceLow => 'price',
        },
        descending: sort == ItemSort.newest || sort == ItemSort.priceHigh,
        after: _pageCursor,
      );
      if (generation != _loadGeneration) return;
      items = [...items, ...page.items];
      _pageCursor = page.cursor;
      hasMore = page.hasMore;
    } catch (error) {
      if (generation == _loadGeneration) {
        Get.snackbar(
          'items_title'.tr,
          ItemErrorMapper.messageKey(error).tr,
          snackPosition: SnackPosition.BOTTOM,
          backgroundColor: AppColor.error,
          colorText: Colors.white,
        );
      }
    } finally {
      isLoadingMore = false;
      if (!isClosed) update();
    }
  }

  void _onScroll() {
    if (!scrollController.hasClients) return;
    if (scrollController.position.extentAfter < 500) loadMoreItems();
  }

  Future<void> openAddItem() async {
    final changed = await Get.toNamed(AppRoute.adminAddItem);
    if (changed == true) await loadItems();
  }

  Future<void> openItemDetails(ItemModel item) async {
    final changed = await Get.toNamed(
      AppRoute.itemDetailsPath(item.id),
      arguments: item,
    );
    if (changed == true) await loadItems();
  }

  Future<void> goBack() => leavePage(fallbackRoute: AppRoute.adminHome);

  @override
  void onClose() {
    _searchDebounce?.cancel();
    scrollController
      ..removeListener(_onScroll)
      ..dispose();
    searchController.dispose();
    super.onClose();
  }
}
