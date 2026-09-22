import 'package:fatoora/core/constants/color.dart';
import 'package:fatoora/core/motion/fatoora_overlays.dart';
import 'package:fatoora/features/invoices/data/models/invoice_item_snapshot.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

Future<InvoiceItemSnapshot?> showCustomLineEditor(
  BuildContext context, {
  required bool canApplyDiscount,
}) {
  final content = _CustomLineEditor(canApplyDiscount: canApplyDiscount);
  if (MediaQuery.sizeOf(context).width >= 760) {
    return showFatooraGetDialog<InvoiceItemSnapshot>(
      Dialog(
        insetPadding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620, maxHeight: 760),
          child: content,
        ),
      ),
    );
  }
  return showFatooraGetBottomSheet<InvoiceItemSnapshot>(
    content,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
  );
}

class _CustomLineEditor extends StatefulWidget {
  const _CustomLineEditor({required this.canApplyDiscount});

  final bool canApplyDiscount;

  @override
  State<_CustomLineEditor> createState() => _CustomLineEditorState();
}

class _CustomLineEditorState extends State<_CustomLineEditor> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _description = TextEditingController();
  final _quantity = TextEditingController(text: '1');
  final _unit = TextEditingController(text: 'pcs');
  final _price = TextEditingController();
  final _discount = TextEditingController(text: '0');
  final _tax = TextEditingController(text: '0');

  double _number(TextEditingController controller) =>
      double.tryParse(controller.text.trim()) ?? 0;

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    Get.back<InvoiceItemSnapshot>(
      result: InvoiceItemSnapshot(
        lineId: 'line-${DateTime.now().microsecondsSinceEpoch}',
        lineType: InvoiceLineType.custom,
        itemId: null,
        itemName: _name.text.trim(),
        description: _description.text.trim(),
        itemCode: '',
        unit: _unit.text.trim(),
        quantity: _number(_quantity),
        unitPrice: _number(_price),
        discount: widget.canApplyDiscount ? _number(_discount) : 0,
        taxPercent: _number(_tax),
        subtotal: 0,
        taxAmount: 0,
        total: 0,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return Material(
      color: AppColor.surface,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + bottom),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'custom_line'.tr,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: Get.back<void>,
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _textField(_name, 'line_name'.tr, required: true),
                const SizedBox(height: 12),
                _textField(
                  _description,
                  'description'.tr,
                  required: true,
                  minLines: 2,
                  maxLines: 4,
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    _sized(_numberField(_quantity, 'quantity'.tr), 150),
                    _sized(_textField(_unit, 'unit'.tr, required: true), 150),
                    _sized(_numberField(_price, 'unit_price'.tr), 170),
                    if (widget.canApplyDiscount)
                      _sized(
                        _numberField(_discount, 'discount'.tr, positive: false),
                        150,
                      ),
                    _sized(_numberField(_tax, 'tax'.tr, positive: false), 130),
                  ],
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: _submit,
                  icon: const Icon(Icons.add_rounded),
                  label: Text('add_custom_line'.tr),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _sized(Widget child, double width) =>
      SizedBox(width: width, child: child);

  TextFormField _numberField(
    TextEditingController controller,
    String label, {
    bool positive = true,
  }) => TextFormField(
    controller: controller,
    keyboardType: const TextInputType.numberWithOptions(decimal: true),
    decoration: InputDecoration(labelText: label),
    validator: (value) {
      final number = double.tryParse(value?.trim() ?? '');
      if (number == null ||
          !number.isFinite ||
          (positive ? number <= 0 : number < 0)) {
        return positive
            ? 'value_must_be_positive'.tr
            : 'value_must_not_be_negative'.tr;
      }
      return null;
    },
  );

  TextFormField _textField(
    TextEditingController controller,
    String label, {
    bool required = false,
    int minLines = 1,
    int maxLines = 1,
  }) => TextFormField(
    controller: controller,
    minLines: minLines,
    maxLines: maxLines,
    decoration: InputDecoration(labelText: label),
    validator: required
        ? (value) =>
              (value?.trim().isEmpty ?? true) ? 'field_required'.tr : null
        : null,
  );

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _quantity.dispose();
    _unit.dispose();
    _price.dispose();
    _discount.dispose();
    _tax.dispose();
    super.dispose();
  }
}
