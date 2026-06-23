import 'package:fatoora/core/constant/color.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class InvoiceActionButtons extends StatelessWidget {
  const InvoiceActionButtons({
    super.key,
    required this.canEdit,
    required this.canDelete,
    required this.onView,
    required this.onEdit,
    required this.onDelete,
    required this.onPrint,
  });

  final bool canEdit;
  final bool canDelete;
  final VoidCallback onView;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onPrint;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: [
        IconButton(
          tooltip: 'invoice_details'.tr,
          onPressed: onView,
          icon: const Icon(Icons.visibility_outlined),
          color: AppColor.secondaryColor,
        ),
        IconButton(
          tooltip: 'edit_invoice'.tr,
          onPressed: canEdit ? onEdit : null,
          icon: const Icon(Icons.edit_outlined),
          color: AppColor.primaryColor,
        ),
        IconButton(
          tooltip: 'delete_invoice'.tr,
          onPressed: canDelete ? onDelete : null,
          icon: const Icon(Icons.delete_outline_rounded),
          color: AppColor.error,
        ),
        IconButton(
          tooltip: 'print_export'.tr,
          onPressed: onPrint,
          icon: const Icon(Icons.print_outlined),
          color: AppColor.grey,
        ),
      ],
    );
  }
}
