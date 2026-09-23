import 'package:fatoora/core/constants/color.dart';
import 'package:fatoora/features/admin_dashboard/view/widgets/dashboard_card.dart';
import 'package:fatoora/features/items/data/models/item_model.dart';
import 'package:fatoora/features/items/view/widgets/item_status_badge.dart';
import 'package:fatoora/features/shared/inventory/inventory_presentation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart' hide TextDirection;

class ItemCard extends StatelessWidget {
  const ItemCard({super.key, required this.item, required this.onTap});

  final ItemModel item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => DashboardCard(
    key: ValueKey('item-card-${item.id}'),
    padding: const EdgeInsets.all(14),
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
                  if (item.code.trim().isNotEmpty)
                    Text(
                      item.code,
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
            ItemStatusBadge(active: item.active),
          ],
        ),
        if (item.description.trim().isNotEmpty) ...[
          const SizedBox(height: 7),
          Text(
            item.description,
            key: ValueKey('item-description-${item.id}'),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: context.appMutedText),
          ),
        ],
        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              '${NumberFormat('#,##0.00').format(item.price)} ${'items_jod'.tr}',
              key: ValueKey('item-price-${item.id}'),
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: AppColor.primaryColor,
                fontWeight: FontWeight.w900,
              ),
            ),
            if (item.unit.trim().isNotEmpty)
              Text(
                item.unit,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: context.appMutedText),
              ),
            if (item.trackStock) InventoryStockStatusChip(item: item),
          ],
        ),
        if (!item.trackStock) ...[
          const SizedBox(height: 6),
          Text(
            'track_stock_disabled'.tr,
            key: ValueKey('item-tracking-disabled-${item.id}'),
            maxLines: 2,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: context.appMutedText,
            ),
          ),
        ],
        if (item.trackStock) ...[
          const SizedBox(height: 6),
          Text(
            '${'current_stock'.tr}: ${inventoryQuantity(item.currentStock)} ${item.unit}'
            '  ·  ${'min_stock'.tr}: ${inventoryQuantity(item.minStock)} ${item.unit}',
            key: ValueKey('item-stock-${item.id}'),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: context.appMutedText,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ],
    ),
  );
}
