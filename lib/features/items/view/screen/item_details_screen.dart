import 'package:fatoora/core/class/handilingdataview.dart';
import 'package:fatoora/core/constants/color.dart';
import 'package:fatoora/features/items/data/models/item_model.dart';
import 'package:fatoora/features/items/controller/item_details_controller.dart';
import 'package:fatoora/features/items/view/widgets/item_action_button.dart';
import 'package:fatoora/features/items/view/widgets/item_details_info_tile.dart';
import 'package:fatoora/features/items/view/widgets/item_status_badge.dart';
import 'package:fatoora/features/admin_dashboard/view/widgets/admin_dashboard_shell.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart' hide TextDirection;

class ItemDetailsScreen extends StatelessWidget {
  const ItemDetailsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return GetBuilder<ItemDetailsController>(
      builder: (controller) => PopScope(
        canPop: controller.allowPop,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) controller.goBack();
        },
        child: AdminDashboardShell(
          child: HandilingDataView(
            statusrequest: controller.statusRequest,
            errorMessage: controller.loadErrorMessageKey.tr,
            retryLabel: 'items_retry'.tr,
            onRetry: controller.item == null ? null : controller.loadItem,
            widget: controller.item == null
                ? const SizedBox.shrink()
                : _DetailsContent(
                    item: controller.item!,
                    controller: controller,
                  ),
          ),
        ),
      ),
    );
  }
}

class _DetailsContent extends StatelessWidget {
  const _DetailsContent({required this.item, required this.controller});

  final ItemModel item;
  final ItemDetailsController controller;

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('yyyy-MM-dd - HH:mm');
    return SingleChildScrollView(
      padding: EdgeInsets.all(MediaQuery.sizeOf(context).width < 600 ? 14 : 24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1050),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  IconButton(
                    onPressed: controller.isActionLoading
                        ? null
                        : controller.goBack,
                    icon: Icon(
                      Directionality.of(context) == TextDirection.rtl
                          ? Icons.arrow_forward_rounded
                          : Icons.arrow_back_rounded,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'items_details'.tr,
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(
                            color: AppColor.secondaryColor,
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                  ),
                  ItemStatusBadge(active: item.active),
                ],
              ),
              const SizedBox(height: 20),
              Card(
                margin: EdgeInsets.zero,
                elevation: 0,
                color: AppColor.surface,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                  side: const BorderSide(color: Color(0xFFE4E8EF)),
                ),
                child: Padding(
                  padding: EdgeInsets.all(
                    MediaQuery.sizeOf(context).width < 600 ? 16 : 26,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 58,
                            height: 58,
                            decoration: BoxDecoration(
                              color: AppColor.primaryLight.withValues(
                                alpha: 0.55,
                              ),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: const Icon(
                              Icons.inventory_2_outlined,
                              color: AppColor.primaryColor,
                              size: 29,
                            ),
                          ),
                          const SizedBox(width: 15),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item.name,
                                  style: Theme.of(context).textTheme.titleLarge
                                      ?.copyWith(
                                        color: AppColor.secondaryColor,
                                        fontWeight: FontWeight.w800,
                                      ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  item.code,
                                  style: Theme.of(context).textTheme.bodyMedium
                                      ?.copyWith(color: AppColor.grey),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 25),
                      Text(
                        'items_information'.tr,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              color: AppColor.secondaryColor,
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                      const SizedBox(height: 14),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final columns = constraints.maxWidth >= 700;
                          final width = columns
                              ? (constraints.maxWidth - 14) / 2
                              : constraints.maxWidth;
                          return Wrap(
                            spacing: 14,
                            runSpacing: 14,
                            children: [
                              SizedBox(
                                width: constraints.maxWidth,
                                child: ItemDetailsInfoTile(
                                  label: 'items_description'.tr,
                                  value: item.description,
                                  icon: Icons.notes_rounded,
                                ),
                              ),
                              SizedBox(
                                width: width,
                                child: ItemDetailsInfoTile(
                                  label: 'items_unit'.tr,
                                  value: item.unit,
                                  icon: Icons.straighten_rounded,
                                ),
                              ),
                              SizedBox(
                                width: width,
                                child: ItemDetailsInfoTile(
                                  label: 'items_price'.tr,
                                  value:
                                      '${NumberFormat('#,##0.00').format(item.price)} ${'items_jod'.tr}',
                                  icon: Icons.payments_outlined,
                                ),
                              ),
                              SizedBox(
                                width: width,
                                child: ItemDetailsInfoTile(
                                  label: 'items_tax_rate'.tr,
                                  value: '${item.taxRate.toStringAsFixed(2)}%',
                                  icon: Icons.percent_rounded,
                                  valueColor: AppColor.accentYellow,
                                ),
                              ),
                              SizedBox(
                                width: width,
                                child: ItemDetailsInfoTile(
                                  label: 'current_stock'.tr,
                                  value: item.trackStock
                                      ? NumberFormat(
                                          '#,##0.###',
                                        ).format(item.currentStock)
                                      : 'track_stock_disabled'.tr,
                                  icon: Icons.inventory_2_outlined,
                                  valueColor: item.isOutOfStock
                                      ? AppColor.error
                                      : item.isLowStock
                                      ? AppColor.accentYellow
                                      : AppColor.success,
                                ),
                              ),
                              SizedBox(
                                width: width,
                                child: ItemDetailsInfoTile(
                                  label: 'min_stock'.tr,
                                  value: NumberFormat(
                                    '#,##0.###',
                                  ).format(item.minStock),
                                  icon: Icons.warning_amber_rounded,
                                ),
                              ),
                              SizedBox(
                                width: width,
                                child: ItemDetailsInfoTile(
                                  label: 'opening_stock'.tr,
                                  value: NumberFormat(
                                    '#,##0.###',
                                  ).format(item.openingStock),
                                  icon: Icons.input_rounded,
                                ),
                              ),
                              SizedBox(
                                width: width,
                                child: ItemDetailsInfoTile(
                                  label: 'cost_price'.tr,
                                  value:
                                      '${NumberFormat('#,##0.00').format(item.costPrice)} ${'items_jod'.tr}',
                                  icon: Icons.price_change_outlined,
                                ),
                              ),
                              SizedBox(
                                width: width,
                                child: ItemDetailsInfoTile(
                                  label: 'barcode'.tr,
                                  value: item.barcode ?? 'items_optional'.tr,
                                  icon: Icons.qr_code_scanner_rounded,
                                ),
                              ),
                              SizedBox(
                                width: width,
                                child: ItemDetailsInfoTile(
                                  label: 'category'.tr,
                                  value: item.category ?? 'items_optional'.tr,
                                  icon: Icons.category_outlined,
                                ),
                              ),
                              SizedBox(
                                width: width,
                                child: ItemDetailsInfoTile(
                                  label: 'warehouse'.tr,
                                  value: item.warehouseId,
                                  icon: Icons.warehouse_outlined,
                                ),
                              ),
                              SizedBox(
                                width: width,
                                child: ItemDetailsInfoTile(
                                  label: 'items_status'.tr,
                                  value: item.active
                                      ? 'items_active'.tr
                                      : 'items_inactive'.tr,
                                  icon: Icons.toggle_on_outlined,
                                  valueColor: item.active
                                      ? AppColor.success
                                      : AppColor.error,
                                ),
                              ),
                              SizedBox(
                                width: width,
                                child: ItemDetailsInfoTile(
                                  label: 'items_created_at'.tr,
                                  value: dateFormat.format(item.createdAt),
                                  icon: Icons.calendar_today_outlined,
                                ),
                              ),
                              SizedBox(
                                width: width,
                                child: ItemDetailsInfoTile(
                                  label: 'items_updated_at'.tr,
                                  value: dateFormat.format(item.updatedAt),
                                  icon: Icons.update_rounded,
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 26),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final narrow = constraints.maxWidth < 650;
                          final buttons = [
                            ItemActionButton(
                              label: 'stock_movements'.tr,
                              icon: Icons.history_rounded,
                              onPressed: controller.openStockDetails,
                              outlined: true,
                            ),
                            ItemActionButton(
                              label: 'items_edit'.tr,
                              icon: Icons.edit_outlined,
                              onPressed: controller.editItem,
                              outlined: true,
                            ),
                            ItemActionButton(
                              label: item.active
                                  ? 'items_deactivate'.tr
                                  : 'items_activate'.tr,
                              icon: item.active
                                  ? Icons.pause_circle_outline_rounded
                                  : Icons.play_circle_outline_rounded,
                              onPressed: controller.toggleActive,
                              color: item.active
                                  ? AppColor.accentYellow
                                  : AppColor.success,
                              outlined: true,
                              loading: controller.isActionLoading,
                            ),
                            ItemActionButton(
                              label: 'items_delete'.tr,
                              icon: Icons.delete_outline_rounded,
                              onPressed: controller.deleteItem,
                              color: AppColor.error,
                              loading: controller.isActionLoading,
                            ),
                          ];
                          if (narrow) {
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                for (var i = 0; i < buttons.length; i++) ...[
                                  buttons[i],
                                  if (i < buttons.length - 1)
                                    const SizedBox(height: 10),
                                ],
                              ],
                            );
                          }
                          return Row(
                            children: [
                              for (var i = 0; i < buttons.length; i++) ...[
                                Expanded(child: buttons[i]),
                                if (i < buttons.length - 1)
                                  const SizedBox(width: 12),
                              ],
                            ],
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
