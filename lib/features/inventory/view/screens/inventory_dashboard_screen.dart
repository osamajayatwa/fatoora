import 'package:fatoora/core/class/handilingdataview.dart';
import 'package:fatoora/core/class/statusrequest.dart';
import 'package:fatoora/core/constants/color.dart';
import 'package:fatoora/core/motion/fatoora_motion_widgets.dart';
import 'package:fatoora/features/admin_dashboard/view/widgets/admin_dashboard_shell.dart';
import 'package:fatoora/features/admin_dashboard/view/widgets/dashboard_card.dart';
import 'package:fatoora/features/inventory/controllers/inventory_dashboard_controller.dart';
import 'package:fatoora/features/inventory/data/models/stock_movement_model.dart';
import 'package:fatoora/features/items/data/models/item_model.dart';
import 'package:fatoora/features/shared/business/business_page_widgets.dart';
import 'package:fatoora/features/shared/dashboard/dashboard_primitives.dart';
import 'package:fatoora/features/shared/inventory/inventory_presentation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart' hide TextDirection;

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
            child: LayoutBuilder(
              builder: (context, constraints) {
                final padding = constraints.maxWidth < 600 ? 14.0 : 24.0;
                return SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: EdgeInsets.fromLTRB(padding, padding, padding, 48),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1240),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _InventoryHeader(controller: controller),
                          const SizedBox(height: 18),
                          _InventoryStats(controller: controller),
                          const SizedBox(height: 22),
                          _DashboardPanels(controller: controller),
                          const SizedBox(height: 26),
                          _InventoryItemsSection(controller: controller),
                        ],
                      ),
                    ),
                  ),
                );
              },
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
  Widget build(BuildContext context) => BusinessPageHeader(
    title: 'inventory'.tr,
    trailing: Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        BusinessSecondaryActionButton(
          label: 'stock_movements'.tr,
          icon: Icons.history_rounded,
          onPressed: controller.openMovements,
        ),
        BusinessPrimaryActionButton(
          label: 'inventory_adjustment'.tr,
          icon: Icons.tune_rounded,
          onPressed: controller.openAdjustment,
        ),
      ],
    ),
  );
}

class _InventoryStats extends StatelessWidget {
  const _InventoryStats({required this.controller});

  final InventoryDashboardController controller;

  @override
  Widget build(BuildContext context) {
    final snapshot = controller.snapshot;
    final money = NumberFormat.currency(symbol: '', decimalDigits: 3);
    final stats = [
      (
        'track_stock'.tr,
        snapshot.trackedItemCount.toString(),
        Icons.inventory_2_outlined,
        AppColor.secondaryColor,
      ),
      (
        'current_stock'.tr,
        inventoryQuantity(snapshot.totalStockQuantity),
        Icons.warehouse_outlined,
        const Color(0xFF32689A),
      ),
      (
        'low_stock'.tr,
        snapshot.lowStockCount.toString(),
        Icons.warning_amber_rounded,
        const Color(0xFFB26A00),
      ),
      (
        'out_of_stock'.tr,
        snapshot.outOfStockCount.toString(),
        Icons.error_outline_rounded,
        AppColor.error,
      ),
      (
        'inventory_value'.tr,
        money.format(snapshot.inventoryValue),
        Icons.payments_outlined,
        AppColor.success,
      ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final textScale = MediaQuery.textScalerOf(context).scale(1);
        final columns = constraints.maxWidth >= 1050
            ? 5
            : constraints.maxWidth >= 700
            ? 3
            : constraints.maxWidth >= 360 && textScale <= 1.3
            ? 2
            : 1;
        const spacing = 12.0;
        final width =
            (constraints.maxWidth - (spacing * (columns - 1))) / columns;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: stats
              .map(
                (stat) => SizedBox(
                  width: width,
                  child: InventoryKpiCard(
                    label: stat.$1,
                    value: stat.$2,
                    icon: stat.$3,
                    color: stat.$4,
                  ),
                ),
              )
              .toList(),
        );
      },
    );
  }
}

class _DashboardPanels extends StatelessWidget {
  const _DashboardPanels({required this.controller});

  final InventoryDashboardController controller;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final low = _LowStockPanel(controller: controller);
      final movements = _RecentMovementsPanel(controller: controller);
      if (constraints.maxWidth < 850) {
        return Column(children: [low, const SizedBox(height: 16), movements]);
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: low),
          const SizedBox(width: 16),
          Expanded(child: movements),
        ],
      );
    },
  );
}

class _LowStockPanel extends StatelessWidget {
  const _LowStockPanel({required this.controller});

  final InventoryDashboardController controller;

  @override
  Widget build(BuildContext context) {
    final items = controller.snapshot.lowStockItems;
    return DashboardCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DashboardSectionTitle(
            titleKey: 'low_stock',
            trailing: _CountBadge(count: controller.snapshot.lowStockCount),
          ),
          if (items.isEmpty)
            const DashboardEmptyState(
              icon: Icons.check_circle_outline_rounded,
              messageKey: 'inventory_no_low_stock',
            )
          else
            ...items.map(
              (item) => _LowStockRow(
                item: item,
                onTap: () => controller.openItem(item),
              ),
            ),
        ],
      ),
    );
  }
}

class _LowStockRow extends StatelessWidget {
  const _LowStockRow({required this.item, required this.onTap});

  final ItemModel item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(12),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 9),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 2),
                Text(
                  '${item.code} · ${'min_stock'.tr}: '
                  '${inventoryQuantity(item.minStock)} ${item.unit}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: context.appMutedText),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(
            '${inventoryQuantity(item.currentStock)} ${item.unit}',
            style: const TextStyle(
              color: Color(0xFFB26A00),
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(width: 4),
          Icon(
            Directionality.of(context) == TextDirection.rtl
                ? Icons.chevron_left_rounded
                : Icons.chevron_right_rounded,
            size: 20,
          ),
        ],
      ),
    ),
  );
}

class _RecentMovementsPanel extends StatelessWidget {
  const _RecentMovementsPanel({required this.controller});

  final InventoryDashboardController controller;

  @override
  Widget build(BuildContext context) {
    final movements = controller.snapshot.recentMovements.take(8).toList();
    return DashboardCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DashboardSectionTitle(
            titleKey: 'stock_movements',
            trailing: IconButton(
              tooltip: 'stock_movements'.tr,
              onPressed: controller.openMovements,
              icon: Icon(
                Directionality.of(context) == TextDirection.rtl
                    ? Icons.arrow_back_rounded
                    : Icons.arrow_forward_rounded,
              ),
            ),
          ),
          if (movements.isEmpty)
            const DashboardEmptyState(
              icon: Icons.history_rounded,
              messageKey: 'inventory_no_movements',
            )
          else
            ...movements.map((movement) => _MovementRow(movement: movement)),
        ],
      ),
    );
  }
}

class _MovementRow extends StatelessWidget {
  const _MovementRow({required this.movement});

  final StockMovementModel movement;

  @override
  Widget build(BuildContext context) {
    final color = movement.isOut ? AppColor.error : AppColor.success;
    final reference = movement.referenceNumber.trim().isNotEmpty
        ? movement.referenceNumber
        : movement.referenceType;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: color.withValues(alpha: .1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              movement.isOut
                  ? Icons.north_east_rounded
                  : Icons.south_west_rounded,
              size: 18,
              color: color,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  movement.itemName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 2),
                Text(
                  [
                    movement.movementType.tr,
                    if (reference.trim().isNotEmpty) reference,
                    DateFormat.yMd().format(movement.movementDate),
                  ].join(' · '),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: context.appMutedText),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${movement.isOut ? '-' : '+'}'
            '${inventoryQuantity(movement.quantity)}',
            style: TextStyle(color: color, fontWeight: FontWeight.w900),
          ),
        ],
      ),
    );
  }
}

class _InventoryItemsSection extends StatelessWidget {
  const _InventoryItemsSection({required this.controller});

  final InventoryDashboardController controller;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      FatooraDashboardSectionTitle(
        title: 'inventory_items'.tr,
        subtitle: 'inventory_items_subtitle'.tr,
      ),
      const SizedBox(height: 4),
      _ItemControls(controller: controller),
      const SizedBox(height: 14),
      _ItemResults(controller: controller),
    ],
  );
}

class _ItemControls extends StatelessWidget {
  const _ItemControls({required this.controller});

  final InventoryDashboardController controller;

  @override
  Widget build(BuildContext context) {
    final search = TextField(
      key: const ValueKey('inventory-item-search'),
      controller: controller.itemSearchController,
      onChanged: controller.onItemSearchChanged,
      onSubmitted: (_) => controller.submitItemSearch(),
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: 'items_search'.tr,
        prefixIcon: const Icon(Icons.search_rounded),
        suffixIcon: controller.itemSearchQuery.isEmpty
            ? null
            : IconButton(
                tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                onPressed: controller.clearItemSearch,
                icon: const Icon(Icons.close_rounded),
              ),
        filled: true,
        fillColor: context.appSurface,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: context.appBorder),
        ),
      ),
    );
    final sort = DropdownButtonFormField<InventoryItemSort>(
      key: const ValueKey('inventory-item-sort'),
      value: controller.itemSort,
      isExpanded: true,
      onChanged: (value) {
        if (value != null) controller.setItemSort(value);
      },
      decoration: InputDecoration(
        labelText: 'items_sort'.tr,
        prefixIcon: const Icon(Icons.sort_rounded),
        filled: true,
        fillColor: context.appSurface,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: context.appBorder),
        ),
      ),
      items: InventoryItemSort.values
          .map(
            (value) => DropdownMenuItem(
              value: value,
              child: Text(switch (value) {
                InventoryItemSort.newest => 'items_newest'.tr,
                InventoryItemSort.oldest => 'items_oldest'.tr,
                InventoryItemSort.priceHigh => 'items_price_high'.tr,
                InventoryItemSort.priceLow => 'items_price_low'.tr,
              }),
            ),
          )
          .toList(),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 680) {
          return Column(children: [search, const SizedBox(height: 10), sort]);
        }
        return Row(
          children: [
            Expanded(child: search),
            const SizedBox(width: 12),
            SizedBox(width: 240, child: sort),
          ],
        );
      },
    );
  }
}

class _ItemResults extends StatelessWidget {
  const _ItemResults({required this.controller});

  final InventoryDashboardController controller;

  @override
  Widget build(BuildContext context) {
    if (controller.itemStatusRequest == StatusRequest.loading) {
      return const Padding(
        key: ValueKey('inventory-items-loading'),
        padding: EdgeInsets.symmetric(vertical: 38),
        child: Center(child: FatooraProgressIndicator()),
      );
    }
    if (controller.itemStatusRequest != StatusRequest.success) {
      return BusinessEmptyState(
        key: const ValueKey('inventory-items-error'),
        icon: Icons.sync_problem_outlined,
        title: controller.itemLoadErrorMessageKey.tr,
        action: FilledButton.icon(
          key: const ValueKey('inventory-items-retry'),
          onPressed: controller.loadItems,
          icon: const Icon(Icons.refresh_rounded),
          label: Text('items_retry'.tr),
        ),
      );
    }
    if (controller.items.isEmpty) {
      return BusinessEmptyState(
        key: const ValueKey('inventory-items-empty'),
        icon: Icons.inventory_2_outlined,
        title: 'inventory_no_items'.tr,
      );
    }
    return Column(
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= 1100
                ? 3
                : constraints.maxWidth >= 720
                ? 2
                : 1;
            const spacing = 12.0;
            final width =
                (constraints.maxWidth - (spacing * (columns - 1))) / columns;
            return Wrap(
              spacing: spacing,
              runSpacing: spacing,
              children: controller.items
                  .map(
                    (item) => SizedBox(
                      width: width,
                      child: WarehouseInventoryItemCard(
                        item: item,
                        onTap: () => controller.openItem(item),
                      ),
                    ),
                  )
                  .toList(),
            );
          },
        ),
        if (controller.hasMoreItems) ...[
          const SizedBox(height: 18),
          BusinessLoadMoreButton(
            key: const ValueKey('inventory-items-load-more'),
            loading: controller.isLoadingMoreItems,
            onPressed: controller.loadMoreItems,
          ),
        ],
      ],
    );
  }
}

class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.primary.withValues(alpha: .09),
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(
      NumberFormat.decimalPattern().format(count),
      style: Theme.of(context).textTheme.labelMedium?.copyWith(
        color: Theme.of(context).colorScheme.primary,
        fontWeight: FontWeight.w800,
      ),
    ),
  );
}
