import 'package:fatoora/core/class/handilingdataview.dart';
import 'package:fatoora/core/constants/color.dart';
import 'package:fatoora/features/admin_dashboard/view/widgets/admin_dashboard_shell.dart';
import 'package:fatoora/features/inventory/controllers/stock_movements_controller.dart';
import 'package:fatoora/features/inventory/data/models/stock_movement_model.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

class StockMovementsScreen extends StatelessWidget {
  const StockMovementsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return GetBuilder<StockMovementsController>(
      builder: (controller) => AdminDashboardShell(
        child: HandilingDataView(
          statusrequest: controller.statusRequest,
          errorMessage: controller.loadErrorMessageKey.tr,
          retryLabel: 'items_retry'.tr,
          onRetry: controller.loadMovements,
          widget: RefreshIndicator(
            color: AppColor.primaryColor,
            onRefresh: controller.loadMovements,
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.all(
                MediaQuery.sizeOf(context).width < 600 ? 14 : 24,
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1180),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'stock_movements'.tr,
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(
                              color: AppColor.secondaryColor,
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                      const SizedBox(height: 16),
                      _MovementFilters(controller: controller),
                      const SizedBox(height: 16),
                      if (controller.movements.isEmpty)
                        Center(child: Text('inventory_no_movements'.tr))
                      else
                        _MovementList(movements: controller.movements),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MovementFilters extends StatelessWidget {
  const _MovementFilters({required this.controller});

  final StockMovementsController controller;

  @override
  Widget build(BuildContext context) {
    final movementTypes = [
      '',
      'opening_balance',
      'invoice_sale',
      'sales_return',
      'manual_adjustment_in',
      'manual_adjustment_out',
      'damage',
      'correction',
    ];
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        SizedBox(
          width: MediaQuery.sizeOf(context).width < 700 ? double.infinity : 360,
          child: TextField(
            controller: controller.searchController,
            onChanged: controller.onSearchChanged,
            decoration: InputDecoration(
              hintText: 'stock_movement_search'.tr,
              prefixIcon: const Icon(Icons.search_rounded),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
        ),
        SizedBox(
          width: MediaQuery.sizeOf(context).width < 700 ? double.infinity : 260,
          child: DropdownButtonFormField<String>(
            value: controller.movementType,
            items: movementTypes
                .map(
                  (type) => DropdownMenuItem(
                    value: type,
                    child: Text(type.isEmpty ? 'all'.tr : type.tr),
                  ),
                )
                .toList(),
            onChanged: (value) => controller.setMovementType(value ?? ''),
            decoration: InputDecoration(
              labelText: 'stock_movement'.tr,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _MovementList extends StatelessWidget {
  const _MovementList({required this.movements});

  final List<StockMovementModel> movements;

  @override
  Widget build(BuildContext context) {
    final date = DateFormat('yyyy-MM-dd HH:mm');
    return Column(
      children: movements
          .map(
            (movement) => Card(
              elevation: 0,
              color: AppColor.surface,
              margin: const EdgeInsets.only(bottom: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: const BorderSide(color: Color(0xFFE4E8EF)),
              ),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: movement.isOut
                      ? AppColor.error.withValues(alpha: 0.12)
                      : AppColor.success.withValues(alpha: 0.12),
                  child: Icon(
                    movement.isOut
                        ? Icons.arrow_upward_rounded
                        : Icons.arrow_downward_rounded,
                    color: movement.isOut ? AppColor.error : AppColor.success,
                  ),
                ),
                title: Text(movement.itemName),
                subtitle: Text(
                  [
                    movement.movementType.tr,
                    movement.referenceNumber,
                    date.format(movement.movementDate),
                  ].where((value) => value.isNotEmpty).join(' / '),
                ),
                trailing: Text(
                  '${movement.isOut ? '-' : '+'}${NumberFormat('#,##0.###').format(movement.quantity)}',
                  style: TextStyle(
                    color: movement.isOut ? AppColor.error : AppColor.success,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          )
          .toList(),
    );
  }
}
