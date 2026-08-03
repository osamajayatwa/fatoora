import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fatoora/core/class/statusrequest.dart';
import 'package:fatoora/features/admin/audit_log/data/models/audit_event_model.dart';
import 'package:fatoora/features/admin/audit_log/data/repositories/audit_log_repository.dart';
import 'package:fatoora/features/shared/business/business_user_context.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class AuditLogController extends GetxController {
  AuditLogController({
    AuditLogDataSource? repository,
    BusinessUserContextReader? contextReader,
    Future<BusinessUserContext> Function()? contextLoader,
  }) : _repository = repository ?? AuditLogRepository(),
       _contextLoader =
           contextLoader ??
           (contextReader ?? BusinessUserContextReader()).requireApprovedUser;

  final AuditLogDataSource _repository;
  final Future<BusinessUserContext> Function() _contextLoader;
  final searchController = TextEditingController();

  StatusRequest statusRequest = StatusRequest.loading;
  StatusRequest detailsStatus = StatusRequest.none;
  BusinessUserContext? userContext;
  List<AuditEventModel> events = const [];
  List<AuditEventModel> relatedEvents = const [];
  DocumentSnapshot<Map<String, dynamic>>? _cursor;
  bool hasMore = false;
  bool loadingMore = false;
  String filterField = '';
  String filterValue = '';
  DateTimeRange? dateRange;
  String searchText = '';

  List<AuditEventModel> get visibleEvents {
    final needle = searchText.trim().toLowerCase();
    if (needle.isEmpty) return events;
    return events
        .where((event) {
          return [
            event.action,
            event.actorName,
            event.actorRole,
            event.entityDisplay,
            event.customerName,
            event.salesRepName,
          ].any((value) => value.toLowerCase().contains(needle));
        })
        .toList(growable: false);
  }

  int get warningCount =>
      events.where((event) => event.severity != 'info').length;
  int get financialCount =>
      events.where((event) => event.hasFinancialImpact).length;
  int get inventoryCount =>
      events.where((event) => event.hasInventoryImpact).length;
  int get actorCount => events
      .map((event) => event.actorUid)
      .where((id) => id.isNotEmpty)
      .toSet()
      .length;

  @override
  void onInit() {
    super.onInit();
    load();
  }

  @override
  void onClose() {
    searchController.dispose();
    super.onClose();
  }

  Future<void> load() async {
    statusRequest = StatusRequest.loading;
    update();
    try {
      final context = await _contextLoader();
      if (!context.isAdmin) {
        statusRequest = StatusRequest.unauthorized;
        update();
        return;
      }
      userContext = context;
      final page = await _repository.fetchPage(
        companyId: context.companyId,
        filter: _filter,
      );
      events = page.events;
      _cursor = page.cursor;
      hasMore = page.hasMore;
      statusRequest = StatusRequest.success;
    } on FirebaseException catch (error) {
      statusRequest = error.code == 'permission-denied'
          ? StatusRequest.unauthorized
          : StatusRequest.serverfailure;
    } catch (_) {
      statusRequest = StatusRequest.failure;
    }
    update();
  }

  Future<void> loadMore() async {
    final context = userContext;
    if (context == null || !hasMore || loadingMore) return;
    loadingMore = true;
    update();
    try {
      final page = await _repository.fetchPage(
        companyId: context.companyId,
        filter: _filter,
        after: _cursor,
      );
      events = [...events, ...page.events];
      _cursor = page.cursor;
      hasMore = page.hasMore;
    } finally {
      loadingMore = false;
      update();
    }
  }

  Future<void> setFilter(String field, String value) async {
    filterField = field;
    filterValue = value;
    dateRange = null;
    await load();
  }

  Future<void> clearFilters() async {
    filterField = '';
    filterValue = '';
    dateRange = null;
    searchController.clear();
    searchText = '';
    await load();
  }

  void search(String value) {
    searchText = value;
    update();
  }

  Future<void> setDateRange(DateTimeRange? range) async {
    dateRange = range;
    filterField = '';
    filterValue = '';
    await load();
  }

  Future<void> loadRelated(AuditEventModel event) async {
    final context = userContext;
    if (context == null) return;
    detailsStatus = StatusRequest.loading;
    relatedEvents = const [];
    update();
    try {
      relatedEvents = await _repository.fetchOperationEvents(
        companyId: context.companyId,
        operationId: event.operationId,
      );
      detailsStatus = StatusRequest.success;
    } catch (_) {
      detailsStatus = StatusRequest.failure;
    }
    update();
  }

  AuditLogFilter get _filter => AuditLogFilter(
    field: filterField.isEmpty ? null : filterField,
    value: filterValue.isEmpty ? null : filterValue,
    from: dateRange?.start,
    to: dateRange?.end.add(const Duration(days: 1)),
  );
}
