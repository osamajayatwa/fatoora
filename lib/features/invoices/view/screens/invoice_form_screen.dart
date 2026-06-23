import 'package:fatoora/core/class/handilingdataview.dart';
import 'package:fatoora/core/constant/app_feature_flags.dart';
import 'package:fatoora/core/constant/color.dart';
import 'package:fatoora/features/invoices/controllers/invoice_form_controller.dart';
import 'package:fatoora/features/invoices/data/models/invoice_enums.dart';
import 'package:fatoora/features/invoices/view/widgets/customer_snapshot_card.dart';
import 'package:fatoora/features/invoices/view/widgets/invoice_items_table.dart';
import 'package:fatoora/features/invoices/view/widgets/invoice_totals_card.dart';
import 'package:fatoora/features/invoices/view/widgets/invoice_type_chip.dart';
import 'package:fatoora/features/invoices/view/widgets/locked_electronic_invoice_banner.dart';
import 'package:fatoora/modules/admin_dashboard/view/widgets/admin_dashboard_shell.dart';
import 'package:fatoora/modules/admin_dashboard/view/widgets/dashboard_card.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart' hide TextDirection;

class InvoiceFormScreen extends StatelessWidget {
  const InvoiceFormScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return GetBuilder<InvoiceFormController>(
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
            onRetry: controller.initialize,
            widget: _InvoiceFormPage(controller: controller),
          ),
        ),
      ),
    );
  }
}

class _InvoiceFormPage extends StatelessWidget {
  const _InvoiceFormPage({required this.controller});

  final InvoiceFormController controller;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: EdgeInsets.all(MediaQuery.sizeOf(context).width < 600 ? 14 : 24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1320),
          child: Form(
            key: controller.formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Header(controller: controller),
                if (controller.readOnly) ...[
                  const SizedBox(height: 14),
                  const LockedElectronicInvoiceBanner(),
                ],
                const SizedBox(height: 18),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final wide = constraints.maxWidth >= 980;
                    final left = _MainFormColumn(controller: controller);
                    final right = _SideColumn(controller: controller);
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
                const SizedBox(height: 22),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.controller});

  final InvoiceFormController controller;

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
          child: Text(
            controller.readOnly
                ? 'invoice_details'.tr
                : controller.isCreateMode
                ? 'create_invoice'.tr
                : 'edit_invoice'.tr,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              color: AppColor.secondaryColor,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        InvoiceTypeChip(type: controller.invoiceType),
      ],
    );
  }
}

class _MainFormColumn extends StatelessWidget {
  const _MainFormColumn({required this.controller});

  final InvoiceFormController controller;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _InvoiceDetailsCard(controller: controller),
        const SizedBox(height: 18),
        CustomerSnapshotCard(
          customer: controller.customerSnapshot,
          onSelect: controller.selectCustomerPlaceholder,
          readOnly: controller.readOnly,
        ),
        const SizedBox(height: 18),
        if (!controller.readOnly) ...[
          _AddItemCard(controller: controller),
          const SizedBox(height: 18),
        ],
        InvoiceItemsTable(
          items: controller.items,
          editable: !controller.readOnly,
          onUpdateItem: controller.updateItem,
          onRemoveItem: controller.removeItem,
        ),
        const SizedBox(height: 18),
        _NotesCard(controller: controller),
      ],
    );
  }
}

class _SideColumn extends StatelessWidget {
  const _SideColumn({required this.controller});

  final InvoiceFormController controller;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InvoiceTotalsCard(
          subtotal: controller.subtotal,
          totalDiscount: controller.totalDiscount,
          totalTax: controller.totalTax,
          grandTotal: controller.grandTotal,
        ),
        const SizedBox(height: 18),
        _ActionCard(controller: controller),
      ],
    );
  }
}

class _InvoiceDetailsCard extends StatelessWidget {
  const _InvoiceDetailsCard({required this.controller});

  final InvoiceFormController controller;

  @override
  Widget build(BuildContext context) {
    return DashboardCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'invoice_details'.tr,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: AppColor.secondaryColor,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 14,
            runSpacing: 14,
            children: [
              SizedBox(
                width: 260,
                child: TextFormField(
                  controller: controller.invoiceNumberController,
                  readOnly: controller.readOnly,
                  decoration: InputDecoration(
                    labelText: 'invoice_number'.tr,
                    prefixIcon: const Icon(Icons.tag_rounded),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'invoice_number_required'.tr
                      : null,
                ),
              ),
              SizedBox(
                width: 240,
                child: OutlinedButton.icon(
                  onPressed: controller.readOnly
                      ? null
                      : () async {
                          final selected = await showDatePicker(
                            context: context,
                            initialDate: controller.invoiceDate,
                            firstDate: DateTime(2020),
                            lastDate: DateTime(DateTime.now().year + 2),
                          );
                          if (selected != null) {
                            controller.setInvoiceDate(selected);
                          }
                        },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColor.secondaryColor,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 18,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  icon: const Icon(Icons.calendar_today_outlined, size: 18),
                  label: Text(
                    DateFormat.yMMMd().format(controller.invoiceDate),
                  ),
                ),
              ),
              SizedBox(
                width: 260,
                child: TextFormField(
                  controller: controller.paymentMethodController,
                  readOnly: controller.readOnly,
                  decoration: InputDecoration(
                    labelText: 'payment_method'.tr,
                    prefixIcon: const Icon(Icons.payments_outlined),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AddItemCard extends StatelessWidget {
  const _AddItemCard({required this.controller});

  final InvoiceFormController controller;

  @override
  Widget build(BuildContext context) {
    return DashboardCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'add_item'.tr,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: AppColor.secondaryColor,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _Input(
                controller: controller.itemNameController,
                label: 'item_name'.tr,
                width: 230,
              ),
              _Input(
                controller: controller.itemCodeController,
                label: 'items_code'.tr,
                width: 150,
              ),
              _Input(
                controller: controller.itemUnitController,
                label: 'items_unit'.tr,
                width: 120,
              ),
              _Input(
                controller: controller.itemQuantityController,
                label: 'quantity'.tr,
                width: 120,
                number: true,
              ),
              _Input(
                controller: controller.itemPriceController,
                label: 'unit_price'.tr,
                width: 140,
                number: true,
              ),
              _Input(
                controller: controller.itemDiscountController,
                label: 'discount'.tr,
                width: 130,
                number: true,
              ),
              _Input(
                controller: controller.itemTaxController,
                label: 'tax'.tr,
                width: 120,
                number: true,
              ),
              FilledButton.icon(
                onPressed: controller.addItemFromInputs,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColor.primaryColor,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 16,
                  ),
                ),
                icon: const Icon(Icons.add_rounded),
                label: Text('add_item'.tr),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _NotesCard extends StatelessWidget {
  const _NotesCard({required this.controller});

  final InvoiceFormController controller;

  @override
  Widget build(BuildContext context) {
    return DashboardCard(
      child: TextFormField(
        controller: controller.notesController,
        readOnly: controller.readOnly,
        minLines: 3,
        maxLines: 6,
        decoration: InputDecoration(
          labelText: 'notes'.tr,
          alignLabelWithHint: true,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({required this.controller});

  final InvoiceFormController controller;

  @override
  Widget build(BuildContext context) {
    return DashboardCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!controller.readOnly) ...[
            OutlinedButton.icon(
              onPressed: controller.isSaving ? null : controller.saveDraft,
              icon: const Icon(Icons.save_outlined),
              label: Text('save_draft'.tr),
            ),
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: controller.isSaving ? null : controller.saveInvoice,
              style: FilledButton.styleFrom(
                backgroundColor: AppColor.primaryColor,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              icon: controller.isSaving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColor.surface,
                      ),
                    )
                  : const Icon(Icons.check_rounded),
              label: Text('save_invoice'.tr),
            ),
            if (controller.invoiceType == InvoiceType.electronic &&
                AppFeatureFlags.jofotaraEnabled) ...[
              const SizedBox(height: 10),
              FilledButton.icon(
                onPressed: controller.canSubmitElectronic
                    ? controller.saveAndSubmit
                    : null,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColor.secondaryColor,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                icon: const Icon(Icons.cloud_upload_outlined),
                label: Text('save_and_submit'.tr),
              ),
            ],
            const SizedBox(height: 10),
          ],
          TextButton.icon(
            onPressed: controller.requestBack,
            icon: const Icon(Icons.close_rounded),
            label: Text('dashboard_cancel'.tr),
          ),
        ],
      ),
    );
  }
}

class _Input extends StatelessWidget {
  const _Input({
    required this.controller,
    required this.label,
    required this.width,
    this.number = false,
  });

  final TextEditingController controller;
  final String label;
  final double width;
  final bool number;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: TextFormField(
        controller: controller,
        keyboardType: number
            ? const TextInputType.numberWithOptions(decimal: true)
            : TextInputType.text,
        decoration: InputDecoration(
          labelText: label,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
    );
  }
}
