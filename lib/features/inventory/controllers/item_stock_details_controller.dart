import 'package:fatoora/core/class/statusrequest.dart';
import 'package:fatoora/core/services/services.dart';
import 'package:fatoora/features/auth/data/repositories/auth_repository.dart';
import 'package:fatoora/features/inventory/controllers/inventory_error_mapper.dart';
import 'package:fatoora/features/inventory/data/models/stock_movement_model.dart';
import 'package:fatoora/features/inventory/data/repositories/inventory_repository.dart';
import 'package:fatoora/features/items/controller/item_error_mapper.dart';
import 'package:fatoora/features/items/data/models/item_model.dart';
import 'package:fatoora/features/items/data/repositories/item_repository.dart';
import 'package:get/get.dart';

class ItemStockDetailsController extends GetxController {
  ItemStockDetailsController({
    required InventoryRepository inventoryRepository,
    required ItemRepository itemRepository,
    required MyServices myServices,
  }) : _inventoryRepository = inventoryRepository,
       _itemRepository = itemRepository,
       _myServices = myServices;

  final InventoryRepository _inventoryRepository;
  final ItemRepository _itemRepository;
  final MyServices _myServices;

  StatusRequest statusRequest = StatusRequest.loading;
  String loadErrorMessageKey = 'inventory_load_error';
  ItemModel? item;
  List<StockMovementModel> movements = const [];

  String get companyId {
    final cached =
        _myServices.sharedPreferences.getString('companyId')?.trim() ?? '';
    return cached.isEmpty ? AuthRepository.defaultCompanyId : cached;
  }

  @override
  void onReady() {
    super.onReady();
    final args = Get.arguments;
    if (args is ItemModel) {
      item = args;
    } else if (args is Map) {
      final itemArg = args['item'];
      if (itemArg is ItemModel) item = itemArg;
    }
    loadDetails();
  }

  Future<void> loadDetails() async {
    final current = item;
    if (current == null) {
      statusRequest = StatusRequest.failure;
      loadErrorMessageKey = 'inventory_item_not_found';
      update();
      return;
    }
    statusRequest = StatusRequest.loading;
    loadErrorMessageKey = 'inventory_load_error';
    update();
    try {
      item = await _itemRepository.getItem(current.id);
      movements = await _inventoryRepository.fetchStockMovements(
        companyId: companyId,
        itemId: current.id,
      );
      statusRequest = StatusRequest.success;
    } catch (error) {
      statusRequest = error is ItemRepositoryException
          ? ItemErrorMapper.status(error)
          : InventoryErrorMapper.status(error);
      loadErrorMessageKey = error is ItemRepositoryException
          ? ItemErrorMapper.messageKey(error, fallback: 'inventory_load_error')
          : InventoryErrorMapper.messageKey(
              error,
              fallback: 'inventory_load_error',
            );
    }
    if (!isClosed) update();
  }
}
