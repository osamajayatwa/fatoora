import 'package:fatoora/core/class/statusrequest.dart';
import 'package:fatoora/core/constants/color.dart';
import 'package:fatoora/core/motion/fatoora_motion_widgets.dart';
import 'package:fatoora/core/motion/fatoora_overlays.dart';
import 'package:fatoora/core/widgets/responsive_data_table_card.dart';
import 'package:fatoora/features/admin_dashboard/view/widgets/admin_dashboard_shell.dart';
import 'package:fatoora/features/items/controller/items_controller.dart';
import 'package:fatoora/features/items/data/models/item_model.dart';
import 'package:fatoora/features/items/view/widgets/item_card.dart';
import 'package:fatoora/features/items/view/widgets/item_filter_tabs.dart';
import 'package:fatoora/features/items/view/widgets/item_search_bar.dart';
import 'package:fatoora/features/items/view/widgets/item_status_badge.dart';
import 'package:fatoora/features/shared/business/business_page_widgets.dart';
import 'package:fatoora/features/shared/inventory/inventory_presentation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart' hide TextDirection;

class ItemsScreen extends StatelessWidget {
  const ItemsScreen({super.key});

  @override
  Widget build(BuildContext context) => GetBuilder<ItemsController>(
    builder: (controller) => PopScope(
      canPop: controller.allowPop,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) controller.goBack();
      },
      child: AdminDashboardShell(
        child: RefreshIndicator(
          onRefresh: controller.loadItems,
          color: AppColor.primaryColor,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              final desktop = width >= 900;
              final padding = width < 600 ? 14.0 : 24.0;
              return CustomScrollView(
                controller: controller.scrollController,
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(padding, padding, padding, 96),
                    sliver: SliverToBoxAdapter(
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 1240),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _ItemsHeader(controller: controller),
                              const SizedBox(height: 14),
                              _ItemsControls(controller: controller),
                              const SizedBox(height: 14),
                              _ItemsResults(
                                controller: controller,
                                desktop: desktop,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    ),
  );
}

class _ItemsHeader extends StatelessWidget {
  const _ItemsHeader({required this.controller});

  final ItemsController controller;

  @override
  Widget build(BuildContext context) {
    final compact =
        MediaQuery.sizeOf(context).width < 600 ||
        MediaQuery.textScalerOf(context).scale(1) > 1.3;
    final title = Row(
      children: [
        IconButton(
          onPressed: controller.goBack,
          tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          icon: Icon(
            Directionality.of(context) == TextDirection.rtl
                ? Icons.arrow_forward_rounded
                : Icons.arrow_back_rounded,
          ),
        ),
        Expanded(
          child: Text(
            'items_title'.tr,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              color: context.appText,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ],
    );
    final action = BusinessPrimaryActionButton(
      label: 'items_add'.tr,
      icon: Icons.add_rounded,
      onPressed: controller.openAddItem,
    );
    if (compact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [title, const SizedBox(height: 10), action],
      );
    }
    return Row(
      children: [
        Expanded(child: title),
        action,
      ],
    );
  }
}

class _ItemsControls extends StatelessWidget {
  const _ItemsControls({required this.controller});

  final ItemsController controller;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      ItemSearchBar(
        controller: controller.searchController,
        onChanged: controller.onSearchChanged,
        onSubmitted: (_) => controller.submitSearch(),
      ),
      if (controller.searchIsTooShort) ...[
        const SizedBox(height: 5),
        Text(
          'items_search_minimum'.tr,
          key: const ValueKey('items-search-minimum'),
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
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: ItemFilterTabs(
              value: controller.filter,
              onChanged: controller.setFilter,
            ),
          ),
          OutlinedButton.icon(
            key: const ValueKey('items-sort-button'),
            onPressed: () => _showSort(context),
            icon: const Icon(Icons.sort_rounded),
            label: Text('${'items_sort'.tr}: ${_sortLabel(controller.sort)}'),
          ),
        ],
      ),
    ],
  );

  Future<void> _showSort(BuildContext context) async {
    final selected = await showFatooraModalBottomSheet<ItemSort>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'items_sort'.tr,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            for (final sort in ItemSort.values)
              ListTile(
                key: ValueKey('items-sort-${sort.name}'),
                title: Text(_sortLabel(sort)),
                trailing: sort == controller.sort
                    ? const Icon(
                        Icons.check_rounded,
                        color: AppColor.primaryColor,
                      )
                    : null,
                onTap: () => Navigator.of(sheetContext).pop(sort),
              ),
          ],
        ),
      ),
    );
    if (selected != null) controller.setSort(selected);
  }

  String _sortLabel(ItemSort sort) => switch (sort) {
    ItemSort.newest => 'items_newest'.tr,
    ItemSort.oldest => 'items_oldest'.tr,
    ItemSort.priceHigh => 'items_price_high'.tr,
    ItemSort.priceLow => 'items_price_low'.tr,
  };
}

class _ItemsResults extends StatelessWidget {
  const _ItemsResults({required this.controller, required this.desktop});

  final ItemsController controller;
  final bool desktop;

  @override
  Widget build(BuildContext context) {
    final loading = controller.statusRequest == StatusRequest.loading;
    final failed =
        !loading && controller.statusRequest != StatusRequest.success;
    if (loading && controller.items.isEmpty) {
      return const Padding(
        key: ValueKey('items-results-loading'),
        padding: EdgeInsets.symmetric(vertical: 48),
        child: Center(child: FatooraProgressIndicator()),
      );
    }
    if (failed && controller.items.isEmpty) {
      return BusinessEmptyState(
        key: const ValueKey('items-results-error'),
        icon: Icons.sync_problem_outlined,
        title: controller.loadErrorMessageKey.tr,
        action: FilledButton.icon(
          key: const ValueKey('items-retry'),
          onPressed: controller.loadItems,
          icon: const Icon(Icons.refresh_rounded),
          label: Text('items_retry'.tr),
        ),
      );
    }
    if (controller.items.isEmpty) {
      return BusinessEmptyState(
        key: ValueKey(
          controller.hasAppliedSearch || controller.filter != ItemFilter.all
              ? 'items-filtered-empty'
              : 'items-empty',
        ),
        icon: Icons.inventory_2_outlined,
        title:
            (controller.hasAppliedSearch || controller.filter != ItemFilter.all
                    ? 'items_no_results'
                    : 'items_empty')
                .tr,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (loading)
          const Padding(
            padding: EdgeInsets.only(bottom: 10),
            child: LinearProgressIndicator(key: ValueKey('items-refreshing')),
          ),
        if (failed) ...[
          Text(controller.loadErrorMessageKey.tr),
          TextButton(
            onPressed: controller.loadItems,
            child: Text('items_retry'.tr),
          ),
        ],
        if (desktop)
          _ItemsTable(controller: controller)
        else
          _ItemsCards(controller: controller),
        if (controller.loadMoreErrorMessageKey != null) ...[
          const SizedBox(height: 10),
          Text(controller.loadMoreErrorMessageKey!.tr),
        ],
        if (controller.hasMore) ...[
          const SizedBox(height: 14),
          BusinessLoadMoreButton(
            key: const ValueKey('items-load-more'),
            loading: controller.isLoadingMore,
            onPressed: controller.loadMoreItems,
          ),
        ],
      ],
    );
  }
}

class _ItemsCards extends StatelessWidget {
  const _ItemsCards({required this.controller});

  final ItemsController controller;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final columns =
          constraints.maxWidth >= 650 &&
              MediaQuery.textScalerOf(context).scale(1) <= 1.3
          ? 2
          : 1;
      const gap = 12.0;
      final cardWidth = (constraints.maxWidth - gap * (columns - 1)) / columns;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [
          for (final item in controller.visibleItems)
            SizedBox(
              width: cardWidth,
              child: ItemCard(
                item: item,
                onTap: () => controller.openItemDetails(item),
              ),
            ),
        ],
      );
    },
  );
}

class _ItemsTable extends StatelessWidget {
  const _ItemsTable({required this.controller});

  final ItemsController controller;

  @override
  Widget build(BuildContext context) => ResponsiveDataTableCard(
    minWidth: 1080,
    child: DataTable(
      showCheckboxColumn: false,
      horizontalMargin: 14,
      columnSpacing: 12,
      columns: [
        _column('items_name', 170),
        _column('items_code', 110),
        _column('items_description', 220),
        _column('items_price', 95),
        _column('items_unit', 65),
        _column('items_status', 90),
        _column('current_stock', 165),
        _column('actions', 52),
      ],
      rows: [
        for (final item in controller.visibleItems)
          DataRow(
            onSelectChanged: (_) => controller.openItemDetails(item),
            cells: [
              DataCell(BoundedTableText(item.name, width: 170)),
              DataCell(BoundedTableText(item.code, width: 110, forceLtr: true)),
              DataCell(
                BoundedTableText(item.description, width: 220, maxLines: 2),
              ),
              DataCell(
                BoundedTableText(
                  NumberFormat('#,##0.00').format(item.price),
                  width: 95,
                ),
              ),
              DataCell(BoundedTableText(item.unit, width: 65)),
              DataCell(
                BoundedTableWidget(
                  width: 90,
                  child: ItemStatusBadge(active: item.active),
                ),
              ),
              DataCell(
                BoundedTableText(
                  item.trackStock
                      ? '${inventoryQuantity(item.currentStock)} ${item.unit} · ${_stockLabel(item)}'
                      : 'track_stock_disabled'.tr,
                  width: 165,
                ),
              ),
              DataCell(
                IconButton(
                  tooltip: 'items_details'.tr,
                  onPressed: () => controller.openItemDetails(item),
                  icon: Icon(
                    Directionality.of(context) == TextDirection.rtl
                        ? Icons.chevron_left_rounded
                        : Icons.chevron_right_rounded,
                  ),
                ),
              ),
            ],
          ),
      ],
    ),
  );

  DataColumn _column(String key, double width) => DataColumn(
    label: SizedBox(
      width: width,
      child: Text(key.tr, maxLines: 2, overflow: TextOverflow.ellipsis),
    ),
  );

  String _stockLabel(ItemModel item) => item.isOutOfStock
      ? 'out_of_stock'.tr
      : item.isLowStock
      ? 'low_stock'.tr
      : 'in_stock'.tr;
}
