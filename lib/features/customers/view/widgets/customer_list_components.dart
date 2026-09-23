import 'package:fatoora/core/constants/color.dart';
import 'package:fatoora/features/admin_dashboard/view/widgets/dashboard_card.dart';
import 'package:fatoora/features/customers/data/models/customer_model.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart' hide TextDirection;

enum CustomerBalanceState { due, credit, zero }

CustomerBalanceState customerBalanceState(double balance) {
  if (balance > 0) return CustomerBalanceState.due;
  if (balance < 0) return CustomerBalanceState.credit;
  return CustomerBalanceState.zero;
}

class CustomerBalanceBadge extends StatelessWidget {
  const CustomerBalanceBadge({
    super.key,
    required this.balance,
    this.compact = false,
  });

  final double balance;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final state = customerBalanceState(balance);
    final amount = NumberFormat.currency(
      symbol: 'JOD ',
      decimalDigits: 3,
    ).format(balance.abs());
    final (label, color, icon) = switch (state) {
      CustomerBalanceState.due => (
        'customers_balance_due'.trParams({'amount': amount}),
        AppColor.error,
        Icons.schedule_rounded,
      ),
      CustomerBalanceState.credit => (
        'customers_balance_credit'.trParams({'amount': amount}),
        const Color(0xFF227A63),
        Icons.savings_outlined,
      ),
      CustomerBalanceState.zero => (
        'customers_balance_zero'.tr,
        context.appMutedText,
        Icons.check_circle_outline_rounded,
      ),
    };
    return Container(
      key: ValueKey('customer-balance-${state.name}'),
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 10,
        vertical: compact ? 5 : 7,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .09),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: .22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: compact ? 13 : 15, color: color),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: color,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class CustomerStatusPill extends StatelessWidget {
  const CustomerStatusPill({super.key, required this.active});

  final bool active;

  @override
  Widget build(BuildContext context) {
    final color = active ? AppColor.success : AppColor.error;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .1),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        active ? 'items_active'.tr : 'items_inactive'.tr,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class CustomerCompactCard extends StatelessWidget {
  const CustomerCompactCard({
    super.key,
    required this.customer,
    required this.onTap,
    required this.showCreator,
  });

  final CustomerModel customer;
  final VoidCallback onTap;
  final bool showCreator;

  @override
  Widget build(BuildContext context) => DashboardCard(
    key: ValueKey('customer-card-${customer.id}'),
    padding: const EdgeInsets.all(14),
    onTap: onTap,
    semanticLabel: customer.name,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                customer.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: context.appText,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            const SizedBox(width: 8),
            CustomerStatusPill(active: customer.active),
          ],
        ),
        if (customer.phone.trim().isNotEmpty) ...[
          const SizedBox(height: 7),
          _CompactInfo(
            icon: Icons.phone_outlined,
            value: customer.phone,
            forceLtr: true,
          ),
        ],
        if (_location.isNotEmpty) ...[
          const SizedBox(height: 5),
          _CompactInfo(icon: Icons.place_outlined, value: _location),
        ],
        const SizedBox(height: 10),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: CustomerBalanceBadge(balance: customer.currentBalance),
              ),
            ),
            if (showCreator && customer.createdByName.trim().isNotEmpty) ...[
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  '${'created_by'.tr}: ${customer.createdByName}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.labelSmall?.copyWith(color: context.appMutedText),
                ),
              ),
            ],
          ],
        ),
      ],
    ),
  );

  String get _location => [
    customer.area.trim(),
    customer.city.trim(),
  ].where((value) => value.isNotEmpty).join(' · ');
}

class _CompactInfo extends StatelessWidget {
  const _CompactInfo({
    required this.icon,
    required this.value,
    this.forceLtr = false,
  });

  final IconData icon;
  final String value;
  final bool forceLtr;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon, size: 15, color: context.appMutedText),
      const SizedBox(width: 7),
      Expanded(
        child: Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textDirection: forceLtr ? TextDirection.ltr : null,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: context.appMutedText),
        ),
      ),
    ],
  );
}
