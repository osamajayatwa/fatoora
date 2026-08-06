import 'package:fatoora/core/constants/color.dart';
import 'package:fatoora/features/financial/controllers/sales_rep_dashboard_controller.dart';
import 'package:fatoora/features/home/view/widgets/sales_rep_dashboard_primitives.dart';
import 'package:fatoora/features/home/view/widgets/sales_rep_dashboard_layout.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

class SalesRepOverviewMetrics extends StatelessWidget {
  const SalesRepOverviewMetrics({super.key, required this.controller});

  final SalesRepDashboardController controller;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final currency = NumberFormat.currency(symbol: 'JOD ', decimalDigits: 3);
    final metrics = [
      _MetricData(
        title: 'sales_rep_home_sales_period'.tr,
        value: currency.format(controller.snapshot.totalSales),
        support: controller.selectedMonthLabel(context),
        icon: Icons.trending_up_rounded,
        color: scheme.primary,
        onTap: controller.openInvoices,
      ),
      _MetricData(
        title: 'sales_rep_home_receipts_period'.tr,
        value: controller.snapshot.receiptCount.toString(),
        support: controller.selectedMonthLabel(context),
        icon: Icons.payments_outlined,
        color: scheme.tertiary,
        onTap: controller.openReceipts,
      ),
      _MetricData(
        title: 'sales_rep_home_cash_with_you'.tr,
        value: currency.format(controller.snapshot.repCashOutstanding),
        support: 'financial_rep_cash_to_settle'.tr,
        icon: Icons.account_balance_wallet_outlined,
        color: scheme.secondary,
        onTap: controller.openCash,
      ),
      _MetricData(
        title: 'sales_rep_home_custody_items'.tr,
        value: 'sales_rep_home_view_inventory'.tr,
        support: 'sales_rep_home_inventory_hint'.tr,
        icon: Icons.inventory_2_outlined,
        color: scheme.primaryContainer,
        onTap: controller.openMyInventory,
      ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SalesRepSectionTitle(title: 'sales_rep_home_overview'.tr),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = SalesRepDashboardLayout.metricColumns(
              constraints.maxWidth,
            );
            final textScale = MediaQuery.textScalerOf(context).scale(1);
            final height = SalesRepDashboardLayout.metricHeight(textScale);
            return GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: metrics.length,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: columns,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                mainAxisExtent: height,
              ),
              itemBuilder: (_, index) => _MetricCard(data: metrics[index]),
            );
          },
        ),
      ],
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.data});

  final _MetricData data;

  @override
  Widget build(BuildContext context) {
    return SalesRepInteractiveCard(
      onTap: data.onTap,
      semanticLabel: data.title,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SalesRepIconBox(icon: data.icon, color: data.color, size: 38),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  data.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: context.appMutedText,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const Spacer(),
          Text(
            data.value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: context.appText,
              fontWeight: FontWeight.w900,
            ),
          ),
          Text(
            data.support,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.labelSmall?.copyWith(color: context.appMutedText),
          ),
        ],
      ),
    );
  }
}

class _MetricData {
  const _MetricData({
    required this.title,
    required this.value,
    required this.support,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final String title;
  final String value;
  final String support;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
}
