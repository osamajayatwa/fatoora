import 'package:fatoora/core/class/handilingdataview.dart';
import 'package:fatoora/core/constants/color.dart';
import 'package:fatoora/features/admin_dashboard/controller/admin_dashboard_controller.dart';
import 'package:fatoora/features/admin_dashboard/view/widgets/admin_welcome_card.dart';
import 'package:fatoora/features/admin_dashboard/view/widgets/dashboard_alerts_card.dart';
import 'package:fatoora/features/admin_dashboard/view/widgets/dashboard_stat_card.dart';
import 'package:fatoora/features/admin_dashboard/view/widgets/invoice_line_chart.dart';
import 'package:fatoora/features/admin_dashboard/view/widgets/invoice_summary_card.dart';
import 'package:fatoora/features/admin_dashboard/view/widgets/latest_invoices_card.dart';
import 'package:fatoora/features/admin_dashboard/view/widgets/sales_by_rep_card.dart';
import 'package:fatoora/features/admin_dashboard/view/widgets/top_customers_card.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class AdminDashboardContent extends StatelessWidget {
  const AdminDashboardContent({super.key});

  @override
  Widget build(BuildContext context) {
    return GetBuilder<AdminDashboardController>(
      builder: (controller) => HandilingDataView(
        statusrequest: controller.statusRequest,
        errorMessage: controller.loadErrorMessageKey.tr,
        retryLabel: 'items_retry'.tr,
        onRetry: controller.refreshDashboard,
        widget: RefreshIndicator(
          color: AppColor.primaryColor,
          onRefresh: controller.refreshDashboard,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.all(
              MediaQuery.sizeOf(context).width < 600 ? 14 : 24,
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1440),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const AdminWelcomeCard(),
                    const SizedBox(height: 22),
                    if (MediaQuery.sizeOf(context).width < 600) ...[
                      TextField(
                        controller: controller.searchController,
                        onChanged: controller.onSearchChanged,
                        decoration: InputDecoration(
                          hintText: 'dashboard_search_hint'.tr,
                          prefixIcon: const Icon(Icons.search_rounded),
                          filled: true,
                          fillColor: context.appSurface,
                        ),
                      ),
                      const SizedBox(height: 18),
                    ],
                    _StatsGrid(),
                    const SizedBox(height: 18),
                    _ResponsivePair(
                      desktopHeight: 420,
                      first: LatestInvoicesCard(),
                      second: InvoiceLineChartCard(
                        values: controller.weeklyInvoiceValues,
                      ),
                    ),
                    const SizedBox(height: 18),
                    _ResponsivePair(
                      desktopHeight: 430,
                      first: InvoiceSummaryCard(),
                      second: TopCustomersCard(),
                    ),
                    const SizedBox(height: 18),
                    SalesByRepCard(),
                    const SizedBox(height: 18),
                    DashboardAlertsCard(),
                    const SizedBox(height: 20),
                    Text(
                      'dashboard_footer'.tr,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: context.appMutedText,
                      ),
                    ),
                    const SizedBox(height: 6),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StatsGrid extends StatelessWidget {
  const _StatsGrid();

  @override
  Widget build(BuildContext context) {
    final stats = Get.find<AdminDashboardController>().stats;
    return LayoutBuilder(
      builder: (context, constraints) {
        final textScale = MediaQuery.textScalerOf(context).scale(1);
        final columns = constraints.maxWidth >= 1200
            ? 5
            : constraints.maxWidth >= 820
            ? 3
            : constraints.maxWidth >= 560
            ? 2
            : 1;
        const spacing = 16.0;
        final width =
            (constraints.maxWidth - (columns - 1) * spacing) / columns;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: stats
              .map(
                (stat) => SizedBox(
                  width: width,
                  height: 190 + ((textScale - 1).clamp(0, 1) * 72),
                  child: DashboardStatCard(stat: stat),
                ),
              )
              .toList(),
        );
      },
    );
  }
}

class _ResponsivePair extends StatelessWidget {
  const _ResponsivePair({
    required this.desktopHeight,
    required this.first,
    required this.second,
  });

  final double desktopHeight;
  final Widget first;
  final Widget second;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final textScale = MediaQuery.textScalerOf(context).scale(1);
        if (constraints.maxWidth < 880 || textScale > 1.3) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [first, const SizedBox(height: 18), second],
          );
        }
        return SizedBox(
          height: desktopHeight + ((textScale - 1).clamp(0, .3) * 160),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: first),
              const SizedBox(width: 18),
              Expanded(child: second),
            ],
          ),
        );
      },
    );
  }
}
