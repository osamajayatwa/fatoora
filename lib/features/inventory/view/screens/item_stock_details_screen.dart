import 'package:fatoora/core/class/handilingdataview.dart';
import 'package:fatoora/core/constants/color.dart';
import 'package:fatoora/features/admin_dashboard/view/widgets/admin_dashboard_shell.dart';
import 'package:fatoora/features/inventory/controllers/item_stock_details_controller.dart';
import 'package:fatoora/features/inventory/data/models/stock_movement_model.dart';
import 'package:fatoora/features/items/data/models/item_model.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart' hide TextDirection;

class ItemStockDetailsScreen extends StatelessWidget {
  const ItemStockDetailsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return GetBuilder<ItemStockDetailsController>(
      builder: (controller) => AdminDashboardShell(
        child: HandilingDataView(
          statusrequest: controller.statusRequest,
          errorMessage: controller.loadErrorMessageKey.tr,
          retryLabel: 'items_retry'.tr,
          onRetry: controller.loadDetails,
          widget: controller.item == null
              ? const SizedBox.shrink()
              : _ItemStockContent(
                  item: controller.item!,
                  movements: controller.movements,
                ),
        ),
      ),
    );
  }
}

class _ItemStockContent extends StatelessWidget {
  const _ItemStockContent({required this.item, required this.movements});

  final ItemModel item;
  final List<StockMovementModel> movements;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: EdgeInsets.all(MediaQuery.sizeOf(context).width < 600 ? 14 : 24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1050),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Header(item: item),
              const SizedBox(height: 16),
              _StockSummary(item: item),
              const SizedBox(height: 18),
              Text(
                'stock_movements'.tr,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: AppColor.secondaryColor,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 12),
              if (movements.isEmpty)
                Card(
                  elevation: 0,
                  color: AppColor.surface,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                    side: const BorderSide(color: Color(0xFFE4E8EF)),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Text('inventory_no_movements'.tr),
                  ),
                )
              else
                _MovementList(movements: movements),
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.item});

  final ItemModel item;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton(
          onPressed: Get.back,
          icon: Icon(
            Directionality.of(context) == TextDirection.rtl
                ? Icons.arrow_forward_rounded
                : Icons.arrow_back_rounded,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.name,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: AppColor.secondaryColor,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                item.code,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: AppColor.grey),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _StockSummary extends StatelessWidget {
  const _StockSummary({required this.item});

  final ItemModel item;

  @override
  Widget build(BuildContext context) {
    final number = NumberFormat('#,##0.###');
    final money = NumberFormat.currency(symbol: '', decimalDigits: 3);
    final values = [
      (
        'current_stock',
        item.trackStock
            ? number.format(item.currentStock)
            : 'track_stock_disabled'.tr,
        Icons.inventory_2_outlined,
        item.isOutOfStock
            ? AppColor.error
            : item.isLowStock
            ? AppColor.accentYellow
            : AppColor.success,
      ),
      (
        'opening_stock',
        number.format(item.openingStock),
        Icons.input_rounded,
        null,
      ),
      ('min_stock', number.format(item.minStock), Icons.warning_rounded, null),
      (
        'cost_price',
        money.format(item.costPrice),
        Icons.price_change_outlined,
        null,
      ),
      ('warehouse', item.warehouseId, Icons.warehouse_outlined, null),
    ];

    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: values
          .map(
            (value) => SizedBox(
              width: MediaQuery.sizeOf(context).width < 700
                  ? double.infinity
                  : 190,
              child: Card(
                elevation: 0,
                color: AppColor.surface,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                  side: const BorderSide(color: Color(0xFFE4E8EF)),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Icon(value.$3, color: value.$4 ?? AppColor.primaryColor),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              value.$1.tr,
                              style: Theme.of(context).textTheme.labelMedium
                                  ?.copyWith(color: AppColor.grey),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              value.$2,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(
                                    color: value.$4 ?? AppColor.secondaryColor,
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

class _MovementList extends StatelessWidget {
  const _MovementList({required this.movements});

  final List<StockMovementModel> movements;

  @override
  Widget build(BuildContext context) {
    final date = DateFormat('yyyy-MM-dd HH:mm');
    final number = NumberFormat('#,##0.###');
    return Column(
      children: movements
          .map(
            (movement) => Card(
              elevation: 0,
              color: AppColor.surface,
              margin: const EdgeInsets.only(bottom: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
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
                title: Text(movement.movementType.tr),
                subtitle: Text(
                  [
                    movement.referenceNumber,
                    date.format(movement.movementDate),
                    movement.createdByName,
                  ].where((value) => value.isNotEmpty).join(' / '),
                ),
                trailing: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${movement.isOut ? '-' : '+'}${number.format(movement.quantity)}',
                      style: TextStyle(
                        color: movement.isOut
                            ? AppColor.error
                            : AppColor.success,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      number.format(movement.quantityAfter),
                      style: Theme.of(
                        context,
                      ).textTheme.labelSmall?.copyWith(color: AppColor.grey),
                    ),
                  ],
                ),
              ),
            ),
          )
          .toList(),
    );
  }
}
