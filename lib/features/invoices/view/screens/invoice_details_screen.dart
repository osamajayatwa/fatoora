import 'package:fatoora/core/class/handilingdataview.dart';
import 'package:fatoora/core/constant/color.dart';
import 'package:fatoora/features/invoices/controllers/invoice_details_controller.dart';
import 'package:fatoora/features/invoices/data/models/invoice_model.dart';
import 'package:fatoora/features/invoices/view/widgets/customer_snapshot_card.dart';
import 'package:fatoora/features/invoices/view/widgets/invoice_items_table.dart';
import 'package:fatoora/features/invoices/view/widgets/invoice_status_chip.dart';
import 'package:fatoora/features/invoices/view/widgets/invoice_totals_card.dart';
import 'package:fatoora/features/invoices/view/widgets/invoice_type_chip.dart';
import 'package:fatoora/features/invoices/view/widgets/locked_electronic_invoice_banner.dart';
import 'package:fatoora/modules/admin_dashboard/view/widgets/admin_dashboard_shell.dart';
import 'package:fatoora/modules/admin_dashboard/view/widgets/dashboard_card.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart' hide TextDirection;

class InvoiceDetailsScreen extends StatelessWidget {
  const InvoiceDetailsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return GetBuilder<InvoiceDetailsController>(
      builder: (controller) => PopScope(
        canPop: controller.allowPop,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) controller.requestBack();
        },
        child: AdminDashboardShell(
          child: HandilingDataView(
            statusrequest: controller.statusRequest,
            errorMessage: controller.loadErrorMessageKey.tr,
            retryLabel: 'items_retry'.tr,
            onRetry: controller.loadInvoice,
            widget: controller.invoice == null
                ? const SizedBox.shrink()
                : _DetailsPage(
                    controller: controller,
                    invoice: controller.invoice!,
                  ),
          ),
        ),
      ),
    );
  }
}

class _DetailsPage extends StatelessWidget {
  const _DetailsPage({required this.controller, required this.invoice});

  final InvoiceDetailsController controller;
  final InvoiceModel invoice;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: EdgeInsets.all(MediaQuery.sizeOf(context).width < 600 ? 14 : 24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1320),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Header(controller: controller, invoice: invoice),
              if (invoice.isLocked) ...[
                const SizedBox(height: 14),
                const LockedElectronicInvoiceBanner(),
              ],
              const SizedBox(height: 18),
              LayoutBuilder(
                builder: (context, constraints) {
                  final wide = constraints.maxWidth >= 980;
                  final left = _LeftColumn(invoice: invoice);
                  final right = _RightColumn(
                    controller: controller,
                    invoice: invoice,
                  );
                  if (!wide) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [left, const SizedBox(height: 18), right],
                    );
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: left),
                      const SizedBox(width: 18),
                      SizedBox(width: 360, child: right),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.controller, required this.invoice});

  final InvoiceDetailsController controller;
  final InvoiceModel invoice;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton(
          onPressed: controller.requestBack,
          icon: Icon(
            Directionality.of(context) == TextDirection.rtl
                ? Icons.arrow_forward_rounded
                : Icons.arrow_back_rounded,
          ),
          color: AppColor.secondaryColor,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                invoice.invoiceNumber,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: AppColor.secondaryColor,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                DateFormat.yMMMd().format(invoice.invoiceDate),
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: AppColor.grey),
              ),
            ],
          ),
        ),
        Wrap(
          spacing: 8,
          children: [
            InvoiceTypeChip(type: invoice.invoiceType),
            InvoiceStatusChip(status: invoice.invoiceStatus),
          ],
        ),
      ],
    );
  }
}

class _LeftColumn extends StatelessWidget {
  const _LeftColumn({required this.invoice});

  final InvoiceModel invoice;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CustomerSnapshotCard(
          customer: invoice.customerSnapshot,
          readOnly: true,
        ),
        const SizedBox(height: 18),
        InvoiceItemsTable(
          items: invoice.items,
          editable: false,
          onUpdateItem:
              ({required index, quantity, unitPrice, discount, taxPercent}) {},
          onRemoveItem: (_) {},
        ),
        const SizedBox(height: 18),
        _NotesCard(invoice: invoice),
        if (invoice.government != null) ...[
          const SizedBox(height: 18),
          _GovernmentCard(invoice: invoice),
        ],
      ],
    );
  }
}

class _RightColumn extends StatelessWidget {
  const _RightColumn({required this.controller, required this.invoice});

  final InvoiceDetailsController controller;
  final InvoiceModel invoice;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InvoiceTotalsCard(
          subtotal: invoice.subtotal,
          totalDiscount: invoice.totalDiscount,
          totalTax: invoice.totalTax,
          grandTotal: invoice.grandTotal,
        ),
        const SizedBox(height: 18),
        DashboardCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FilledButton.icon(
                onPressed: controller.canEdit ? controller.editInvoice : null,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColor.primaryColor,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                icon: const Icon(Icons.edit_outlined),
                label: Text('edit_invoice'.tr),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: controller.printOrExportPlaceholder,
                icon: const Icon(Icons.print_outlined),
                label: Text('print_export'.tr),
              ),
              if (controller.canSubmit) ...[
                const SizedBox(height: 10),
                FilledButton.icon(
                  onPressed: controller.isSubmitting
                      ? null
                      : controller.submitElectronicInvoicePlaceholder,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColor.secondaryColor,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  icon: const Icon(Icons.cloud_upload_outlined),
                  label: Text('submit_to_jofotara'.tr),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _NotesCard extends StatelessWidget {
  const _NotesCard({required this.invoice});

  final InvoiceModel invoice;

  @override
  Widget build(BuildContext context) {
    return DashboardCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'notes'.tr,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: AppColor.secondaryColor,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            invoice.notes.isEmpty ? 'items_optional'.tr : invoice.notes,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: AppColor.darkGrey),
          ),
        ],
      ),
    );
  }
}

class _GovernmentCard extends StatelessWidget {
  const _GovernmentCard({required this.invoice});

  final InvoiceModel invoice;

  @override
  Widget build(BuildContext context) {
    final government = invoice.government!;
    return DashboardCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'government_response'.tr,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: AppColor.secondaryColor,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 12),
          _Line(
            label: 'government_invoice_id'.tr,
            value: government.governmentInvoiceId,
          ),
          _Line(label: 'uuid'.tr, value: government.uuid),
          _Line(label: 'jo_fotara_status'.tr, value: government.joFotaraStatus),
          _Line(
            label: 'jo_fotara_error_code'.tr,
            value: government.joFotaraErrorCode,
          ),
          _Line(
            label: 'jo_fotara_error_message'.tr,
            value: government.joFotaraErrorMessage,
          ),
        ],
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    if (value.trim().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 150,
            child: Text(
              label,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: AppColor.grey,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: AppColor.secondaryColor,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
