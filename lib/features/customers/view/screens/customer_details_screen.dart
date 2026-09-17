import 'package:fatoora/core/class/handilingdataview.dart';
import 'package:fatoora/core/constants/color.dart';
import 'package:fatoora/core/motion/fatoora_overlays.dart';
import 'package:fatoora/features/customers/controllers/customer_details_controller.dart';
import 'package:fatoora/features/customers/data/models/customer_model.dart';
import 'package:fatoora/features/customers/data/models/customer_opening_balance.dart';
import 'package:fatoora/features/customers/data/models/customer_transaction_model.dart';
import 'package:fatoora/features/customers/view/widgets/customer_opening_balance_dialog.dart';
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
              if (controller.openingBalance != null) ...[
                const SizedBox(height: 16),
                _OpeningBalanceCard(transaction: controller.openingBalance!),
              ],
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
    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 520;
        return DashboardCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: 14,
                runSpacing: 14,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: narrow
                          ? constraints.maxWidth
                          : (constraints.maxWidth - 16)
                                .clamp(260.0, 520.0)
                                .toDouble(),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          customer.name,
                          softWrap: true,
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(
                                color: AppColor.secondaryColor,
                                fontWeight: FontWeight.w900,
                              ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          customer.active
                              ? 'items_active'.tr
                              : 'items_inactive'.tr,
                          style: Theme.of(context).textTheme.labelLarge
                              ?.copyWith(
                                color: customer.active
                                    ? AppColor.success
                                    : AppColor.error,
                                fontWeight: FontWeight.w800,
                              ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _ResponsiveActionButton(
                    narrow: narrow,
                    child: OutlinedButton.icon(
                      onPressed: controller.editCustomer,
                      icon: const Icon(Icons.edit_outlined),
                      label: Text('customers_edit'.tr),
                    ),
                  ),
                  _ResponsiveActionButton(
                    narrow: narrow,
                    child: OutlinedButton.icon(
                      onPressed:
                          customer.active &&
                              !controller.isPostingOpeningBalance &&
                              !controller.isCheckingOpeningBalance
                          ? () => _openOpeningBalance(context)
                          : null,
                      icon: const Icon(Icons.account_balance_wallet_outlined),
                      label: Text(
                        (controller.openingBalance == null
                                ? 'customers_add_opening_balance'
                                : 'customers_edit_opening_balance')
                            .tr,
                      ),
                    ),
                  ),
                  _ResponsiveActionButton(
                    narrow: narrow,
                    child: FilledButton.icon(
                      onPressed: controller.openStatement,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColor.primaryColor,
                      ),
                      icon: const Icon(Icons.article_outlined),
                      label: Text('customers_statement'.tr),
                    ),
                  ),
                  _ResponsiveActionButton(
                    narrow: narrow,
                    child: TextButton.icon(
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
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _openOpeningBalance(BuildContext context) async {
    final ready = await controller.prepareOpeningBalance();
    if (!ready || !context.mounted) return;

    final existing = controller.openingBalance;
    if (existing != null) {
      final updated = await showFatooraDialog<CustomerTransactionModel>(
        context: context,
        barrierDismissible: false,
        builder: (_) => CustomerOpeningBalanceEditDialog(
          customerName: customer.name,
          transaction: existing,
          onSubmit: controller.updateOpeningBalance,
        ),
      );
      if (updated != null && !controller.isClosed) {
        controller.openingBalanceUpdateDialogCompleted(updated);
      }
      return;
    }

    final saved = await showFatooraDialog<CustomerTransactionModel>(
      context: context,
      barrierDismissible: false,
      builder: (_) => CustomerOpeningBalanceDialog(
        customerName: customer.name,
        onSubmit: controller.addOpeningBalance,
      ),
    );
    if (saved != null && !controller.isClosed) {
      controller.openingBalanceDialogCompleted(saved);
    }
  }
}

class _ResponsiveActionButton extends StatelessWidget {
  const _ResponsiveActionButton({required this.narrow, required this.child});

  final bool narrow;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!narrow) return child;
    return SizedBox(width: double.infinity, child: child);
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
        final cardWidth = constraints.maxWidth < 620
            ? constraints.maxWidth
            : (constraints.maxWidth - 24) / 3;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            SizedBox(
              width: cardWidth,
              child: _MetricCard(
                label: 'customers_balance'.tr,
                value: currency.format(customer.currentBalance),
                icon: Icons.account_balance_wallet_outlined,
              ),
            ),
            SizedBox(
              width: cardWidth,
              child: _MetricCard(
                label: 'customers_total_sales'.tr,
                value: currency.format(customer.totalSales),
                icon: Icons.trending_up_rounded,
              ),
            ),
            SizedBox(
              width: cardWidth,
              child: _MetricCard(
                label: 'customers_total_paid'.tr,
                value: currency.format(customer.totalPaid),
                icon: Icons.payments_outlined,
              ),
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
                  softWrap: true,
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

class _OpeningBalanceCard extends StatelessWidget {
  const _OpeningBalanceCard({required this.transaction});

  final CustomerTransactionModel transaction;

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(symbol: 'JOD ', decimalDigits: 3);
    final type = CustomerOpeningBalanceType.fromValue(
      transaction.openingBalanceType,
    );
    return DashboardCard(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final narrow = constraints.maxWidth < 560;
          final details = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'customers_opening_balance_details'.tr,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: AppColor.secondaryColor,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '${currency.format(transaction.amount)} · '
                '${(type == CustomerOpeningBalanceType.customerCredit ? 'customers_has_credit' : 'customers_owes_us').tr}',
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(
                DateFormat.yMd().format(transaction.transactionDate),
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: AppColor.grey),
              ),
            ],
          );
          final action = OutlinedButton.icon(
            onPressed: () => showFatooraDialog<void>(
              context: context,
              builder: (_) =>
                  CustomerOpeningBalanceDetailsDialog(transaction: transaction),
            ),
            icon: const Icon(Icons.visibility_outlined),
            label: Text('customers_view_details'.tr),
          );
          if (narrow) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [details, const SizedBox(height: 12), action],
            );
          }
          return Row(
            children: [
              const Icon(Icons.history_rounded, color: AppColor.primaryColor),
              const SizedBox(width: 14),
              Expanded(child: details),
              const SizedBox(width: 14),
              action,
            ],
          );
        },
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
      child: LayoutBuilder(
        builder: (context, constraints) {
          final narrow = constraints.maxWidth < 420;
          final labelWidget = Text(
            label,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: AppColor.grey,
              fontWeight: FontWeight.w800,
            ),
          );
          final valueWidget = Text(
            value,
            softWrap: true,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: AppColor.secondaryColor),
          );
          if (narrow) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [labelWidget, const SizedBox(height: 4), valueWidget],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: 130, child: labelWidget),
              Expanded(child: valueWidget),
            ],
          );
        },
      ),
    );
  }
}
