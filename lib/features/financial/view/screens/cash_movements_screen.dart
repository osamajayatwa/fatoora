import 'package:fatoora/core/class/handilingdataview.dart';
import 'package:fatoora/core/constants/color.dart';
import 'package:fatoora/features/admin_dashboard/view/widgets/dashboard_card.dart';
import 'package:fatoora/features/financial/controllers/cash_movements_controller.dart';
import 'package:fatoora/features/financial/data/models/cash_movement_model.dart';
import 'package:fatoora/features/financial/data/models/financial_dashboard_snapshot.dart';
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
        child: HandilingDataView(
          statusrequest: controller.statusRequest,
          errorMessage: controller.loadErrorMessageKey.tr,
          retryLabel: 'items_retry'.tr,
          onRetry: controller.loadCash,
          widget: RefreshIndicator(
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
                          if (controller.isAdmin &&
                              controller
                                  .snapshot
                                  .repCashOutstandingBySalesRep
                                  .isNotEmpty) ...[
                            const SizedBox(height: 16),
                            _RepCashBalances(controller: controller),
                          ],
                          const SizedBox(height: 16),
                          if (controller.snapshot.movements.isEmpty)
                            const _EmptyCashMovements()
                          else
                            _CashMovementList(controller: controller),
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

class _CashHeader extends StatelessWidget {
  const _CashHeader({required this.controller});

  final CashMovementsController controller;

  @override
  Widget build(BuildContext context) {
    final compact =
        MediaQuery.sizeOf(context).width < 760 ||
        MediaQuery.textScalerOf(context).scale(1) > 1.3;
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
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.picture_as_pdf_outlined),
          label: Text('export_pdf'.tr),
        ),
      ],
    );

    final title = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'financial_cash'.tr,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            color: AppColor.secondaryColor,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'financial_cash_subtitle'.tr,
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: AppColor.grey),
        ),
      ],
    );

    return DashboardCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          compact
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [title, const SizedBox(height: 12), controls],
                )
              : Row(
                  children: [
                    Expanded(child: title),
                    const SizedBox(width: 16),
                    controls,
                  ],
                ),
          const SizedBox(height: 18),
          _CashSummaryGrid(
            snapshot: controller.snapshot,
            isAdmin: controller.isAdmin,
          ),
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
        titleKey: 'financial_opening_balance',
        value: snapshot.openingBalance,
        color: AppColor.secondaryColor,
        icon: Icons.first_page_rounded,
      ),
      _CashSummaryData(
        titleKey: 'financial_period_cash_in',
        value: snapshot.totalIn,
        color: AppColor.success,
        icon: Icons.south_west_rounded,
      ),
      _CashSummaryData(
        titleKey: 'financial_period_cash_out',
        value: snapshot.totalOut,
        color: AppColor.error,
        icon: Icons.north_east_rounded,
      ),
      _CashSummaryData(
        titleKey: 'financial_closing_balance',
        value: snapshot.closingBalance,
        color: AppColor.primaryColor,
        icon: Icons.last_page_rounded,
      ),
      if (isAdmin)
        _CashSummaryData(
          titleKey: 'financial_rep_cash_outstanding',
          value: snapshot.repCashOutstanding,
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
  final double value;
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
  final double value;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(symbol: 'JOD ', decimalDigits: 3);
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
                  currency.format(value),
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
    final currency = NumberFormat.currency(symbol: 'JOD ', decimalDigits: 3);
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
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      rep.salesRepName.isEmpty
                          ? 'sales_rep'.tr
                          : rep.salesRepName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppColor.secondaryColor,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    currency.format(rep.amount),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: rep.amount > 0 ? AppColor.success : AppColor.grey,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: rep.amount <= 0 || controller.isSavingSettlement
                        ? null
                        : () => _showSettlementDialog(context, controller, rep),
                    icon: const Icon(Icons.payments_outlined),
                    label: Text('financial_settle'.tr),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: Color(0xFFF0F1F5)),
          ],
        ],
      ),
    );
  }
}

class _CashMovementList extends StatelessWidget {
  const _CashMovementList({required this.controller});

  final CashMovementsController controller;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final movement in controller.snapshot.movements) ...[
          _CashMovementCard(movement: movement),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}

class _CashMovementCard extends StatelessWidget {
  const _CashMovementCard({required this.movement});

  final CashMovementModel movement;

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(symbol: 'JOD ', decimalDigits: 3);
    final date = DateFormat.yMd();
    final color = movement.isOut ? AppColor.error : AppColor.success;
    return DashboardCard(
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(
              movement.isOut
                  ? Icons.north_east_rounded
                  : Icons.south_west_rounded,
              color: color,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'financial_movement_${movement.effectiveType}'.tr,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColor.secondaryColor,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  [
                    if (movement.effectiveReferenceNumber.isNotEmpty)
                      movement.effectiveReferenceNumber,
                    if (movement.customerName.isNotEmpty) movement.customerName,
                    if (movement.salesRepName.isNotEmpty) movement.salesRepName,
                    date.format(movement.date),
                  ].join('  |  '),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: AppColor.grey),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            '${movement.isOut ? '-' : '+'}${currency.format(movement.amount)}',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w900,
            ),
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
    return DashboardCard(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 36),
        child: Column(
          children: [
            const Icon(Icons.payments_outlined, size: 44, color: AppColor.grey),
            const SizedBox(height: 12),
            Text(
              'financial_no_cash_movements'.tr,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: AppColor.secondaryColor,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
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
  final result = await Get.dialog<bool>(
    AlertDialog(
      title: Text('financial_cash_settlement'.tr),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            rep.salesRepName.isEmpty ? 'sales_rep'.tr : rep.salesRepName,
            style: Theme.of(context).textTheme.titleMedium,
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
