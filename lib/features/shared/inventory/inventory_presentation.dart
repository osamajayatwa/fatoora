import 'package:fatoora/core/constants/color.dart';
import 'package:fatoora/features/admin_dashboard/view/widgets/dashboard_card.dart';
import 'package:fatoora/features/inventory/data/models/stock_movement_model.dart';
import 'package:fatoora/features/items/data/models/item_model.dart';
import 'package:fatoora/features/rep_inventory/data/models/rep_inventory_balance_model.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart' hide TextDirection;

String inventoryQuantity(double value) =>
    NumberFormat('#,##0.###').format(value);

class InventoryKpiCard extends StatelessWidget {
  const InventoryKpiCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    this.onTap,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => DashboardCard(
    padding: const EdgeInsets.all(14),
    onTap: onTap,
    semanticLabel: label,
    child: Row(
      children: [
        Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: color.withValues(alpha: .11),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, size: 21, color: color),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: context.appMutedText,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: context.appText,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class InventoryStockStatusChip extends StatelessWidget {
  const InventoryStockStatusChip({super.key, required this.item});

  final ItemModel item;

  @override
  Widget build(BuildContext context) {
    final (label, color, icon) = !item.trackStock
        ? ('track_stock_disabled'.tr, context.appMutedText, Icons.block_rounded)
        : item.isOutOfStock
        ? ('out_of_stock'.tr, AppColor.error, Icons.error_outline_rounded)
        : item.isLowStock
        ? ('low_stock'.tr, const Color(0xFFB26A00), Icons.warning_amber_rounded)
        : ('in_stock'.tr, AppColor.success, Icons.check_circle_outline_rounded);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 156),
      child: Container(
        key: ValueKey('stock-status-${item.id}'),
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .1),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: color.withValues(alpha: .25)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class WarehouseInventoryItemCard extends StatelessWidget {
  const WarehouseInventoryItemCard({
    super.key,
    required this.item,
    required this.onTap,
  });

  final ItemModel item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => DashboardCard(
    key: ValueKey('warehouse-item-${item.id}'),
    padding: const EdgeInsets.all(15),
    onTap: onTap,
    semanticLabel: item.name,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: context.appText,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  if (item.code.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      item.code,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textDirection: TextDirection.ltr,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: context.appMutedText,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 10),
            InventoryStockStatusChip(item: item),
          ],
        ),
        if (item.trackStock) ...[
          const SizedBox(height: 13),
          Wrap(
            spacing: 18,
            runSpacing: 9,
            crossAxisAlignment: WrapCrossAlignment.end,
            children: [
              _QuantityFact(
                key: ValueKey('warehouse-quantity-${item.id}'),
                label: 'current_stock'.tr,
                value: inventoryQuantity(item.currentStock),
                unit: item.unit,
                prominent: true,
              ),
              _QuantityFact(
                key: ValueKey('minimum-stock-${item.id}'),
                label: 'min_stock'.tr,
                value: inventoryQuantity(item.minStock),
                unit: item.unit,
              ),
            ],
          ),
        ],
      ],
    ),
  );
}

class CustodyInventoryItemCard extends StatelessWidget {
  const CustodyInventoryItemCard({super.key, required this.balance});

  final RepInventoryBalanceModel balance;

  @override
  Widget build(BuildContext context) => DashboardCard(
    key: ValueKey('custody-item-${balance.itemId}'),
    padding: const EdgeInsets.all(15),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          balance.itemNameSnapshot,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: context.appText,
            fontWeight: FontWeight.w900,
          ),
        ),
        if (balance.modelSnapshot.isNotEmpty) ...[
          const SizedBox(height: 3),
          Text(
            balance.modelSnapshot,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textDirection: TextDirection.ltr,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: context.appMutedText),
          ),
        ],
        const SizedBox(height: 12),
        _QuantityFact(
          key: ValueKey('custody-quantity-${balance.itemId}'),
          label: 'rep_inventory_custody_quantity'.tr,
          value: inventoryQuantity(balance.quantity),
          unit: balance.unitSnapshot,
          prominent: true,
        ),
        const SizedBox(height: 9),
        Text(
          '${'rep_inventory_last_updated'.tr}: '
          '${DateFormat.yMd().add_jm().format(balance.updatedAt)}',
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: context.appMutedText),
        ),
      ],
    ),
  );
}

class StockMovementCard extends StatelessWidget {
  const StockMovementCard({super.key, required this.movement});

  final StockMovementModel movement;

  @override
  Widget build(BuildContext context) {
    final color = movement.isOut ? AppColor.error : AppColor.success;
    final reference = movement.referenceNumber.trim().isNotEmpty
        ? movement.referenceNumber
        : movement.referenceType;
    return DashboardCard(
      key: ValueKey('stock-movement-${movement.id}'),
      padding: const EdgeInsets.all(15),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 38,
                height: 38,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: .1),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(
                  movement.isOut
                      ? Icons.north_east_rounded
                      : Icons.south_west_rounded,
                  color: color,
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      movement.itemName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: context.appText,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    if (movement.itemCode.trim().isNotEmpty)
                      Text(
                        movement.itemCode,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textDirection: TextDirection.ltr,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: context.appMutedText,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 88,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${movement.isOut ? '-' : '+'}'
                      '${inventoryQuantity(movement.quantity)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: color,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      (movement.isOut
                              ? 'inventory_movement_out'
                              : 'inventory_movement_in')
                          .tr,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: color,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 11),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              _MovementTag(label: movement.movementType.tr),
              if (reference.trim().isNotEmpty) _MovementTag(label: reference),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            '${'quantity_before'.tr}: '
            '${inventoryQuantity(movement.quantityBefore)}  →  '
            '${'quantity_after'.tr}: '
            '${inventoryQuantity(movement.quantityAfter)}',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: context.appText,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 5),
          Wrap(
            spacing: 12,
            runSpacing: 4,
            children: [
              Text(
                DateFormat('yyyy-MM-dd HH:mm').format(movement.movementDate),
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: context.appMutedText),
              ),
              if (movement.createdByName.trim().isNotEmpty)
                Text(
                  '${'created_by'.tr}: ${movement.createdByName}',
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: context.appMutedText),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MovementTag extends StatelessWidget {
  const _MovementTag({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: context.appSurfaceMuted,
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: context.appBorder),
    ),
    child: Text(
      label,
      style: Theme.of(
        context,
      ).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w700),
    ),
  );
}

class _QuantityFact extends StatelessWidget {
  const _QuantityFact({
    super.key,
    required this.label,
    required this.value,
    required this.unit,
    this.prominent = false,
  });

  final String label;
  final String value;
  final String unit;
  final bool prominent;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: context.appMutedText,
          fontWeight: FontWeight.w600,
        ),
      ),
      const SizedBox(height: 2),
      Text.rich(
        TextSpan(
          children: [
            TextSpan(text: value),
            if (unit.trim().isNotEmpty)
              TextSpan(
                text: ' ${unit.trim()}',
                style: TextStyle(
                  fontSize: prominent ? 13 : 11,
                  color: context.appMutedText,
                  fontWeight: FontWeight.w700,
                ),
              ),
          ],
        ),
        style:
            (prominent
                    ? Theme.of(context).textTheme.headlineSmall
                    : Theme.of(context).textTheme.titleMedium)
                ?.copyWith(color: context.appText, fontWeight: FontWeight.w900),
      ),
    ],
  );
}
