import 'package:fatoora/core/constants/color.dart';
import 'package:fatoora/features/invoices/data/models/invoice_enums.dart';
import 'package:fatoora/features/invoices/data/models/invoice_list_query.dart';
import 'package:fatoora/features/invoices/view/widgets/invoice_filter_option_picker.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class InvoiceFilterBar extends StatelessWidget {
  const InvoiceFilterBar({
    super.key,
    required this.type,
    required this.status,
    required this.paymentStatus,
    required this.returnStatus,
    required this.salesRep,
    required this.customer,
    required this.fromDate,
    required this.toDate,
    required this.sortField,
    required this.sortDirection,
    required this.hasActiveFilters,
    required this.loadSalesRepOptions,
    required this.loadCustomerOptions,
    required this.onTypeChanged,
    required this.onStatusChanged,
    required this.onPaymentStatusChanged,
    required this.onReturnStatusChanged,
    required this.onSalesRepChanged,
    required this.onCustomerChanged,
    required this.onDateRangeChanged,
    required this.onSortFieldChanged,
    required this.onSortDirectionChanged,
    required this.onClear,
  });

  final InvoiceType? type;
  final InvoiceStatus? status;
  final PaymentStatus? paymentStatus;
  final InvoiceReturnStatus? returnStatus;
  final InvoiceFilterOption? salesRep;
  final InvoiceFilterOption? customer;
  final DateTime? fromDate;
  final DateTime? toDate;
  final InvoiceSortField sortField;
  final InvoiceSortDirection sortDirection;
  final bool hasActiveFilters;
  final InvoiceFilterOptionLoader loadSalesRepOptions;
  final InvoiceFilterOptionLoader loadCustomerOptions;
  final ValueChanged<InvoiceType?> onTypeChanged;
  final ValueChanged<InvoiceStatus?> onStatusChanged;
  final ValueChanged<PaymentStatus?> onPaymentStatusChanged;
  final ValueChanged<InvoiceReturnStatus?> onReturnStatusChanged;
  final ValueChanged<InvoiceFilterOption?> onSalesRepChanged;
  final ValueChanged<InvoiceFilterOption?> onCustomerChanged;
  final ValueChanged<DateTimeRange?> onDateRangeChanged;
  final ValueChanged<InvoiceSortField> onSortFieldChanged;
  final ValueChanged<InvoiceSortDirection> onSortDirectionChanged;
  final VoidCallback onClear;

  bool get _hasDateRange => fromDate != null || toDate != null;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: AppColor.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: Color(0xFFE1E5ED)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final controlWidth = constraints.maxWidth < 520
                ? constraints.maxWidth
                : 224.0;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _SectionHeader(
                  icon: Icons.filter_alt_outlined,
                  title: 'invoice_filters'.tr,
                  action: hasActiveFilters
                      ? TextButton.icon(
                          onPressed: onClear,
                          icon: const Icon(
                            Icons.filter_alt_off_rounded,
                            size: 18,
                          ),
                          label: Text('clear_filters'.tr),
                        )
                      : null,
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    _control(
                      controlWidth,
                      _selectionControl(
                        label: 'sales_rep'.tr,
                        icon: Icons.badge_outlined,
                        value:
                            salesRep?.label ?? 'all_sales_representatives'.tr,
                        onTap: () => _openSalesRepPicker(context),
                      ),
                    ),
                    _control(
                      controlWidth,
                      _selectionControl(
                        label: 'customer_name'.tr,
                        icon: Icons.person_search_outlined,
                        value: customer?.label ?? 'all_customers'.tr,
                        onTap: () => _openCustomerPicker(context),
                      ),
                    ),
                    _control(controlWidth, _invoiceStatusDropdown()),
                    _control(controlWidth, _paymentStatusDropdown()),
                    _control(controlWidth, _typeDropdown()),
                    _control(controlWidth, _returnStatusDropdown()),
                    _control(controlWidth, _dateButton(context)),
                  ],
                ),
                if (hasActiveFilters) ...[
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _activeFilterChips(),
                  ),
                ],
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 14),
                  child: Divider(height: 1),
                ),
                _SectionHeader(
                  icon: Icons.sort_rounded,
                  title: 'sort_invoices'.tr,
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _control(controlWidth, _sortFieldDropdown()),
                    _control(controlWidth, _sortDirectionButton()),
                  ],
                ),
                if (_hasDateRange) ...[
                  const SizedBox(height: 8),
                  Text(
                    'date_range_sort_notice'.tr,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: const Color(0xFF657184),
                    ),
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _control(double width, Widget child) =>
      SizedBox(width: width, child: child);

  Widget _selectionControl({
    required String label,
    required IconData icon,
    required String value,
    required VoidCallback onTap,
  }) {
    return Semantics(
      button: true,
      label: '$label: $value',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: InputDecorator(
          decoration: _decoration(label, icon),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const Icon(Icons.arrow_drop_down_rounded),
            ],
          ),
        ),
      ),
    );
  }

  Widget _typeDropdown() {
    return DropdownButtonFormField<InvoiceType?>(
      value: type,
      isExpanded: true,
      decoration: _decoration('invoice_type'.tr, Icons.category_outlined),
      items: [
        DropdownMenuItem(value: null, child: Text('all_invoice_types'.tr)),
        ...InvoiceType.values.map(
          (value) =>
              DropdownMenuItem(value: value, child: Text(_typeLabel(value).tr)),
        ),
      ],
      onChanged: onTypeChanged,
    );
  }

  Widget _invoiceStatusDropdown() {
    return DropdownButtonFormField<InvoiceStatus?>(
      value: status,
      isExpanded: true,
      decoration: _decoration('invoice_status'.tr, Icons.flag_outlined),
      items: [
        DropdownMenuItem(value: null, child: Text('all_invoice_statuses'.tr)),
        ...InvoiceStatus.values.map(
          (value) => DropdownMenuItem(
            value: value,
            child: Text(_statusLabel(value).tr),
          ),
        ),
      ],
      onChanged: onStatusChanged,
    );
  }

  Widget _paymentStatusDropdown() {
    return DropdownButtonFormField<PaymentStatus?>(
      value: paymentStatus,
      isExpanded: true,
      decoration: _decoration('payment_status'.tr, Icons.payments_outlined),
      items: [
        DropdownMenuItem(value: null, child: Text('all_payment_statuses'.tr)),
        ...PaymentStatus.values.map(
          (value) =>
              DropdownMenuItem(value: value, child: Text(value.value.tr)),
        ),
      ],
      onChanged: onPaymentStatusChanged,
    );
  }

  Widget _returnStatusDropdown() {
    return DropdownButtonFormField<InvoiceReturnStatus?>(
      value: returnStatus,
      isExpanded: true,
      decoration: _decoration(
        'return_status'.tr,
        Icons.assignment_return_outlined,
      ),
      items: [
        DropdownMenuItem(value: null, child: Text('all_return_statuses'.tr)),
        ...InvoiceReturnStatus.values.map(
          (value) =>
              DropdownMenuItem(value: value, child: Text(value.value.tr)),
        ),
      ],
      onChanged: onReturnStatusChanged,
    );
  }

  Widget _dateButton(BuildContext context) {
    return OutlinedButton.icon(
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
        if (range != null) onDateRangeChanged(range);
      },
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColor.secondaryColor,
        alignment: AlignmentDirectional.centerStart,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 18),
        side: const BorderSide(color: Color(0xFFE1E5ED)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      icon: const Icon(Icons.date_range_rounded, size: 20),
      label: Text(_dateLabel(), overflow: TextOverflow.ellipsis),
    );
  }

  Widget _sortFieldDropdown() {
    return DropdownButtonFormField<InvoiceSortField>(
      value: sortField,
      isExpanded: true,
      decoration: _decoration('sort_by'.tr, Icons.sort_by_alpha_rounded),
      items: InvoiceSortField.values
          .map(
            (value) => DropdownMenuItem(
              value: value,
              child: Text(_sortLabel(value).tr),
            ),
          )
          .toList(growable: false),
      onChanged: _hasDateRange
          ? null
          : (value) {
              if (value != null) onSortFieldChanged(value);
            },
    );
  }

  Widget _sortDirectionButton() {
    final ascending = sortDirection == InvoiceSortDirection.ascending;
    return OutlinedButton.icon(
      onPressed: () => onSortDirectionChanged(
        ascending
            ? InvoiceSortDirection.descending
            : InvoiceSortDirection.ascending,
      ),
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColor.secondaryColor,
        alignment: AlignmentDirectional.centerStart,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 18),
        side: const BorderSide(color: Color(0xFFE1E5ED)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      icon: Icon(
        ascending ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
        size: 20,
      ),
      label: Text(ascending ? 'ascending'.tr : 'descending'.tr),
    );
  }

  List<Widget> _activeFilterChips() {
    return [
      if (salesRep != null)
        _chip('sales_rep'.tr, salesRep!.label, () => onSalesRepChanged(null)),
      if (customer != null)
        _chip(
          'customer_name'.tr,
          customer!.label,
          () => onCustomerChanged(null),
        ),
      if (status != null)
        _chip(
          'invoice_status'.tr,
          _statusLabel(status!).tr,
          () => onStatusChanged(null),
        ),
      if (paymentStatus != null)
        _chip(
          'payment_status'.tr,
          paymentStatus!.value.tr,
          () => onPaymentStatusChanged(null),
        ),
      if (type != null)
        _chip(
          'invoice_type'.tr,
          _typeLabel(type!).tr,
          () => onTypeChanged(null),
        ),
      if (returnStatus != null)
        _chip(
          'return_status'.tr,
          returnStatus!.value.tr,
          () => onReturnStatusChanged(null),
        ),
      if (_hasDateRange)
        _chip('date_range'.tr, _dateLabel(), () => onDateRangeChanged(null)),
    ];
  }

  Widget _chip(String label, String value, VoidCallback onDeleted) {
    return InputChip(
      label: Text('$label: $value'),
      onDeleted: onDeleted,
      deleteIcon: const Icon(Icons.close_rounded, size: 17),
      backgroundColor: AppColor.primaryColor.withValues(alpha: 0.08),
      side: BorderSide(color: AppColor.primaryColor.withValues(alpha: 0.2)),
    );
  }

  void _openSalesRepPicker(BuildContext context) {
    _openOptionPicker(
      context: context,
      title: 'select_sales_representative'.tr,
      searchHint: 'search_sales_representatives'.tr,
      allLabel: 'all_sales_representatives'.tr,
      selected: salesRep,
      loader: loadSalesRepOptions,
      onSelected: onSalesRepChanged,
    );
  }

  void _openCustomerPicker(BuildContext context) {
    _openOptionPicker(
      context: context,
      title: 'select_customer'.tr,
      searchHint: 'search_customers'.tr,
      allLabel: 'all_customers'.tr,
      selected: customer,
      loader: loadCustomerOptions,
      onSelected: onCustomerChanged,
    );
  }

  void _openOptionPicker({
    required BuildContext context,
    required String title,
    required String searchHint,
    required String allLabel,
    required InvoiceFilterOption? selected,
    required InvoiceFilterOptionLoader loader,
    required ValueChanged<InvoiceFilterOption?> onSelected,
  }) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: AppColor.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => InvoiceFilterOptionPicker(
        title: title,
        searchHint: searchHint,
        allLabel: allLabel,
        selected: selected,
        loadOptions: loader,
        onSelected: onSelected,
      ),
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
    if (fromDate == null && toDate == null) return 'date_range'.tr;
    final start = fromDate == null ? '...' : _formatDate(fromDate!);
    final end = toDate == null ? '...' : _formatDate(toDate!);
    return '$start - $end';
  }

  String _formatDate(DateTime date) {
    return '${date.year}/${date.month.toString().padLeft(2, '0')}/${date.day.toString().padLeft(2, '0')}';
  }

  String _sortLabel(InvoiceSortField value) => switch (value) {
    InvoiceSortField.invoiceNumber => 'invoice_number',
    InvoiceSortField.invoiceDate => 'invoice_date',
    InvoiceSortField.customerName => 'customer_name',
    InvoiceSortField.salesRepresentativeName => 'sales_rep',
    InvoiceSortField.invoiceTotal => 'grand_total',
    InvoiceSortField.remainingBalance => 'remaining_amount',
    InvoiceSortField.invoiceStatus => 'invoice_status',
    InvoiceSortField.createdDate => 'created_date',
  };

  String _typeLabel(InvoiceType value) => switch (value) {
    InvoiceType.regular => 'regular_invoice',
    InvoiceType.electronic => 'electronic_invoice',
  };

  String _statusLabel(InvoiceStatus value) => switch (value) {
    InvoiceStatus.draft => 'draft',
    InvoiceStatus.confirmed => 'confirmed',
    InvoiceStatus.pendingSubmit => 'pending_submit',
    InvoiceStatus.accepted => 'accepted',
    InvoiceStatus.rejected => 'rejected',
    InvoiceStatus.cancelled => 'cancelled',
  };
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.icon, required this.title, this.action});

  final IconData icon;
  final String title;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: AppColor.primaryColor, size: 21),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: AppColor.secondaryColor,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        if (action != null) action!,
      ],
    );
  }
}
