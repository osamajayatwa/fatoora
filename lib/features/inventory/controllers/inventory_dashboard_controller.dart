import 'package:fatoora/app/routes/app_routes.dart';
import 'package:fatoora/core/class/statusrequest.dart';
import 'package:fatoora/core/services/services.dart';
import 'package:fatoora/features/auth/data/repositories/auth_repository.dart';
import 'package:fatoora/features/inventory/controllers/inventory_error_mapper.dart';
import 'package:fatoora/features/inventory/data/models/inventory_dashboard_snapshot.dart';
import 'package:fatoora/features/inventory/data/repositories/inventory_repository.dart';
import 'package:get/get.dart';

class InventoryDashboardController extends GetxController {
  InventoryDashboardController({
    required InventoryRepository repository,
    required MyServices myServices,
  }) : _repository = repository,
       _myServices = myServices;

  final InventoryRepository _repository;
  final MyServices _myServices;

  StatusRequest statusRequest = StatusRequest.loading;
  String loadErrorMessageKey = 'inventory_load_error';
  InventoryDashboardSnapshot snapshot =
      const InventoryDashboardSnapshot.empty();

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
      snapshot = await _repository.fetchDashboard(companyId: companyId);
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

  Future<void> refreshDashboard() => loadDashboard();

  void openMovements() => Get.toNamed(AppRoute.stockMovements);

  void openAdjustment() => Get.toNamed(AppRoute.inventoryAdjustment);
}
