import 'package:fatoora/core/class/statusrequest.dart';
import 'package:fatoora/core/constants/color.dart';
import 'package:fatoora/core/motion/fatoora_overlays.dart';
import 'package:fatoora/core/motion/fatoora_motion_widgets.dart';
import 'package:fatoora/core/widgets/responsive_data_table_card.dart';
import 'package:fatoora/features/admin_dashboard/view/widgets/dashboard_card.dart';
import 'package:fatoora/features/financial/controllers/cash_movements_controller.dart';
import 'package:fatoora/features/financial/data/models/cash_movement_model.dart';
import 'package:fatoora/features/financial/data/models/financial_dashboard_snapshot.dart';
import 'package:fatoora/features/financial/view/widgets/cash_movement_presentation.dart';
import 'package:fatoora/features/shared/business/business_page_widgets.dart';
import 'package:fatoora/features/shared/business/business_shell.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

class CashMovementsScreen extends StatelessWidget {
  const CashMovementsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return GetBuilder<CashMovementsController>(
      builder: (controller) => BusinessShell(
        title: 'financial_cash'.tr,
        child: RefreshIndicator(
          onRefresh: controller.refreshCash,
          color: AppColor.primaryColor,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final padding = constraints.maxWidth < 600 ? 14.0 : 24.0;
              return SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.fromLTRB(padding, padding, padding, 96),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1220),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _CashHeader(controller: controller),
                        if (controller.statusRequest == StatusRequest.success &&
                            controller.isAdmin &&
                            controller
                                .snapshot
                                .repCashOutstandingBySalesRep
                                .isNotEmpty) ...[
                          const SizedBox(height: 16),
                          _RepCashBalances(controller: controller),
                        ],
                        const SizedBox(height: 16),
                        _CashResults(controller: controller),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _CashHeader extends StatelessWidget {
  const _CashHeader({required this.controller});

  final CashMovementsController controller;

  @override
  Widget build(BuildContext context) {
    final controls = Wrap(
      spacing: 8,
      runSpacing: 8,
      alignment: WrapAlignment.end,
      children: [
        OutlinedButton.icon(
          onPressed: () async {
            final range = await showDateRangePicker(
              context: context,
              firstDate: DateTime(2020),
              lastDate: DateTime.now().add(const Duration(days: 365)),
              initialDateRange:
                  controller.fromDate != null && controller.toDate != null
                  ? DateTimeRange(
                      start: controller.fromDate!,
                      end: controller.toDate!,
                    )
                  : null,
            );
            if (range != null) {
              controller.setDateRange(range.start, range.end);
            }
          },
          icon: const Icon(Icons.date_range_outlined),
          label: Text('financial_filter_dates'.tr),
        ),
        if (controller.fromDate != null || controller.toDate != null)
          IconButton.outlined(
            tooltip: 'financial_clear_dates'.tr,
            onPressed: controller.clearDateRange,
            icon: const Icon(Icons.close_rounded),
          ),
        OutlinedButton.icon(
          onPressed: controller.isPrinting ? null : controller.printCashReport,
          icon: controller.isPrinting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: FatooraProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.picture_as_pdf_outlined),
          label: Text('export_pdf'.tr),
        ),
      ],
    );

    return DashboardCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          BusinessPageHeader(
            title: 'financial_cash'.tr,
            subtitle: 'financial_cash_subtitle'.tr,
            trailing: controls,
            stretchTrailingOnCompact: false,
          ),
          if (controller.statusRequest == StatusRequest.success) ...[
            const SizedBox(height: 14),
            Text(
              controller.isAdmin
                  ? 'financial_company_cash'.tr
                  : 'ledger_rep_cash'.tr,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: AppColor.secondaryColor,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 10),
            _CashSummaryGrid(
              snapshot: controller.snapshot,
              isAdmin: controller.isAdmin,
            ),
            const SizedBox(height: 8),
            Text('cash_scope_hint'.tr),
            Text('cash_balance_hint'.tr),
          ],
        ],
      ),
    );
  }
}

class _CashSummaryGrid extends StatelessWidget {
  const _CashSummaryGrid({required this.snapshot, required this.isAdmin});

  final FinancialCashSnapshot snapshot;
  final bool isAdmin;

  @override
  Widget build(BuildContext context) {
    final tiles = [
      _CashSummaryData(
        titleKey: isAdmin
            ? 'cash_company_opening'
            : 'financial_opening_balance',
        value: snapshot.units('openingBalance'),
        color: AppColor.secondaryColor,
        icon: Icons.first_page_rounded,
      ),
      _CashSummaryData(
        titleKey: isAdmin ? 'cash_all_accounts_in' : 'financial_period_cash_in',
        value: snapshot.units('totalIn'),
        color: AppColor.success,
        icon: Icons.south_west_rounded,
      ),
      _CashSummaryData(
        titleKey: isAdmin
            ? 'cash_all_accounts_out'
            : 'financial_period_cash_out',
        value: snapshot.units('totalOut'),
        color: AppColor.error,
        icon: Icons.north_east_rounded,
      ),
      _CashSummaryData(
        titleKey: isAdmin
            ? 'cash_company_closing'
            : 'financial_closing_balance',
        value: snapshot.units('closingBalance'),
        color: AppColor.primaryColor,
        icon: Icons.last_page_rounded,
      ),
      if (isAdmin)
        _CashSummaryData(
          titleKey: 'financial_rep_cash_outstanding',
          value: snapshot.units('repCashOutstanding'),
          color: AppColor.secondaryColor,
          icon: Icons.payments_outlined,
        ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 760 ? 3 : 1;
        const spacing = 12.0;
        final width =
            (constraints.maxWidth - (columns - 1) * spacing) / columns;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final tile in tiles)
              _CashSummaryTile(
                width: width,
                titleKey: tile.titleKey,
                value: tile.value,
                color: tile.color,
                icon: tile.icon,
              ),
          ],
        );
      },
    );
  }
}

class _CashSummaryData {
  const _CashSummaryData({
    required this.titleKey,
    required this.value,
    required this.color,
    required this.icon,
  });

  final String titleKey;
  final BigInt? value;
  final Color color;
  final IconData icon;
}

class _CashSummaryTile extends StatelessWidget {
  const _CashSummaryTile({
    required this.width,
    required this.titleKey,
    required this.value,
    required this.color,
    required this.icon,
  });

  final double width;
  final String titleKey;
  final BigInt? value;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  titleKey.tr,
                  style: Theme.of(
                    context,
                  ).textTheme.labelMedium?.copyWith(color: AppColor.grey),
                ),
                const SizedBox(height: 3),
                Text(
                  cashMoneyText(
                    value,
                    t: (k) => k.tr,
                    arabic: Get.locale?.languageCode == 'ar',
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: color,
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

class _RepCashBalances extends StatelessWidget {
  const _RepCashBalances({required this.controller});

  final CashMovementsController controller;

  @override
  Widget build(BuildContext context) {
    return DashboardCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'financial_cash_by_rep'.tr,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: AppColor.secondaryColor,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 10),
          for (final rep
              in controller.snapshot.repCashOutstandingBySalesRep) ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final name = Text(
                    rep.salesRepName.isEmpty
                        ? 'sales_rep'.tr
                        : rep.salesRepName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColor.secondaryColor,
                      fontWeight: FontWeight.w700,
                    ),
                  );
                  final amount = Text(
                    cashMoneyText(
                      rep.cashUnits,
                      t: (k) => k.tr,
                      arabic: Get.locale?.languageCode == 'ar',
                    ),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: rep.amount > 0 ? AppColor.success : AppColor.grey,
                      fontWeight: FontWeight.w900,
                    ),
                  );
                  final action = OutlinedButton.icon(
                    onPressed: rep.amount <= 0 || controller.isSavingSettlement
                        ? null
                        : () => _showSettlementDialog(context, controller, rep),
                    icon: const Icon(Icons.payments_outlined),
                    label: Text('financial_settle'.tr),
                  );
                  if (constraints.maxWidth < 530 ||
                      MediaQuery.textScalerOf(context).scale(1) > 1.3) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        name,
                        const SizedBox(height: 6),
                        amount,
                        const SizedBox(height: 8),
                        action,
                      ],
                    );
                  }
                  return Row(
                    children: [
                      Expanded(child: name),
                      const SizedBox(width: 10),
                      amount,
                      const SizedBox(width: 8),
                      action,
                    ],
                  );
                },
              ),
            ),
            const Divider(height: 1, color: Color(0xFFF0F1F5)),
          ],
        ],
      ),
    );
  }
}

class _CashResults extends StatelessWidget {
  const _CashResults({required this.controller});
  final CashMovementsController controller;

  @override
  Widget build(BuildContext context) {
    if (controller.statusRequest == StatusRequest.loading) {
      return const Center(
        key: ValueKey('cash-results-loading'),
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 48),
          child: CircularProgressIndicator(),
        ),
      );
    }
    if (controller.statusRequest != StatusRequest.success) {
      return BusinessEmptyState(
        key: const ValueKey('cash-results-error'),
        icon: Icons.error_outline_rounded,
        title: controller.loadErrorMessageKey.tr,
        action: OutlinedButton.icon(
          onPressed: controller.loadCash,
          icon: const Icon(Icons.refresh_rounded),
          label: Text('items_retry'.tr),
        ),
      );
    }
    if (controller.snapshot.movements.isEmpty) {
      return const _EmptyCashMovements();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _CashMovementList(controller: controller),
        if (controller.loadMoreErrorMessageKey != null) ...[
          const SizedBox(height: 12),
          BusinessEmptyState(
            key: const ValueKey('cash-load-more-error'),
            icon: Icons.error_outline_rounded,
            title: controller.loadMoreErrorMessageKey!.tr,
            action: OutlinedButton.icon(
              onPressed: controller.loadMore,
              icon: const Icon(Icons.refresh_rounded),
              label: Text('items_retry'.tr),
            ),
          ),
        ],
        if (controller.hasMore &&
            controller.loadMoreErrorMessageKey == null) ...[
          const SizedBox(height: 12),
          BusinessLoadMoreButton(
            loading: controller.isLoadingMore,
            onPressed: controller.loadMore,
          ),
        ],
      ],
    );
  }
}

class _CashMovementList extends StatelessWidget {
  const _CashMovementList({required this.controller});

  final CashMovementsController controller;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 900 &&
            MediaQuery.textScalerOf(context).scale(1) <= 1.3) {
          return _CashMovementTable(controller: controller);
        }
        final groups = cashMovementPresentationGroups(
          controller.snapshot.movements,
        );
        final twoColumns =
            constraints.maxWidth >= 650 &&
            MediaQuery.textScalerOf(context).scale(1) <= 1.3;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final group in groups)
              SizedBox(
                width: twoColumns
                    ? (constraints.maxWidth - 12) / 2
                    : constraints.maxWidth,
                child: group.length == 2
                    ? _SettlementPairCard(movements: group)
                    : _CashMovementCard(
                        movement: group.single,
                        showRepresentative: controller.isAdmin,
                      ),
              ),
          ],
        );
      },
    );
  }
}

class _CashMovementCard extends StatelessWidget {
  const _CashMovementCard({
    required this.movement,
    required this.showRepresentative,
  });

  final CashMovementModel movement;
  final bool showRepresentative;

  @override
  Widget build(BuildContext context) {
    final date = DateFormat.yMd();
    final color = !movement.hasDirection
        ? AppColor.grey
        : movement.isOut
        ? AppColor.error
        : AppColor.success;
    return DashboardCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                !movement.hasDirection
                    ? Icons.help_outline
                    : movement.isOut
                    ? Icons.north_east_rounded
                    : Icons.south_west_rounded,
                color: color,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  cashTypeText(movement, (k) => k.tr),
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: AppColor.secondaryColor,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Text(
                cashDirectionText(movement, (k) => k.tr),
                style: TextStyle(color: color, fontWeight: FontWeight.w900),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            cashAmountText(
              movement,
              t: (k) => k.tr,
              arabic: Get.locale?.languageCode == 'ar',
            ),
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: color,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            cashAccountText(movement, (k) => k.tr),
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          Text(
            [
              if (movement.effectiveReferenceNumber.isNotEmpty)
                movement.effectiveReferenceNumber,
              if (movement.settlementId.isNotEmpty) movement.settlementId,
              if (movement.customerName.isNotEmpty) movement.customerName,
              if (showRepresentative && movement.salesRepName.isNotEmpty)
                '${'cash_detail_stored_rep'.tr}: ${movement.salesRepName}',
              movement.date == null
                  ? 'cash_unavailable'.tr
                  : date.format(movement.date!),
            ].join('  |  '),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          CashMovementDetails(movement: movement),
        ],
      ),
    );
  }
}

class _SettlementPairCard extends StatelessWidget {
  const _SettlementPairCard({required this.movements});
  final List<CashMovementModel> movements;

  @override
  Widget build(BuildContext context) {
    return DashboardCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'financial_cash_settlement'.tr,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: AppColor.secondaryColor,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            movements.first.settlementId,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 10),
          for (final movement in movements) ...[
            LayoutBuilder(
              builder: (context, constraints) {
                final label = Text(
                  '${cashDirectionText(movement, (k) => k.tr)} - ${cashAccountText(movement, (k) => k.tr)}',
                );
                final amount = Text(
                  cashAmountText(
                    movement,
                    t: (k) => k.tr,
                    arabic: Get.locale?.languageCode == 'ar',
                  ),
                  style: TextStyle(
                    color: movement.isOut ? AppColor.error : AppColor.success,
                    fontWeight: FontWeight.w900,
                  ),
                );
                if (constraints.maxWidth < 380 ||
                    MediaQuery.textScalerOf(context).scale(1) > 1.3) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [label, const SizedBox(height: 3), amount],
                  );
                }
                return Row(
                  children: [
                    Expanded(child: label),
                    const SizedBox(width: 8),
                    amount,
                  ],
                );
              },
            ),
            CashMovementDetails(movement: movement),
            const SizedBox(height: 6),
          ],
          Text(
            movements.first.date == null
                ? 'cash_unavailable'.tr
                : DateFormat.yMd().format(movements.first.date!),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _CashMovementTable extends StatelessWidget {
  const _CashMovementTable({required this.controller});
  final CashMovementsController controller;

  @override
  Widget build(BuildContext context) {
    DataColumn column(String key, double width) => DataColumn(
      label: SizedBox(
        width: width,
        child: Text(key.tr, maxLines: 2, overflow: TextOverflow.ellipsis),
      ),
    );
    return ResponsiveDataTableCard(
      minWidth: controller.isAdmin ? 1050 : 900,
      child: DataTable(
        columnSpacing: 14,
        horizontalMargin: 14,
        columns: [
          column('cash_direction', 80),
          column('financial_amount', 120),
          column('financial_type', 145),
          column('financial_reference', 140),
          column('cash_account', 145),
          column('financial_date', 100),
          column('cash_details', 80),
          if (controller.isAdmin) column('cash_detail_stored_rep', 125),
        ],
        rows: [
          for (final movement in controller.snapshot.movements)
            DataRow(
              cells: [
                DataCell(
                  BoundedTableText(
                    cashDirectionText(movement, (k) => k.tr),
                    width: 80,
                  ),
                ),
                DataCell(
                  BoundedTableText(
                    cashAmountText(
                      movement,
                      t: (k) => k.tr,
                      arabic: Get.locale?.languageCode == 'ar',
                    ),
                    width: 120,
                    forceLtr: true,
                  ),
                ),
                DataCell(
                  BoundedTableText(
                    cashTypeText(movement, (k) => k.tr),
                    width: 145,
                  ),
                ),
                DataCell(
                  BoundedTableText(
                    movement.effectiveReferenceNumber.isNotEmpty
                        ? movement.effectiveReferenceNumber
                        : movement.settlementId.isNotEmpty
                        ? movement.settlementId
                        : 'cash_unavailable'.tr,
                    width: 140,
                    forceLtr: true,
                  ),
                ),
                DataCell(
                  BoundedTableText(
                    cashAccountText(movement, (k) => k.tr),
                    width: 145,
                  ),
                ),
                DataCell(
                  BoundedTableText(
                    movement.date == null
                        ? 'cash_unavailable'.tr
                        : DateFormat.yMd().format(movement.date!),
                    width: 100,
                    forceLtr: true,
                  ),
                ),
                DataCell(
                  IconButton(
                    key: ValueKey('cash-open-${movement.id}'),
                    tooltip: 'cash_details'.tr,
                    icon: const Icon(Icons.info_outline),
                    onPressed: () => showModalBottomSheet<void>(
                      context: context,
                      isScrollControlled: true,
                      useSafeArea: true,
                      builder: (_) => FractionallySizedBox(
                        heightFactor: 0.85,
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.all(20),
                          child: CashMovementDetails(
                            movement: movement,
                            initiallyExpanded: true,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                if (controller.isAdmin)
                  DataCell(
                    BoundedTableText(
                      movement.salesRepName.isNotEmpty
                          ? movement.salesRepName
                          : movement.salesRepId.isNotEmpty
                          ? movement.salesRepId
                          : 'cash_unavailable'.tr,
                      width: 125,
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _EmptyCashMovements extends StatelessWidget {
  const _EmptyCashMovements();

  @override
  Widget build(BuildContext context) {
    return BusinessEmptyState(
      icon: Icons.payments_outlined,
      title: 'financial_no_cash_movements'.tr,
    );
  }
}

Future<void> _showSettlementDialog(
  BuildContext context,
  CashMovementsController controller,
  FinancialRepAmount rep,
) async {
  final amountController = TextEditingController(
    text: rep.amount.toStringAsFixed(3),
  );
  final notesController = TextEditingController();
  final result = await showFatooraGetDialog<bool>(
    AlertDialog(
      scrollable: true,
      title: Text('financial_cash_settlement'.tr),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            rep.salesRepName.isEmpty ? 'sales_rep'.tr : rep.salesRepName,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'financial_settlement_transfer_hint'.tr,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 6),
          Text(
            '${'financial_rep_cash_outstanding'.tr}: '
            '${NumberFormat.currency(symbol: 'JOD ', decimalDigits: 3).format(rep.amount)}',
          ),
          const SizedBox(height: 14),
          TextField(
            controller: amountController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: 'financial_amount'.tr,
              prefixIcon: const Icon(Icons.payments_outlined),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: notesController,
            decoration: InputDecoration(
              labelText: 'notes'.tr,
              prefixIcon: const Icon(Icons.notes_outlined),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Get.back(result: false),
          child: Text('dashboard_cancel'.tr),
        ),
        FilledButton(
          onPressed: () => Get.back(result: true),
          child: Text('financial_settle'.tr),
        ),
      ],
    ),
  );
  if (result != true) {
    amountController.dispose();
    notesController.dispose();
    return;
  }
  final amount = double.tryParse(amountController.text.trim()) ?? 0;
  final notes = notesController.text.trim();
  amountController.dispose();
  notesController.dispose();
  if (amount <= 0 || amount > rep.amount) {
    Get.snackbar('financial_cash_settlement'.tr, 'financial_invalid_data'.tr);
    return;
  }
  await controller.recordSettlement(rep: rep, amount: amount, notes: notes);
}
