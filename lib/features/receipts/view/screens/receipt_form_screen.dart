import 'dart:ui' as ui;

import 'package:fatoora/core/constants/color.dart';
import 'package:fatoora/features/receipts/controllers/receipt_form_controller.dart';
import 'package:fatoora/features/shared/business/business_shell.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

class ReceiptFormScreen extends StatelessWidget {
  const ReceiptFormScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return GetBuilder<ReceiptFormController>(
      builder: (controller) => BusinessShell(
        title: 'create_receipt'.tr,
        showBackButton: true,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final padding = constraints.maxWidth < 600 ? 14.0 : 24.0;
            return SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(padding, padding, padding, 96),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 760),
                  child: Card(
                    margin: EdgeInsets.zero,
                    elevation: 0,
                    color: AppColor.surface,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                      side: const BorderSide(color: Color(0xFFE4E8EF)),
                    ),
                    child: Padding(
                      padding: EdgeInsets.all(
                        constraints.maxWidth < 600 ? 16 : 22,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _FormHeader(controller: controller),
                          const SizedBox(height: 20),
                          _CustomerSelector(controller: controller),
                          const SizedBox(height: 16),
                          TextField(
                            controller: controller.amountController,
                            onChanged: controller.onAmountChanged,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: InputDecoration(
                              labelText: 'receipt_amount'.tr,
                              prefixIcon: const Icon(Icons.payments_outlined),
                              border: const OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'receipts_current_balance'.trParams({
                                    'amount':
                                        (controller.customer?.currentBalance ??
                                                0)
                                            .toStringAsFixed(3),
                                  }),
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(color: AppColor.grey),
                                ),
                              ),
                              TextButton.icon(
                                onPressed: controller.useFullBalance,
                                icon: const Icon(Icons.done_all_rounded),
                                label: Text('receipts_pay_full_balance'.tr),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          _PaymentMethodSelector(controller: controller),
                          const SizedBox(height: 16),
                          _ReceiptDateField(controller: controller),
                          const SizedBox(height: 16),
                          TextField(
                            controller: controller.notesController,
                            maxLines: 3,
                            decoration: InputDecoration(
                              labelText: 'notes'.tr,
                              alignLabelWithHint: true,
                              border: const OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 22),
                          FilledButton.icon(
                            onPressed: controller.isSaving
                                ? null
                                : controller.saveReceipt,
                            style: FilledButton.styleFrom(
                              backgroundColor: AppColor.primaryColor,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 18,
                                vertical: 15,
                              ),
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
                                : const Icon(Icons.save_outlined),
                            label: Text('save_receipt'.tr),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _FormHeader extends StatelessWidget {
  const _FormHeader({required this.controller});

  final ReceiptFormController controller;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton.filledTonal(
          tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          onPressed: Get.back<void>,
          icon: Icon(
            Directionality.of(context) == ui.TextDirection.rtl
                ? Icons.arrow_forward_rounded
                : Icons.arrow_back_rounded,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'create_receipt'.tr,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: AppColor.secondaryColor,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'create_receipt_subtitle'.tr,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: AppColor.grey),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CustomerSelector extends StatelessWidget {
  const _CustomerSelector({required this.controller});

  final ReceiptFormController controller;

  @override
  Widget build(BuildContext context) {
    final customer = controller.customer;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => controller.selectCustomer(context),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: 'select_customer'.tr,
          prefixIcon: const Icon(Icons.person_search_outlined),
          border: const OutlineInputBorder(),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                customer == null
                    ? 'receipts_customer_required'.tr
                    : customer.name,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: customer == null
                      ? AppColor.grey
                      : AppColor.secondaryColor,
                  fontWeight: customer == null
                      ? FontWeight.w500
                      : FontWeight.w700,
                ),
              ),
            ),
            const Icon(Icons.keyboard_arrow_down_rounded),
          ],
        ),
      ),
    );
  }
}

class _PaymentMethodSelector extends StatelessWidget {
  const _PaymentMethodSelector({required this.controller});

  final ReceiptFormController controller;

  @override
  Widget build(BuildContext context) {
    return InputDecorator(
      decoration: InputDecoration(
        labelText: 'payment_method'.tr,
        border: const OutlineInputBorder(),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final method in ReceiptFormController.paymentMethods)
            ChoiceChip(
              selected: controller.paymentMethod == method,
              onSelected: (_) => controller.setPaymentMethod(method),
              label: Text('payment_method_$method'.tr),
            ),
        ],
      ),
    );
  }
}

class _ReceiptDateField extends StatelessWidget {
  const _ReceiptDateField({required this.controller});

  final ReceiptFormController controller;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          firstDate: DateTime(2020),
          lastDate: DateTime.now().add(const Duration(days: 365)),
          initialDate: controller.receiptDate,
        );
        if (picked != null) controller.setReceiptDate(picked);
      },
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: 'receipt_date'.tr,
          prefixIcon: const Icon(Icons.calendar_today_outlined),
          border: const OutlineInputBorder(),
        ),
        child: Text(DateFormat.yMd().format(controller.receiptDate)),
      ),
    );
  }
}
