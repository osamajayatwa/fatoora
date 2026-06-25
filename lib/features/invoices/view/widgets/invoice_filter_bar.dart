import 'package:fatoora/core/constants/color.dart';
import 'package:fatoora/features/invoices/data/models/invoice_enums.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class InvoiceFilterBar extends StatelessWidget {
  const InvoiceFilterBar({
    super.key,
    required this.type,
    required this.status,
    required this.fromDate,
    required this.toDate,
    required this.hasFilters,
    required this.onTypeChanged,
    required this.onStatusChanged,
    required this.onDateRangeChanged,
    required this.onClear,
  });

  final InvoiceType? type;
  final InvoiceStatus? status;
  final DateTime? fromDate;
  final DateTime? toDate;
  final bool hasFilters;
  final ValueChanged<InvoiceType?> onTypeChanged;
  final ValueChanged<InvoiceStatus?> onStatusChanged;
  final ValueChanged<DateTimeRange?> onDateRangeChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SizedBox(
          width: 210,
          child: DropdownButtonFormField<InvoiceType?>(
            value: type,
            isExpanded: true,
            decoration: _decoration('invoice_type'.tr, Icons.category_outlined),
            items: [
              DropdownMenuItem(
                value: null,
                child: Text('all_invoice_types'.tr),
              ),
              ...InvoiceType.values.map(
                (value) => DropdownMenuItem(
                  value: value,
                  child: Text(_typeLabel(value).tr),
                ),
              ),
            ],
            onChanged: onTypeChanged,
          ),
        ),
        SizedBox(
          width: 210,
          child: DropdownButtonFormField<InvoiceStatus?>(
            value: status,
            isExpanded: true,
            decoration: _decoration('invoice_status'.tr, Icons.flag_outlined),
            items: [
              DropdownMenuItem(
                value: null,
                child: Text('all_invoice_statuses'.tr),
              ),
              ...InvoiceStatus.values.map(
                (value) => DropdownMenuItem(
                  value: value,
                  child: Text(_statusLabel(value).tr),
                ),
              ),
            ],
            onChanged: onStatusChanged,
          ),
        ),
        OutlinedButton.icon(
          onPressed: () async {
            final now = DateTime.now();
            final range = await showDateRangePicker(
              context: context,
              firstDate: DateTime(now.year - 5),
              lastDate: DateTime(now.year + 2),
              initialDateRange: fromDate == null || toDate == null
                  ? null
                  : DateTimeRange(start: fromDate!, end: toDate!),
            );
            onDateRangeChanged(range);
          },
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColor.secondaryColor,
            side: const BorderSide(color: Color(0xFFE1E5ED)),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          icon: const Icon(Icons.date_range_rounded, size: 18),
          label: Text(_dateLabel()),
        ),
        if (hasFilters)
          TextButton.icon(
            onPressed: onClear,
            icon: const Icon(Icons.filter_alt_off_rounded, size: 18),
            label: Text('clear_filters'.tr),
          ),
      ],
    );
  }

  InputDecoration _decoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon),
      filled: true,
      fillColor: AppColor.surface,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFE1E5ED)),
      ),
    );
  }

  String _dateLabel() {
    if (fromDate == null || toDate == null) return 'date_range'.tr;
    return '${_formatDate(fromDate!)} - ${_formatDate(toDate!)}';
  }

  String _formatDate(DateTime date) {
    return '${date.year}/${date.month.toString().padLeft(2, '0')}/${date.day.toString().padLeft(2, '0')}';
  }

  String _typeLabel(InvoiceType type) {
    return switch (type) {
      InvoiceType.regular => 'regular_invoice',
      InvoiceType.electronic => 'electronic_invoice',
    };
  }

  String _statusLabel(InvoiceStatus status) {
    return switch (status) {
      InvoiceStatus.draft => 'draft',
      InvoiceStatus.confirmed => 'confirmed',
      InvoiceStatus.pendingSubmit => 'pending_submit',
      InvoiceStatus.accepted => 'accepted',
      InvoiceStatus.rejected => 'rejected',
      InvoiceStatus.cancelled => 'cancelled',
    };
  }
}
