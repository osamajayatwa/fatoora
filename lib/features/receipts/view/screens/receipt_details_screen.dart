import 'dart:ui' as ui;

import 'package:fatoora/core/class/handilingdataview.dart';
import 'package:fatoora/core/constants/color.dart';
import 'package:fatoora/features/receipts/controllers/receipt_details_controller.dart';
import 'package:fatoora/features/receipts/data/models/receipt_model.dart';
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
              : _ReceiptDetails(receipt: controller.receipt!),
        ),
      ),
    );
  }
}

class _ReceiptDetails extends StatelessWidget {
  const _ReceiptDetails({required this.receipt});

  final ReceiptModel receipt;

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(symbol: 'JOD ', decimalDigits: 3);
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
                  Row(
                    children: [
                      IconButton.filledTonal(
                        tooltip: MaterialLocalizations.of(
                          context,
                        ).backButtonTooltip,
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
                              receipt.receiptNumber,
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
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 22),
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
                        label: 'receipt_amount'.tr,
                        value: currency.format(receipt.amount),
                        icon: Icons.payments_outlined,
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
                      _InfoTile(
                        label: 'sales_rep'.tr,
                        value: receipt.salesRepName,
                        icon: Icons.badge_outlined,
                      ),
                      _InfoTile(
                        label: 'created_by'.tr,
                        value: receipt.createdByName,
                        icon: Icons.verified_user_outlined,
                      ),
                    ],
                  ),
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
                    overflow: TextOverflow.ellipsis,
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
