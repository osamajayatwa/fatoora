import 'package:fatoora/core/class/handilingdataview.dart';
import 'package:fatoora/core/constants/color.dart';
import 'package:fatoora/features/admin_dashboard/view/widgets/dashboard_card.dart';
import 'package:fatoora/features/customers/data/models/customer_model.dart';
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
                          else if (constraints.maxWidth < 760)
                            _CustomerCards(controller: controller)
                          else
                            _CustomerTable(controller: controller),
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
    return DashboardCard(
      child: Wrap(
        spacing: 18,
        runSpacing: 12,
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: 680,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'dashboard_account_statement'.tr,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: context.appText,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  (controller.isAdmin
                          ? 'statements_admin_scope'
                          : 'statements_user_scope')
                      .tr,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: context.appMutedText),
                ),
              ],
            ),
          ),
          Chip(
            avatar: const Icon(Icons.people_alt_outlined, size: 18),
            label: Text(
              'statements_customer_count'.trParams({
                'count': controller.customers.length.toString(),
              }),
            ),
          ),
        ],
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
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: context.appSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: context.appBorder),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columns: [
            DataColumn(label: Text('customer_name'.tr)),
            DataColumn(label: Text('Phone'.tr)),
            if (controller.isAdmin)
              DataColumn(label: Text('statements_created_by'.tr)),
            DataColumn(label: Text('customers_balance'.tr)),
            DataColumn(label: Text('invoice_status'.tr)),
            DataColumn(label: Text('actions'.tr)),
          ],
          rows: controller.customers
              .map((customer) {
                return DataRow(
                  cells: [
                    DataCell(Text(customer.name)),
                    DataCell(Text(customer.phone)),
                    if (controller.isAdmin)
                      DataCell(Text(customer.createdByName)),
                    DataCell(Text(currency.format(customer.currentBalance))),
                    DataCell(_StatusBadge(active: customer.active)),
                    DataCell(
                      IconButton(
                        tooltip: 'statements_open'.tr,
                        onPressed: () => controller.openStatement(customer),
                        icon: const Icon(Icons.article_outlined),
                      ),
                    ),
                  ],
                );
              })
              .toList(growable: false),
        ),
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
    return DashboardCard(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 34),
        child: Column(
          children: [
            Icon(Icons.article_outlined, size: 46, color: context.appMutedText),
            const SizedBox(height: 12),
            Text(
              (searching ? 'statements_no_search_results' : 'statements_empty')
                  .tr,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: context.appText,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
