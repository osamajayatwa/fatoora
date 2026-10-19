import 'dart:ui' as ui;

import 'package:fatoora/core/class/handilingdataview.dart';
import 'package:fatoora/core/constants/color.dart';
import 'package:fatoora/core/motion/fatoora_motion_widgets.dart';
import 'package:fatoora/features/customers/view/widgets/customer_list_components.dart';
import 'package:fatoora/features/receipts/controllers/receipt_details_controller.dart';
import 'package:fatoora/features/receipts/data/models/receipt_model.dart';
import 'package:fatoora/features/receipts/view/widgets/receipt_presentation.dart';
import 'package:fatoora/features/shared/business/business_shell.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

class ReceiptDetailsScreen extends StatelessWidget {
  const ReceiptDetailsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return GetBuilder<ReceiptDetailsController>(
      builder: (controller) => BusinessShell(
        title: 'receipt_details'.tr,
        showBackButton: true,
        child: HandilingDataView(
          statusrequest: controller.statusRequest,
          errorMessage: controller.loadErrorMessageKey.tr,
          retryLabel: 'items_retry'.tr,
          onRetry: controller.loadReceipt,
          widget: controller.receipt == null
              ? const SizedBox.shrink()
              : _ReceiptDetails(
                  controller: controller,
                  receipt: controller.receipt!,
                ),
        ),
      ),
    );
  }
}

class _ReceiptDetails extends StatelessWidget {
  const _ReceiptDetails({required this.controller, required this.receipt});

  final ReceiptDetailsController controller;
  final ReceiptModel receipt;

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(symbol: 'JOD ', decimalDigits: 3);
    final allocations = receiptAllocationRows(receipt);
    final cashKey = receiptCashDestinationKey(receipt);
    final padding = MediaQuery.sizeOf(context).width < 600 ? 14.0 : 24.0;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(padding, padding, padding, 96),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 860),
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
                MediaQuery.sizeOf(context).width < 600 ? 16 : 24,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final compact =
                          constraints.maxWidth < 520 ||
                          MediaQuery.textScalerOf(context).scale(1) > 1.3;
                      final leading = IconButton.filledTonal(
                        tooltip: MaterialLocalizations.of(
                          context,
                        ).backButtonTooltip,
                        onPressed: Get.back<void>,
                        icon: Icon(
                          Directionality.of(context) == ui.TextDirection.rtl
                              ? Icons.arrow_forward_rounded
                              : Icons.arrow_back_rounded,
                        ),
                      );
                      final title = Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            receipt.receiptNumber,
                            softWrap: true,
                            style: Theme.of(context).textTheme.headlineSmall
                                ?.copyWith(
                                  color: AppColor.secondaryColor,
                                  fontWeight: FontWeight.w900,
                                ),
                          ),
                          Text(
                            'receipt_details'.tr,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(color: AppColor.grey),
                          ),
                        ],
                      );
                      final pdfButton = OutlinedButton.icon(
                        onPressed: controller.isPrinting
                            ? null
                            : controller.printReceipt,
                        icon: controller.isPrinting
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: FatooraProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.picture_as_pdf_outlined),
                        label: Text('export_pdf'.tr),
                      );
                      if (compact) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                leading,
                                const SizedBox(width: 12),
                                Expanded(child: title),
                              ],
                            ),
                            const SizedBox(height: 12),
                            pdfButton,
                          ],
                        );
                      }
                      return Row(
                        children: [
                          leading,
                          const SizedBox(width: 12),
                          Expanded(child: title),
                          const SizedBox(width: 12),
                          pdfButton,
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 18),
                  ReceiptStatusBadge(receipt: receipt),
                  if (receipt.isCancelled) ...[
                    const SizedBox(height: 8),
                    Text(
                      '${'receipts_cancel_reason'.tr}: ${receipt.cancellationReason}',
                      key: const ValueKey('receipt-cancellation-reason'),
                    ),
                    Text(
                      '${'receipts_cancelled_by'.tr}: ${receipt.cancelledByName}',
                    ),
                    if (receipt.cancelledAt != null)
                      Text(
                        DateFormat.yMd().add_jm().format(receipt.cancelledAt!),
                      ),
                    Text('receipts_cancelled_history'.tr),
                  ],
                  if (controller.canCancel || controller.isCancelling) ...[
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      key: const ValueKey('receipt-cancel-action'),
                      onPressed: controller.isCancelling
                          ? null
                          : controller.requestCancellation,
                      icon: const Icon(Icons.cancel_outlined),
                      label: Text('receipts_cancel_title'.tr),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Text(
                    'receipt_amount'.tr,
                    style: Theme.of(
                      context,
                    ).textTheme.labelMedium?.copyWith(color: AppColor.grey),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    currency.format(receipt.amount),
                    key: const ValueKey('receipt-detail-amount'),
                    softWrap: true,
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      color: AppColor.primaryColor,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const Divider(height: 28),
                  Wrap(
                    spacing: 14,
                    runSpacing: 14,
                    children: [
                      _InfoTile(
                        label: 'customer_name'.tr,
                        value: receipt.customerSnapshot.name,
                        icon: Icons.person_outline,
                      ),
                      _InfoTile(
                        label: 'payment_method'.tr,
                        value: 'payment_method_${receipt.paymentMethod}'.tr,
                        icon: Icons.account_balance_wallet_outlined,
                      ),
                      _InfoTile(
                        label: 'receipt_date'.tr,
                        value: DateFormat.yMd().format(receipt.receiptDate),
                        icon: Icons.calendar_today_outlined,
                      ),
                      if (cashKey != null)
                        _InfoTile(
                          label: 'receipts_cash_destination'.tr,
                          value: cashKey.tr,
                          icon: Icons.account_balance_wallet_outlined,
                        ),
                      if (controller.showSalesRepresentative &&
                          receipt.salesRepName.trim().isNotEmpty)
                        _InfoTile(
                          label: 'sales_rep'.tr,
                          value: receipt.salesRepName,
                          icon: Icons.badge_outlined,
                        ),
                      if (controller.showSalesRepresentative &&
                          receipt.createdByName.trim().isNotEmpty)
                        _InfoTile(
                          label: 'created_by'.tr,
                          value: receipt.createdByName,
                          icon: Icons.verified_user_outlined,
                        ),
                    ],
                  ),
                  if (receipt.resultingCustomerBalance != null) ...[
                    const SizedBox(height: 18),
                    Text(
                      (receipt.isCancelled
                              ? 'receipts_original_balance_after'
                              : 'receipts_balance_after')
                          .tr,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: AppColor.secondaryColor,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: CustomerBalanceBadge(
                        balance: receipt.resultingCustomerBalance!,
                      ),
                    ),
                  ],
                  const SizedBox(height: 22),
                  Text(
                    'receipts_allocation_title'.tr,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: AppColor.secondaryColor,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (allocations.isEmpty)
                    Text('receipts_no_allocation'.tr)
                  else
                    for (final allocation in allocations) ...[
                      _AllocationRow(allocation: allocation, money: currency),
                      const SizedBox(height: 8),
                    ],
                  if (receipt.notes.isNotEmpty) ...[
                    const SizedBox(height: 18),
                    Text(
                      'notes'.tr,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: AppColor.secondaryColor,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(receipt.notes),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AllocationRow extends StatelessWidget {
  const _AllocationRow({required this.allocation, required this.money});

  final ReceiptInvoiceAllocation allocation;
  final NumberFormat money;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: const Color(0xFFF8FAFD),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: const Color(0xFFE4E8EF)),
    ),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final number = allocation.invoiceNumber.isEmpty
            ? allocation.invoiceId
            : allocation.invoiceNumber;
        final title = Text(
          number,
          softWrap: true,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
            color: AppColor.secondaryColor,
            fontWeight: FontWeight.w800,
          ),
        );
        final amount = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'receipts_allocated_from_receipt'.tr,
              style: Theme.of(context).textTheme.labelSmall,
            ),
            Text(
              money.format(allocation.amount),
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: AppColor.primaryColor,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        );
        if (constraints.maxWidth < 480 ||
            MediaQuery.textScalerOf(context).scale(1) > 1.3) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [title, const SizedBox(height: 8), amount],
          );
        }
        return Row(
          children: [
            Expanded(child: title),
            const SizedBox(width: 12),
            amount,
          ],
        );
      },
    ),
  );
}

class _InfoTile extends StatelessWidget {
  const _InfoTile({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: MediaQuery.sizeOf(context).width < 700 ? double.infinity : 250,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFD),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFE4E8EF)),
        ),
        child: Row(
          children: [
            Icon(icon, color: AppColor.primaryColor),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: Theme.of(
                      context,
                    ).textTheme.labelSmall?.copyWith(color: AppColor.grey),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    value.isEmpty ? '-' : value,
                    softWrap: true,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColor.secondaryColor,
                      fontWeight: FontWeight.w800,
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
