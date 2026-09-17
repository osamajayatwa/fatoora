import 'package:fatoora/core/constants/color.dart';
import 'package:fatoora/features/admin/audit_log/data/models/audit_event_model.dart';
import 'package:fatoora/features/admin/audit_log/data/repositories/audit_log_repository.dart';
import 'package:flutter/material.dart';
import 'package:fatoora/core/motion/fatoora_motion_widgets.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

class EntityAuditTimeline extends StatelessWidget {
  const EntityAuditTimeline({
    super.key,
    required this.companyId,
    required this.entityType,
    required this.entityId,
    this.repository,
  });

  final String companyId;
  final String entityType;
  final String entityId;
  final AuditLogRepository? repository;

  @override
  Widget build(BuildContext context) {
    final source = repository ?? AuditLogRepository();
    return FutureBuilder<List<AuditEventModel>>(
      future: source.fetchEntityTimeline(
        companyId: companyId,
        entityType: entityType,
        entityId: entityId,
      ),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: FatooraProgressIndicator());
        }
        final events = snapshot.data ?? const [];
        if (events.isEmpty) return Text('audit_no_entity_events'.tr);
        return Column(
          children: events
              .map(
                (event) => ListTile(
                  leading: const Icon(
                    Icons.history_rounded,
                    color: AppColor.primaryColor,
                  ),
                  title: Text(event.action.tr),
                  subtitle: Text(
                    '${DateFormat.yMd().add_Hms().format(event.occurredAt.toLocal())}'
                    ' · ${event.actorName}',
                  ),
                ),
              )
              .toList(growable: false),
        );
      },
    );
  }
}
