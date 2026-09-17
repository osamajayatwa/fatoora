import 'dart:async';

import 'package:fatoora/core/class/statusrequest.dart';
import 'package:fatoora/core/data/firestore_query_pager.dart';
import 'package:fatoora/core/services/services.dart';
import 'package:fatoora/core/search/server_search_policy.dart';
import 'package:fatoora/features/auth/data/repositories/auth_repository.dart';
import 'package:fatoora/features/inventory/controllers/inventory_error_mapper.dart';
import 'package:fatoora/features/inventory/data/models/stock_movement_model.dart';
import 'package:fatoora/features/inventory/data/repositories/inventory_repository.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class StockMovementsController extends GetxController {
  StockMovementsController({
    required InventoryRepository repository,
    required MyServices myServices,
  }) : _repository = repository,
       _myServices = myServices;

  final InventoryRepository _repository;
  final MyServices _myServices;
  final TextEditingController searchController = TextEditingController();

  StatusRequest statusRequest = StatusRequest.loading;
  String loadErrorMessageKey = 'inventory_load_error';
  List<StockMovementModel> movements = const [];
  String itemId = '';
  String movementType = '';
  String searchText = '';
  Timer? _debounce;
  int _loadGeneration = 0;
  String _appliedSearchText = '';
  FirestorePageCursor? _pageCursor;
  bool hasMore = false;
  bool isLoadingMore = false;

  String get companyId {
    final cached =
        _myServices.sharedPreferences.getString('companyId')?.trim() ?? '';
    return cached.isEmpty ? AuthRepository.defaultCompanyId : cached;
  }

  @override
  void onReady() {
    super.onReady();
    final args = Get.arguments;
    if (args is Map) {
      itemId = (args['itemId'] as String?)?.trim() ?? '';
    }
    loadMovements();
  }

  Future<void> loadMovements() async {
    _debounce?.cancel();
    final generation = ++_loadGeneration;
    final requestedSearch = serverSearchTerm(searchText);
    statusRequest = StatusRequest.loading;
    _pageCursor = null;
    hasMore = false;
    loadErrorMessageKey = 'inventory_load_error';
    update();
    try {
      final page = await _repository.fetchStockMovementsPage(
        companyId: companyId,
        itemId: itemId,
        movementType: movementType,
        searchText: requestedSearch,
      );
      if (generation != _loadGeneration) return;
      movements = page.items;
      _pageCursor = page.cursor;
      hasMore = page.hasMore;
      _appliedSearchText = requestedSearch;
      statusRequest = StatusRequest.success;
    } catch (error) {
      if (generation != _loadGeneration) return;
      statusRequest = InventoryErrorMapper.status(error);
      loadErrorMessageKey = InventoryErrorMapper.messageKey(
        error,
        fallback: 'inventory_load_error',
      );
    }
    if (!isClosed) update();
  }

  void onSearchChanged(String value) {
    searchText = value;
    _debounce?.cancel();
    _loadGeneration++;
    update();
    if (serverSearchTerm(value).isEmpty) {
      if (_appliedSearchText.isNotEmpty ||
          statusRequest != StatusRequest.success) {
        loadMovements();
      }
      return;
    }
    _debounce = Timer(serverSearchDebounce, loadMovements);
  }

  void submitSearch() {
    _debounce?.cancel();
    if (serverSearchTerm(searchText).isEmpty &&
        _appliedSearchText.isEmpty &&
        statusRequest == StatusRequest.success) {
      return;
    }
    loadMovements();
  }

  void clearSearch() {
    _debounce?.cancel();
    searchText = '';
    searchController.clear();
    loadMovements();
  }

  void setMovementType(String value) {
    _debounce?.cancel();
    movementType = value;
    loadMovements();
  }

  Future<void> loadMore() async {
    if (isLoadingMore || !hasMore || _pageCursor == null) return;
    isLoadingMore = true;
    final generation = _loadGeneration;
    update();
    try {
      final page = await _repository.fetchStockMovementsPage(
        companyId: companyId,
        itemId: itemId,
        movementType: movementType,
        searchText: serverSearchTerm(searchText),
        after: _pageCursor,
      );
      if (generation != _loadGeneration) return;
      movements = [...movements, ...page.items];
      _pageCursor = page.cursor;
      hasMore = page.hasMore;
    } catch (error) {
      if (generation == _loadGeneration) {
        loadErrorMessageKey = InventoryErrorMapper.messageKey(error);
      }
    } finally {
      isLoadingMore = false;
      if (!isClosed) update();
    }
  }

  @override
  void onClose() {
    _debounce?.cancel();
    searchController.dispose();
    super.onClose();
  }
}
