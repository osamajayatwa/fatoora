import 'package:fatoora/core/constants/color.dart';
import 'package:fatoora/features/customers/data/models/customer_opening_balance.dart';
import 'package:fatoora/features/customers/data/models/customer_transaction_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

class CustomerOpeningBalanceDialog extends StatefulWidget {
  const CustomerOpeningBalanceDialog({
    required this.customerName,
    required this.onSubmit,
    super.key,
  });

  final String customerName;
  final Future<CustomerTransactionModel?> Function({
    required CustomerOpeningBalanceType balanceType,
    required double amount,
    required DateTime transactionDate,
    required String notes,
  })
  onSubmit;

  @override
  State<CustomerOpeningBalanceDialog> createState() =>
      _CustomerOpeningBalanceDialogState();
}

class _CustomerOpeningBalanceDialogState
    extends State<CustomerOpeningBalanceDialog> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _notesController = TextEditingController();
  CustomerOpeningBalanceType _balanceType =
      CustomerOpeningBalanceType.customerOwes;
  DateTime _transactionDate = DateTime.now();
  bool _submitting = false;

  @override
  void dispose() {
    _amountController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    return Dialog(
      insetPadding: EdgeInsets.symmetric(
        horizontal: media.size.width < 520 ? 12 : 32,
        vertical: 24,
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 560,
          maxHeight: media.size.height - 48,
        ),
        child: SingleChildScrollView(
          padding: EdgeInsets.all(media.size.width < 520 ? 18 : 24),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.account_balance_wallet_outlined,
                      color: AppColor.primaryColor,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'customers_add_opening_balance'.tr,
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(fontWeight: FontWeight.w900),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            widget.customerName,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: _submitting
                          ? null
                          : () => Navigator.of(context).pop(),
                      tooltip: MaterialLocalizations.of(
                        context,
                      ).closeButtonTooltip,
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColor.accentYellow.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AppColor.accentYellow.withValues(alpha: 0.35),
                    ),
                  ),
                  child: Text(
                    'customers_opening_balance_warning'.tr,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                DropdownButtonFormField<CustomerOpeningBalanceType>(
                  value: _balanceType,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: 'customers_opening_balance_type'.tr,
                    prefixIcon: const Icon(Icons.swap_vert_rounded),
                  ),
                  items: CustomerOpeningBalanceType.values
                      .map(
                        (type) => DropdownMenuItem(
                          value: type,
                          child: Text(
                            type == CustomerOpeningBalanceType.customerOwes
                                ? 'customers_owes_us'.tr
                                : 'customers_has_credit'.tr,
                          ),
                        ),
                      )
                      .toList(growable: false),
                  onChanged: _submitting
                      ? null
                      : (value) {
                          if (value != null) {
                            setState(() => _balanceType = value);
                          }
                        },
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _amountController,
                  enabled: !_submitting,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                  ],
                  decoration: InputDecoration(
                    labelText: 'customers_opening_balance_amount'.tr,
                    prefixIcon: const Icon(Icons.payments_outlined),
                    suffixText: 'JOD',
                  ),
                  validator: (value) {
                    final normalized = value?.trim() ?? '';
                    final amount = double.tryParse(normalized);
                    if (amount == null || !amount.isFinite || amount <= 0) {
                      return 'customers_opening_balance_amount_invalid'.tr;
                    }
                    if (!RegExp(r'^\d+(\.\d{1,3})?$').hasMatch(normalized) ||
                        (amount * 1000).round() <= 0 ||
                        amount > 999999999) {
                      return 'customers_opening_balance_amount_invalid'.tr;
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 14),
                OutlinedButton.icon(
                  onPressed: _submitting ? null : _selectDate,
                  icon: const Icon(Icons.event_outlined),
                  label: Text(
                    '${'customers_opening_balance_date'.tr}: '
                    '${DateFormat.yMd().format(_transactionDate)}',
                  ),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _notesController,
                  enabled: !_submitting,
                  minLines: 2,
                  maxLines: 4,
                  maxLength: 500,
                  decoration: InputDecoration(
                    labelText: 'notes'.tr,
                    hintText: 'customers_opening_balance_notes_hint'.tr,
                    alignLabelWithHint: true,
                  ),
                ),
                const SizedBox(height: 8),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final narrow = constraints.maxWidth < 390;
                    final cancel = OutlinedButton(
                      onPressed: _submitting
                          ? null
                          : () => Navigator.of(context).pop(),
                      child: Text('items_cancel'.tr),
                    );
                    final submit = FilledButton.icon(
                      onPressed: _submitting ? null : _submit,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColor.primaryColor,
                      ),
                      icon: _submitting
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.lock_outline_rounded),
                      label: Text('customers_post_opening_balance'.tr),
                    );
                    if (narrow) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [submit, const SizedBox(height: 10), cancel],
                      );
                    }
                    return Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        cancel,
                        const SizedBox(width: 10),
                        Flexible(child: submit),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _selectDate() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: _transactionDate,
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
    );
    if (selected != null && mounted) {
      setState(() => _transactionDate = selected);
    }
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _submitting = true);
    CustomerTransactionModel? saved;
    try {
      saved = await widget.onSubmit(
        balanceType: _balanceType,
        amount: double.parse(_amountController.text.trim()),
        transactionDate: _transactionDate,
        notes: _notesController.text,
      );
      if (saved != null && mounted) {
        Navigator.of(context).pop(saved);
      }
    } catch (_) {
      if (mounted) {
        Get.snackbar(
          'customers'.tr,
          (saved == null
                  ? 'customers_opening_balance_error'
                  : 'customers_opening_balance_close_error')
              .tr,
          snackPosition: SnackPosition.BOTTOM,
          backgroundColor: AppColor.error,
          colorText: AppColor.surface,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }
}

class CustomerOpeningBalanceDetailsDialog extends StatelessWidget {
  const CustomerOpeningBalanceDetailsDialog({
    required this.transaction,
    super.key,
  });

  final CustomerTransactionModel transaction;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final currency = NumberFormat.currency(symbol: 'JOD ', decimalDigits: 3);
    final type = CustomerOpeningBalanceType.fromValue(
      transaction.openingBalanceType,
    );
    return Dialog(
      insetPadding: EdgeInsets.symmetric(
        horizontal: media.size.width < 520 ? 12 : 32,
        vertical: 24,
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 520,
          maxHeight: media.size.height - 48,
        ),
        child: SingleChildScrollView(
          padding: EdgeInsets.all(media.size.width < 520 ? 18 : 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.account_balance_wallet_outlined,
                    color: AppColor.primaryColor,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'customers_opening_balance_details'.tr,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    tooltip: MaterialLocalizations.of(
                      context,
                    ).closeButtonTooltip,
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColor.success.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppColor.success.withValues(alpha: 0.28),
                  ),
                ),
                child: Text(
                  'customers_opening_balance_already_registered'.tr,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              const SizedBox(height: 14),
              _OpeningBalanceDetailRow(
                label: 'customers_opening_balance_amount'.tr,
                value: currency.format(transaction.amount),
              ),
              _OpeningBalanceDetailRow(
                label: 'customers_opening_balance_type'.tr,
                value: type == CustomerOpeningBalanceType.customerCredit
                    ? 'customers_has_credit'.tr
                    : 'customers_owes_us'.tr,
              ),
              _OpeningBalanceDetailRow(
                label: 'customers_opening_balance_date'.tr,
                value: DateFormat.yMd().format(transaction.transactionDate),
              ),
              _OpeningBalanceDetailRow(
                label: 'customers_opening_balance_reference'.tr,
                value: transaction.sourceNumber.isEmpty
                    ? transaction.id
                    : transaction.sourceNumber,
              ),
              _OpeningBalanceDetailRow(
                label: 'created_by'.tr,
                value: transaction.createdByName,
              ),
              if (transaction.notes.isNotEmpty)
                _OpeningBalanceDetailRow(
                  label: 'notes'.tr,
                  value: transaction.notes,
                ),
              const SizedBox(height: 14),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColor.primaryColor,
                ),
                child: Text('customers_close'.tr),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OpeningBalanceDetailRow extends StatelessWidget {
  const _OpeningBalanceDetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final narrow = constraints.maxWidth < 380;
          final labelWidget = Text(
            label,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: AppColor.grey,
              fontWeight: FontWeight.w800,
            ),
          );
          final valueWidget = Text(
            value,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
          );
          if (narrow) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [labelWidget, const SizedBox(height: 4), valueWidget],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: 170, child: labelWidget),
              Expanded(child: valueWidget),
            ],
          );
        },
      ),
    );
  }
}
