import 'package:fatoora/core/constants/color.dart';
import 'package:fatoora/app/routes/app_routes.dart';
import 'package:fatoora/features/admin_dashboard/controller/admin_dashboard_controller.dart';
import 'package:fatoora/features/admin_dashboard/model/admin_dashboard_models.dart';
import 'package:fatoora/features/admin_dashboard/view/widgets/dashboard_card.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class LatestInvoicesCard extends StatelessWidget {
  const LatestInvoicesCard({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<AdminDashboardController>();
    return DashboardCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DashboardSectionTitle(
            titleKey: 'dashboard_latest_invoices',
            trailing: TextButton(
              onPressed: () => controller.navigateTo(AppRoute.invoices),
              child: Text('dashboard_view_all'.tr),
            ),
          ),
          const SizedBox(height: 12),
          GetBuilder<AdminDashboardController>(
            id: 'invoices',
            builder: (controller) {
              final invoices = controller.visibleInvoices;
              if (invoices.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 60),
                  child: Column(
                    children: [
                      const Icon(
                        Icons.search_off_rounded,
                        size: 42,
                        color: AppColor.grey,
                      ),
                      const SizedBox(height: 10),
                      Text('dashboard_no_invoice_results'.tr),
                    ],
                  ),
                );
              }
              return Column(
                children: [
                  for (var index = 0; index < invoices.length; index++) ...[
                    _InvoiceRow(invoice: invoices[index]),
                    if (index != invoices.length - 1)
                      const Divider(height: 1, color: Color(0xFFF0F1F5)),
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _InvoiceRow extends StatelessWidget {
  const _InvoiceRow({required this.invoice});

  final DashboardInvoice invoice;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: AppColor.primaryLight.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.receipt_long_outlined,
              color: AppColor.primaryColor,
              size: 21,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  invoice.customer,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColor.secondaryColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  invoice.number,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: AppColor.grey),
                ),
              ],
            ),
          ),
          if (MediaQuery.sizeOf(context).width > 410)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 8),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: invoice.statusColor.withValues(alpha: 0.11),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                invoice.statusKey.tr,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: invoice.statusColor,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          Expanded(
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  invoice.amount,
                  maxLines: 1,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFF17213B),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  'dashboard_jod'.tr,
                  style: Theme.of(
                    context,
                  ).textTheme.labelSmall?.copyWith(color: AppColor.grey),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
