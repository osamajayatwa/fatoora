import 'package:fatoora/core/class/handilingdataview.dart';
import 'package:fatoora/core/constants/color.dart';
import 'package:fatoora/features/admin_dashboard/view/widgets/dashboard_card.dart';
import 'package:fatoora/features/customers/view/widgets/customer_picker_sheet.dart';
import 'package:fatoora/features/invoices/view/widgets/customer_snapshot_card.dart';
import 'package:fatoora/features/invoices/view/widgets/invoice_items_table.dart';
import 'package:fatoora/features/invoices/view/widgets/invoice_totals_card.dart';
import 'package:fatoora/features/invoices/view/widgets/item_picker_sheet.dart';
import 'package:fatoora/features/quotations/controllers/quotation_form_controller.dart';
import 'package:fatoora/features/shared/business/business_shell.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart' hide TextDirection;

class QuotationFormScreen extends StatelessWidget {
  const QuotationFormScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return GetBuilder<QuotationFormController>(
      builder: (controller) => BusinessShell(
        title: controller.isCreateMode
            ? 'create_quotation'.tr
            : 'edit_quotation'.tr,
        showBackButton: true,
        onBack: controller.requestBack,
        child: HandilingDataView(
          statusrequest: controller.statusRequest,
          errorMessage: controller.loadErrorMessageKey.tr,
          retryLabel: 'items_retry'.tr,
          onRetry: controller.initialize,
          widget: _FormBody(controller: controller),
        ),
      ),
    );
  }
}

class _FormBody extends StatelessWidget {
  const _FormBody({required this.controller});

  final QuotationFormController controller;

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
                const SizedBox(height: 18),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final wide = constraints.maxWidth >= 980;
                    final left = _MainColumn(controller: controller);
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

  final QuotationFormController controller;

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
            controller.isCreateMode
                ? 'create_quotation'.tr
                : 'edit_quotation'.tr,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              color: AppColor.secondaryColor,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ],
    );
  }
}

class _MainColumn extends StatelessWidget {
  const _MainColumn({required this.controller});

  final QuotationFormController controller;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _DetailsCard(controller: controller),
        const SizedBox(height: 18),
        CustomerSnapshotCard(
          customer: controller.customerSnapshot,
          onSelect: () async {
            final customer = await showCustomerPicker(context);
            if (customer != null) controller.selectCustomer(customer);
          },
          readOnly: controller.readOnly,
        ),
        const SizedBox(height: 18),
        _AddItemCard(controller: controller),
        const SizedBox(height: 18),
        InvoiceItemsTable(
          items: controller.invoiceItems,
          editable: !controller.readOnly,
          onUpdateItem: controller.updateItem,
          onRemoveItem: controller.removeItem,
        ),
        const SizedBox(height: 18),
        _TextCard(
          controller: controller.notesController,
          labelKey: 'notes',
          readOnly: controller.readOnly,
        ),
        const SizedBox(height: 18),
        _TextCard(
          controller: controller.termsController,
          labelKey: 'terms',
          readOnly: controller.readOnly,
        ),
      ],
    );
  }
}

class _SideColumn extends StatelessWidget {
  const _SideColumn({required this.controller});

  final QuotationFormController controller;

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
        DashboardCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              OutlinedButton.icon(
                onPressed: controller.isSaving ? null : controller.saveDraft,
                icon: controller.isSaving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save_outlined),
                label: Text('save_draft'.tr),
              ),
              const SizedBox(height: 10),
              Text(
                'quotation_has_no_financial_effect'.tr,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: AppColor.grey),
              ),
              const SizedBox(height: 10),
              TextButton.icon(
                onPressed: controller.requestBack,
                icon: const Icon(Icons.close_rounded),
                label: Text('dashboard_cancel'.tr),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DetailsCard extends StatelessWidget {
  const _DetailsCard({required this.controller});

  final QuotationFormController controller;

  @override
  Widget build(BuildContext context) {
    return DashboardCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'quotation_details'.tr,
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
                  controller: controller.quotationNumberController,
                  readOnly: true,
                  decoration: InputDecoration(
                    labelText: 'quotation_number'.tr,
                    prefixIcon: const Icon(Icons.tag_rounded),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
              SizedBox(
                width: 250,
                child: OutlinedButton.icon(
                  onPressed: controller.readOnly
                      ? null
                      : () async {
                          final selected = await showDatePicker(
                            context: context,
                            initialDate: controller.quotationDate,
                            firstDate: DateTime(2020),
                            lastDate: DateTime(DateTime.now().year + 2),
                          );
                          if (selected != null) {
                            controller.setQuotationDate(selected);
                          }
                        },
                  icon: const Icon(Icons.calendar_today_outlined, size: 18),
                  label: Text(
                    '${'quotation_date'.tr}: ${DateFormat.yMMMd().format(controller.quotationDate)}',
                  ),
                ),
              ),
              SizedBox(
                width: 250,
                child: OutlinedButton.icon(
                  onPressed: controller.readOnly
                      ? null
                      : () async {
                          final selected = await showDatePicker(
                            context: context,
                            initialDate: controller.validUntil,
                            firstDate: DateTime(2020),
                            lastDate: DateTime(DateTime.now().year + 2),
                          );
                          if (selected != null) {
                            controller.setValidUntil(selected);
                          }
                        },
                  icon: const Icon(Icons.event_available_outlined, size: 18),
                  label: Text(
                    '${'valid_until'.tr}: ${DateFormat.yMMMd().format(controller.validUntil)}',
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

  final QuotationFormController controller;

  @override
  Widget build(BuildContext context) {
    if (controller.readOnly) return const SizedBox.shrink();
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
              FilledButton.icon(
                onPressed: () async {
                  final item = await showInvoiceItemPicker(context);
                  if (item != null) controller.addCatalogItem(item);
                },
                style: FilledButton.styleFrom(
                  backgroundColor: AppColor.primaryColor,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 16,
                  ),
                ),
                icon: const Icon(Icons.inventory_2_outlined),
                label: Text('select_item'.tr),
              ),
              Text(
                'invoice_items_catalog_only'.tr,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: AppColor.grey),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TextCard extends StatelessWidget {
  const _TextCard({
    required this.controller,
    required this.labelKey,
    required this.readOnly,
  });

  final TextEditingController controller;
  final String labelKey;
  final bool readOnly;

  @override
  Widget build(BuildContext context) {
    return DashboardCard(
      child: TextFormField(
        controller: controller,
        readOnly: readOnly,
        minLines: 3,
        maxLines: 6,
        decoration: InputDecoration(
          labelText: labelKey.tr,
          alignLabelWithHint: true,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
    );
  }
}
