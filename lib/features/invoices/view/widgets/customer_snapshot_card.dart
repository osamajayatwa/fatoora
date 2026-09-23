import 'package:fatoora/core/constants/color.dart';
import 'package:fatoora/features/invoices/data/models/invoice_customer_snapshot.dart';
import 'package:fatoora/features/admin_dashboard/view/widgets/dashboard_card.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class CustomerSnapshotCard extends StatelessWidget {
  const CustomerSnapshotCard({
    super.key,
    required this.customer,
    this.onSelect,
    this.readOnly = false,
  });

  final InvoiceCustomerSnapshot? customer;
  final VoidCallback? onSelect;
  final bool readOnly;

  @override
  Widget build(BuildContext context) {
    return DashboardCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final compact =
                  constraints.maxWidth < 330 ||
                  MediaQuery.textScalerOf(context).scale(1) > 1.3;
              final title = Text(
                'customer_snapshot'.tr,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: AppColor.secondaryColor,
                  fontWeight: FontWeight.w800,
                ),
              );
              final action = OutlinedButton.icon(
                onPressed: onSelect,
                icon: const Icon(Icons.person_search_outlined, size: 18),
                label: Text('select_customer'.tr),
              );
              if (compact) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    title,
                    if (!readOnly) ...[const SizedBox(height: 10), action],
                  ],
                );
              }
              return Row(
                children: [
                  Expanded(child: title),
                  if (!readOnly) action,
                ],
              );
            },
          ),
          const SizedBox(height: 14),
          if (customer == null)
            Text(
              'customer_required'.tr,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: AppColor.grey),
            )
          else ...[
            Text(
              customer!.name,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: AppColor.secondaryColor,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              children: [
                _Info(label: 'Phone'.tr, value: customer!.phone),
                _Info(label: 'city'.tr, value: customer!.city),
                _Info(label: 'tax_number'.tr, value: customer!.taxNumber),
                _Info(
                  label: 'national_number'.tr,
                  value: customer!.nationalNumber,
                ),
                _Info(label: 'address'.tr, value: customer!.address),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _Info extends StatelessWidget {
  const _Info({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    if (value.trim().isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, constraints) => ConstrainedBox(
        constraints: BoxConstraints(maxWidth: constraints.maxWidth),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: const Color(0xFFF4F6FA),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            '$label: $value',
            softWrap: true,
            style: Theme.of(
              context,
            ).textTheme.labelMedium?.copyWith(color: AppColor.secondaryColor),
          ),
        ),
      ),
    );
  }
}
