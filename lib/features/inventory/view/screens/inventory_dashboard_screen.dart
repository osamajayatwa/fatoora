import 'package:fatoora/core/class/handilingdataview.dart';
import 'package:fatoora/core/constants/color.dart';
import 'package:fatoora/features/admin_dashboard/view/widgets/admin_dashboard_shell.dart';
import 'package:fatoora/features/inventory/controllers/inventory_dashboard_controller.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

class InventoryDashboardScreen extends StatelessWidget {
  const InventoryDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return GetBuilder<InventoryDashboardController>(
      builder: (controller) => AdminDashboardShell(
        child: HandilingDataView(
          statusrequest: controller.statusRequest,
          errorMessage: controller.loadErrorMessageKey.tr,
          retryLabel: 'items_retry'.tr,
          onRetry: controller.loadDashboard,
          widget: RefreshIndicator(
            color: AppColor.primaryColor,
            onRefresh: controller.refreshDashboard,
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
                      _InventoryHeader(controller: controller),
                      const SizedBox(height: 18),
                      _InventoryStats(controller: controller),
                      const SizedBox(height: 18),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          if (constraints.maxWidth < 850) {
                            return Column(
                              children: [
                                _LowStockPanel(controller: controller),
                                const SizedBox(height: 18),
                                _RecentMovementsPanel(controller: controller),
                              ],
                            );
                          }
                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: _LowStockPanel(controller: controller),
                              ),
                              const SizedBox(width: 18),
                              Expanded(
                                child: _RecentMovementsPanel(
                                  controller: controller,
                                ),
                              ),
                            ],
                          );
                        },
                      ),
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

class _InventoryHeader extends StatelessWidget {
  const _InventoryHeader({required this.controller});

  final InventoryDashboardController controller;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            'inventory'.tr,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              color: AppColor.secondaryColor,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        IconButton.filled(
          tooltip: 'stock_movements'.tr,
          onPressed: controller.openMovements,
          icon: const Icon(Icons.history_rounded),
          style: IconButton.styleFrom(backgroundColor: AppColor.primaryColor),
        ),
        const SizedBox(width: 8),
        FilledButton.icon(
          onPressed: controller.openAdjustment,
          icon: const Icon(Icons.tune_rounded),
          label: Text('inventory_adjustment'.tr),
          style: FilledButton.styleFrom(
            backgroundColor: AppColor.secondaryColor,
          ),
        ),
      ],
    );
  }
}

class _InventoryStats extends StatelessWidget {
  const _InventoryStats({required this.controller});

  final InventoryDashboardController controller;

  @override
  Widget build(BuildContext context) {
    final snapshot = controller.snapshot;
    final money = NumberFormat.currency(symbol: '', decimalDigits: 3);
    final stats = [
      ('track_stock', snapshot.trackedItemCount.toString(), Icons.inventory),
      (
        'current_stock',
        NumberFormat('#,##0.###').format(snapshot.totalStockQuantity),
        Icons.warehouse_outlined,
      ),
      ('low_stock', snapshot.lowStockCount.toString(), Icons.warning_rounded),
      (
        'out_of_stock',
        snapshot.outOfStockCount.toString(),
        Icons.error_outline_rounded,
      ),
      (
        'inventory_value',
        money.format(snapshot.inventoryValue),
        Icons.payments_outlined,
      ),
    ];
    return Wrap(
      spacing: 14,
      runSpacing: 14,
      children: stats
          .map(
            (stat) => SizedBox(
              width: MediaQuery.sizeOf(context).width < 700
                  ? double.infinity
                  : 210,
              child: Card(
                elevation: 0,
                color: AppColor.surface,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: const BorderSide(color: Color(0xFFE4E8EF)),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Icon(stat.$3, color: AppColor.primaryColor),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              stat.$1.tr,
                              style: Theme.of(context).textTheme.labelMedium
                                  ?.copyWith(color: AppColor.grey),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              stat.$2,
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(
                                    color: AppColor.secondaryColor,
                                    fontWeight: FontWeight.w800,
                                  ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          )
          .toList(),
    );
  }
}

class _LowStockPanel extends StatelessWidget {
  const _LowStockPanel({required this.controller});

  final InventoryDashboardController controller;

  @override
  Widget build(BuildContext context) {
    final items = controller.snapshot.lowStockItems;
    return _Panel(
      title: 'low_stock'.tr,
      child: items.isEmpty
          ? Text('inventory_no_low_stock'.tr)
          : Column(
              children: items
                  .map(
                    (item) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(item.name),
                      subtitle: Text(item.code),
                      trailing: Text(
                        NumberFormat('#,##0.###').format(item.currentStock),
                      ),
                    ),
                  )
                  .toList(),
            ),
    );
  }
}

class _RecentMovementsPanel extends StatelessWidget {
  const _RecentMovementsPanel({required this.controller});

  final InventoryDashboardController controller;

  @override
  Widget build(BuildContext context) {
    final movements = controller.snapshot.recentMovements.take(8).toList();
    return _Panel(
      title: 'stock_movements'.tr,
      child: movements.isEmpty
          ? Text('inventory_no_movements'.tr)
          : Column(
              children: movements
                  .map(
                    (movement) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(movement.itemName),
                      subtitle: Text(movement.movementType.tr),
                      trailing: Text(
                        '${movement.isOut ? '-' : '+'}${NumberFormat('#,##0.###').format(movement.quantity)}',
                        style: TextStyle(
                          color: movement.isOut
                              ? AppColor.error
                              : AppColor.success,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: AppColor.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: Color(0xFFE4E8EF)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: AppColor.secondaryColor,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}
