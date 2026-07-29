import 'package:fatoora/core/constants/color.dart';
import 'package:fatoora/features/financial/controllers/sales_rep_dashboard_controller.dart';
import 'package:fatoora/features/home/view/widgets/sales_rep_dashboard_primitives.dart';
import 'package:fatoora/features/home/view/widgets/sales_rep_dashboard_layout.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class SalesRepPrimaryActions extends StatelessWidget {
  const SalesRepPrimaryActions({super.key, required this.controller});

  final SalesRepDashboardController controller;

  @override
  Widget build(BuildContext context) {
    final actions = [
      _PrimaryActionData(
        title: 'dashboard_new_invoice'.tr,
        subtitle: 'sales_rep_home_create_invoice_subtitle'.tr,
        icon: Icons.note_add_outlined,
        onTap: controller.createInvoice,
        emphasized: true,
      ),
      _PrimaryActionData(
        title: 'create_receipt'.tr,
        subtitle: 'sales_rep_home_record_payment_subtitle'.tr,
        icon: Icons.add_card_outlined,
        onTap: controller.createReceipt,
      ),
      _PrimaryActionData(
        title: 'sales_rep_home_add_customer'.tr,
        subtitle: 'sales_rep_home_add_customer_subtitle'.tr,
        icon: Icons.person_add_alt_1_outlined,
        onTap: controller.createCustomer,
      ),
      _PrimaryActionData(
        title: 'rep_inventory_my_inventory'.tr,
        subtitle: 'sales_rep_home_inventory_subtitle'.tr,
        icon: Icons.inventory_2_outlined,
        onTap: controller.openMyInventory,
      ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SalesRepSectionTitle(title: 'sales_rep_home_quick_actions'.tr),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = SalesRepDashboardLayout.primaryActionColumns(
              constraints.maxWidth,
            );
            final textScale = MediaQuery.textScalerOf(context).scale(1);
            return GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: actions.length,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: columns,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                mainAxisExtent: SalesRepDashboardLayout.primaryActionHeight(
                  textScale,
                  columns: columns,
                ),
              ),
              itemBuilder: (_, index) =>
                  _PrimaryActionCard(data: actions[index]),
            );
          },
        ),
      ],
    );
  }
}

class _PrimaryActionCard extends StatelessWidget {
  const _PrimaryActionCard({required this.data});

  final _PrimaryActionData data;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SalesRepInteractiveCard(
      onTap: data.onTap,
      semanticLabel: data.title,
      tint: data.emphasized
          ? Color.alphaBlend(
              AppColor.primaryColor.withValues(alpha: 0.075),
              scheme.surface,
            )
          : null,
      borderColor: data.emphasized
          ? AppColor.primaryColor.withValues(alpha: 0.42)
          : null,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final horizontal = constraints.maxWidth >= 260;
          final icon = SalesRepIconBox(
            icon: data.icon,
            color: data.emphasized ? AppColor.primaryColor : scheme.secondary,
            size: 46,
          );
          final arrow = _ActionArrow(emphasized: data.emphasized);
          final label = _PrimaryActionLabel(data: data);
          if (horizontal) {
            return Row(
              children: [
                icon,
                const SizedBox(width: 13),
                Expanded(child: label),
                const SizedBox(width: 8),
                arrow,
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [icon, const Spacer(), arrow]),
              const Spacer(),
              label,
            ],
          );
        },
      ),
    );
  }
}

class _PrimaryActionLabel extends StatelessWidget {
  const _PrimaryActionLabel({required this.data});

  final _PrimaryActionData data;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        data.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
          color: context.appText,
          fontWeight: FontWeight.w800,
        ),
      ),
      const SizedBox(height: 4),
      Text(
        data.subtitle,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(
          context,
        ).textTheme.bodySmall?.copyWith(color: context.appMutedText),
      ),
    ],
  );
}

class _ActionArrow extends StatelessWidget {
  const _ActionArrow({required this.emphasized});

  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final color = emphasized ? AppColor.primaryColor : context.appMutedText;
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(9),
      ),
      alignment: Alignment.center,
      child: Icon(Icons.arrow_forward_rounded, size: 16, color: color),
    );
  }
}

class SalesRepSecondaryServices extends StatelessWidget {
  const SalesRepSecondaryServices({super.key, required this.controller});

  final SalesRepDashboardController controller;

  @override
  Widget build(BuildContext context) {
    final services = [
      _ServiceData(
        'dashboard_invoices'.tr,
        Icons.receipt_long_outlined,
        controller.openInvoices,
      ),
      _ServiceData(
        'dashboard_customers'.tr,
        Icons.people_alt_outlined,
        controller.openCustomers,
      ),
      _ServiceData(
        'dashboard_quotations'.tr,
        Icons.request_quote_outlined,
        controller.openQuotations,
      ),
      _ServiceData(
        'sales_returns'.tr,
        Icons.assignment_return_outlined,
        controller.openSalesReturns,
      ),
      _ServiceData(
        'my_expenses'.tr,
        Icons.request_page_outlined,
        controller.openExpenses,
      ),
      _ServiceData(
        'financial_receivables'.tr,
        Icons.account_balance_outlined,
        controller.openReceivables,
      ),
      _ServiceData(
        'financial_cash'.tr,
        Icons.account_balance_wallet_outlined,
        controller.openCash,
      ),
      _ServiceData(
        'dashboard_account_statement'.tr,
        Icons.article_outlined,
        controller.openStatements,
      ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SalesRepSectionTitle(title: 'sales_rep_home_more_services'.tr),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = SalesRepDashboardLayout.secondaryServiceColumns(
              constraints.maxWidth,
            );
            final textScale = MediaQuery.textScalerOf(context).scale(1);
            return GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: services.length,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: columns,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                mainAxisExtent: SalesRepDashboardLayout.secondaryServiceHeight(
                  textScale,
                ),
              ),
              itemBuilder: (_, index) =>
                  _SecondaryServiceTile(data: services[index]),
            );
          },
        ),
      ],
    );
  }
}

class _SecondaryServiceTile extends StatelessWidget {
  const _SecondaryServiceTile({required this.data});

  final _ServiceData data;

  @override
  Widget build(BuildContext context) {
    return SalesRepInteractiveCard(
      onTap: data.onTap,
      semanticLabel: data.title,
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
      child: Row(
        children: [
          SalesRepIconBox(
            icon: data.icon,
            color: Theme.of(context).colorScheme.secondary,
            size: 38,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              data.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: context.appText,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Icon(
            Icons.chevron_right_rounded,
            size: 18,
            color: context.appMutedText,
          ),
        ],
      ),
    );
  }
}

class _PrimaryActionData {
  const _PrimaryActionData({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
    this.emphasized = false,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;
  final bool emphasized;
}

class _ServiceData {
  const _ServiceData(this.title, this.icon, this.onTap);

  final String title;
  final IconData icon;
  final VoidCallback onTap;
}
