import 'package:fatoora/app/routes/app_routes.dart';
import 'package:fatoora/core/constants/color.dart';
import 'package:fatoora/features/admin_dashboard/view/widgets/admin_dashboard_shell.dart';
import 'package:fatoora/features/admin_dashboard/view/widgets/dashboard_card.dart';
import 'package:fatoora/features/financial/data/models/financial_dashboard_snapshot.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart' hide TextDirection;

class AdminSalesRepDetailsScreen extends StatelessWidget {
  const AdminSalesRepDetailsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final row = Get.arguments is FinancialRepSalesSummary
        ? Get.arguments as FinancialRepSalesSummary
        : null;
    return AdminDashboardShell(
      child: SingleChildScrollView(
        padding: EdgeInsets.all(
          MediaQuery.sizeOf(context).width < 600 ? 14 : 24,
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 980),
            child: row == null
                ? const _UnavailableState()
                : _SalesRepDetails(row: row),
          ),
        ),
      ),
    );
  }
}

class _SalesRepDetails extends StatelessWidget {
  const _SalesRepDetails({required this.row});

  final FinancialRepSalesSummary row;

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(symbol: 'JOD ', decimalDigits: 3);
    final metrics = [
      _MetricData(
        'dashboard_net_confirmed_sales',
        currency.format(row.totalSales),
        Icons.trending_up_rounded,
        AppColor.primaryColor,
      ),
      _MetricData(
        'financial_cash_sales',
        currency.format(row.cashSales),
        Icons.payments_outlined,
        AppColor.success,
      ),
      _MetricData(
        'financial_credit_sales',
        currency.format(row.creditSales),
        Icons.article_outlined,
        AppColor.tertiaryColor,
      ),
      _MetricData(
        'financial_partial_sales',
        currency.format(row.partialSales),
        Icons.pie_chart_outline_rounded,
        const Color(0xFFFF9838),
      ),
      _MetricData(
        'receipts_collected',
        currency.format(row.receiptsCollected),
        Icons.receipt_outlined,
        const Color(0xFF35A7FF),
      ),
      _MetricData(
        'financial_cash_in_hand',
        currency.format(row.cashInHand),
        Icons.account_balance_wallet_outlined,
        const Color(0xFF6657E8),
      ),
      _MetricData(
        'dashboard_invoices_count',
        row.invoiceCount.toString(),
        Icons.receipt_long_outlined,
        AppColor.secondaryColor,
      ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            IconButton.filledTonal(
              onPressed: Get.back<void>,
              icon: Icon(
                Directionality.of(context) == TextDirection.rtl
                    ? Icons.arrow_forward_rounded
                    : Icons.arrow_back_rounded,
              ),
            ),
            const SizedBox(width: 12),
            CircleAvatar(
              radius: 27,
              backgroundColor: Theme.of(
                context,
              ).colorScheme.primary.withValues(alpha: .13),
              child: Text(
                _initial(row.salesRepName),
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    row.salesRepName.trim().isEmpty
                        ? 'sales_rep'.tr
                        : row.salesRepName,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  Text(
                    'dashboard_sales_rep_details_subtitle'.tr,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: context.appMutedText,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 22),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= 760
                ? 3
                : constraints.maxWidth >= 500
                ? 2
                : 1;
            const spacing = 14.0;
            final width =
                (constraints.maxWidth - (columns - 1) * spacing) / columns;
            return Wrap(
              spacing: spacing,
              runSpacing: spacing,
              children: [
                for (final metric in metrics)
                  SizedBox(
                    width: width,
                    child: _MetricCard(metric: metric),
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: 18),
        DashboardCard(
          child: Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              FilledButton.icon(
                onPressed: () => Get.toNamed(AppRoute.invoices),
                icon: const Icon(Icons.receipt_long_outlined),
                label: Text('dashboard_view_invoices'.tr),
              ),
              OutlinedButton.icon(
                onPressed: () => Get.toNamed(AppRoute.cashMovements),
                icon: const Icon(Icons.account_balance_wallet_outlined),
                label: Text('financial_cash'.tr),
              ),
              OutlinedButton.icon(
                onPressed: () => Get.toNamed(AppRoute.adminUsers),
                icon: const Icon(Icons.manage_accounts_outlined),
                label: Text('admin_users'.tr),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.metric});

  final _MetricData metric;

  @override
  Widget build(BuildContext context) {
    return DashboardCard(
      padding: const EdgeInsets.all(18),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: metric.color.withValues(alpha: .13),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(metric.icon, color: metric.color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  metric.labelKey.tr,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: context.appMutedText,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  metric.value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
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

class _UnavailableState extends StatelessWidget {
  const _UnavailableState();

  @override
  Widget build(BuildContext context) {
    return DashboardCard(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 50),
        child: Column(
          children: [
            Icon(
              Icons.person_search_outlined,
              size: 52,
              color: context.appMutedText,
            ),
            const SizedBox(height: 14),
            Text('dashboard_sales_rep_details_unavailable'.tr),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: () => Get.offNamed(AppRoute.adminUsers),
              icon: const Icon(Icons.manage_accounts_outlined),
              label: Text('admin_users'.tr),
            ),
          ],
        ),
      ),
    );
  }
}

class _MetricData {
  const _MetricData(this.labelKey, this.value, this.icon, this.color);

  final String labelKey;
  final String value;
  final IconData icon;
  final Color color;
}

String _initial(String value) {
  final name = value.trim();
  return name.isEmpty ? 'S' : name.characters.first.toUpperCase();
}
