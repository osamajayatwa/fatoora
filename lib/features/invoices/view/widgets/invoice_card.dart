import 'dart:ui' as ui;

import 'package:fatoora/core/constants/color.dart';
import 'package:fatoora/features/invoices/data/models/invoice_model.dart';
import 'package:fatoora/features/invoices/data/models/invoice_enums.dart';
import 'package:fatoora/features/invoices/view/widgets/invoice_actions_menu.dart';
import 'package:fatoora/features/invoices/view/widgets/invoice_status_chip.dart';
import 'package:fatoora/features/invoices/view/widgets/invoice_type_chip.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

class InvoiceCard extends StatelessWidget {
  const InvoiceCard({
    super.key,
    required this.invoice,
    required this.onView,
    required this.onEdit,
    required this.onDelete,
    required this.onPrint,
    this.showSalesRepresentative = false,
  });

  final InvoiceModel invoice;
  final VoidCallback onView;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onPrint;
  final bool showSalesRepresentative;

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(symbol: 'JOD ', decimalDigits: 3);
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: AppColor.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: Color(0xFFE4E8EF)),
      ),
      child: InkWell(
        onTap: onView,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(15, 14, 10, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      invoice.invoiceNumber,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: AppColor.secondaryColor,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  InvoiceActionsMenu(
                    showView: true,
                    showDelete: true,
                    canEdit: invoice.canEdit,
                    canDelete: invoice.canDelete,
                    onView: onView,
                    onEdit: onEdit,
                    onDelete: onDelete,
                    onPrint: onPrint,
                  ),
                ],
              ),
              const SizedBox(height: 5),
              Text(
                invoice.customerSnapshot?.name ?? 'customer_name'.tr,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColor.secondaryColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 10),
              LayoutBuilder(
                builder: (context, constraints) {
                  final total = Text(
                    currency.format(invoice.grandTotal),
                    textDirection: ui.TextDirection.ltr,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: AppColor.primaryColor,
                      fontWeight: FontWeight.w900,
                    ),
                  );
                  final date = _InfoPill(
                    icon: Icons.calendar_today_outlined,
                    label: DateFormat.yMMMd().format(invoice.invoiceDate),
                  );
                  if (constraints.maxWidth < 310 ||
                      MediaQuery.textScalerOf(context).scale(1) > 1.4) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [total, const SizedBox(height: 7), date],
                    );
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(child: total),
                      date,
                    ],
                  );
                },
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  InvoiceStatusChip(status: invoice.invoiceStatus),
                  InvoicePaymentStatusChip(status: invoice.paymentStatus),
                  InvoiceTypeChip(type: invoice.invoiceType),
                  if (invoice.returnStatus != InvoiceReturnStatus.none)
                    InvoiceReturnStatusChip(status: invoice.returnStatus),
                  if (showSalesRepresentative &&
                      invoice.salesRepName.trim().isNotEmpty)
                    _InfoPill(
                      icon: Icons.badge_outlined,
                      label: invoice.salesRepName,
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoPill extends StatelessWidget {
  const _InfoPill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFF4F6FA),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppColor.grey),
          const SizedBox(width: 6),
          Flexible(
            child: Text(label, style: Theme.of(context).textTheme.labelSmall),
          ),
        ],
      ),
    );
  }
}
