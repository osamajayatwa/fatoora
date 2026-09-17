import 'package:fatoora/core/class/handilingdataview.dart';
import 'package:fatoora/core/motion/fatoora_motion_widgets.dart';
import 'package:fatoora/core/constants/color.dart';
import 'package:fatoora/core/widgets/responsive_data_table_card.dart';
import 'package:fatoora/features/admin_dashboard/view/widgets/dashboard_card.dart';
import 'package:fatoora/features/customers/data/models/customer_model.dart';
import 'package:fatoora/features/shared/business/business_page_widgets.dart';
import 'package:fatoora/features/shared/business/business_shell.dart';
import 'package:fatoora/features/statements/controllers/statements_controller.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

class StatementsScreen extends StatelessWidget {
  const StatementsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return GetBuilder<StatementsController>(
      builder: (controller) => BusinessShell(
        title: 'dashboard_account_statement'.tr,
        showBackButton: !controller.isAdmin,
        onBack: controller.goBack,
        child: HandilingDataView(
          statusrequest: controller.statusRequest,
          errorMessage: controller.loadErrorMessageKey.tr,
          retryLabel: 'items_retry'.tr,
          onRetry: controller.loadCustomers,
          widget: RefreshIndicator(
            onRefresh: controller.refreshCustomers,
            color: AppColor.primaryColor,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final padding = constraints.maxWidth < 600 ? 14.0 : 24.0;
                return SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: EdgeInsets.fromLTRB(padding, padding, padding, 96),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1180),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _Header(controller: controller),
                          const SizedBox(height: 16),
                          _Search(controller: controller),
                          const SizedBox(height: 16),
                          if (controller.customers.isEmpty)
                            _EmptyState(searching: controller.hasSearch)
                          else if (constraints.maxWidth < 900)
                            _CustomerCards(controller: controller)
                          else
                            _CustomerTable(controller: controller),
                          if (controller.hasMore || controller.isLoadingMore)
                            Padding(
                              padding: const EdgeInsets.only(top: 16),
                              child: Center(
                                child: controller.isLoadingMore
                                    ? const FatooraProgressIndicator()
                                    : OutlinedButton.icon(
                                        onPressed: controller.loadMore,
                                        icon: const Icon(
                                          Icons.expand_more_rounded,
                                        ),
                                        label: Text('load_more_records'.tr),
                                      ),
                              ),
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
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.controller});

  final StatementsController controller;

  @override
  Widget build(BuildContext context) {
    return BusinessPageHeader(
      title: 'dashboard_account_statement'.tr,
      subtitle:
          (controller.isAdmin
                  ? 'statements_admin_scope'
                  : 'statements_user_scope')
              .tr,
      stretchTrailingOnCompact: false,
      trailing: Chip(
        avatar: const Icon(Icons.people_alt_outlined, size: 18),
        label: Text(
          'statements_customer_count'.trParams({
            'count': controller.customers.length.toString(),
          }),
        ),
      ),
    );
  }
}

class _Search extends StatelessWidget {
  const _Search({required this.controller});

  final StatementsController controller;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller.searchController,
      onChanged: controller.onSearchChanged,
      onSubmitted: (_) => controller.submitSearch(),
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: 'statements_search_hint'.tr,
        prefixIcon: const Icon(Icons.search_rounded),
        suffixIcon: controller.hasSearch
            ? IconButton(
                tooltip: 'clear_filters'.tr,
                onPressed: controller.clearSearch,
                icon: const Icon(Icons.close_rounded),
              )
            : null,
        filled: true,
        fillColor: context.appSurface,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }
}

class _CustomerCards extends StatelessWidget {
  const _CustomerCards({required this.controller});

  final StatementsController controller;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final customer in controller.customers) ...[
          _CustomerCard(
            customer: customer,
            showCreator: controller.isAdmin,
            onOpen: () => controller.openStatement(customer),
          ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}

class _CustomerCard extends StatelessWidget {
  const _CustomerCard({
    required this.customer,
    required this.showCreator,
    required this.onOpen,
  });

  final CustomerModel customer;
  final bool showCreator;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(symbol: 'JOD ', decimalDigits: 3);
    return DashboardCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  customer.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: context.appText,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              _StatusBadge(active: customer.active),
            ],
          ),
          const SizedBox(height: 10),
          if (customer.phone.isNotEmpty) Text(customer.phone),
          if (showCreator && customer.createdByName.isNotEmpty)
            Text(
              '${'statements_created_by'.tr}: ${customer.createdByName}',
              style: TextStyle(color: context.appMutedText),
            ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Text(
                  currency.format(customer.currentBalance),
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: customer.currentBalance > 0
                        ? AppColor.error
                        : AppColor.success,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              FilledButton.icon(
                onPressed: onOpen,
                icon: const Icon(Icons.article_outlined),
                label: Text('statements_open'.tr),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CustomerTable extends StatelessWidget {
  const _CustomerTable({required this.controller});

  final StatementsController controller;

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(symbol: 'JOD ', decimalDigits: 3);
    return ResponsiveDataTableCard(
      minWidth: controller.isAdmin ? 820 : 680,
      color: context.appSurface,
      borderColor: context.appBorder,
      child: DataTable(
        columnSpacing: 14,
        horizontalMargin: 14,
        columns: [
          _column('customer_name', width: 220),
          _column('Phone', width: 128),
          if (controller.isAdmin) _column('statements_created_by', width: 150),
          _column('customers_balance', width: 126, numeric: true),
          _column('invoice_status', width: 92),
          _column('actions', width: 64),
        ],
        rows: controller.customers
            .map((customer) {
              return DataRow(
                cells: [
                  DataCell(BoundedTableText(customer.name, width: 220)),
                  DataCell(
                    BoundedTableText(
                      customer.phone,
                      width: 128,
                      forceLtr: true,
                    ),
                  ),
                  if (controller.isAdmin)
                    DataCell(
                      BoundedTableText(customer.createdByName, width: 150),
                    ),
                  DataCell(
                    BoundedTableText(
                      currency.format(customer.currentBalance),
                      width: 126,
                      textAlign: TextAlign.end,
                      forceLtr: true,
                    ),
                  ),
                  DataCell(
                    BoundedTableWidget(
                      width: 92,
                      child: _StatusBadge(active: customer.active),
                    ),
                  ),
                  DataCell(
                    SizedBox(
                      width: 64,
                      child: IconButton(
                        tooltip: 'statements_open'.tr,
                        onPressed: () => controller.openStatement(customer),
                        icon: const Icon(Icons.article_outlined),
                      ),
                    ),
                  ),
                ],
              );
            })
            .toList(growable: false),
      ),
    );
  }

  DataColumn _column(
    String labelKey, {
    required double width,
    bool numeric = false,
  }) {
    return DataColumn(
      numeric: numeric,
      label: SizedBox(
        width: width,
        child: Text(labelKey.tr, maxLines: 2, overflow: TextOverflow.ellipsis),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.active});

  final bool active;

  @override
  Widget build(BuildContext context) {
    final color = active ? AppColor.success : AppColor.error;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        (active ? 'items_active' : 'items_inactive').tr,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.searching});

  final bool searching;

  @override
  Widget build(BuildContext context) {
    return BusinessEmptyState(
      icon: Icons.article_outlined,
      title:
          (searching ? 'statements_no_search_results' : 'statements_empty').tr,
    );
  }
}
