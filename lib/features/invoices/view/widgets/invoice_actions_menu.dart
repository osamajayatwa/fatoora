import 'package:fatoora/core/constants/color.dart';
import 'package:fatoora/core/motion/fatoora_motion.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

enum _InvoiceMenuAction {
  view,
  edit,
  createSalesReturn,
  print,
  delete,
  convertToTaxInvoice,
}

class InvoiceActionsMenu extends StatelessWidget {
  const InvoiceActionsMenu({
    super.key,
    this.compact = true,
    this.showView = false,
    this.showEdit = true,
    this.showCreateSalesReturn = false,
    this.showPrint = true,
    this.showDelete = false,
    this.canEdit = false,
    this.canCreateSalesReturn = false,
    this.canPrint = true,
    this.canDelete = false,
    this.onView,
    this.onEdit,
    this.onCreateSalesReturn,
    this.onPrint,
    this.onDelete,
  });

  final bool compact;
  final bool showView;
  final bool showEdit;
  final bool showCreateSalesReturn;
  final bool showPrint;
  final bool showDelete;
  final bool canEdit;
  final bool canCreateSalesReturn;
  final bool canPrint;
  final bool canDelete;
  final VoidCallback? onView;
  final VoidCallback? onEdit;
  final VoidCallback? onCreateSalesReturn;
  final VoidCallback? onPrint;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final menu = PopupMenuButton<_InvoiceMenuAction>(
      tooltip: 'actions'.tr,
      position: PopupMenuPosition.under,
      popUpAnimationStyle: FatooraMotion.overlayStyle(
        context,
        duration: FatooraMotion.standard,
        reverseDuration: FatooraMotion.quick,
      ),
      onSelected: _onSelected,
      itemBuilder: _buildItems,
      icon: compact ? const Icon(Icons.more_vert_rounded) : null,
      child: compact ? null : const _FullActionsTrigger(),
    );
    return compact
        ? menu
        : Semantics(button: true, label: 'actions'.tr, child: menu);
  }

  List<PopupMenuEntry<_InvoiceMenuAction>> _buildItems(BuildContext context) {
    return [
      if (showView)
        _item(
          value: _InvoiceMenuAction.view,
          icon: Icons.visibility_outlined,
          label: 'invoice_details'.tr,
          enabled: onView != null,
        ),
      if (showEdit)
        _item(
          value: _InvoiceMenuAction.edit,
          icon: Icons.edit_outlined,
          label: 'edit_invoice'.tr,
          enabled: canEdit && onEdit != null,
        ),
      if (showCreateSalesReturn)
        _item(
          value: _InvoiceMenuAction.createSalesReturn,
          icon: Icons.assignment_return_outlined,
          label: 'create_sales_return'.tr,
          enabled: canCreateSalesReturn && onCreateSalesReturn != null,
        ),
      if (showPrint)
        _item(
          value: _InvoiceMenuAction.print,
          icon: Icons.print_outlined,
          label: 'print_export'.tr,
          enabled: canPrint && onPrint != null,
        ),
      if (showDelete)
        _item(
          value: _InvoiceMenuAction.delete,
          icon: Icons.delete_outline_rounded,
          label: 'delete_invoice'.tr,
          enabled: canDelete && onDelete != null,
          color: AppColor.error,
        ),
      _item(
        value: _InvoiceMenuAction.convertToTaxInvoice,
        icon: Icons.receipt_long_outlined,
        label: 'convert_to_tax_invoice'.tr,
        enabled: false,
      ),
    ];
  }

  PopupMenuItem<_InvoiceMenuAction> _item({
    required _InvoiceMenuAction value,
    required IconData icon,
    required String label,
    required bool enabled,
    Color? color,
  }) {
    return PopupMenuItem<_InvoiceMenuAction>(
      value: value,
      enabled: enabled,
      child: Row(
        children: [
          Icon(icon, color: enabled ? color : null),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              label,
              style: color == null || !enabled ? null : TextStyle(color: color),
            ),
          ),
        ],
      ),
    );
  }

  void _onSelected(_InvoiceMenuAction action) {
    switch (action) {
      case _InvoiceMenuAction.view:
        onView?.call();
      case _InvoiceMenuAction.edit:
        onEdit?.call();
      case _InvoiceMenuAction.createSalesReturn:
        onCreateSalesReturn?.call();
      case _InvoiceMenuAction.print:
        onPrint?.call();
      case _InvoiceMenuAction.delete:
        onDelete?.call();
      case _InvoiceMenuAction.convertToTaxInvoice:
        return;
    }
  }
}

class _FullActionsTrigger extends StatelessWidget {
  const _FullActionsTrigger();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.more_vert_rounded, size: 20),
          const SizedBox(width: 7),
          Text('actions'.tr),
          const SizedBox(width: 4),
          const Icon(Icons.arrow_drop_down_rounded, size: 20),
        ],
      ),
    );
  }
}
