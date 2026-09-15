import 'package:fatoora/core/class/handilingdataview.dart';
import 'package:fatoora/core/constants/color.dart';
import 'package:fatoora/features/items/controller/items_controller.dart';
import 'package:fatoora/features/items/view/widgets/item_card.dart';
import 'package:fatoora/features/items/view/widgets/item_empty_state.dart';
import 'package:fatoora/features/items/view/widgets/item_filter_tabs.dart';
import 'package:fatoora/features/items/view/widgets/item_search_bar.dart';
import 'package:fatoora/features/admin_dashboard/view/widgets/admin_dashboard_shell.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class ItemsScreen extends StatelessWidget {
  const ItemsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return GetBuilder<ItemsController>(
      builder: (controller) => PopScope(
        canPop: controller.allowPop,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) controller.goBack();
        },
        child: AdminDashboardShell(
          child: Stack(
            children: [
              HandilingDataView(
                statusrequest: controller.statusRequest,
                errorMessage: controller.loadErrorMessageKey.tr,
                retryLabel: 'items_retry'.tr,
                onRetry: controller.loadItems,
                widget: RefreshIndicator(
                  onRefresh: controller.loadItems,
                  color: AppColor.primaryColor,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final padding = constraints.maxWidth < 600 ? 14.0 : 24.0;
                      return CustomScrollView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        slivers: [
                          SliverPadding(
                            padding: EdgeInsets.fromLTRB(
                              padding,
                              padding,
                              padding,
                              8,
                            ),
                            sliver: SliverToBoxAdapter(
                              child: Center(
                                child: ConstrainedBox(
                                  constraints: const BoxConstraints(
                                    maxWidth: 1240,
                                  ),
                                  child: _ItemsHeader(controller: controller),
                                ),
                              ),
                            ),
                          ),
                          if (controller.visibleItems.isEmpty)
                            const SliverFillRemaining(
                              hasScrollBody: false,
                              child: ItemEmptyState(),
                            )
                          else
                            SliverPadding(
                              padding: EdgeInsets.fromLTRB(
                                padding,
                                10,
                                padding,
                                96,
                              ),
                              sliver: SliverLayoutBuilder(
                                builder: (context, sliverConstraints) {
                                  final width =
                                      sliverConstraints.crossAxisExtent;
                                  final textScale = MediaQuery.textScalerOf(
                                    context,
                                  ).scale(1);
                                  final columns = width >= 1050
                                      ? 3
                                      : width >= 650
                                      ? 2
                                      : 1;
                                  return SliverGrid(
                                    delegate: SliverChildBuilderDelegate(
                                      (context, index) {
                                        final item =
                                            controller.visibleItems[index];
                                        return ItemCard(
                                          item: item,
                                          onTap: () =>
                                              controller.openItemDetails(item),
                                        );
                                      },
                                      childCount:
                                          controller.visibleItems.length,
                                    ),
                                    gridDelegate:
                                        SliverGridDelegateWithFixedCrossAxisCount(
                                          crossAxisCount: columns,
                                          crossAxisSpacing: 16,
                                          mainAxisSpacing: 16,
                                          mainAxisExtent:
                                              238 +
                                              ((textScale - 1).clamp(0, 1) *
                                                  88),
                                        ),
                                  );
                                },
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                ),
              ),
              PositionedDirectional(
                end: 24,
                bottom: 22,
                child: FloatingActionButton.extended(
                  heroTag: 'add-item-fab',
                  onPressed: controller.openAddItem,
                  backgroundColor: AppColor.primaryColor,
                  foregroundColor: Colors.white,
                  icon: const Icon(Icons.add_rounded),
                  label: Text('items_add'.tr),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ItemsHeader extends StatelessWidget {
  const _ItemsHeader({required this.controller});

  final ItemsController controller;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            IconButton(
              onPressed: controller.goBack,
              icon: Icon(
                Directionality.of(context) == TextDirection.rtl
                    ? Icons.arrow_forward_rounded
                    : Icons.arrow_back_rounded,
              ),
              color: AppColor.secondaryColor,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'items_title'.tr,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: AppColor.secondaryColor,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        LayoutBuilder(
          builder: (context, constraints) {
            final desktop = constraints.maxWidth >= 760;
            final search = ItemSearchBar(
              controller: controller.searchController,
              onChanged: controller.onSearchChanged,
            );
            final sort = _SortDropdown(
              value: controller.sort,
              onChanged: controller.setSort,
            );
            if (!desktop) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  search,
                  const SizedBox(height: 12),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: ItemFilterTabs(
                      value: controller.filter,
                      onChanged: controller.setFilter,
                    ),
                  ),
                  const SizedBox(height: 12),
                  sort,
                ],
              );
            }
            return Column(
              children: [
                Row(
                  children: [
                    Expanded(child: search),
                    const SizedBox(width: 14),
                    SizedBox(width: 230, child: sort),
                  ],
                ),
                const SizedBox(height: 15),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: ItemFilterTabs(
                    value: controller.filter,
                    onChanged: controller.setFilter,
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _SortDropdown extends StatelessWidget {
  const _SortDropdown({required this.value, required this.onChanged});

  final ItemSort value;
  final ValueChanged<ItemSort> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<ItemSort>(
      value: value,
      isExpanded: true,
      onChanged: (next) {
        if (next != null) onChanged(next);
      },
      decoration: InputDecoration(
        labelText: 'items_sort'.tr,
        prefixIcon: const Icon(Icons.sort_rounded),
        filled: true,
        fillColor: AppColor.surface,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFE1E5ED)),
        ),
      ),
      items: ItemSort.values
          .map(
            (sort) => DropdownMenuItem(
              value: sort,
              child: Text(switch (sort) {
                ItemSort.newest => 'items_newest'.tr,
                ItemSort.oldest => 'items_oldest'.tr,
                ItemSort.priceHigh => 'items_price_high'.tr,
                ItemSort.priceLow => 'items_price_low'.tr,
              }),
            ),
          )
          .toList(),
    );
  }
}
