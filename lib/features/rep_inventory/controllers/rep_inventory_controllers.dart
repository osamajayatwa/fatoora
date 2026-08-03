import 'package:fatoora/app/routes/app_routes.dart';
import 'package:fatoora/core/class/statusrequest.dart';
import 'package:fatoora/core/services/services.dart';
import 'package:fatoora/features/auth/data/models/app_user_model.dart';
import 'package:fatoora/features/auth/data/repositories/auth_repository.dart';
import 'package:fatoora/features/items/data/models/item_model.dart';
import 'package:fatoora/features/rep_inventory/data/models/inventory_transfer_model.dart';
import 'package:fatoora/features/rep_inventory/data/models/rep_inventory_balance_model.dart';
import 'package:fatoora/features/rep_inventory/data/models/rep_inventory_enums.dart';
import 'package:fatoora/features/rep_inventory/data/models/rep_inventory_movement_model.dart';
import 'package:fatoora/features/rep_inventory/data/repositories/rep_inventory_repository.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

List<T> _uniqueById<T>(Iterable<T> values, String Function(T value) idOf) {
  final unique = <String, T>{};
  for (final value in values) {
    final id = idOf(value).trim();
    if (id.isNotEmpty) unique.putIfAbsent(id, () => value);
  }
  return List<T>.unmodifiable(unique.values);
}

mixin RepInventoryControllerContext {
  MyServices get services;

  String get companyId =>
      services.sharedPreferences.getString('companyId') ??
      AuthRepository.defaultCompanyId;
  bool get isAdmin =>
      services.sharedPreferences.getString('role') == AuthRepository.adminRole;
  String get currentUid =>
      services.sharedPreferences.getString('uid')?.trim() ?? '';

  String inventoryErrorMessage(Object error) {
    if (error is! RepInventoryRepositoryException) {
      return 'rep_inventory_error_unknown';
    }
    return switch (error.error) {
      RepInventoryRepositoryError.permissionDenied =>
        'rep_inventory_error_permission',
      RepInventoryRepositoryError.unavailable =>
        'rep_inventory_error_unavailable',
      RepInventoryRepositoryError.timeout => 'rep_inventory_error_timeout',
      RepInventoryRepositoryError.notFound => 'rep_inventory_error_not_found',
      RepInventoryRepositoryError.invalidRepresentative ||
      RepInventoryRepositoryError.inactiveRepresentative =>
        'rep_inventory_error_rep',
      RepInventoryRepositoryError.untrackedItem =>
        'rep_inventory_error_untracked',
      RepInventoryRepositoryError.invalidQuantity =>
        'rep_inventory_error_quantity',
      RepInventoryRepositoryError.duplicateItem =>
        'rep_inventory_error_duplicate',
      RepInventoryRepositoryError.emptyTransfer => 'rep_inventory_error_empty',
      RepInventoryRepositoryError.tooManyLines =>
        'rep_inventory_error_too_many',
      RepInventoryRepositoryError.insufficientWarehouseStock =>
        'rep_inventory_error_warehouse_stock',
      RepInventoryRepositoryError.insufficientRepStock =>
        'rep_inventory_error_rep_stock',
      RepInventoryRepositoryError.alreadyConfirmed =>
        'rep_inventory_error_confirmed',
      RepInventoryRepositoryError.notEditable =>
        'rep_inventory_error_not_editable',
      RepInventoryRepositoryError.concurrentUpdate =>
        'rep_inventory_error_concurrent',
      _ => 'rep_inventory_error_unknown',
    };
  }

  void showInventoryError(Object error) {
    Get.snackbar(
      'error'.tr,
      inventoryErrorMessage(error).tr,
      snackPosition: SnackPosition.BOTTOM,
    );
  }
}

class RepInventoryController extends GetxController
    with RepInventoryControllerContext {
  RepInventoryController({
    required RepInventoryRepository repository,
    required MyServices myServices,
  }) : _repository = repository,
       _services = myServices;

  final RepInventoryRepository _repository;
  final MyServices _services;
  @override
  MyServices get services => _services;

  StatusRequest statusRequest = StatusRequest.loading;
  List<AppUserModel> salesReps = const [];
  List<RepInventoryBalanceModel> balances = const [];
  List<RepInventoryMovementModel> movements = const [];
  List<InventoryTransferModel> transfers = const [];
  String selectedSalesRepId = '';
  String selectedSalesRepName = '';
  String errorKey = 'rep_inventory_error_unknown';

  @override
  void onInit() {
    super.onInit();
    final arguments = Get.arguments;
    if (arguments is Map) {
      selectedSalesRepId = (arguments['salesRepId'] ?? '').toString().trim();
      selectedSalesRepName = (arguments['salesRepName'] ?? '')
          .toString()
          .trim();
    }
    if (!isAdmin) selectedSalesRepId = currentUid;
  }

  @override
  void onReady() {
    super.onReady();
    load();
  }

  Future<void> load() async {
    statusRequest = StatusRequest.loading;
    update();
    try {
      if (isAdmin) {
        salesReps = _uniqueById(
          await _repository.fetchApprovedSalesReps(companyId: companyId),
          (rep) => rep.uid,
        );
        final selectedRep = salesReps
            .where((rep) => rep.uid == selectedSalesRepId)
            .firstOrNull;
        if (selectedRep == null) {
          selectedSalesRepId = salesReps.firstOrNull?.uid ?? '';
          selectedSalesRepName = salesReps.firstOrNull?.name ?? '';
        } else {
          selectedSalesRepName = selectedRep.name;
        }
      }
      if (selectedSalesRepId.isEmpty) {
        balances = const [];
        movements = const [];
        transfers = const [];
      } else {
        final results = await Future.wait([
          _repository.fetchBalances(
            companyId: companyId,
            salesRepId: selectedSalesRepId,
          ),
          _repository.fetchMovements(
            companyId: companyId,
            salesRepId: selectedSalesRepId,
          ),
          _repository.fetchTransfers(
            companyId: companyId,
            salesRepId: selectedSalesRepId,
          ),
        ]);
        balances = results[0] as List<RepInventoryBalanceModel>;
        movements = results[1] as List<RepInventoryMovementModel>;
        transfers = results[2] as List<InventoryTransferModel>;
      }
      statusRequest = StatusRequest.success;
    } catch (error) {
      statusRequest = StatusRequest.failure;
      errorKey = inventoryErrorMessage(error);
    }
    if (!isClosed) update();
  }

  Future<void> selectSalesRep(String? id) async {
    if (id == null || id == selectedSalesRepId) return;
    selectedSalesRepId = id;
    selectedSalesRepName =
        salesReps
            .where((rep) => rep.uid == id)
            .map((rep) => rep.name)
            .firstOrNull ??
        '';
    await load();
  }

  void createTransfer() => Get.toNamed(AppRoute.repInventoryTransferForm);
  void openTransfer(InventoryTransferModel transfer) => Get.toNamed(
    AppRoute.repInventoryTransferDetails,
    arguments: {'transferId': transfer.id},
  );
}

class InventoryTransfersController extends GetxController
    with RepInventoryControllerContext {
  InventoryTransfersController({
    required RepInventoryRepository repository,
    required MyServices myServices,
  }) : _repository = repository,
       _services = myServices;

  final RepInventoryRepository _repository;
  final MyServices _services;
  @override
  MyServices get services => _services;

  final searchController = TextEditingController();
  StatusRequest statusRequest = StatusRequest.loading;
  List<InventoryTransferModel> transfers = const [];
  List<AppUserModel> salesReps = const [];
  String selectedSalesRepId = '';
  InventoryTransferStatus? statusFilter;
  InventoryTransferType? typeFilter;
  DateTime? fromDate;
  DateTime? toDate;
  String errorKey = 'rep_inventory_error_unknown';

  @override
  void onReady() {
    super.onReady();
    load();
  }

  Future<void> load() async {
    statusRequest = StatusRequest.loading;
    update();
    try {
      if (salesReps.isEmpty && isAdmin) {
        salesReps = _uniqueById(
          await _repository.fetchApprovedSalesReps(companyId: companyId),
          (rep) => rep.uid,
        );
        if (selectedSalesRepId.isNotEmpty &&
            !salesReps.any((rep) => rep.uid == selectedSalesRepId)) {
          selectedSalesRepId = '';
        }
      }
      transfers = await _repository.fetchTransfers(
        companyId: companyId,
        salesRepId: selectedSalesRepId,
        status: statusFilter,
        type: typeFilter,
        fromDate: fromDate,
        toDate: toDate,
        searchText: searchController.text,
      );
      statusRequest = StatusRequest.success;
    } catch (error) {
      statusRequest = StatusRequest.failure;
      errorKey = inventoryErrorMessage(error);
    }
    if (!isClosed) update();
  }

  void open(InventoryTransferModel transfer) => Get.toNamed(
    AppRoute.repInventoryTransferDetails,
    arguments: {'transferId': transfer.id},
  );
  void create() => Get.toNamed(AppRoute.repInventoryTransferForm);

  Future<void> selectDateRange(BuildContext context) async {
    final now = DateTime.now();
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: now,
      initialDateRange: fromDate == null || toDate == null
          ? null
          : DateTimeRange(start: fromDate!, end: toDate!),
    );
    if (range == null) return;
    fromDate = range.start;
    toDate = range.end;
    await load();
  }

  void clearFilters() {
    selectedSalesRepId = '';
    statusFilter = null;
    typeFilter = null;
    fromDate = null;
    toDate = null;
    load();
  }

  @override
  void onClose() {
    searchController.dispose();
    super.onClose();
  }
}

class InventoryTransferFormController extends GetxController
    with RepInventoryControllerContext {
  InventoryTransferFormController({
    required RepInventoryRepository repository,
    required MyServices myServices,
  }) : _repository = repository,
       _services = myServices;

  final RepInventoryRepository _repository;
  final MyServices _services;
  @override
  MyServices get services => _services;

  final quantityController = TextEditingController();
  final notesController = TextEditingController();
  StatusRequest statusRequest = StatusRequest.loading;
  List<AppUserModel> salesReps = const [];
  List<ItemModel> items = const [];
  Map<String, double> repQuantities = const {};
  List<InventoryTransferLine> lines = [];
  String selectedSalesRepId = '';
  String selectedItemId = '';
  InventoryTransferType type = InventoryTransferType.warehouseToRep;
  String draftId = '';
  bool isSaving = false;
  bool isConfirming = false;
  String errorKey = 'rep_inventory_error_unknown';

  @override
  void onReady() {
    super.onReady();
    load();
  }

  Future<void> load() async {
    try {
      final results = await Future.wait([
        _repository.fetchApprovedSalesReps(companyId: companyId),
        _repository.fetchTrackedItems(),
      ]);
      salesReps = _uniqueById(
        results[0] as List<AppUserModel>,
        (rep) => rep.uid,
      );
      items = _uniqueById(results[1] as List<ItemModel>, (item) => item.id);
      if (!salesReps.any((rep) => rep.uid == selectedSalesRepId)) {
        selectedSalesRepId = salesReps.firstOrNull?.uid ?? '';
      }
      _selectFirstAvailableItemIfNeeded();
      await _loadRepBalances();
      statusRequest = StatusRequest.success;
    } catch (error) {
      statusRequest = StatusRequest.failure;
      errorKey = inventoryErrorMessage(error);
    }
    if (!isClosed) update();
  }

  void addLine() {
    final quantity = double.tryParse(quantityController.text.trim()) ?? 0;
    final item = items.where((entry) => entry.id == selectedItemId).firstOrNull;
    final available = type == InventoryTransferType.warehouseToRep
        ? item?.currentStock ?? 0
        : repQuantities[item?.id] ?? 0;
    if (item == null || quantity <= 0) {
      showInventoryError(
        const RepInventoryRepositoryException(
          RepInventoryRepositoryError.invalidQuantity,
        ),
      );
      return;
    }
    if (quantity > available + 0.0005) {
      showInventoryError(
        RepInventoryRepositoryException(
          type == InventoryTransferType.warehouseToRep
              ? RepInventoryRepositoryError.insufficientWarehouseStock
              : RepInventoryRepositoryError.insufficientRepStock,
        ),
      );
      return;
    }
    if (lines.any((line) => line.itemId == item.id)) {
      showInventoryError(
        const RepInventoryRepositoryException(
          RepInventoryRepositoryError.duplicateItem,
        ),
      );
      return;
    }
    lines = [
      ...lines,
      InventoryTransferLine(
        itemId: item.id,
        modelSnapshot: item.code,
        itemNameSnapshot: item.name,
        unitSnapshot: item.unit,
        quantity: quantity,
      ),
    ];
    quantityController.clear();
    selectedItemId =
        items
            .where((entry) => !lines.any((line) => line.itemId == entry.id))
            .map((entry) => entry.id)
            .firstOrNull ??
        '';
    update();
  }

  void removeLine(String itemId) {
    lines = lines.where((line) => line.itemId != itemId).toList();
    if (selectedItemId.isEmpty && items.any((item) => item.id == itemId)) {
      selectedItemId = itemId;
    }
    update();
  }

  void selectItem(String? value) {
    final id = value?.trim() ?? '';
    selectedItemId =
        items.any(
          (item) =>
              item.id == id && !lines.any((line) => line.itemId == item.id),
        )
        ? id
        : '';
    update();
  }

  Future<void> selectSalesRep(String? value) async {
    if (selectedSalesRepId == value) return;
    selectedSalesRepId = value ?? '';
    lines = [];
    _selectFirstAvailableItemIfNeeded();
    await _loadRepBalances();
    update();
  }

  void selectType(InventoryTransferType? value) {
    if (value == null || value == type) return;
    type = value;
    lines = [];
    _selectFirstAvailableItemIfNeeded();
    update();
  }

  void _selectFirstAvailableItemIfNeeded() {
    final availableIds = items
        .where((item) => !lines.any((line) => line.itemId == item.id))
        .map((item) => item.id)
        .toSet();
    if (!availableIds.contains(selectedItemId)) {
      selectedItemId = availableIds.firstOrNull ?? '';
    }
  }

  Future<void> _loadRepBalances() async {
    if (selectedSalesRepId.isEmpty) {
      repQuantities = const {};
      return;
    }
    final balances = await _repository.fetchBalances(
      companyId: companyId,
      salesRepId: selectedSalesRepId,
    );
    repQuantities = {
      for (final balance in balances) balance.itemId: balance.quantity,
    };
  }

  Future<InventoryTransferModel?> _save() async {
    if (selectedSalesRepId.isEmpty || lines.isEmpty) {
      showInventoryError(
        const RepInventoryRepositoryException(
          RepInventoryRepositoryError.emptyTransfer,
        ),
      );
      return null;
    }
    final saved = await _repository.saveDraft(
      companyId: companyId,
      transferId: draftId,
      type: type,
      salesRepId: selectedSalesRepId,
      lines: lines,
      notes: notesController.text,
    );
    draftId = saved.id;
    return saved;
  }

  Future<void> saveDraft() async {
    if (isSaving || isConfirming) return;
    isSaving = true;
    update();
    try {
      final saved = await _save();
      if (saved != null) {
        Get.snackbar('success'.tr, 'rep_inventory_draft_saved'.tr);
        Get.offNamed(
          AppRoute.repInventoryTransferDetails,
          arguments: {'transferId': saved.id},
        );
      }
    } catch (error) {
      showInventoryError(error);
    } finally {
      isSaving = false;
      if (!isClosed) update();
    }
  }

  Future<void> confirm() async {
    if (isSaving || isConfirming) return;
    isConfirming = true;
    update();
    try {
      final saved = await _save();
      if (saved == null) return;
      final confirmed = await _repository.confirmTransfer(
        companyId: companyId,
        transferId: saved.id,
      );
      Get.snackbar('success'.tr, 'rep_inventory_confirmed'.tr);
      Get.offNamed(
        AppRoute.repInventoryTransferDetails,
        arguments: {'transferId': confirmed.id},
      );
    } catch (error) {
      showInventoryError(error);
    } finally {
      isConfirming = false;
      if (!isClosed) update();
    }
  }

  @override
  void onClose() {
    quantityController.dispose();
    notesController.dispose();
    super.onClose();
  }
}

class InventoryTransferDetailsController extends GetxController
    with RepInventoryControllerContext {
  InventoryTransferDetailsController({
    required RepInventoryRepository repository,
    required MyServices myServices,
  }) : _repository = repository,
       _services = myServices;

  final RepInventoryRepository _repository;
  final MyServices _services;
  @override
  MyServices get services => _services;
  StatusRequest statusRequest = StatusRequest.loading;
  InventoryTransferModel? transfer;
  String errorKey = 'rep_inventory_error_unknown';

  @override
  void onReady() {
    super.onReady();
    load();
  }

  Future<void> load() async {
    try {
      final args = Get.arguments;
      final id = args is Map ? (args['transferId'] ?? '').toString() : '';
      transfer = await _repository.getTransfer(
        companyId: companyId,
        transferId: id,
      );
      statusRequest = transfer == null
          ? StatusRequest.failure
          : StatusRequest.success;
      if (transfer == null) errorKey = 'rep_inventory_error_not_found';
    } catch (error) {
      statusRequest = StatusRequest.failure;
      errorKey = inventoryErrorMessage(error);
    }
    if (!isClosed) update();
  }

  Future<void> confirm() async {
    final current = transfer;
    if (current == null || !current.isDraft) return;
    try {
      transfer = await _repository.confirmTransfer(
        companyId: companyId,
        transferId: current.id,
      );
      Get.snackbar('success'.tr, 'rep_inventory_confirmed'.tr);
      update();
    } catch (error) {
      showInventoryError(error);
    }
  }

  Future<void> cancel() async {
    final current = transfer;
    if (current == null || !current.isDraft) return;
    try {
      await _repository.cancelDraft(
        companyId: companyId,
        transferId: current.id,
      );
      await load();
      Get.snackbar('success'.tr, 'rep_inventory_cancelled'.tr);
    } catch (error) {
      showInventoryError(error);
    }
  }

  Future<void> deleteDraft() async {
    final current = transfer;
    if (current == null || !current.isDraft) return;
    try {
      await _repository.deleteDraft(
        companyId: companyId,
        transferId: current.id,
      );
      Get.back<void>();
      Get.snackbar('success'.tr, 'rep_inventory_deleted'.tr);
    } catch (error) {
      showInventoryError(error);
    }
  }
}
