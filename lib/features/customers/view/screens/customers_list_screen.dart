import 'package:fatoora/core/class/handilingdataview.dart';
import 'package:fatoora/core/constants/color.dart';
import 'package:fatoora/features/customers/controllers/customers_controller.dart';
import 'package:fatoora/features/customers/data/models/customer_model.dart';
import 'package:fatoora/features/admin_dashboard/view/widgets/dashboard_card.dart';
import 'package:fatoora/features/shared/business/business_shell.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

class CustomersListScreen extends StatelessWidget {
  const CustomersListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return GetBuilder<CustomersController>(
      builder: (controller) => BusinessShell(
        title: 'customers'.tr,
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
                final compact = constraints.maxWidth < 760;
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
                          const SizedBox(height: 16),
                          _CustomerSearch(controller: controller),
                          const SizedBox(height: 16),
                          if (controller.customers.isEmpty)
                            _EmptyCustomers(searching: controller.hasSearch)
                          else if (compact)
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

class _CustomersHeader extends StatelessWidget {
  const _CustomersHeader({required this.controller});

  final CustomersController controller;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 620;
    final title = Text(
      'customers'.tr,
      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
        color: AppColor.secondaryColor,
        fontWeight: FontWeight.w900,
      ),
    );
    final action = controller.canCreateCustomer
        ? FilledButton.icon(
            onPressed: controller.openCreateCustomer,
            style: FilledButton.styleFrom(
              backgroundColor: AppColor.primaryColor,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            ),
            icon: const Icon(Icons.person_add_alt_1_outlined),
            label: Text('customers_add'.tr),
          )
        : null;
    if (compact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          title,
          if (action != null) ...[const SizedBox(height: 12), action],
        ],
      );
    }
    return Row(
      children: [
        Expanded(child: title),
        if (action != null) ...[const SizedBox(width: 16), action],
      ],
    );
  }
}

class _CustomerSearch extends StatelessWidget {
  const _CustomerSearch({required this.controller});

  final CustomersController controller;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller.searchController,
      onChanged: controller.onSearchChanged,
      decoration: InputDecoration(
        hintText: 'customers_search_hint'.tr,
        prefixIcon: const Icon(Icons.search_rounded),
        suffixIcon: controller.hasSearch
            ? IconButton(
                onPressed: controller.clearSearch,
                icon: const Icon(Icons.close_rounded),
              )
            : null,
        filled: true,
        fillColor: AppColor.surface,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }
}

class _CustomerCards extends StatelessWidget {
  const _CustomerCards({required this.controller});

  final CustomersController controller;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final customer in controller.customers) ...[
          _CustomerCard(
            customer: customer,
            onTap: () => controller.openCustomerDetails(customer),
          ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}

class _CustomerCard extends StatelessWidget {
  const _CustomerCard({required this.customer, required this.onTap});

  final CustomerModel customer;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(symbol: 'JOD ', decimalDigits: 3);
    return DashboardCard(
      padding: EdgeInsets.zero,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      customer.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: AppColor.secondaryColor,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  _StatusPill(active: customer.active),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (customer.phone.isNotEmpty)
                    _InfoPill(
                      icon: Icons.phone_outlined,
                      label: customer.phone,
                    ),
                  if (customer.city.isNotEmpty)
                    _InfoPill(
                      icon: Icons.location_city_outlined,
                      label: customer.city,
                    ),
                  if (customer.area.isNotEmpty)
                    _InfoPill(icon: Icons.place_outlined, label: customer.area),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                currency.format(customer.currentBalance),
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: customer.currentBalance > 0
                      ? AppColor.error
                      : AppColor.success,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CustomerTable extends StatelessWidget {
  const _CustomerTable({required this.controller});

  final CustomersController controller;

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(symbol: 'JOD ', decimalDigits: 3);
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: AppColor.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: Color(0xFFE4E8EF)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columns: [
            DataColumn(label: Text('customer_name'.tr)),
            DataColumn(label: Text('Phone'.tr)),
            DataColumn(label: Text('city'.tr)),
            DataColumn(label: Text('customers_area'.tr)),
            DataColumn(label: Text('customers_balance'.tr)),
            DataColumn(label: Text('invoice_status'.tr)),
            DataColumn(label: Text('actions'.tr)),
          ],
          rows: controller.customers
              .map(
                (customer) => DataRow(
                  cells: [
                    DataCell(Text(customer.name)),
                    DataCell(Text(customer.phone)),
                    DataCell(Text(customer.city)),
                    DataCell(Text(customer.area)),
                    DataCell(Text(currency.format(customer.currentBalance))),
                    DataCell(_StatusPill(active: customer.active)),
                    DataCell(
                      IconButton(
                        tooltip: 'invoice_details'.tr,
                        onPressed: () =>
                            controller.openCustomerDetails(customer),
                        icon: const Icon(Icons.chevron_right_rounded),
                      ),
                    ),
                  ],
                ),
              )
              .toList(),
        ),
      ),
    );
  }
}

class _EmptyCustomers extends StatelessWidget {
  const _EmptyCustomers({required this.searching});

  final bool searching;

  @override
  Widget build(BuildContext context) {
    return DashboardCard(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 36),
        child: Column(
          children: [
            Icon(Icons.people_alt_outlined, size: 44, color: AppColor.grey),
            const SizedBox(height: 12),
            Text(
              searching
                  ? 'customers_no_search_results'.tr
                  : 'customers_empty'.tr,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: AppColor.secondaryColor,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.active});

  final bool active;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: active
            ? AppColor.success.withValues(alpha: 0.12)
            : AppColor.error.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        active ? 'items_active'.tr : 'items_inactive'.tr,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: active ? AppColor.success : AppColor.error,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _InfoPill extends StatelessWidget {
  const _InfoPill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFF4F6FA),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppColor.grey),
          const SizedBox(width: 6),
          Text(label, style: Theme.of(context).textTheme.labelSmall),
        ],
      ),
    );
  }
}
