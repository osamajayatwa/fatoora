import 'package:fatoora/core/class/handilingdataview.dart';
import 'package:fatoora/core/constants/color.dart';
import 'package:fatoora/features/customers/controllers/customer_details_controller.dart';
import 'package:fatoora/features/customers/data/models/customer_model.dart';
import 'package:fatoora/features/admin_dashboard/view/widgets/dashboard_card.dart';
import 'package:fatoora/features/shared/business/business_shell.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

class CustomerDetailsScreen extends StatelessWidget {
  const CustomerDetailsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return GetBuilder<CustomerDetailsController>(
      builder: (controller) => BusinessShell(
        title: 'customers_details'.tr,
        showBackButton: true,
        onBack: controller.requestBack,
        child: HandilingDataView(
          statusrequest: controller.statusRequest,
          errorMessage: controller.loadErrorMessageKey.tr,
          retryLabel: 'items_retry'.tr,
          onRetry: controller.loadCustomer,
          widget: _DetailsBody(controller: controller),
        ),
      ),
    );
  }
}

class _DetailsBody extends StatelessWidget {
  const _DetailsBody({required this.controller});

  final CustomerDetailsController controller;

  @override
  Widget build(BuildContext context) {
    final customer = controller.customer;
    if (customer == null) return const SizedBox.shrink();
    return SingleChildScrollView(
      padding: EdgeInsets.all(MediaQuery.sizeOf(context).width < 600 ? 14 : 24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 980),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Header(customer: customer, controller: controller),
              const SizedBox(height: 16),
              _BalanceCards(customer: customer),
              const SizedBox(height: 16),
              _InfoCard(customer: customer),
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.customer, required this.controller});

  final CustomerModel customer;
  final CustomerDetailsController controller;

  @override
  Widget build(BuildContext context) {
    return DashboardCard(
      child: Wrap(
        spacing: 14,
        runSpacing: 14,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: 420,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  customer.name,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: AppColor.secondaryColor,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  customer.active ? 'items_active'.tr : 'items_inactive'.tr,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: customer.active ? AppColor.success : AppColor.error,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          OutlinedButton.icon(
            onPressed: controller.editCustomer,
            icon: const Icon(Icons.edit_outlined),
            label: Text('customers_edit'.tr),
          ),
          FilledButton.icon(
            onPressed: controller.openStatement,
            style: FilledButton.styleFrom(
              backgroundColor: AppColor.primaryColor,
            ),
            icon: const Icon(Icons.article_outlined),
            label: Text('customers_statement'.tr),
          ),
          TextButton.icon(
            onPressed: controller.isUpdating
                ? null
                : () => controller.setActive(!customer.active),
            icon: Icon(
              customer.active
                  ? Icons.visibility_off_outlined
                  : Icons.visibility_outlined,
            ),
            label: Text(
              customer.active
                  ? 'customers_deactivate'.tr
                  : 'customers_activate'.tr,
            ),
          ),
        ],
      ),
    );
  }
}

class _BalanceCards extends StatelessWidget {
  const _BalanceCards({required this.customer});

  final CustomerModel customer;

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(symbol: 'JOD ', decimalDigits: 3);
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth < 760 ? 1 : 3;
        return GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: columns,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: columns == 1 ? 4.5 : 2.1,
          children: [
            _MetricCard(
              label: 'customers_balance'.tr,
              value: currency.format(customer.currentBalance),
              icon: Icons.account_balance_wallet_outlined,
            ),
            _MetricCard(
              label: 'customers_total_sales'.tr,
              value: currency.format(customer.totalSales),
              icon: Icons.trending_up_rounded,
            ),
            _MetricCard(
              label: 'customers_total_paid'.tr,
              value: currency.format(customer.totalPaid),
              icon: Icons.payments_outlined,
            ),
          ],
        );
      },
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return DashboardCard(
      child: Row(
        children: [
          Icon(icon, color: AppColor.primaryColor),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: Theme.of(context).textTheme.labelMedium),
                const SizedBox(height: 5),
                Text(
                  value,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: AppColor.secondaryColor,
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
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.customer});

  final CustomerModel customer;

  @override
  Widget build(BuildContext context) {
    return DashboardCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'customers_contact_info'.tr,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: AppColor.secondaryColor,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 14),
          _InfoRow(label: 'Phone'.tr, value: customer.phone),
          _InfoRow(label: 'address'.tr, value: customer.addressText),
          _InfoRow(label: 'city'.tr, value: customer.city),
          _InfoRow(label: 'customers_area'.tr, value: customer.area),
          _InfoRow(label: 'notes'.tr, value: customer.notes),
          _InfoRow(label: 'created_by'.tr, value: customer.createdByName),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    if (value.trim().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(
              label,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: AppColor.grey,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: AppColor.secondaryColor),
            ),
          ),
        ],
      ),
    );
  }
}
