import 'dart:async';

import 'package:fatoora/core/class/statusrequest.dart';
import 'package:fatoora/core/services/services.dart';
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
    statusRequest = StatusRequest.loading;
    loadErrorMessageKey = 'inventory_load_error';
    update();
    try {
      movements = await _repository.fetchStockMovements(
        companyId: companyId,
        itemId: itemId,
        movementType: movementType,
        searchText: searchText,
      );
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

  void onSearchChanged(String value) {
    searchText = value;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), loadMovements);
  }

  void setMovementType(String value) {
    movementType = value;
    loadMovements();
  }

  @override
  void onClose() {
    _debounce?.cancel();
    searchController.dispose();
    super.onClose();
  }
}
