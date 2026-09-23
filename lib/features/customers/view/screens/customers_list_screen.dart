import 'package:fatoora/core/class/statusrequest.dart';
import 'package:fatoora/core/constants/color.dart';
import 'package:fatoora/core/motion/fatoora_motion_widgets.dart';
import 'package:fatoora/core/widgets/responsive_data_table_card.dart';
import 'package:fatoora/features/admin_dashboard/view/widgets/dashboard_card.dart';
import 'package:fatoora/features/customers/controllers/customers_controller.dart';
import 'package:fatoora/features/customers/data/models/customer_model.dart';
import 'package:fatoora/features/customers/view/widgets/customer_list_components.dart';
import 'package:fatoora/features/shared/business/business_page_widgets.dart';
import 'package:fatoora/features/shared/business/business_shell.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class CustomersListScreen extends StatelessWidget {
  const CustomersListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return GetBuilder<CustomersController>(
      builder: (controller) => BusinessShell(
        title: 'customers'.tr,
        child: RefreshIndicator(
          onRefresh: controller.refreshCustomers,
          color: AppColor.primaryColor,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final desktop = constraints.maxWidth >= 900;
              final padding = constraints.maxWidth < 600 ? 14.0 : 24.0;
              return SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.fromLTRB(padding, padding, padding, 96),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1200),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _CustomersHeader(controller: controller),
                        const SizedBox(height: 14),
                        _CustomerSearch(controller: controller),
                        const SizedBox(height: 14),
                        _CustomerResults(
                          controller: controller,
                          desktop: desktop,
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _CustomersHeader extends StatelessWidget {
  const _CustomersHeader({required this.controller});

  final CustomersController controller;

  @override
  Widget build(BuildContext context) => BusinessPageHeader(
    title: 'customers'.tr,
    trailing: controller.canCreateCustomer
        ? BusinessPrimaryActionButton(
            onPressed: controller.openCreateCustomer,
            icon: Icons.person_add_alt_1_outlined,
            label: 'customers_add'.tr,
          )
        : null,
  );
}

class _CustomerSearch extends StatelessWidget {
  const _CustomerSearch({required this.controller});

  final CustomersController controller;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      TextField(
        key: const ValueKey('customer-search-field'),
        controller: controller.searchController,
        onChanged: controller.onSearchChanged,
        onSubmitted: (_) => controller.submitSearch(),
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: 'customers_search_hint'.tr,
          prefixIcon: const Icon(Icons.search_rounded),
          suffixIcon: controller.hasSearch
              ? IconButton(
                  tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                  onPressed: controller.clearSearch,
                  icon: const Icon(Icons.close_rounded),
                )
              : null,
          filled: true,
          fillColor: context.appSurface,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: context.appBorder),
          ),
        ),
      ),
      if (controller.searchIsTooShort) ...[
        const SizedBox(height: 6),
        Text(
          'customers_search_minimum'.tr,
          key: const ValueKey('customer-search-minimum-hint'),
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: context.appMutedText),
        ),
      ],
    ],
  );
}

class _CustomerResults extends StatelessWidget {
  const _CustomerResults({required this.controller, required this.desktop});

  final CustomersController controller;
  final bool desktop;

  @override
  Widget build(BuildContext context) {
    final loading = controller.statusRequest == StatusRequest.loading;
    final failed =
        controller.statusRequest != StatusRequest.success &&
        controller.statusRequest != StatusRequest.loading;
    if (loading && controller.customers.isEmpty) {
      return const Padding(
        key: ValueKey('customer-results-loading'),
        padding: EdgeInsets.symmetric(vertical: 44),
        child: Center(child: FatooraProgressIndicator()),
      );
    }
    if (failed && controller.customers.isEmpty) {
      return BusinessEmptyState(
        key: const ValueKey('customer-results-error'),
        icon: Icons.sync_problem_outlined,
        title: controller.loadErrorMessageKey.tr,
        action: FilledButton.icon(
          key: const ValueKey('customer-retry-button'),
          onPressed: controller.loadCustomers,
          icon: const Icon(Icons.refresh_rounded),
          label: Text('items_retry'.tr),
        ),
      );
    }
    if (controller.customers.isEmpty) {
      return BusinessEmptyState(
        key: ValueKey(
          controller.hasAppliedSearch
              ? 'customer-search-empty'
              : 'customer-list-empty',
        ),
        icon: Icons.people_alt_outlined,
        title: controller.hasAppliedSearch
            ? 'customers_no_search_results'.tr
            : 'customers_empty'.tr,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (loading)
          const Padding(
            padding: EdgeInsets.only(bottom: 10),
            child: LinearProgressIndicator(
              key: ValueKey('customer-results-refreshing'),
              minHeight: 3,
            ),
          ),
        if (failed) ...[
          _InlineError(controller: controller),
          const SizedBox(height: 10),
        ],
        if (desktop)
          _CustomerTable(controller: controller)
        else
          _CustomerCards(controller: controller),
        if (controller.hasMore) ...[
          const SizedBox(height: 16),
          BusinessLoadMoreButton(
            key: const ValueKey('customer-load-more'),
            loading: controller.isLoadingMore,
            onPressed: controller.loadMoreCustomers,
          ),
        ],
      ],
    );
  }
}

class _InlineError extends StatelessWidget {
  const _InlineError({required this.controller});

  final CustomersController controller;

  @override
  Widget build(BuildContext context) => DashboardCard(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    child: Row(
      children: [
        const Icon(Icons.sync_problem_outlined, color: AppColor.error),
        const SizedBox(width: 10),
        Expanded(child: Text(controller.loadErrorMessageKey.tr)),
        TextButton(
          onPressed: controller.loadCustomers,
          child: Text('items_retry'.tr),
        ),
      ],
    ),
  );
}

class _CustomerCards extends StatelessWidget {
  const _CustomerCards({required this.controller});

  final CustomersController controller;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final textScale = MediaQuery.textScalerOf(context).scale(1);
      final columns = constraints.maxWidth >= 650 && textScale <= 1.3 ? 2 : 1;
      const spacing = 12.0;
      final width = (constraints.maxWidth - spacing * (columns - 1)) / columns;
      return Wrap(
        spacing: spacing,
        runSpacing: spacing,
        children: controller.customers
            .map(
              (customer) => SizedBox(
                width: width,
                child: CustomerCompactCard(
                  customer: customer,
                  showCreator: controller.isAdmin,
                  onTap: () => controller.openCustomerDetails(customer),
                ),
              ),
            )
            .toList(),
      );
    },
  );
}

class _CustomerTable extends StatelessWidget {
  const _CustomerTable({required this.controller});

  final CustomersController controller;

  @override
  Widget build(BuildContext context) {
    final showCreator = controller.isAdmin;
    return ResponsiveDataTableCard(
      minWidth: showCreator ? 1080 : 900,
      child: DataTable(
        columnSpacing: 14,
        horizontalMargin: 14,
        showCheckboxColumn: false,
        columns: [
          _column('customer_name', width: 210),
          _column('Phone', width: 128),
          _column('address', width: 155),
          _column('customers_balance', width: 190),
          _column('invoice_status', width: 86),
          if (showCreator) _column('created_by', width: 130),
          _column('actions', width: 52),
        ],
        rows: controller.customers
            .map(
              (customer) => DataRow(
                onSelectChanged: (_) =>
                    controller.openCustomerDetails(customer),
                cells: [
                  DataCell(BoundedTableText(customer.name, width: 210)),
                  DataCell(
                    BoundedTableText(
                      customer.phone,
                      width: 128,
                      forceLtr: true,
                    ),
                  ),
                  DataCell(BoundedTableText(_location(customer), width: 155)),
                  DataCell(
                    BoundedTableWidget(
                      width: 190,
                      child: CustomerBalanceBadge(
                        balance: customer.currentBalance,
                        compact: true,
                      ),
                    ),
                  ),
                  DataCell(
                    BoundedTableWidget(
                      width: 86,
                      child: CustomerStatusPill(active: customer.active),
                    ),
                  ),
                  if (showCreator)
                    DataCell(
                      BoundedTableText(customer.createdByName, width: 130),
                    ),
                  DataCell(
                    SizedBox(
                      width: 52,
                      child: IconButton(
                        tooltip: 'customers_details'.tr,
                        onPressed: () =>
                            controller.openCustomerDetails(customer),
                        icon: Icon(
                          Directionality.of(context) == TextDirection.rtl
                              ? Icons.chevron_left_rounded
                              : Icons.chevron_right_rounded,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            )
            .toList(),
      ),
    );
  }

  String _location(CustomerModel customer) => [
    customer.area.trim(),
    customer.city.trim(),
  ].where((value) => value.isNotEmpty).join(' · ');

  DataColumn _column(
    String labelKey, {
    required double width,
    bool numeric = false,
  }) => DataColumn(
    numeric: numeric,
    label: SizedBox(
      width: width,
      child: Text(labelKey.tr, maxLines: 2, overflow: TextOverflow.ellipsis),
    ),
  );
}
