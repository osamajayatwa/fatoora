import 'package:fatoora/core/class/statusrequest.dart';
import 'package:fatoora/core/constants/color.dart';
import 'package:fatoora/features/rep_inventory/controllers/rep_inventory_controllers.dart';
import 'package:fatoora/features/rep_inventory/data/models/inventory_transfer_model.dart';
import 'package:fatoora/features/rep_inventory/data/models/rep_inventory_enums.dart';
import 'package:fatoora/features/shared/business/business_shell.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

class RepInventoryScreen extends StatelessWidget {
  const RepInventoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return GetBuilder<RepInventoryController>(
      builder: (controller) => BusinessShell(
        title: 'rep_inventory_title'.tr,
        showBackButton: true,
        child: _LoadState(
          status: controller.statusRequest,
          errorKey: controller.errorKey,
          retry: controller.load,
          child: RefreshIndicator(
            onRefresh: controller.load,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              children: [
                _ResponsiveHeader(
                  title: controller.isAdmin
                      ? 'rep_inventory_title'.tr
                      : 'rep_inventory_my_inventory'.tr,
                  action: controller.isAdmin
                      ? FilledButton.icon(
                          onPressed: controller.createTransfer,
                          icon: const Icon(Icons.swap_horiz_rounded),
                          label: Text('rep_inventory_new_transfer'.tr),
                        )
                      : null,
                ),
                if (controller.isAdmin) ...[
                  const SizedBox(height: 14),
                  DropdownButtonFormField<String>(
                    value: _existingDropdownValue(
                      controller.selectedSalesRepId,
                      controller.salesReps.map((rep) => rep.uid),
                    ),
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: 'rep_inventory_sales_rep'.tr,
                      border: const OutlineInputBorder(),
                    ),
                    items: _uniqueDropdownItems(
                      controller.salesReps.map(
                        (rep) => DropdownMenuItem(
                          value: rep.uid,
                          child: Text(
                            rep.name,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ),
                    onChanged: controller.selectSalesRep,
                  ),
                ],
                const SizedBox(height: 20),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Wrap(
                      spacing: 30,
                      runSpacing: 12,
                      children: [
                        _Fact(
                          'rep_inventory_distinct_items'.tr,
                          controller.balances.length.toString(),
                        ),
                        _Fact(
                          'rep_inventory_total_quantity'.tr,
                          _quantity(
                            controller.balances.fold(
                              0,
                              (total, balance) => total + balance.quantity,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                _SectionTitle(
                  title: 'rep_inventory_balances'.tr,
                  count: controller.balances.length,
                ),
                if (controller.balances.isEmpty)
                  const _EmptyCard(keyName: 'rep_inventory_no_balances')
                else
                  ...controller.balances.map(
                    (balance) => Card(
                      child: ListTile(
                        leading: const CircleAvatar(
                          child: Icon(Icons.inventory_2_outlined),
                        ),
                        title: Text(balance.itemNameSnapshot),
                        subtitle: Text(
                          '${balance.modelSnapshot} · ${balance.unitSnapshot}\n'
                          '${'rep_inventory_last_updated'.tr}: '
                          '${DateFormat.yMd().add_jm().format(balance.updatedAt)}',
                        ),
                        isThreeLine: true,
                        trailing: Text(
                          _quantity(balance.quantity),
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                      ),
                    ),
                  ),
                const SizedBox(height: 20),
                _SectionTitle(
                  title: 'rep_inventory_recent_movements'.tr,
                  count: controller.movements.length,
                ),
                if (controller.movements.isEmpty)
                  const _EmptyCard(keyName: 'rep_inventory_no_movements')
                else
                  ...controller.movements
                      .take(40)
                      .map(
                        (movement) => Card(
                          child: ListTile(
                            leading: Icon(
                              movement.direction ==
                                      RepInventoryDirection.inbound
                                  ? Icons.south_west_rounded
                                  : Icons.north_east_rounded,
                              color:
                                  movement.direction ==
                                      RepInventoryDirection.inbound
                                  ? AppColor.success
                                  : AppColor.error,
                            ),
                            title: Text(movement.itemNameSnapshot),
                            subtitle: Text(
                              '${_reasonLabel(movement.reason)} · '
                              '${DateFormat.yMd().add_jm().format(movement.createdAt)}',
                            ),
                            trailing: Text(
                              '${movement.direction == RepInventoryDirection.inbound ? '+' : '-'}'
                              '${_quantity(movement.quantity)}',
                            ),
                          ),
                        ),
                      ),
                const SizedBox(height: 20),
                _SectionTitle(
                  title: 'rep_inventory_transfers'.tr,
                  count: controller.transfers.length,
                ),
                if (controller.transfers.isEmpty)
                  const _EmptyCard(keyName: 'rep_inventory_no_transfers')
                else
                  ...controller.transfers
                      .take(30)
                      .map(
                        (transfer) => _TransferCard(
                          transfer: transfer,
                          onTap: () => controller.openTransfer(transfer),
                        ),
                      ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class InventoryTransfersScreen extends StatelessWidget {
  const InventoryTransfersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return GetBuilder<InventoryTransfersController>(
      builder: (controller) => BusinessShell(
        title: 'rep_inventory_transfers'.tr,
        child: _LoadState(
          status: controller.statusRequest,
          errorKey: controller.errorKey,
          retry: controller.load,
          child: RefreshIndicator(
            onRefresh: controller.load,
            child: ListView(
              padding: const EdgeInsets.all(16),
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                _ResponsiveSearchHeader(
                  search: TextField(
                    controller: controller.searchController,
                    decoration: InputDecoration(
                      hintText: 'rep_inventory_search'.tr,
                      prefixIcon: const Icon(Icons.search),
                      border: const OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => controller.load(),
                  ),
                  action: FilledButton.icon(
                    onPressed: controller.create,
                    icon: const Icon(Icons.add),
                    label: Text('rep_inventory_new_transfer'.tr),
                  ),
                ),
                const SizedBox(height: 16),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final compact = constraints.maxWidth < 600;
                    final availableWidth = constraints.maxWidth;
                    return Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        SizedBox(
                          width: compact ? availableWidth : 230,
                          child: DropdownButtonFormField<String>(
                            value: _existingDropdownValue(
                              controller.selectedSalesRepId,
                              <String>[
                                '',
                                ...controller.salesReps.map((rep) => rep.uid),
                              ],
                            ),
                            isExpanded: true,
                            decoration: InputDecoration(
                              labelText: 'rep_inventory_sales_rep'.tr,
                              border: const OutlineInputBorder(),
                            ),
                            items: _uniqueDropdownItems([
                              DropdownMenuItem<String>(
                                value: '',
                                child: Text(
                                  'rep_inventory_all'.tr,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              ...controller.salesReps.map(
                                (rep) => DropdownMenuItem(
                                  value: rep.uid,
                                  child: Text(
                                    rep.name,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                            ]),
                            onChanged: (value) {
                              controller.selectedSalesRepId = value ?? '';
                              controller.load();
                            },
                          ),
                        ),
                        SizedBox(
                          width: compact ? availableWidth : 220,
                          child: DropdownButtonFormField<String>(
                            value: controller.typeFilter?.value ?? '',
                            isExpanded: true,
                            decoration: InputDecoration(
                              labelText: 'rep_inventory_transfer_type'.tr,
                              border: const OutlineInputBorder(),
                            ),
                            items: [
                              DropdownMenuItem(
                                value: '',
                                child: Text(
                                  'rep_inventory_all'.tr,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              ...InventoryTransferType.values.map(
                                (type) => DropdownMenuItem(
                                  value: type.value,
                                  child: Text(
                                    _typeLabel(type),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                            ],
                            onChanged: (value) {
                              controller.typeFilter = InventoryTransferType
                                  .values
                                  .where((type) => type.value == value)
                                  .firstOrNull;
                              controller.load();
                            },
                          ),
                        ),
                        SizedBox(
                          width: compact ? availableWidth : 180,
                          child: DropdownButtonFormField<String>(
                            value: controller.statusFilter?.value ?? '',
                            isExpanded: true,
                            decoration: InputDecoration(
                              labelText: 'rep_inventory_status'.tr,
                              border: const OutlineInputBorder(),
                            ),
                            items: [
                              DropdownMenuItem(
                                value: '',
                                child: Text(
                                  'rep_inventory_all'.tr,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              ...InventoryTransferStatus.values.map(
                                (status) => DropdownMenuItem(
                                  value: status.value,
                                  child: Text(
                                    _statusLabel(status),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                            ],
                            onChanged: (value) {
                              controller.statusFilter = InventoryTransferStatus
                                  .values
                                  .where((status) => status.value == value)
                                  .firstOrNull;
                              controller.load();
                            },
                          ),
                        ),
                        OutlinedButton.icon(
                          onPressed: () => controller.selectDateRange(context),
                          icon: const Icon(Icons.date_range_outlined),
                          label: Text(
                            controller.fromDate == null ||
                                    controller.toDate == null
                                ? 'rep_inventory_date_range'.tr
                                : '${DateFormat.yMd().format(controller.fromDate!)}'
                                      ' – '
                                      '${DateFormat.yMd().format(controller.toDate!)}',
                          ),
                        ),
                        TextButton(
                          onPressed: controller.clearFilters,
                          child: Text('rep_inventory_clear_filters'.tr),
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 16),
                if (controller.transfers.isEmpty)
                  const _EmptyCard(keyName: 'rep_inventory_no_transfers')
                else
                  ...controller.transfers.map(
                    (transfer) => _TransferCard(
                      transfer: transfer,
                      onTap: () => controller.open(transfer),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class InventoryTransferFormScreen extends StatelessWidget {
  const InventoryTransferFormScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return GetBuilder<InventoryTransferFormController>(
      builder: (controller) => BusinessShell(
        title: 'rep_inventory_new_transfer'.tr,
        showBackButton: true,
        child: _LoadState(
          status: controller.statusRequest,
          errorKey: controller.errorKey,
          retry: controller.load,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              DropdownButtonFormField<String>(
                value: _existingDropdownValue(
                  controller.selectedSalesRepId,
                  controller.salesReps.map((rep) => rep.uid),
                ),
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: 'rep_inventory_sales_rep'.tr,
                  border: const OutlineInputBorder(),
                ),
                items: _uniqueDropdownItems(
                  controller.salesReps.map(
                    (rep) => DropdownMenuItem(
                      value: rep.uid,
                      child: Text(rep.name, overflow: TextOverflow.ellipsis),
                    ),
                  ),
                ),
                onChanged: controller.selectSalesRep,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<InventoryTransferType>(
                value: controller.type,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: 'rep_inventory_transfer_type'.tr,
                  border: const OutlineInputBorder(),
                ),
                items: InventoryTransferType.values
                    .map(
                      (type) => DropdownMenuItem(
                        value: type,
                        child: Text(
                          _typeLabel(type),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                    .toList(),
                onChanged: controller.selectType,
              ),
              const SizedBox(height: 20),
              LayoutBuilder(
                builder: (context, constraints) {
                  final availableItems = controller.items
                      .where(
                        (entry) => !controller.lines.any(
                          (line) => line.itemId == entry.id,
                        ),
                      )
                      .toList(growable: false);
                  final availableItemIds = availableItems
                      .map((entry) => entry.id)
                      .toList(growable: false);
                  final selectedItemId = _existingDropdownValue(
                    controller.selectedItemId,
                    availableItemIds,
                  );
                  final item = InputDecorator(
                    isEmpty: selectedItemId == null,
                    decoration: InputDecoration(
                      labelText: 'rep_inventory_item'.tr,
                      border: const OutlineInputBorder(),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: selectedItemId,
                        isExpanded: true,
                        isDense: true,
                        items: _uniqueDropdownItems(
                          availableItems.map(
                            (entry) => DropdownMenuItem(
                              value: entry.id,
                              child: Text(
                                '${entry.name} (${entry.code}) · '
                                '${'rep_inventory_warehouse'.tr}: '
                                '${_quantity(entry.currentStock)} · '
                                '${'rep_inventory_rep_stock'.tr}: '
                                '${_quantity(controller.repQuantities[entry.id] ?? 0)}',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                        ),
                        onChanged: controller.selectItem,
                      ),
                    ),
                  );
                  final quantity = TextField(
                    controller: controller.quantityController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: 'rep_inventory_quantity'.tr,
                      border: const OutlineInputBorder(),
                    ),
                  );
                  if (constraints.maxWidth < 650) {
                    return Column(
                      children: [item, const SizedBox(height: 12), quantity],
                    );
                  }
                  return Row(
                    children: [
                      Expanded(flex: 2, child: item),
                      const SizedBox(width: 12),
                      Expanded(child: quantity),
                    ],
                  );
                },
              ),
              const SizedBox(height: 10),
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: OutlinedButton.icon(
                  onPressed: controller.addLine,
                  icon: const Icon(Icons.playlist_add),
                  label: Text('rep_inventory_add_line'.tr),
                ),
              ),
              const SizedBox(height: 16),
              if (controller.lines.isEmpty)
                const _EmptyCard(keyName: 'rep_inventory_no_lines')
              else
                ...controller.lines.map(
                  (line) => Card(
                    child: ListTile(
                      title: Text(line.itemNameSnapshot),
                      subtitle: Text(
                        '${line.modelSnapshot} · '
                        '${'rep_inventory_available'.tr}: '
                        '${_quantity(controller.type == InventoryTransferType.warehouseToRep ? controller.items.where((item) => item.id == line.itemId).map((item) => item.currentStock).firstOrNull ?? 0 : controller.repQuantities[line.itemId] ?? 0)}',
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '${_quantity(line.quantity)} ${line.unitSnapshot}',
                          ),
                          IconButton(
                            onPressed: () => controller.removeLine(line.itemId),
                            icon: const Icon(Icons.delete_outline),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 12),
              TextField(
                controller: controller.notesController,
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: 'rep_inventory_notes'.tr,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 18),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 10,
                runSpacing: 10,
                children: [
                  OutlinedButton(
                    onPressed: controller.isSaving || controller.isConfirming
                        ? null
                        : controller.saveDraft,
                    child: Text('rep_inventory_save_draft'.tr),
                  ),
                  FilledButton.icon(
                    onPressed: controller.isSaving || controller.isConfirming
                        ? null
                        : controller.confirm,
                    icon: controller.isConfirming
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.check),
                    label: Text('rep_inventory_confirm'.tr),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class InventoryTransferDetailsScreen extends StatelessWidget {
  const InventoryTransferDetailsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return GetBuilder<InventoryTransferDetailsController>(
      builder: (controller) {
        final transfer = controller.transfer;
        return BusinessShell(
          title: 'rep_inventory_transfer_details'.tr,
          showBackButton: true,
          child: _LoadState(
            status: controller.statusRequest,
            errorKey: controller.errorKey,
            retry: controller.load,
            child: transfer == null
                ? const SizedBox.shrink()
                : ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Wrap(
                            spacing: 30,
                            runSpacing: 14,
                            children: [
                              _Fact(
                                'rep_inventory_number'.tr,
                                transfer.transferNumber,
                              ),
                              _Fact(
                                'rep_inventory_sales_rep'.tr,
                                transfer.salesRepNameSnapshot,
                              ),
                              _Fact(
                                'rep_inventory_transfer_type'.tr,
                                _typeLabel(transfer.type),
                              ),
                              _Fact(
                                'rep_inventory_status'.tr,
                                _statusLabel(transfer.status),
                              ),
                              _Fact(
                                'rep_inventory_total_quantity'.tr,
                                _quantity(transfer.totalQuantity),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      ...transfer.lines.map(
                        (line) => Card(
                          child: ListTile(
                            title: Text(line.itemNameSnapshot),
                            trailing: Text(_quantity(line.quantity)),
                            subtitle: Text(
                              '${line.modelSnapshot} · ${line.unitSnapshot}\n'
                              '${'rep_inventory_warehouse'.tr}: '
                              '${_beforeAfter(line.warehouseQuantityBefore, line.warehouseQuantityAfter)} · '
                              '${'rep_inventory_rep_stock'.tr}: '
                              '${_beforeAfter(line.repQuantityBefore, line.repQuantityAfter)}\n'
                              '${'rep_inventory_movements'.tr}: '
                              '${line.companyMovementId} / ${line.repMovementId}',
                            ),
                            isThreeLine: true,
                          ),
                        ),
                      ),
                      if (transfer.notes.isNotEmpty)
                        Card(
                          child: ListTile(
                            title: Text('rep_inventory_notes'.tr),
                            subtitle: Text(transfer.notes),
                          ),
                        ),
                      if (controller.isAdmin && transfer.isDraft)
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Wrap(
                            alignment: WrapAlignment.end,
                            spacing: 10,
                            runSpacing: 10,
                            children: [
                              TextButton.icon(
                                onPressed: controller.cancel,
                                icon: const Icon(Icons.cancel_outlined),
                                label: Text('rep_inventory_cancel'.tr),
                              ),
                              TextButton.icon(
                                onPressed: () => Get.defaultDialog<void>(
                                  title: 'rep_inventory_delete_draft'.tr,
                                  middleText:
                                      'rep_inventory_delete_draft_message'.tr,
                                  textCancel: 'cancel'.tr,
                                  textConfirm: 'delete'.tr,
                                  onConfirm: () {
                                    Get.back<void>();
                                    controller.deleteDraft();
                                  },
                                ),
                                icon: const Icon(Icons.delete_outline),
                                label: Text('delete'.tr),
                              ),
                              FilledButton.icon(
                                onPressed: controller.confirm,
                                icon: const Icon(Icons.check_circle_outline),
                                label: Text('rep_inventory_confirm'.tr),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
          ),
        );
      },
    );
  }
}

class _ResponsiveHeader extends StatelessWidget {
  const _ResponsiveHeader({required this.title, this.action});

  final String title;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final titleWidget = Text(
      title,
      style: Theme.of(
        context,
      ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
    );
    if (action == null) return titleWidget;
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 520) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              titleWidget,
              const SizedBox(height: 10),
              Align(alignment: AlignmentDirectional.centerEnd, child: action),
            ],
          );
        }
        return Row(
          children: [
            Expanded(child: titleWidget),
            const SizedBox(width: 12),
            action!,
          ],
        );
      },
    );
  }
}

class _ResponsiveSearchHeader extends StatelessWidget {
  const _ResponsiveSearchHeader({required this.search, required this.action});

  final Widget search;
  final Widget action;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      if (constraints.maxWidth < 520) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [search, const SizedBox(height: 10), action],
        );
      }
      return Row(
        children: [
          Expanded(child: search),
          const SizedBox(width: 10),
          action,
        ],
      );
    },
  );
}

class _LoadState extends StatelessWidget {
  const _LoadState({
    required this.status,
    required this.errorKey,
    required this.retry,
    required this.child,
  });

  final StatusRequest status;
  final String errorKey;
  final Future<void> Function() retry;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (status == StatusRequest.loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (status != StatusRequest.success) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(errorKey.tr, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: retry, child: Text('retry'.tr)),
          ],
        ),
      );
    }
    return child;
  }
}

class _TransferCard extends StatelessWidget {
  const _TransferCard({required this.transfer, required this.onTap});

  final InventoryTransferModel transfer;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        onTap: onTap,
        leading: const CircleAvatar(child: Icon(Icons.swap_horiz_rounded)),
        title: Text(
          '${transfer.transferNumber} · ${transfer.salesRepNameSnapshot}',
        ),
        subtitle: Text(
          '${_typeLabel(transfer.type)} · ${_statusLabel(transfer.status)}',
        ),
        trailing: Text(_quantity(transfer.totalQuantity)),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, required this.count});

  final String title;
  final int count;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      '$title ($count)',
      style: Theme.of(
        context,
      ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
    ),
  );
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard({required this.keyName});

  final String keyName;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Center(child: Text(keyName.tr)),
    ),
  );
}

class _Fact extends StatelessWidget {
  const _Fact(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 210,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(color: context.appMutedText)),
        const SizedBox(height: 4),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
      ],
    ),
  );
}

T? _existingDropdownValue<T>(T? value, Iterable<T> availableValues) {
  if (value == null || !availableValues.contains(value)) return null;
  return value;
}

List<DropdownMenuItem<T>> _uniqueDropdownItems<T>(
  Iterable<DropdownMenuItem<T>> items,
) {
  final unique = <T, DropdownMenuItem<T>>{};
  for (final item in items) {
    final value = item.value;
    if (value != null) unique.putIfAbsent(value, () => item);
  }
  return List<DropdownMenuItem<T>>.unmodifiable(unique.values);
}

String _quantity(double value) {
  final fixed = value.toStringAsFixed(3);
  return fixed.replaceFirst(RegExp(r'\.?0+$'), '');
}

String _beforeAfter(double? before, double? after) {
  if (before == null || after == null) return '—';
  return '${_quantity(before)} → ${_quantity(after)}';
}

String _typeLabel(InventoryTransferType type) =>
    (type == InventoryTransferType.warehouseToRep
            ? 'rep_inventory_warehouse_to_rep'
            : 'rep_inventory_rep_to_warehouse')
        .tr;

String _statusLabel(InventoryTransferStatus status) =>
    'rep_inventory_status_${status.value}'.tr;

String _reasonLabel(RepInventoryReason reason) =>
    'rep_inventory_reason_${reason.value}'.tr;
