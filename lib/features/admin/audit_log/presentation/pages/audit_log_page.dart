import 'package:fatoora/core/class/statusrequest.dart';
import 'package:fatoora/core/constants/color.dart';
import 'package:fatoora/core/motion/fatoora_overlays.dart';
import 'package:fatoora/features/admin/audit_log/controllers/audit_log_controller.dart';
import 'package:fatoora/features/admin/audit_log/data/models/audit_event_model.dart';
import 'package:fatoora/features/admin/audit_log/presentation/widgets/audit_event_details.dart';
import 'package:fatoora/features/admin_dashboard/view/widgets/admin_dashboard_shell.dart';
import 'package:fatoora/features/shared/business/business_page_widgets.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

class AuditLogPage extends GetView<AuditLogController> {
  const AuditLogPage({super.key});

  @override
  Widget build(BuildContext context) => AdminDashboardShell(
    child: GetBuilder<AuditLogController>(
      builder: (controller) => _AuditLogBody(controller: controller),
    ),
  );
}

class _AuditLogBody extends StatelessWidget {
  const _AuditLogBody({required this.controller});
  final AuditLogController controller;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final compact = constraints.maxWidth < 760;
      return RefreshIndicator(
        onRefresh: controller.load,
        child: ListView(
          padding: EdgeInsets.all(compact ? 14 : 24),
          children: [
            BusinessPageHeader(
              title: 'audit_log_title'.tr,
              subtitle: compact ? null : 'audit_log_description'.tr,
            ),
            _FilterToolbar(controller: controller, compact: compact),
            if (controller.statusRequest == StatusRequest.success) ...[
              const SizedBox(height: 14),
              _SummaryCards(controller: controller),
            ],
            const SizedBox(height: 14),
            _AuditResults(
              controller: controller,
              compact: compact,
              onOpen: (event) => _openDetails(context, event),
            ),
          ],
        ),
      );
    },
  );

  Future<void> _openDetails(BuildContext context, AuditEventModel event) async {
    await controller.loadRelated(event);
    if (!context.mounted) return;
    final wide = MediaQuery.sizeOf(context).width >= 900;
    if (wide) {
      await showFatooraDialog<void>(
        context: context,
        builder: (_) => Dialog(
          alignment: AlignmentDirectional.centerEnd,
          insetPadding: const EdgeInsets.all(20),
          child: SizedBox(
            width: 620,
            height: MediaQuery.sizeOf(context).height - 40,
            child: AuditEventDetails(event: event),
          ),
        ),
      );
    } else {
      await showFatooraModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => SizedBox(
          height: MediaQuery.sizeOf(context).height * .94,
          child: AuditEventDetails(event: event),
        ),
      );
    }
  }
}

class _AuditResults extends StatelessWidget {
  const _AuditResults({
    required this.controller,
    required this.compact,
    required this.onOpen,
  });
  final AuditLogController controller;
  final bool compact;
  final ValueChanged<AuditEventModel> onOpen;

  @override
  Widget build(BuildContext context) {
    if (controller.statusRequest == StatusRequest.loading) {
      return const Center(
        key: ValueKey('audit-results-loading'),
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 48),
          child: CircularProgressIndicator(),
        ),
      );
    }
    if (controller.statusRequest != StatusRequest.success) {
      return BusinessEmptyState(
        key: const ValueKey('audit-results-error'),
        icon: Icons.error_outline_rounded,
        title: controller.statusRequest == StatusRequest.unauthorized
            ? 'audit_admin_only'.tr
            : 'audit_load_failed'.tr,
        action: OutlinedButton.icon(
          onPressed: controller.load,
          icon: const Icon(Icons.refresh_rounded),
          label: Text('retry'.tr),
        ),
      );
    }
    if (controller.visibleEvents.isEmpty) return _EmptyState();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (compact)
          for (final event in controller.visibleEvents) ...[
            _EventCard(event: event, onOpen: () => onOpen(event)),
            const SizedBox(height: 10),
          ]
        else
          _EventTable(events: controller.visibleEvents, onOpen: onOpen),
        if (controller.loadMoreErrorMessageKey != null) ...[
          const SizedBox(height: 12),
          BusinessEmptyState(
            key: const ValueKey('audit-load-more-error'),
            icon: Icons.error_outline_rounded,
            title: controller.loadMoreErrorMessageKey!.tr,
            action: OutlinedButton.icon(
              onPressed: controller.loadMore,
              icon: const Icon(Icons.refresh_rounded),
              label: Text('retry'.tr),
            ),
          ),
        ],
        if (controller.hasMore &&
            controller.loadMoreErrorMessageKey == null) ...[
          const SizedBox(height: 14),
          BusinessLoadMoreButton(
            loading: controller.loadingMore,
            onPressed: controller.loadMore,
          ),
        ],
      ],
    );
  }
}

class _SummaryCards extends StatelessWidget {
  const _SummaryCards({required this.controller});
  final AuditLogController controller;

  @override
  Widget build(BuildContext context) {
    final values = [
      ('audit_events_loaded'.tr, controller.events.length, Icons.history),
      ('audit_financial_events'.tr, controller.financialCount, Icons.payments),
      (
        'audit_inventory_events'.tr,
        controller.inventoryCount,
        Icons.inventory_2,
      ),
      ('audit_warning_events'.tr, controller.warningCount, Icons.warning_amber),
      ('audit_active_actors'.tr, controller.actorCount, Icons.people_alt),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth < 600
            ? constraints.maxWidth
            : (constraints.maxWidth - 48) / 3;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: values
              .map(
                (value) => SizedBox(
                  width: width,
                  child: Card(
                    margin: EdgeInsets.zero,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          CircleAvatar(
                            backgroundColor: AppColor.primaryColor.withValues(
                              alpha: .12,
                            ),
                            foregroundColor: AppColor.primaryColor,
                            child: Icon(value.$3),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${value.$2}',
                                  style: Theme.of(context)
                                      .textTheme
                                      .headlineSmall
                                      ?.copyWith(fontWeight: FontWeight.w800),
                                ),
                                Text(
                                  value.$1,
                                  style: TextStyle(color: context.appMutedText),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              )
              .toList(growable: false),
        );
      },
    );
  }
}

class _FilterToolbar extends StatelessWidget {
  const _FilterToolbar({required this.controller, required this.compact});
  final AuditLogController controller;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (compact) return _CompactAuditFilters(controller: controller);
    final search = TextField(
      controller: controller.searchController,
      onChanged: controller.search,
      decoration: InputDecoration(
        labelText: 'audit_search'.tr,
        prefixIcon: const Icon(Icons.search_rounded),
        border: const OutlineInputBorder(),
      ),
    );
    final category = DropdownButtonFormField<String>(
      value: controller.filterField == 'category' ? controller.filterValue : '',
      decoration: InputDecoration(
        labelText: 'audit_category'.tr,
        border: const OutlineInputBorder(),
      ),
      items: [
        DropdownMenuItem(value: '', child: Text('all'.tr)),
        ...[
          'sales',
          'financial',
          'inventory',
          'customers',
          'security',
          'settings',
        ].map((value) => DropdownMenuItem(value: value, child: Text(value.tr))),
      ],
      onChanged: (value) => controller.setFilter('category', value ?? ''),
    );
    final severity = DropdownButtonFormField<String>(
      value: controller.filterField == 'severity' ? controller.filterValue : '',
      decoration: InputDecoration(
        labelText: 'audit_severity'.tr,
        border: const OutlineInputBorder(),
      ),
      items: [
        DropdownMenuItem(value: '', child: Text('all'.tr)),
        ...[
          'info',
          'warning',
          'critical',
        ].map((value) => DropdownMenuItem(value: value, child: Text(value.tr))),
      ],
      onChanged: (value) => controller.setFilter('severity', value ?? ''),
    );
    final date = OutlinedButton.icon(
      onPressed: () async {
        final now = DateTime.now();
        final selected = await showDateRangePicker(
          context: context,
          firstDate: DateTime(now.year - 5),
          lastDate: DateTime(now.year + 1),
          initialDateRange: controller.dateRange,
        );
        if (context.mounted) await controller.setDateRange(selected);
      },
      icon: const Icon(Icons.date_range_rounded),
      label: Text(
        controller.dateRange == null
            ? 'audit_date_range'.tr
            : '${DateFormat.yMd().format(controller.dateRange!.start)} – '
                  '${DateFormat.yMd().format(controller.dateRange!.end)}',
      ),
    );
    final clear = IconButton.filledTonal(
      tooltip: 'audit_clear_filters'.tr,
      onPressed: controller.clearFilters,
      icon: const Icon(Icons.filter_alt_off_rounded),
    );
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: compact
            ? Column(
                children: [
                  search,
                  const SizedBox(height: 10),
                  category,
                  const SizedBox(height: 10),
                  severity,
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(child: date),
                      clear,
                    ],
                  ),
                ],
              )
            : Row(
                children: [
                  Expanded(flex: 3, child: search),
                  const SizedBox(width: 10),
                  Expanded(flex: 2, child: category),
                  const SizedBox(width: 10),
                  Expanded(flex: 2, child: severity),
                  const SizedBox(width: 10),
                  date,
                  const SizedBox(width: 6),
                  clear,
                ],
              ),
      ),
    );
  }
}

class _CompactAuditFilters extends StatelessWidget {
  const _CompactAuditFilters({required this.controller});
  final AuditLogController controller;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      TextField(
        key: const ValueKey('audit-search'),
        controller: controller.searchController,
        onChanged: controller.search,
        decoration: InputDecoration(
          labelText: 'audit_search'.tr,
          prefixIcon: const Icon(Icons.search_rounded),
          filled: true,
          fillColor: AppColor.surface,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
      const SizedBox(height: 10),
      Align(
        alignment: AlignmentDirectional.centerStart,
        child: OutlinedButton.icon(
          key: const ValueKey('audit-filter-button'),
          onPressed: () => _showFilter(context),
          icon: const Icon(Icons.tune_rounded),
          label: Text('audit_filter'.tr),
        ),
      ),
      if (controller.filterValue.isNotEmpty ||
          controller.dateRange != null ||
          controller.searchText.isNotEmpty) ...[
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            if (controller.searchText.isNotEmpty)
              InputChip(
                label: Text(controller.searchText),
                onDeleted: () {
                  controller.searchController.clear();
                  controller.search('');
                },
              ),
            if (controller.filterValue.isNotEmpty)
              InputChip(
                label: Text(controller.filterValue.tr),
                onDeleted: controller.clearFilters,
              ),
            if (controller.dateRange != null)
              InputChip(
                label: Text(
                  '${DateFormat.yMd().format(controller.dateRange!.start)} - '
                  '${DateFormat.yMd().format(controller.dateRange!.end)}',
                ),
                onDeleted: () => controller.setDateRange(null),
              ),
            TextButton(
              onPressed: controller.clearFilters,
              child: Text('audit_clear_filters'.tr),
            ),
          ],
        ),
      ],
    ],
  );

  Future<void> _showFilter(BuildContext context) async {
    final action = await showFatooraModalBottomSheet<(String, String)>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: FractionallySizedBox(
          heightFactor: 0.75,
          child: ListView(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'audit_filter'.tr,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              ListTile(
                title: Text('audit_date_range'.tr),
                leading: const Icon(Icons.date_range_outlined),
                onTap: () => Navigator.of(sheetContext).pop(('date', '')),
              ),
              for (final value in const [
                'sales',
                'financial',
                'inventory',
                'customers',
                'security',
                'settings',
              ])
                ListTile(
                  title: Text('${'audit_category'.tr}: ${value.tr}'),
                  onTap: () =>
                      Navigator.of(sheetContext).pop(('category', value)),
                ),
              for (final value in const ['info', 'warning', 'critical'])
                ListTile(
                  title: Text('${'audit_severity'.tr}: ${value.tr}'),
                  onTap: () =>
                      Navigator.of(sheetContext).pop(('severity', value)),
                ),
            ],
          ),
        ),
      ),
    );
    if (action == null) return;
    if (action.$1 == 'date' && context.mounted) {
      final now = DateTime.now();
      final range = await showDateRangePicker(
        context: context,
        firstDate: DateTime(now.year - 5),
        lastDate: DateTime(now.year + 1),
        initialDateRange: controller.dateRange,
      );
      if (range != null) await controller.setDateRange(range);
    } else {
      await controller.setFilter(action.$1, action.$2);
    }
  }
}

class _EventTable extends StatelessWidget {
  const _EventTable({required this.events, required this.onOpen});
  final List<AuditEventModel> events;
  final ValueChanged<AuditEventModel> onOpen;

  @override
  Widget build(BuildContext context) => Card(
    margin: EdgeInsets.zero,
    clipBehavior: Clip.antiAlias,
    child: SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columns: [
          DataColumn(label: Text('audit_time'.tr)),
          DataColumn(label: Text('audit_action'.tr)),
          DataColumn(label: Text('audit_actor'.tr)),
          DataColumn(label: Text('audit_entity'.tr)),
          DataColumn(label: Text('audit_impact'.tr)),
          DataColumn(label: Text('audit_status'.tr)),
          const DataColumn(label: Text('')),
        ],
        rows: events
            .map(
              (event) => DataRow(
                cells: [
                  DataCell(Text(_date(event))),
                  DataCell(
                    SizedBox(
                      width: 220,
                      child: Text(
                        event.action.tr,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  DataCell(Text('${event.actorName}\n${event.actorRole.tr}')),
                  DataCell(Text(event.entityDisplay)),
                  DataCell(_ImpactBadges(event: event)),
                  DataCell(_StatusBadges(event: event)),
                  DataCell(
                    IconButton(
                      tooltip: 'audit_view_details'.tr,
                      onPressed: () => onOpen(event),
                      icon: const Icon(Icons.open_in_new_rounded),
                    ),
                  ),
                ],
              ),
            )
            .toList(growable: false),
      ),
    ),
  );
}

class _EventCard extends StatelessWidget {
  const _EventCard({required this.event, required this.onOpen});
  final AuditEventModel event;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) => Card(
    margin: EdgeInsets.zero,
    child: InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onOpen,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    event.action.tr,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                _StatusBadges(event: event),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '${event.entityDisplay} · ${event.actorName}',
              style: TextStyle(color: context.appMutedText),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(child: Text(_date(event))),
                _ImpactBadges(event: event),
                const Icon(Icons.chevron_right_rounded),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

class _ImpactBadges extends StatelessWidget {
  const _ImpactBadges({required this.event});
  final AuditEventModel event;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 4,
    children: [
      if (event.hasFinancialImpact)
        const Tooltip(
          message: 'Financial impact',
          child: Icon(Icons.payments_outlined, color: Colors.green),
        ),
      if (event.hasInventoryImpact)
        const Tooltip(
          message: 'Inventory impact',
          child: Icon(Icons.inventory_2_outlined, color: Colors.blue),
        ),
    ],
  );
}

class _StatusBadges extends StatelessWidget {
  const _StatusBadges({required this.event});
  final AuditEventModel event;

  @override
  Widget build(BuildContext context) {
    final color = event.severity == 'critical'
        ? AppColor.error
        : event.severity == 'warning'
        ? Colors.orange
        : Colors.green;
    return Chip(
      visualDensity: VisualDensity.compact,
      side: BorderSide.none,
      backgroundColor: color.withValues(alpha: .12),
      label: Text(
        event.severity.tr,
        style: TextStyle(color: color, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) => BusinessEmptyState(
    icon: Icons.history_toggle_off_rounded,
    title: 'audit_no_events'.tr,
  );
}

String _date(AuditEventModel event) =>
    DateFormat('yyyy-MM-dd\nHH:mm:ss').format(event.occurredAt.toLocal());
