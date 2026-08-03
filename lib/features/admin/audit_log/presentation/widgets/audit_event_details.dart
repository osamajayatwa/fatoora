import 'package:fatoora/core/constants/color.dart';
import 'package:fatoora/features/admin/audit_log/controllers/audit_log_controller.dart';
import 'package:fatoora/features/admin/audit_log/data/models/audit_event_model.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

class AuditEventDetails extends StatelessWidget {
  const AuditEventDetails({super.key, required this.event});

  final AuditEventModel event;

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<AuditLogController>();
    return Material(
      color: context.appSurface,
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 12, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'audit_event_details'.tr,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'close'.tr,
                    onPressed: Get.back<void>,
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: context.appBorder),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  _Section(
                    title: 'audit_overview'.tr,
                    children: [
                      _Entry('audit_action'.tr, _actionLabel(event)),
                      _Entry(
                        'audit_time'.tr,
                        DateFormat(
                          'yyyy-MM-dd  HH:mm:ss',
                        ).format(event.occurredAt.toLocal()),
                      ),
                      _Entry('audit_result'.tr, event.result.tr),
                      _Entry('audit_severity'.tr, event.severity.tr),
                      _Entry('audit_source'.tr, event.source.tr),
                    ],
                  ),
                  _Section(
                    title: 'audit_actor'.tr,
                    children: [
                      _Entry('audit_actor_name'.tr, event.actorName),
                      _Entry('audit_role'.tr, event.actorRole.tr),
                      _Entry('audit_actor_id'.tr, event.actorUid),
                    ],
                  ),
                  _Section(
                    title: 'audit_entity'.tr,
                    children: [
                      _Entry('audit_entity_type'.tr, event.entityType.tr),
                      _Entry('audit_entity_number'.tr, event.entityDisplay),
                      _Entry('audit_entity_id'.tr, event.entityId),
                    ],
                  ),
                  if (event.changes.isNotEmpty)
                    _Section(
                      title: 'audit_changes'.tr,
                      children: event.changes
                          .map(
                            (change) => _ChangeEntry(
                              field: change.field,
                              before: change.before,
                              after: change.after,
                            ),
                          )
                          .toList(growable: false),
                    ),
                  if (event.hasFinancialImpact)
                    _MapSection(
                      title: 'audit_financial_impact'.tr,
                      values: event.financialImpact,
                    ),
                  if (event.hasInventoryImpact)
                    _Section(
                      title: 'audit_inventory_impact'.tr,
                      children: event.inventoryImpact
                          .map(
                            (impact) => Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Column(
                                  children: impact.entries
                                      .where((entry) => _show(entry.value))
                                      .map(
                                        (entry) => _Entry(
                                          entry.key.tr,
                                          _display(entry.value),
                                        ),
                                      )
                                      .toList(growable: false),
                                ),
                              ),
                            ),
                          )
                          .toList(growable: false),
                    ),
                  if (event.relatedEntities.isNotEmpty)
                    _Section(
                      title: 'audit_related_entities'.tr,
                      children: event.relatedEntities
                          .map(
                            (entity) => _Entry(
                              _display(entity['entityType']).tr,
                              _display(entity['entityId']),
                            ),
                          )
                          .toList(growable: false),
                    ),
                  if (event.reason.isNotEmpty || event.notes.isNotEmpty)
                    _Section(
                      title: 'audit_reason_notes'.tr,
                      children: [
                        if (event.reason.isNotEmpty)
                          _Entry('audit_reason'.tr, event.reason),
                        if (event.notes.isNotEmpty)
                          _Entry('audit_notes'.tr, event.notes),
                      ],
                    ),
                  _Section(
                    title: 'audit_related_events'.tr,
                    children: [
                      if (controller.detailsStatus.name == 'loading')
                        const LinearProgressIndicator()
                      else if (controller.relatedEvents.isEmpty)
                        Text('audit_no_related_events'.tr)
                      else
                        ...controller.relatedEvents.map(
                          (related) => ListTile(
                            contentPadding: EdgeInsets.zero,
                            dense: true,
                            leading: Icon(
                              related.displayInTimeline
                                  ? Icons.star_rounded
                                  : Icons.link_rounded,
                              color: AppColor.primaryColor,
                            ),
                            title: Text(_actionLabel(related)),
                            subtitle: Text(related.entityDisplay),
                          ),
                        ),
                    ],
                  ),
                  _MapSection(
                    title: 'audit_technical_metadata'.tr,
                    values: {
                      'eventId': event.id,
                      'operationId': event.operationId,
                      'schemaVersion': event.schemaVersion,
                      ...event.metadata,
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 22),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w800,
            color: AppColor.primaryColor,
          ),
        ),
        const SizedBox(height: 8),
        ...children,
      ],
    ),
  );
}

class _MapSection extends StatelessWidget {
  const _MapSection({required this.title, required this.values});
  final String title;
  final Map<String, dynamic> values;

  @override
  Widget build(BuildContext context) => _Section(
    title: title,
    children: values.entries
        .where((entry) => _show(entry.value))
        .map((entry) => _Entry(entry.key.tr, _display(entry.value)))
        .toList(growable: false),
  );
}

class _Entry extends StatelessWidget {
  const _Entry(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    if (value.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 145,
            child: Text(
              label,
              style: TextStyle(
                color: context.appMutedText,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(child: SelectableText(value)),
        ],
      ),
    );
  }
}

class _ChangeEntry extends StatelessWidget {
  const _ChangeEntry({
    required this.field,
    required this.before,
    required this.after,
  });
  final String field;
  final Object? before;
  final Object? after;

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 8),
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(field.tr, style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _ValueChip(label: 'audit_before'.tr, value: _display(before)),
              const Icon(Icons.arrow_forward_rounded, size: 18),
              _ValueChip(label: 'audit_after'.tr, value: _display(after)),
            ],
          ),
        ],
      ),
    ),
  );
}

class _ValueChip extends StatelessWidget {
  const _ValueChip({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) =>
      Chip(label: Text('$label: ${value.isEmpty ? '—' : value}'));
}

String _actionLabel(AuditEventModel event) {
  final args = event.summaryArgs.map(
    (key, value) => MapEntry(key, _display(value)),
  );
  final translated = event.summaryKey.trParams(args);
  return translated == event.summaryKey ? event.action.tr : translated;
}

bool _show(Object? value) =>
    value != null && value != '' && value != 0 && value != 0.0;
String _display(Object? value) {
  if (value == null) return '';
  if (value is num) return NumberFormat('#,##0.###').format(value);
  if (value is Map || value is List) return value.toString();
  return value.toString();
}
