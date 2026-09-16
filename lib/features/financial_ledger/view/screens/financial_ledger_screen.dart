import 'package:fatoora/core/class/handilingdataview.dart';
import 'package:fatoora/core/constants/color.dart';
import 'package:fatoora/features/admin_dashboard/view/widgets/dashboard_card.dart';
import 'package:fatoora/features/financial_ledger/controllers/financial_ledger_controller.dart';
import 'package:fatoora/features/financial_ledger/data/models/financial_ledger_entry.dart';
import 'package:fatoora/features/shared/business/business_shell.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

class FinancialLedgerScreen extends StatelessWidget {
  const FinancialLedgerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return GetBuilder<FinancialLedgerController>(
      builder: (controller) => BusinessShell(
        title: 'financial_ledger'.tr,
        child: HandilingDataView(
          statusrequest: controller.statusRequest,
          errorMessage: controller.loadErrorMessageKey.tr,
          retryLabel: 'items_retry'.tr,
          onRetry: controller.loadInitial,
          widget: RefreshIndicator(
            color: AppColor.primaryColor,
            onRefresh: controller.refreshLedger,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final padding = constraints.maxWidth < 600 ? 14.0 : 24.0;
                return SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: EdgeInsets.fromLTRB(padding, padding, padding, 96),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1500),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _Header(controller: controller),
                          const SizedBox(height: 16),
                          _Summary(controller: controller),
                          const SizedBox(height: 16),
                          _Filters(controller: controller),
                          const SizedBox(height: 16),
                          if (controller.entries.isEmpty)
                            const _EmptyLedger()
                          else
                            _LedgerResults(controller: controller),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.controller});

  final FinancialLedgerController controller;

  @override
  Widget build(BuildContext context) {
    return DashboardCard(
      child: Wrap(
        spacing: 16,
        runSpacing: 14,
        crossAxisAlignment: WrapCrossAlignment.center,
        alignment: WrapAlignment.spaceBetween,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 650),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'financial_ledger'.tr,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: AppColor.secondaryColor,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  'ledger_subtitle'.tr,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: AppColor.grey),
                ),
              ],
            ),
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: controller.isCopying
                    ? null
                    : controller.copyFilteredRows,
                icon: controller.isCopying
                    ? const _ButtonLoader()
                    : const Icon(Icons.content_copy_rounded),
                label: Text('ledger_copy_tsv'.tr),
              ),
              FilledButton.icon(
                onPressed: controller.isExporting
                    ? null
                    : controller.exportAccountingReport,
                icon: controller.isExporting
                    ? const _ButtonLoader(color: Colors.white)
                    : const Icon(Icons.download_rounded),
                label: Text('ledger_export_accounting_report'.tr),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ButtonLoader extends StatelessWidget {
  const _ButtonLoader({this.color});

  final Color? color;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 16,
    height: 16,
    child: CircularProgressIndicator(strokeWidth: 2, color: color),
  );
}

class _Summary extends StatelessWidget {
  const _Summary({required this.controller});

  final FinancialLedgerController controller;

  @override
  Widget build(BuildContext context) {
    final summary = controller.summary;
    final cards = [
      _SummaryData(
        'ledger_summary_net_sales',
        summary.sales,
        Icons.trending_up_rounded,
        AppColor.primaryColor,
      ),
      _SummaryData(
        'ledger_summary_gross_cash_sales',
        summary.cashSales,
        Icons.point_of_sale_rounded,
        AppColor.success,
      ),
      _SummaryData(
        'ledger_summary_gross_credit_sales',
        summary.creditSales,
        Icons.pending_actions_rounded,
        const Color(0xFF6B5B95),
      ),
      _SummaryData(
        'ledger_summary_receipts',
        summary.receipts,
        Icons.payments_outlined,
        const Color(0xFF2D8C73),
      ),
      _SummaryData(
        'ledger_summary_expenses',
        summary.expenses,
        Icons.receipt_long_outlined,
        AppColor.error,
      ),
      _SummaryData(
        'ledger_summary_returns',
        summary.returns,
        Icons.assignment_return_outlined,
        const Color(0xFFB7791F),
      ),
      _SummaryData(
        'ledger_summary_settlements',
        summary.settlements,
        Icons.swap_horiz_rounded,
        AppColor.secondaryColor,
      ),
      _SummaryData(
        'ledger_summary_receivables_net',
        summary.receivables,
        Icons.account_balance_outlined,
        const Color(0xFF3C7A89),
      ),
      _SummaryData(
        'ledger_summary_company_cash_net',
        summary.companyCashNet,
        Icons.account_balance_wallet_outlined,
        AppColor.secondaryColor,
      ),
      _SummaryData(
        'ledger_summary_rep_cash_in',
        summary.repCashIn,
        Icons.south_west_rounded,
        AppColor.success,
      ),
      _SummaryData(
        'ledger_summary_rep_cash_out',
        summary.repCashOut,
        Icons.north_east_rounded,
        AppColor.error,
      ),
    ];
    return DashboardCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final title = Text(
                'ledger_filtered_summary'.tr,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: AppColor.secondaryColor,
                  fontWeight: FontWeight.w900,
                ),
              );
              final count = Text(
                '${summary.entryCount} ${'ledger_entries'.tr}',
                style: Theme.of(
                  context,
                ).textTheme.labelLarge?.copyWith(color: AppColor.grey),
              );
              if (constraints.maxWidth < 520 ||
                  MediaQuery.textScalerOf(context).scale(1) > 1.3) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [title, const SizedBox(height: 6), count],
                );
              }
              return Row(
                children: [
                  Expanded(child: title),
                  const SizedBox(width: 12),
                  count,
                ],
              );
            },
          ),
          const SizedBox(height: 13),
          LayoutBuilder(
            builder: (context, constraints) {
              final largeText = MediaQuery.textScalerOf(context).scale(1) > 1.3;
              final width = !largeText && constraints.maxWidth >= 900
                  ? (constraints.maxWidth - 30) / 4
                  : !largeText && constraints.maxWidth >= 560
                  ? (constraints.maxWidth - 10) / 2
                  : constraints.maxWidth;
              return Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final card in cards)
                    _SummaryCard(width: width, data: card),
                ],
              );
            },
          ),
          const SizedBox(height: 10),
          Text(
            'ledger_summary_note'.tr,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: AppColor.grey),
          ),
        ],
      ),
    );
  }
}

class _SummaryData {
  const _SummaryData(this.labelKey, this.value, this.icon, this.color);

  final String labelKey;
  final double value;
  final IconData icon;
  final Color color;
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.width, required this.data});

  final double width;
  final _SummaryData data;

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(symbol: 'JOD ', decimalDigits: 3);
    return Container(
      width: width,
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: data.color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(data.icon, size: 21, color: data.color),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  data.labelKey.tr,
                  style: Theme.of(
                    context,
                  ).textTheme.labelSmall?.copyWith(color: AppColor.grey),
                ),
                const SizedBox(height: 3),
                Text(
                  currency.format(data.value),
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: data.color,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Filters extends StatelessWidget {
  const _Filters({required this.controller});

  final FinancialLedgerController controller;

  @override
  Widget build(BuildContext context) {
    final filters = controller.filters;
    return DashboardCard(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final stacked =
              constraints.maxWidth < 620 ||
              MediaQuery.textScalerOf(context).scale(1) > 1.3;
          double width(double preferred) =>
              stacked ? constraints.maxWidth : preferred;
          return Wrap(
            spacing: 10,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: width(300),
                child: TextField(
                  controller: controller.searchController,
                  onChanged: controller.onSearchChanged,
                  onSubmitted: (_) => controller.submitSearch(),
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    labelText: 'ledger_search'.tr,
                    hintText: 'ledger_search_hint'.tr,
                    errorText: controller.searchTooShort
                        ? 'ledger_search_min'.tr
                        : null,
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: controller.searchController.text.isEmpty
                        ? null
                        : IconButton(
                            onPressed: controller.clearSearch,
                            icon: const Icon(Icons.close_rounded),
                          ),
                    border: const OutlineInputBorder(),
                  ),
                ),
              ),
              _FilterDropdown(
                width: width(215),
                label: 'ledger_movement_type'.tr,
                value: filters.type,
                items: const [
                  '',
                  'invoice_sale',
                  'receipt',
                  'expense',
                  'sales_return',
                  'refund',
                  'settlement',
                  'opening_balance',
                  'opening_balance_adjustment',
                ],
                labelFor: (value) =>
                    value.isEmpty ? 'all'.tr : 'ledger_type_$value'.tr,
                onChanged: controller.setType,
              ),
              _OptionDropdown(
                width: width(250),
                label: 'ledger_account'.tr,
                value: filters.accountKey,
                options: controller.accountOptions,
                onChanged: controller.setAccount,
              ),
              _OptionDropdown(
                width: width(240),
                label: 'ledger_customer'.tr,
                value: filters.customerId,
                options: [
                  for (final customer in controller.lookups.customers)
                    LedgerFilterOption(customer.id, customer.name),
                ],
                onChanged: controller.setCustomer,
              ),
              _OptionDropdown(
                width: width(240),
                label: 'ledger_sales_rep'.tr,
                value: filters.salesRepId,
                options: [
                  for (final rep in controller.lookups.representatives)
                    LedgerFilterOption(rep.uid, rep.name),
                ],
                onChanged: controller.setSalesRep,
              ),
              _FilterDropdown(
                width: width(210),
                label: 'ledger_payment_method'.tr,
                value: filters.paymentMethod,
                items: const [
                  '',
                  'cash',
                  'credit',
                  'bank',
                  'check',
                  'cliq',
                  'personal_cash',
                  'cash_refund',
                  'credit_customer_balance',
                ],
                labelFor: (value) =>
                    value.isEmpty ? 'all'.tr : 'ledger_payment_$value'.tr,
                onChanged: controller.setPaymentMethod,
              ),
              OutlinedButton.icon(
                onPressed: () async {
                  final range = await showDateRangePicker(
                    context: context,
                    firstDate: DateTime(2020),
                    lastDate: DateTime.now().add(const Duration(days: 365)),
                    initialDateRange: DateTimeRange(
                      start: filters.fromDate,
                      end: filters.toDate,
                    ),
                  );
                  controller.setDateRange(range);
                },
                icon: const Icon(Icons.date_range_outlined),
                label: Text(
                  '${DateFormat.yMd().format(filters.fromDate)} — '
                  '${DateFormat.yMd().format(filters.toDate)}',
                ),
              ),
              TextButton.icon(
                onPressed: controller.clearFilters,
                icon: const Icon(Icons.restart_alt_rounded),
                label: Text('ledger_reset_filters'.tr),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _FilterDropdown extends StatelessWidget {
  const _FilterDropdown({
    required this.width,
    required this.label,
    required this.value,
    required this.items,
    required this.labelFor,
    required this.onChanged,
  });

  final double width;
  final String label;
  final String value;
  final List<String> items;
  final String Function(String) labelFor;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    child: DropdownButtonFormField<String>(
      value: value,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
      items: [
        for (final item in items)
          DropdownMenuItem(value: item, child: Text(labelFor(item))),
      ],
      onChanged: onChanged,
    ),
  );
}

class _OptionDropdown extends StatelessWidget {
  const _OptionDropdown({
    required this.width,
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final double width;
  final String label;
  final String value;
  final List<LedgerFilterOption> options;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    child: DropdownButtonFormField<String>(
      value: value,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
      items: [
        DropdownMenuItem(value: '', child: Text('all'.tr)),
        for (final option in options)
          DropdownMenuItem(
            value: option.id,
            child: Text(
              option.label.startsWith('ledger_')
                  ? option.label.tr
                  : option.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
      onChanged: onChanged,
    ),
  );
}

class _LedgerResults extends StatelessWidget {
  const _LedgerResults({required this.controller});

  final FinancialLedgerController controller;

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 1050;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (wide)
          _LedgerTable(controller: controller)
        else
          for (final entry in controller.entries) ...[
            _LedgerCard(
              entry: entry,
              onTap: () => controller.openOriginal(entry),
            ),
            const SizedBox(height: 10),
          ],
        if (controller.hasMore) ...[
          const SizedBox(height: 14),
          Center(
            child: OutlinedButton.icon(
              onPressed: controller.isLoadingMore ? null : controller.loadMore,
              icon: controller.isLoadingMore
                  ? const _ButtonLoader()
                  : const Icon(Icons.expand_more_rounded),
              label: Text('ledger_load_more'.tr),
            ),
          ),
        ],
      ],
    );
  }
}

class _LedgerTable extends StatelessWidget {
  const _LedgerTable({required this.controller});

  final FinancialLedgerController controller;

  @override
  Widget build(BuildContext context) {
    final date = DateFormat('yyyy-MM-dd HH:mm');
    final money = NumberFormat.currency(symbol: 'JOD ', decimalDigits: 3);
    return DashboardCard(
      padding: EdgeInsets.zero,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowColor: WidgetStatePropertyAll(
            AppColor.primaryColor.withValues(alpha: 0.08),
          ),
          columns: [
            for (final key in const [
              'ledger_date',
              'ledger_movement_type',
              'ledger_description',
              'ledger_debit',
              'ledger_credit',
              'ledger_amount',
              'ledger_customer',
              'ledger_sales_rep',
              'ledger_reference',
            ])
              DataColumn(label: Text(key.tr)),
          ],
          rows: [
            for (final entry in controller.entries)
              DataRow(
                onSelectChanged: (_) => controller.openOriginal(entry),
                cells: [
                  DataCell(Text(date.format(entry.occurredAt))),
                  DataCell(Text('ledger_type_${entry.type}'.tr)),
                  DataCell(
                    SizedBox(
                      width: 230,
                      child: Text(
                        entry.effectiveDescription,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  DataCell(
                    Text(
                      _accountLabel(
                        entry.debitAccountKey,
                        entry.debitAccountName,
                      ),
                    ),
                  ),
                  DataCell(
                    Text(
                      _accountLabel(
                        entry.creditAccountKey,
                        entry.creditAccountName,
                      ),
                    ),
                  ),
                  DataCell(
                    Text(
                      money.format(entry.amount),
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                  DataCell(Text(entry.customerName)),
                  DataCell(Text(entry.salesRepName)),
                  DataCell(Text(entry.referenceNumber)),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _LedgerCard extends StatelessWidget {
  const _LedgerCard({required this.entry, required this.onTap});

  final FinancialLedgerEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final money = NumberFormat.currency(symbol: 'JOD ', decimalDigits: 3);
    final date = DateFormat('yyyy-MM-dd HH:mm');
    return DashboardCard(
      padding: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(15),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              LayoutBuilder(
                builder: (context, constraints) {
                  final description = Text(
                    entry.effectiveDescription,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: AppColor.secondaryColor,
                      fontWeight: FontWeight.w900,
                    ),
                  );
                  final amount = Text(
                    money.format(entry.amount),
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: AppColor.primaryColor,
                      fontWeight: FontWeight.w900,
                    ),
                  );
                  if (constraints.maxWidth < 440 ||
                      MediaQuery.textScalerOf(context).scale(1) > 1.3) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        description,
                        const SizedBox(height: 5),
                        Align(
                          alignment: AlignmentDirectional.centerEnd,
                          child: amount,
                        ),
                      ],
                    );
                  }
                  return Row(
                    children: [
                      Expanded(child: description),
                      const SizedBox(width: 12),
                      amount,
                    ],
                  );
                },
              ),
              const SizedBox(height: 7),
              Text(
                '${'ledger_type_${entry.type}'.tr}  |  ${date.format(entry.occurredAt)}',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: AppColor.grey),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _AccountChip(
                    label:
                        '${'ledger_debit'.tr}: ${_accountLabel(entry.debitAccountKey, entry.debitAccountName)}',
                    color: AppColor.success,
                  ),
                  _AccountChip(
                    label:
                        '${'ledger_credit'.tr}: ${_accountLabel(entry.creditAccountKey, entry.creditAccountName)}',
                    color: AppColor.error,
                  ),
                ],
              ),
              if (entry.customerName.isNotEmpty ||
                  entry.salesRepName.isNotEmpty ||
                  entry.referenceNumber.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  [
                    entry.customerName,
                    entry.salesRepName,
                    entry.referenceNumber,
                  ].where((value) => value.isNotEmpty).join('  |  '),
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: AppColor.grey),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _AccountChip extends StatelessWidget {
  const _AccountChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      label,
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
        color: color,
        fontWeight: FontWeight.w800,
      ),
    ),
  );
}

class _EmptyLedger extends StatelessWidget {
  const _EmptyLedger();

  @override
  Widget build(BuildContext context) => DashboardCard(
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 44),
      child: Column(
        children: [
          const Icon(Icons.menu_book_outlined, size: 48, color: AppColor.grey),
          const SizedBox(height: 12),
          Text(
            'ledger_empty'.tr,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: AppColor.secondaryColor,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    ),
  );
}

String _accountLabel(String key, String fallback) => switch (key) {
  'company_cash' => 'ledger_account_company_cash'.tr,
  'sales' => 'ledger_account_sales'.tr,
  'expenses' => 'ledger_account_expenses'.tr,
  'bank_unallocated' => 'ledger_account_bank'.tr,
  'check_clearing' => 'ledger_account_checks'.tr,
  'cliq_clearing' => 'ledger_account_cliq'.tr,
  'opening_balance_equity' => 'ledger_account_opening_equity'.tr,
  _ => fallback.isEmpty ? key : fallback,
};
