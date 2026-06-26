import 'package:fatoora/core/class/handilingdataview.dart';
import 'package:fatoora/core/constants/color.dart';
import 'package:fatoora/core/services/services.dart';
import 'package:fatoora/features/admin_dashboard/view/widgets/dashboard_card.dart';
import 'package:fatoora/features/auth/utils/auth_session.dart';
import 'package:fatoora/features/financial/controllers/sales_rep_dashboard_controller.dart';
import 'package:fatoora/features/invoices/data/models/invoice_model.dart';
import 'package:fatoora/features/receipts/data/models/receipt_model.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final services = Get.find<MyServices>();
    final name = AuthSession.cachedDisplayName(services);

    return GetBuilder<SalesRepDashboardController>(
      builder: (controller) => Scaffold(
        backgroundColor: AppColor.background,
        appBar: AppBar(
          title: Text('home_title'.tr),
          actions: [
            IconButton(
              tooltip: 'dashboard_refresh'.tr,
              onPressed: controller.refreshDashboard,
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
        body: SafeArea(
          child: HandilingDataView(
            statusrequest: controller.statusRequest,
            errorMessage: controller.loadErrorMessageKey.tr,
            retryLabel: 'items_retry'.tr,
            onRetry: controller.loadDashboard,
            widget: RefreshIndicator(
              onRefresh: controller.refreshDashboard,
              color: AppColor.primaryColor,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final padding = constraints.maxWidth < 600 ? 14.0 : 24.0;
                  return SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: EdgeInsets.fromLTRB(padding, padding, padding, 96),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1120),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _WelcomeCard(name: name, controller: controller),
                            const SizedBox(height: 16),
                            _SalesRepStats(controller: controller),
                            const SizedBox(height: 16),
                            _QuickActions(controller: controller),
                            const SizedBox(height: 16),
                            _RecentActivity(controller: controller),
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
      ),
    );
  }
}

class _WelcomeCard extends StatelessWidget {
  const _WelcomeCard({required this.name, required this.controller});

  final String name;
  final SalesRepDashboardController controller;

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(symbol: 'JOD ', decimalDigits: 3);
    return DashboardCard(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 620;
          final title = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'home_welcome_admin'.trParams({'name': name}),
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: AppColor.secondaryColor,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                'financial_sales_rep_summary'.tr,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: AppColor.grey),
              ),
            ],
          );
          final cash = _HighlightAmount(
            labelKey: 'financial_cash_in_hand',
            value: currency.format(controller.snapshot.cashInHand),
          );
          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [title, const SizedBox(height: 16), cash],
            );
          }
          return Row(
            children: [
              Expanded(child: title),
              const SizedBox(width: 18),
              cash,
            ],
          );
        },
      ),
    );
  }
}

class _HighlightAmount extends StatelessWidget {
  const _HighlightAmount({required this.labelKey, required this.value});

  final String labelKey;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          labelKey.tr,
          style: Theme.of(
            context,
          ).textTheme.labelMedium?.copyWith(color: AppColor.grey),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            color: AppColor.primaryColor,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }
}

class _SalesRepStats extends StatelessWidget {
  const _SalesRepStats({required this.controller});

  final SalesRepDashboardController controller;

  @override
  Widget build(BuildContext context) {
    final snapshot = controller.snapshot;
    final currency = NumberFormat.currency(symbol: 'JOD ', decimalDigits: 3);
    final tiles = [
      _StatData(
        'financial_total_sales',
        currency.format(snapshot.totalSales),
        Icons.trending_up_rounded,
        AppColor.secondaryColor,
      ),
      _StatData(
        'financial_cash_sales',
        currency.format(snapshot.cashSales),
        Icons.payments_outlined,
        AppColor.success,
      ),
      _StatData(
        'financial_credit_sales',
        currency.format(snapshot.creditSales),
        Icons.article_outlined,
        AppColor.error,
      ),
      _StatData(
        'financial_partial_sales',
        currency.format(snapshot.partialSales),
        Icons.pie_chart_outline_rounded,
        const Color(0xFFFF9838),
      ),
      _StatData(
        'financial_total_receivables',
        currency.format(snapshot.totalReceivables),
        Icons.account_balance_outlined,
        AppColor.tertiaryColor,
      ),
      _StatData(
        'dashboard_invoices_count',
        snapshot.invoiceCount.toString(),
        Icons.receipt_long_outlined,
        const Color(0xFF35A7FF),
      ),
      _StatData(
        'dashboard_customers_count',
        snapshot.customerCount.toString(),
        Icons.people_alt_outlined,
        const Color(0xFF6657E8),
      ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 900
            ? 4
            : constraints.maxWidth >= 620
            ? 2
            : 1;
        const spacing = 12.0;
        final width =
            (constraints.maxWidth - (columns - 1) * spacing) / columns;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final tile in tiles) _StatTile(width: width, data: tile),
          ],
        );
      },
    );
  }
}

class _QuickActions extends StatelessWidget {
  const _QuickActions({required this.controller});

  final SalesRepDashboardController controller;

  @override
  Widget build(BuildContext context) {
    final actions = [
      _ActionData(
        'dashboard_new_invoice',
        Icons.note_add_outlined,
        controller.createInvoice,
      ),
      _ActionData(
        'dashboard_invoices',
        Icons.receipt_long_outlined,
        controller.openInvoices,
      ),
      _ActionData(
        'sales_returns',
        Icons.assignment_return_outlined,
        controller.openSalesReturns,
      ),
      _ActionData(
        'dashboard_customers',
        Icons.people_alt_outlined,
        controller.openCustomers,
      ),
      _ActionData(
        'financial_receivables',
        Icons.account_balance_outlined,
        controller.openReceivables,
      ),
      _ActionData(
        'financial_cash',
        Icons.account_balance_wallet_outlined,
        controller.openCash,
      ),
    ];
    return DashboardCard(
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          for (final action in actions)
            FilledButton.icon(
              onPressed: action.onPressed,
              style: FilledButton.styleFrom(
                backgroundColor: AppColor.primaryColor,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
              ),
              icon: Icon(action.icon),
              label: Text(action.labelKey.tr),
            ),
        ],
      ),
    );
  }
}

class _RecentActivity extends StatelessWidget {
  const _RecentActivity({required this.controller});

  final SalesRepDashboardController controller;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 820) {
          return Column(
            children: [
              _RecentInvoices(invoices: controller.snapshot.recentInvoices),
              const SizedBox(height: 16),
              _RecentReceipts(receipts: controller.snapshot.recentReceipts),
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _RecentInvoices(
                invoices: controller.snapshot.recentInvoices,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _RecentReceipts(
                receipts: controller.snapshot.recentReceipts,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _RecentInvoices extends StatelessWidget {
  const _RecentInvoices({required this.invoices});

  final List<InvoiceModel> invoices;

  @override
  Widget build(BuildContext context) {
    return DashboardCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'dashboard_latest_invoices'.tr,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: AppColor.secondaryColor,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 10),
          if (invoices.isEmpty)
            Text('dashboard_no_invoice_results'.tr)
          else
            for (final invoice in invoices) _InvoiceLine(invoice: invoice),
        ],
      ),
    );
  }
}

class _RecentReceipts extends StatelessWidget {
  const _RecentReceipts({required this.receipts});

  final List<ReceiptModel> receipts;

  @override
  Widget build(BuildContext context) {
    return DashboardCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'financial_recent_receipts'.tr,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: AppColor.secondaryColor,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 10),
          if (receipts.isEmpty)
            Text('financial_no_receipts'.tr)
          else
            for (final receipt in receipts) _ReceiptLine(receipt: receipt),
        ],
      ),
    );
  }
}

class _InvoiceLine extends StatelessWidget {
  const _InvoiceLine({required this.invoice});

  final InvoiceModel invoice;

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(symbol: 'JOD ', decimalDigits: 3);
    return _ActivityLine(
      icon: Icons.receipt_long_outlined,
      title: invoice.customerSnapshot?.name ?? invoice.customerId,
      subtitle: invoice.invoiceNumber,
      amount: currency.format(invoice.grandTotal),
    );
  }
}

class _ReceiptLine extends StatelessWidget {
  const _ReceiptLine({required this.receipt});

  final ReceiptModel receipt;

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(symbol: 'JOD ', decimalDigits: 3);
    return _ActivityLine(
      icon: Icons.payments_outlined,
      title: receipt.customerSnapshot.name,
      subtitle: receipt.receiptNumber,
      amount: currency.format(receipt.amount),
    );
  }
}

class _ActivityLine extends StatelessWidget {
  const _ActivityLine({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.amount,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String amount;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, color: AppColor.primaryColor),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColor.secondaryColor,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  subtitle,
                  style: Theme.of(
                    context,
                  ).textTheme.labelSmall?.copyWith(color: AppColor.grey),
                ),
              ],
            ),
          ),
          Text(
            amount,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: AppColor.secondaryColor,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.width, required this.data});

  final double width;
  final _StatData data;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: DashboardCard(
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: data.color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(data.icon, color: data.color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    data.titleKey.tr,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(
                      context,
                    ).textTheme.labelMedium?.copyWith(color: AppColor.grey),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    data.value,
                    maxLines: 1,
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
      ),
    );
  }
}

class _StatData {
  const _StatData(this.titleKey, this.value, this.icon, this.color);

  final String titleKey;
  final String value;
  final IconData icon;
  final Color color;
}

class _ActionData {
  const _ActionData(this.labelKey, this.icon, this.onPressed);

  final String labelKey;
  final IconData icon;
  final VoidCallback onPressed;
}
