import 'package:fatoora/core/constant/color.dart';
import 'package:fatoora/modules/admin_dashboard/controller/admin_dashboard_controller.dart';
import 'package:fatoora/modules/admin_dashboard/view/widgets/dashboard_alerts_card.dart';
import 'package:fatoora/modules/admin_dashboard/view/widgets/dashboard_stat_card.dart';
import 'package:fatoora/modules/admin_dashboard/view/widgets/invoice_line_chart.dart';
import 'package:fatoora/modules/admin_dashboard/view/widgets/invoice_summary_card.dart';
import 'package:fatoora/modules/admin_dashboard/view/widgets/latest_invoices_card.dart';
import 'package:fatoora/modules/admin_dashboard/view/widgets/quick_actions_card.dart';
import 'package:fatoora/modules/admin_dashboard/view/widgets/top_customers_card.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class AdminDashboardContent extends StatelessWidget {
  const AdminDashboardContent({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<AdminDashboardController>();
    return RefreshIndicator(
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
                const _DashboardWelcome(),
                const SizedBox(height: 22),
                if (MediaQuery.sizeOf(context).width < 600) ...[
                  TextField(
                    controller: controller.searchController,
                    onChanged: controller.onSearchChanged,
                    decoration: InputDecoration(
                      hintText: 'dashboard_search_hint'.tr,
                      prefixIcon: const Icon(Icons.search_rounded),
                      filled: true,
                      fillColor: AppColor.surface,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: Color(0xFFE1E5ED)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: Color(0xFFE1E5ED)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                ],
                const _StatsGrid(),
                const SizedBox(height: 18),
                _ResponsivePair(
                  desktopHeight: 420,
                  first: const LatestInvoicesCard(),
                  second: InvoiceLineChartCard(
                    values: controller.weeklyInvoiceValues,
                  ),
                ),
                const SizedBox(height: 18),
                const _ResponsivePair(
                  desktopHeight: 350,
                  first: QuickActionsCard(),
                  second: InvoiceSummaryCard(),
                ),
                const SizedBox(height: 18),
                const _ResponsivePair(
                  desktopHeight: 310,
                  first: TopCustomersCard(),
                  second: DashboardAlertsCard(),
                ),
                const SizedBox(height: 20),
                Text(
                  'dashboard_footer'.tr,
                  textAlign: TextAlign.center,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: AppColor.grey),
                ),
                const SizedBox(height: 6),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DashboardWelcome extends StatelessWidget {
  const _DashboardWelcome();

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<AdminDashboardController>();
    final compact = MediaQuery.sizeOf(context).width < 650;
    final title = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'dashboard_welcome'.trParams({'name': controller.adminName}),
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            color: AppColor.secondaryColor,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          'dashboard_daily_summary'.tr,
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: AppColor.grey),
        ),
      ],
    );
    final controls = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
          decoration: BoxDecoration(
            color: AppColor.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE1E5ED)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.calendar_today_outlined,
                size: 17,
                color: AppColor.primaryColor,
              ),
              const SizedBox(width: 8),
              Text(
                MaterialLocalizations.of(
                  context,
                ).formatMediumDate(DateTime.now()),
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: AppColor.secondaryColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        GetBuilder<AdminDashboardController>(
          builder: (controller) => IconButton.filled(
            tooltip: 'dashboard_refresh'.tr,
            onPressed: controller.isRefreshing
                ? null
                : controller.refreshDashboard,
            style: IconButton.styleFrom(
              backgroundColor: AppColor.primaryColor,
              foregroundColor: AppColor.surface,
            ),
            icon: controller.isRefreshing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColor.surface,
                    ),
                  )
                : const Icon(Icons.refresh_rounded),
          ),
        ),
      ],
    );

    return compact
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              title,
              const SizedBox(height: 16),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: controls,
              ),
            ],
          )
        : Row(
            children: [
              Expanded(child: title),
              const SizedBox(width: 18),
              controls,
            ],
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
        final columns = constraints.maxWidth >= 820
            ? 4
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
                  height: 190,
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
        if (constraints.maxWidth < 880) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [first, const SizedBox(height: 18), second],
          );
        }
        return SizedBox(
          height: desktopHeight,
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
