import 'package:fatoora/core/constants/color.dart';
import 'package:fatoora/core/motion/fatoora_overlays.dart';
import 'package:fatoora/features/invoices/data/models/invoice_enums.dart';
import 'package:fatoora/features/invoices/data/models/invoice_list_query.dart';
import 'package:fatoora/features/invoices/view/widgets/invoice_filter_option_picker.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class InvoiceFilterSelection {
  const InvoiceFilterSelection({
    required this.type,
    required this.status,
    required this.paymentStatus,
    required this.returnStatus,
    required this.salesRep,
    required this.customer,
    required this.dateRange,
  });

  final InvoiceType? type;
  final InvoiceStatus? status;
  final PaymentStatus? paymentStatus;
  final InvoiceReturnStatus? returnStatus;
  final InvoiceFilterOption? salesRep;
  final InvoiceFilterOption? customer;
  final DateTimeRange? dateRange;
}

class InvoiceSortSelection {
  const InvoiceSortSelection(this.field, this.direction);

  final InvoiceSortField field;
  final InvoiceSortDirection direction;
}

class InvoiceCompactToolbar extends StatelessWidget {
  const InvoiceCompactToolbar({
    super.key,
    required this.activeFilterCount,
    required this.sortField,
    required this.sortDirection,
    required this.onFiltersPressed,
    required this.onSortPressed,
  });

  final int activeFilterCount;
  final InvoiceSortField sortField;
  final InvoiceSortDirection sortDirection;
  final VoidCallback onFiltersPressed;
  final VoidCallback onSortPressed;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            key: const ValueKey('invoice-filter-button'),
            onPressed: onFiltersPressed,
            icon: const Icon(Icons.tune_rounded),
            label: Text(
              activeFilterCount == 0
                  ? 'invoice_filters'.tr
                  : '${'invoice_filters'.tr} ($activeFilterCount)',
            ),
            style: _buttonStyle(),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: OutlinedButton.icon(
            key: const ValueKey('invoice-sort-button'),
            onPressed: onSortPressed,
            icon: Icon(
              sortDirection == InvoiceSortDirection.ascending
                  ? Icons.arrow_upward_rounded
                  : Icons.arrow_downward_rounded,
            ),
            label: Text(
              invoiceSortLabel(sortField).tr,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            style: _buttonStyle(),
          ),
        ),
      ],
    );
  }

  ButtonStyle _buttonStyle() => OutlinedButton.styleFrom(
    foregroundColor: AppColor.secondaryColor,
    minimumSize: const Size(0, 48),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    side: const BorderSide(color: Color(0xFFDDE2EA)),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
  );
}

class InvoiceActiveFilterChips extends StatelessWidget {
  const InvoiceActiveFilterChips({
    super.key,
    required this.type,
    required this.status,
    required this.paymentStatus,
    required this.returnStatus,
    required this.salesRep,
    required this.customer,
    required this.fromDate,
    required this.toDate,
    required this.onTypeRemoved,
    required this.onStatusRemoved,
    required this.onPaymentStatusRemoved,
    required this.onReturnStatusRemoved,
    required this.onSalesRepRemoved,
    required this.onCustomerRemoved,
    required this.onDateRangeRemoved,
    required this.onClearAll,
  });

  final InvoiceType? type;
  final InvoiceStatus? status;
  final PaymentStatus? paymentStatus;
  final InvoiceReturnStatus? returnStatus;
  final InvoiceFilterOption? salesRep;
  final InvoiceFilterOption? customer;
  final DateTime? fromDate;
  final DateTime? toDate;
  final VoidCallback onTypeRemoved;
  final VoidCallback onStatusRemoved;
  final VoidCallback onPaymentStatusRemoved;
  final VoidCallback onReturnStatusRemoved;
  final VoidCallback onSalesRepRemoved;
  final VoidCallback onCustomerRemoved;
  final VoidCallback onDateRangeRemoved;
  final VoidCallback onClearAll;

  @override
  Widget build(BuildContext context) {
    final chips = <Widget>[
      if (salesRep != null)
        _chip('sales_rep'.tr, salesRep!.label, onSalesRepRemoved),
      if (customer != null)
        _chip('customer_name'.tr, customer!.label, onCustomerRemoved),
      if (status != null)
        _chip(
          'invoice_status'.tr,
          invoiceStatusLabel(status!).tr,
          onStatusRemoved,
        ),
      if (paymentStatus != null)
        _chip(
          'payment_status'.tr,
          paymentStatus!.value.tr,
          onPaymentStatusRemoved,
        ),
      if (type != null)
        _chip('invoice_type'.tr, invoiceTypeLabel(type!).tr, onTypeRemoved),
      if (returnStatus != null)
        _chip(
          'return_status'.tr,
          returnStatus!.value.tr,
          onReturnStatusRemoved,
        ),
      if (fromDate != null || toDate != null)
        _chip(
          'date_range'.tr,
          invoiceDateRangeLabel(fromDate, toDate),
          onDateRangeRemoved,
        ),
    ];
    if (chips.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 42,
      child: SingleChildScrollView(
        key: const ValueKey('invoice-active-filter-chips'),
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (var index = 0; index < chips.length; index++) ...[
              if (index > 0) const SizedBox(width: 8),
              chips[index],
            ],
            if (chips.length > 1) ...[
              const SizedBox(width: 8),
              TextButton(
                key: const ValueKey('invoice-clear-all-filters'),
                onPressed: onClearAll,
                child: Text('clear_all'.tr),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _chip(String label, String value, VoidCallback onDeleted) {
    return InputChip(
      label: Text('$label: $value', overflow: TextOverflow.ellipsis),
      onDeleted: onDeleted,
      deleteIcon: const Icon(Icons.close_rounded, size: 17),
      backgroundColor: AppColor.primaryColor.withValues(alpha: 0.07),
      side: BorderSide(color: AppColor.primaryColor.withValues(alpha: 0.18)),
      visualDensity: VisualDensity.compact,
    );
  }
}

Future<void> showInvoiceFilterSheet({
  required BuildContext context,
  required InvoiceFilterSelection initial,
  required bool showSalesRepresentative,
  required InvoiceFilterOptionLoader loadSalesRepOptions,
  required InvoiceFilterOptionLoader loadCustomerOptions,
  required ValueChanged<InvoiceFilterSelection> onApply,
}) {
  return showFatooraModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: AppColor.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => _InvoiceFilterSheet(
      initial: initial,
      showSalesRepresentative: showSalesRepresentative,
      loadSalesRepOptions: loadSalesRepOptions,
      loadCustomerOptions: loadCustomerOptions,
      onApply: onApply,
    ),
  );
}

class _InvoiceFilterSheet extends StatefulWidget {
  const _InvoiceFilterSheet({
    required this.initial,
    required this.showSalesRepresentative,
    required this.loadSalesRepOptions,
    required this.loadCustomerOptions,
    required this.onApply,
  });

  final InvoiceFilterSelection initial;
  final bool showSalesRepresentative;
  final InvoiceFilterOptionLoader loadSalesRepOptions;
  final InvoiceFilterOptionLoader loadCustomerOptions;
  final ValueChanged<InvoiceFilterSelection> onApply;

  @override
  State<_InvoiceFilterSheet> createState() => _InvoiceFilterSheetState();
}

class _InvoiceFilterSheetState extends State<_InvoiceFilterSheet> {
  late InvoiceType? _type = widget.initial.type;
  late InvoiceStatus? _status = widget.initial.status;
  late PaymentStatus? _paymentStatus = widget.initial.paymentStatus;
  late InvoiceReturnStatus? _returnStatus = widget.initial.returnStatus;
  late InvoiceFilterOption? _salesRep = widget.initial.salesRep;
  late InvoiceFilterOption? _customer = widget.initial.customer;
  late DateTimeRange? _dateRange = widget.initial.dateRange;

  void _reset() => setState(() {
    _type = null;
    _status = null;
    _paymentStatus = null;
    _returnStatus = null;
    _salesRep = null;
    _customer = null;
    _dateRange = null;
  });

  void _apply() {
    widget.onApply(
      InvoiceFilterSelection(
        type: _type,
        status: _status,
        paymentStatus: _paymentStatus,
        returnStatus: _returnStatus,
        salesRep: widget.showSalesRepresentative ? _salesRep : null,
        customer: _customer,
        dateRange: _dateRange,
      ),
    );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 16, 20, 16 + bottomInset),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.88,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _SheetHeader(title: 'invoice_filters'.tr),
              const SizedBox(height: 10),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (widget.showSalesRepresentative) ...[
                        _selectionField(
                          key: const ValueKey('invoice-filter-sales-rep'),
                          label: 'sales_rep'.tr,
                          value:
                              _salesRep?.label ??
                              'all_sales_representatives'.tr,
                          icon: Icons.badge_outlined,
                          onTap: _openSalesRepPicker,
                        ),
                        const SizedBox(height: 12),
                      ],
                      _selectionField(
                        key: const ValueKey('invoice-filter-customer'),
                        label: 'customer_name'.tr,
                        value: _customer?.label ?? 'all_customers'.tr,
                        icon: Icons.person_search_outlined,
                        onTap: _openCustomerPicker,
                      ),
                      const SizedBox(height: 12),
                      _dropdown<InvoiceStatus>(
                        key: const ValueKey('invoice-filter-status'),
                        label: 'invoice_status'.tr,
                        value: _status,
                        allLabel: 'all_invoice_statuses'.tr,
                        values: InvoiceStatus.values,
                        labelFor: (value) => invoiceStatusLabel(value).tr,
                        onChanged: (value) => setState(() => _status = value),
                      ),
                      const SizedBox(height: 12),
                      _dropdown<PaymentStatus>(
                        key: const ValueKey('invoice-filter-payment-status'),
                        label: 'payment_status'.tr,
                        value: _paymentStatus,
                        allLabel: 'all_payment_statuses'.tr,
                        values: PaymentStatus.values,
                        labelFor: (value) => value.value.tr,
                        onChanged: (value) =>
                            setState(() => _paymentStatus = value),
                      ),
                      const SizedBox(height: 12),
                      _dropdown<InvoiceType>(
                        key: const ValueKey('invoice-filter-type'),
                        label: 'invoice_type'.tr,
                        value: _type,
                        allLabel: 'all_invoice_types'.tr,
                        values: InvoiceType.values,
                        labelFor: (value) => invoiceTypeLabel(value).tr,
                        onChanged: (value) => setState(() => _type = value),
                      ),
                      const SizedBox(height: 12),
                      _dropdown<InvoiceReturnStatus>(
                        key: const ValueKey('invoice-filter-return-status'),
                        label: 'return_status'.tr,
                        value: _returnStatus,
                        allLabel: 'all_return_statuses'.tr,
                        values: InvoiceReturnStatus.values,
                        labelFor: (value) => value.value.tr,
                        onChanged: (value) =>
                            setState(() => _returnStatus = value),
                      ),
                      const SizedBox(height: 12),
                      _selectionField(
                        key: const ValueKey('invoice-filter-date-range'),
                        label: 'date_range'.tr,
                        value: invoiceDateRangeLabel(
                          _dateRange?.start,
                          _dateRange?.end,
                        ),
                        icon: Icons.date_range_rounded,
                        onTap: _pickDateRange,
                        onClear: _dateRange == null
                            ? null
                            : () => setState(() => _dateRange = null),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      key: const ValueKey('invoice-filter-reset'),
                      onPressed: _reset,
                      child: Text('clear_all'.tr),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      key: const ValueKey('invoice-filter-apply'),
                      onPressed: _apply,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColor.primaryColor,
                      ),
                      child: Text('apply_filters'.tr),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _dropdown<T>({
    required Key key,
    required String label,
    required T? value,
    required String allLabel,
    required List<T> values,
    required String Function(T) labelFor,
    required ValueChanged<T?> onChanged,
  }) {
    return DropdownButtonFormField<T?>(
      key: key,
      value: value,
      isExpanded: true,
      decoration: _decoration(label),
      items: [
        DropdownMenuItem<T?>(value: null, child: Text(allLabel)),
        ...values.map(
          (item) =>
              DropdownMenuItem<T?>(value: item, child: Text(labelFor(item))),
        ),
      ],
      onChanged: onChanged,
    );
  }

  Widget _selectionField({
    required Key key,
    required String label,
    required String value,
    required IconData icon,
    required VoidCallback onTap,
    VoidCallback? onClear,
  }) {
    return InkWell(
      key: key,
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: InputDecorator(
        decoration: _decoration(label).copyWith(prefixIcon: Icon(icon)),
        child: Row(
          children: [
            Expanded(
              child: Text(value, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
            if (onClear != null)
              IconButton(
                onPressed: onClear,
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.close_rounded, size: 19),
              )
            else
              const Icon(Icons.arrow_drop_down_rounded),
          ],
        ),
      ),
    );
  }

  InputDecoration _decoration(String label) => InputDecoration(
    labelText: label,
    filled: true,
    fillColor: AppColor.surface,
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: Color(0xFFE1E5ED)),
    ),
  );

  Future<void> _pickDateRange() async {
    final now = DateTime.now();
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 2),
      initialDateRange: _dateRange,
    );
    if (range != null && mounted) setState(() => _dateRange = range);
  }

  void _openSalesRepPicker() => _openOptionPicker(
    title: 'select_sales_representative'.tr,
    searchHint: 'search_sales_representatives'.tr,
    allLabel: 'all_sales_representatives'.tr,
    selected: _salesRep,
    loader: widget.loadSalesRepOptions,
    onSelected: (value) => setState(() => _salesRep = value),
  );

  void _openCustomerPicker() => _openOptionPicker(
    title: 'select_customer'.tr,
    searchHint: 'search_customers'.tr,
    allLabel: 'all_customers'.tr,
    selected: _customer,
    loader: widget.loadCustomerOptions,
    onSelected: (value) => setState(() => _customer = value),
  );

  void _openOptionPicker({
    required String title,
    required String searchHint,
    required String allLabel,
    required InvoiceFilterOption? selected,
    required InvoiceFilterOptionLoader loader,
    required ValueChanged<InvoiceFilterOption?> onSelected,
  }) {
    showFatooraModalBottomSheet<void>(
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
}

Future<void> showInvoiceSortSheet({
  required BuildContext context,
  required InvoiceSortField initialField,
  required InvoiceSortDirection initialDirection,
  required bool forceInvoiceDate,
  required ValueChanged<InvoiceSortSelection> onApply,
}) {
  return showFatooraModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: AppColor.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => _InvoiceSortSheet(
      initialField: initialField,
      initialDirection: initialDirection,
      forceInvoiceDate: forceInvoiceDate,
      onApply: onApply,
    ),
  );
}

class _InvoiceSortSheet extends StatefulWidget {
  const _InvoiceSortSheet({
    required this.initialField,
    required this.initialDirection,
    required this.forceInvoiceDate,
    required this.onApply,
  });

  final InvoiceSortField initialField;
  final InvoiceSortDirection initialDirection;
  final bool forceInvoiceDate;
  final ValueChanged<InvoiceSortSelection> onApply;

  @override
  State<_InvoiceSortSheet> createState() => _InvoiceSortSheetState();
}

class _InvoiceSortSheetState extends State<_InvoiceSortSheet> {
  late InvoiceSortField _field = widget.forceInvoiceDate
      ? InvoiceSortField.invoiceDate
      : widget.initialField;
  late InvoiceSortDirection _direction = widget.initialDirection;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.82,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _SheetHeader(title: 'sort_invoices'.tr),
              if (widget.forceInvoiceDate) ...[
                const SizedBox(height: 8),
                Text(
                  'date_range_sort_notice'.tr,
                  key: const ValueKey('invoice-sort-date-notice'),
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: AppColor.grey),
                ),
              ],
              const SizedBox(height: 8),
              Expanded(
                child: ListView(
                  children: [
                    for (final field in InvoiceSortField.values)
                      RadioListTile<InvoiceSortField>(
                        key: ValueKey('invoice-sort-${field.name}'),
                        value: field,
                        groupValue: _field,
                        onChanged:
                            widget.forceInvoiceDate &&
                                field != InvoiceSortField.invoiceDate
                            ? null
                            : (value) {
                                if (value != null) {
                                  setState(() => _field = value);
                                }
                              },
                        title: Text(invoiceSortLabel(field).tr),
                        secondary:
                            widget.forceInvoiceDate &&
                                field != InvoiceSortField.invoiceDate
                            ? const Icon(Icons.lock_outline_rounded, size: 18)
                            : null,
                        dense: true,
                      ),
                    const Divider(height: 24),
                    SegmentedButton<InvoiceSortDirection>(
                      key: const ValueKey('invoice-sort-direction'),
                      segments: [
                        ButtonSegment(
                          value: InvoiceSortDirection.ascending,
                          icon: const Icon(Icons.arrow_upward_rounded),
                          label: Text('ascending'.tr),
                        ),
                        ButtonSegment(
                          value: InvoiceSortDirection.descending,
                          icon: const Icon(Icons.arrow_downward_rounded),
                          label: Text('descending'.tr),
                        ),
                      ],
                      selected: {_direction},
                      onSelectionChanged: (value) =>
                          setState(() => _direction = value.single),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              FilledButton(
                key: const ValueKey('invoice-sort-apply'),
                onPressed: () {
                  widget.onApply(InvoiceSortSelection(_field, _direction));
                  Navigator.of(context).pop();
                },
                style: FilledButton.styleFrom(
                  backgroundColor: AppColor.primaryColor,
                  minimumSize: const Size.fromHeight(48),
                ),
                child: Text('apply_sort'.tr),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SheetHeader extends StatelessWidget {
  const _SheetHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: AppColor.secondaryColor,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        IconButton(
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.close_rounded),
        ),
      ],
    );
  }
}

String invoiceSortLabel(InvoiceSortField value) => switch (value) {
  InvoiceSortField.invoiceNumber => 'invoice_number',
  InvoiceSortField.invoiceDate => 'invoice_date',
  InvoiceSortField.customerName => 'customer_name',
  InvoiceSortField.salesRepresentativeName => 'sales_rep',
  InvoiceSortField.invoiceTotal => 'grand_total',
  InvoiceSortField.remainingBalance => 'remaining_amount',
  InvoiceSortField.invoiceStatus => 'invoice_status',
  InvoiceSortField.createdDate => 'created_date',
};

String invoiceTypeLabel(InvoiceType value) => switch (value) {
  InvoiceType.regular => 'regular_invoice',
  InvoiceType.electronic => 'electronic_invoice',
};

String invoiceStatusLabel(InvoiceStatus value) => switch (value) {
  InvoiceStatus.draft => 'draft',
  InvoiceStatus.confirmed => 'confirmed',
  InvoiceStatus.pendingSubmit => 'pending_submit',
  InvoiceStatus.accepted => 'accepted',
  InvoiceStatus.rejected => 'rejected',
  InvoiceStatus.cancelled => 'cancelled',
};

String invoiceDateRangeLabel(DateTime? from, DateTime? to) {
  if (from == null && to == null) return 'date_range'.tr;
  final start = from == null ? '...' : _formatInvoiceDate(from);
  final end = to == null ? '...' : _formatInvoiceDate(to);
  return '$start - $end';
}

String _formatInvoiceDate(DateTime date) =>
    '${date.year}/${date.month.toString().padLeft(2, '0')}/${date.day.toString().padLeft(2, '0')}';
