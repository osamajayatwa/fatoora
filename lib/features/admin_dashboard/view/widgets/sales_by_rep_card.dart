import 'package:fatoora/app/routes/app_routes.dart';
import 'package:fatoora/core/constants/color.dart';
import 'package:fatoora/features/admin_dashboard/controller/admin_dashboard_controller.dart';
import 'package:fatoora/features/admin_dashboard/view/widgets/dashboard_card.dart';
import 'package:fatoora/features/financial/data/models/financial_dashboard_snapshot.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart' hide TextDirection;

class SalesByRepCard extends StatelessWidget {
  const SalesByRepCard({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<AdminDashboardController>();
    final rows = controller.snapshot.salesByRepSummary;
    return DashboardCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DashboardSectionTitle(
            titleKey: 'dashboard_sales_by_representative',
            subtitleKey: 'dashboard_sales_by_rep_subtitle',
            trailing: TextButton.icon(
              onPressed: () => controller.navigateTo(AppRoute.adminUsers),
              icon: const Icon(Icons.manage_accounts_outlined),
              label: Text('admin_users'.tr),
            ),
          ),
          const SizedBox(height: 18),
          if (rows.isEmpty)
            const DashboardEmptyState(
              icon: Icons.groups_2_outlined,
              messageKey: 'dashboard_no_sales_reps_yet',
            )
          else
            LayoutBuilder(
              builder: (context, constraints) {
                final columns = constraints.maxWidth >= 1080
                    ? 3
                    : constraints.maxWidth >= 660
                    ? 2
                    : 1;
                const spacing = 14.0;
                final width =
                    (constraints.maxWidth - (columns - 1) * spacing) / columns;
                return Wrap(
                  spacing: spacing,
                  runSpacing: spacing,
                  children: [
                    for (final row in rows)
                      SizedBox(
                        width: width,
                        child: DashboardSalesRepCard(
                          row: row,
                          onTap: () => controller.openSalesRepDetails(row),
                        ),
                      ),
                  ],
                );
              },
            ),
        ],
      ),
    );
  }
}

class DashboardSalesRepCard extends StatelessWidget {
  const DashboardSalesRepCard({
    super.key,
    required this.row,
    required this.onTap,
  });

  final FinancialRepSalesSummary row;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(symbol: 'JOD ', decimalDigits: 3);
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: context.appSurfaceMuted,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: context.appBorder),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 22,
                    backgroundColor: scheme.primary.withValues(alpha: .13),
                    child: Text(
                      _initial(row.salesRepName),
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: scheme.primary,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _repName(row),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w900),
                        ),
                        Text(
                          'sales_rep'.tr,
                          style: Theme.of(context).textTheme.labelMedium
                              ?.copyWith(color: context.appMutedText),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Directionality.of(context) == TextDirection.rtl
                        ? Icons.chevron_left_rounded
                        : Icons.chevron_right_rounded,
                    color: context.appMutedText,
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Text(
                'dashboard_net_confirmed_sales'.tr,
                style: Theme.of(
                  context,
                ).textTheme.labelMedium?.copyWith(color: context.appMutedText),
              ),
              const SizedBox(height: 4),
              Text(
                currency.format(row.totalSales),
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: scheme.primary,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 16),
              Divider(color: context.appBorder),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: _RepMetric(
                      label: 'dashboard_invoices_count'.tr,
                      value: row.invoiceCount.toString(),
                    ),
                  ),
                  Expanded(
                    child: _RepMetric(
                      label: 'receipts_collected'.tr,
                      value: currency.format(row.receiptsCollected),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _RepMetric(
                label: 'financial_rep_cash_outstanding'.tr,
                value: currency.format(row.cashInHand),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RepMetric extends StatelessWidget {
  const _RepMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(
            context,
          ).textTheme.labelSmall?.copyWith(color: context.appMutedText),
        ),
        const SizedBox(height: 3),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(
            context,
          ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800),
        ),
      ],
    );
  }
}

String _repName(FinancialRepSalesSummary row) {
  return row.salesRepName.trim().isEmpty ? 'sales_rep'.tr : row.salesRepName;
}

String _initial(String value) {
  final name = value.trim();
  return name.isEmpty ? 'S' : name.characters.first.toUpperCase();
}
