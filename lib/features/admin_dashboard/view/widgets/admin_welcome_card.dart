import 'package:fatoora/app/routes/app_routes.dart';
import 'package:fatoora/core/constants/color.dart';
import 'package:fatoora/features/admin_dashboard/controller/admin_dashboard_controller.dart';
import 'package:fatoora/features/admin_dashboard/view/widgets/quick_actions_sheet.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

class AdminWelcomeCard extends StatelessWidget {
  const AdminWelcomeCard({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<AdminDashboardController>();
    final currency = NumberFormat.currency(symbol: 'JOD ', decimalDigits: 3);
    return Container(
      padding: EdgeInsets.all(MediaQuery.sizeOf(context).width < 600 ? 18 : 24),
      decoration: BoxDecoration(
        gradient: AppColor.mainGradient,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: AppColor.primaryDark.withValues(alpha: .22),
            blurRadius: 28,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 820;
          final introduction = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'dashboard_welcome'.trParams({'name': controller.adminName}),
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'financial_monthly_dashboard_summary'.tr,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.white.withValues(alpha: .82),
                ),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _WelcomeMetric(
                    icon: Icons.trending_up_rounded,
                    label: 'dashboard_net_sales'.tr,
                    value: currency.format(controller.snapshot.totalSales),
                    onTap: () => controller.navigateTo(AppRoute.invoices),
                  ),
                  _WelcomeMetric(
                    icon: Icons.account_balance_wallet_outlined,
                    label: 'financial_company_cash'.tr,
                    value: currency.format(controller.snapshot.companyCash),
                    onTap: () => controller.navigateTo(AppRoute.cashMovements),
                  ),
                  _WelcomeMetric(
                    icon: Icons.payments_outlined,
                    label: 'financial_rep_cash_outstanding'.tr,
                    value: currency.format(
                      controller.snapshot.repCashOutstanding,
                    ),
                    onTap: () => controller.navigateTo(AppRoute.cashMovements),
                  ),
                ],
              ),
            ],
          );
          final controls = Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 10,
            runSpacing: 10,
            children: [
              OutlinedButton.icon(
                onPressed: () => controller.selectMonth(context),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  backgroundColor: Colors.white.withValues(alpha: .13),
                  side: BorderSide(color: Colors.white.withValues(alpha: .22)),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                ),
                icon: const Icon(Icons.calendar_month_outlined, size: 17),
                label: Text(
                  controller.selectedMonthLabel(context),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              QuickActionsButton(
                actions: controller.quickActions,
                onSelected: controller.navigateTo,
                light: true,
              ),
            ],
          );
          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [introduction, const SizedBox(height: 20), controls],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: introduction),
              const SizedBox(width: 24),
              controls,
            ],
          );
        },
      ),
    );
  }
}

class _WelcomeMetric extends StatelessWidget {
  const _WelcomeMetric({
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: .12),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 17, color: Colors.white),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  '$label  $value',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
