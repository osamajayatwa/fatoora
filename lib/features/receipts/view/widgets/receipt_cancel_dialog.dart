import 'package:flutter/material.dart';
import 'package:get/get.dart';

class ReceiptCancelDialog extends StatefulWidget {
  const ReceiptCancelDialog({super.key});
  @override
  State<ReceiptCancelDialog> createState() => _ReceiptCancelDialogState();
}

class _ReceiptCancelDialogState extends State<ReceiptCancelDialog> {
  final _reason = TextEditingController();
  final _form = GlobalKey<FormState>();
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('receipts_cancel_title'.tr),
    content: SingleChildScrollView(
      child: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('receipts_cancel_warning'.tr),
            const SizedBox(height: 16),
            TextFormField(
              key: const ValueKey('receipt-cancel-reason'),
              controller: _reason,
              maxLength: 500,
              minLines: 2,
              maxLines: 4,
              decoration: InputDecoration(
                labelText: 'receipts_cancel_reason'.tr,
              ),
              validator: (value) => value == null || value.trim().isEmpty
                  ? 'receipts_cancel_reason_required'.tr
                  : null,
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Get.back<String>(),
        child: Text('receipts_keep'.tr),
      ),
      FilledButton(
        key: const ValueKey('receipt-cancel-confirm'),
        onPressed: () {
          if (_form.currentState!.validate()) {
            Get.back(result: _reason.text.trim());
          }
        },
        child: Text('receipts_cancel_confirm'.tr),
      ),
    ],
  );
  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }
}
