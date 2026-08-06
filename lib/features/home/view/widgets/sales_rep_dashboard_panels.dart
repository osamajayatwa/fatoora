import 'package:fatoora/core/constants/color.dart';
import 'package:fatoora/features/financial/controllers/sales_rep_dashboard_controller.dart';
import 'package:fatoora/features/home/view/widgets/sales_rep_dashboard_primitives.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

class SalesRepNeedsAttentionPanel extends StatelessWidget {
  const SalesRepNeedsAttentionPanel({super.key, required this.controller});

  final SalesRepDashboardController controller;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final currency = NumberFormat.currency(symbol: 'JOD ', decimalDigits: 3);
    final snapshot = controller.snapshot;
    final alerts = <_AttentionData>[
      if (snapshot.pendingExpenseCount > 0)
        _AttentionData(
          title: 'sales_rep_home_pending_expenses'.tr,
          detail: 'sales_rep_home_pending_expenses_detail'.tr,
          badge: snapshot.pendingExpenseCount.toString(),
          icon: Icons.pending_actions_outlined,
          color: scheme.secondary,
          onTap: controller.openExpenses,
        ),
      if (snapshot.totalReceivables > 0)
        _AttentionData(
          title: 'sales_rep_home_receivables_attention'.tr,
          detail: 'sales_rep_home_receivables_detail'.tr,
          badge: currency.format(snapshot.totalReceivables),
          icon: Icons.account_balance_outlined,
          color: scheme.secondary,
          onTap: controller.openReceivables,
        ),
      if (snapshot.repCashOutstanding > 0)
        _AttentionData(
          title: 'sales_rep_home_cash_attention'.tr,
          detail: 'sales_rep_home_cash_attention_detail'.tr,
          badge: currency.format(snapshot.repCashOutstanding),
          icon: Icons.account_balance_wallet_outlined,
          color: scheme.primary,
          onTap: controller.openCash,
        ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SalesRepSectionTitle(title: 'sales_rep_home_needs_attention'.tr),
        SalesRepDashboardSurface(
          padding: EdgeInsets.zero,
          child: alerts.isEmpty
              ? const _AllGoodRow()
              : Column(
                  children: [
                    for (var index = 0; index < alerts.length; index++) ...[
                      _AttentionRow(data: alerts[index]),
                      if (index < alerts.length - 1)
                        Divider(
                          height: 1,
                          indent: 64,
                          color: context.appBorder,
                        ),
                    ],
                  ],
                ),
        ),
      ],
    );
  }
}

class _AttentionRow extends StatelessWidget {
  const _AttentionRow({required this.data});

  final _AttentionData data;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: data.onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.all(13),
          child: Row(
            children: [
              SalesRepIconBox(icon: data.icon, color: data.color, size: 40),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      data.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: context.appText,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      data.detail,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: context.appMutedText,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                constraints: const BoxConstraints(maxWidth: 112),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                decoration: BoxDecoration(
                  color: data.color.withValues(alpha: 0.11),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  data.badge,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: data.color,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: context.appMutedText,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AllGoodRow extends StatelessWidget {
  const _AllGoodRow();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(14),
    child: Row(
      children: [
        SalesRepIconBox(
          icon: Icons.check_circle_outline_rounded,
          color: Theme.of(context).colorScheme.tertiary,
          size: 40,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'sales_rep_home_all_good'.tr,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: context.appText,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                'sales_rep_home_all_good_detail'.tr,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: context.appMutedText),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class SalesRepRecentActivityPanel extends StatelessWidget {
  const SalesRepRecentActivityPanel({super.key, required this.controller});

  final SalesRepDashboardController controller;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final activities = [
      ...controller.snapshot.recentInvoices.map(
        (invoice) => _ActivityData(
          date: invoice.invoiceDate,
          title: 'sales_rep_home_invoice_created'.tr,
          detail:
              '${invoice.customerSnapshot?.name ?? invoice.customerId} · '
              '${invoice.invoiceNumber}',
          amount: invoice.grandTotal,
          icon: Icons.receipt_long_outlined,
          color: scheme.primary,
          onTap: controller.openInvoices,
        ),
      ),
      ...controller.snapshot.recentReceipts.map(
        (receipt) => _ActivityData(
          date: receipt.receiptDate,
          title: 'sales_rep_home_payment_recorded'.tr,
          detail: '${receipt.customerSnapshot.name} · ${receipt.receiptNumber}',
          amount: receipt.amount,
          icon: Icons.payments_outlined,
          color: scheme.tertiary,
          onTap: controller.openReceipts,
        ),
      ),
    ]..sort((a, b) => b.date.compareTo(a.date));
    final visible = activities.take(5).toList(growable: false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SalesRepSectionTitle(title: 'sales_rep_home_recent_activity'.tr),
        SalesRepDashboardSurface(
          padding: EdgeInsets.zero,
          child: visible.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(18),
                  child: Text(
                    'sales_rep_home_no_activity'.tr,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: context.appMutedText,
                    ),
                  ),
                )
              : Column(
                  children: [
                    for (var index = 0; index < visible.length; index++) ...[
                      _ActivityRow(data: visible[index]),
                      if (index < visible.length - 1)
                        Divider(
                          height: 1,
                          indent: 62,
                          color: context.appBorder,
                        ),
                    ],
                  ],
                ),
        ),
      ],
    );
  }
}

class _ActivityRow extends StatelessWidget {
  const _ActivityRow({required this.data});

  final _ActivityData data;

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(symbol: 'JOD ', decimalDigits: 3);
    final locale = Get.locale?.toLanguageTag();
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: data.onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
          child: Row(
            children: [
              SalesRepIconBox(icon: data.icon, color: data.color, size: 38),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      data.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: context.appText,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      data.detail,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: context.appMutedText,
                      ),
                    ),
                    Text(
                      DateFormat.yMd(locale).add_jm().format(data.date),
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: context.appMutedText,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 105),
                child: Text(
                  currency.format(data.amount),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: context.appText,
                    fontWeight: FontWeight.w800,
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

class _AttentionData {
  const _AttentionData({
    required this.title,
    required this.detail,
    required this.badge,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final String title;
  final String detail;
  final String badge;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
}

class _ActivityData {
  const _ActivityData({
    required this.date,
    required this.title,
    required this.detail,
    required this.amount,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final DateTime date;
  final String title;
  final String detail;
  final double amount;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
}
