import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fatoora/app/routes/app_routes.dart';
import 'package:fatoora/core/class/statusrequest.dart';
import 'package:fatoora/core/constants/color.dart';
import 'package:fatoora/core/services/services.dart';
import 'package:fatoora/core/search/server_search_policy.dart';
import 'package:fatoora/features/auth/data/repositories/auth_repository.dart';
import 'package:fatoora/features/financial_ledger/data/models/financial_ledger_entry.dart';
import 'package:fatoora/features/financial_ledger/data/models/financial_ledger_filters.dart';
import 'package:fatoora/features/financial_ledger/data/models/financial_ledger_summary.dart';
import 'package:fatoora/features/financial_ledger/data/repositories/financial_ledger_repository.dart';
import 'package:fatoora/features/financial_ledger/data/services/financial_ledger_excel_service.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class FinancialLedgerController extends GetxController {
  FinancialLedgerController({
    required FinancialLedgerRepository repository,
    required FinancialLedgerExcelService excelService,
    required MyServices myServices,
  }) : _repository = repository,
       _excelService = excelService,
       _myServices = myServices;

  final FinancialLedgerRepository _repository;
  final FinancialLedgerExcelService _excelService;
  final MyServices _myServices;

  final searchController = TextEditingController();
  StatusRequest statusRequest = StatusRequest.loading;
  String loadErrorMessageKey = 'ledger_load_error';
  FinancialLedgerFilters filters = FinancialLedgerFilters.currentMonth();
  FinancialLedgerSummary summary = const FinancialLedgerSummary();
  FinancialLedgerLookups lookups = const FinancialLedgerLookups(
    representatives: [],
    customers: [],
  );
  List<FinancialLedgerEntry> entries = const [];
  FinancialLedgerCursor? _cursor;
  bool hasMore = false;
  bool isLoadingMore = false;
  bool isExporting = false;
  bool isCopying = false;
  Timer? _searchDebounce;
  int _loadGeneration = 0;

  String get companyId =>
      _myServices.sharedPreferences.getString('companyId') ??
      AuthRepository.defaultCompanyId;

  bool get searchTooShort {
    return serverSearchIsTooShort(normalizeLedgerSearch(searchController.text));
  }

  List<LedgerFilterOption> get accountOptions {
    final options = <LedgerFilterOption>[
      const LedgerFilterOption('company_cash', 'ledger_account_company_cash'),
      const LedgerFilterOption('sales', 'ledger_account_sales'),
      const LedgerFilterOption('expenses', 'ledger_account_expenses'),
      const LedgerFilterOption('bank_unallocated', 'ledger_account_bank'),
      const LedgerFilterOption('check_clearing', 'ledger_account_checks'),
      const LedgerFilterOption('cliq_clearing', 'ledger_account_cliq'),
      const LedgerFilterOption(
        'opening_balance_equity',
        'ledger_account_opening_equity',
      ),
      for (final rep in lookups.representatives)
        LedgerFilterOption(
          'rep_cash:${rep.uid}',
          '${rep.name} — ${'ledger_rep_cash'.tr}',
        ),
      for (final rep in lookups.representatives)
        LedgerFilterOption(
          'rep_payable:${rep.uid}',
          '${rep.name} — ${'ledger_payable'.tr}',
        ),
      for (final customer in lookups.customers)
        LedgerFilterOption('customer:${customer.id}', customer.name),
    ];
    return options;
  }

  @override
  void onReady() {
    super.onReady();
    loadInitial();
  }

  @override
  void onClose() {
    _searchDebounce?.cancel();
    searchController.dispose();
    super.onClose();
  }

  Future<void> loadInitial() async {
    _searchDebounce?.cancel();
    final generation = ++_loadGeneration;
    final requestedFilters = filters;
    statusRequest = StatusRequest.loading;
    loadErrorMessageKey = 'ledger_load_error';
    update();
    try {
      final results = await Future.wait<Object>([
        _repository.fetchPage(companyId: companyId, filters: requestedFilters),
        _repository.fetchSummary(
          companyId: companyId,
          filters: requestedFilters,
        ),
        _repository.fetchLookups(companyId),
      ]);
      if (generation != _loadGeneration) return;
      final page = results[0] as FinancialLedgerPage;
      entries = page.entries;
      _cursor = page.cursor;
      hasMore = page.hasMore;
      summary = results[1] as FinancialLedgerSummary;
      lookups = results[2] as FinancialLedgerLookups;
      statusRequest = StatusRequest.success;
    } catch (error) {
      if (generation != _loadGeneration) return;
      statusRequest = _statusFor(error);
      loadErrorMessageKey = _messageFor(error);
    }
    if (!isClosed) update();
  }

  Future<void> refreshLedger() => loadInitial();

  Future<void> loadMore() async {
    if (isLoadingMore || !hasMore || _cursor == null) return;
    isLoadingMore = true;
    final generation = _loadGeneration;
    update();
    try {
      final page = await _repository.fetchPage(
        companyId: companyId,
        filters: filters,
        after: _cursor,
      );
      if (generation != _loadGeneration) return;
      entries = [...entries, ...page.entries];
      _cursor = page.cursor;
      hasMore = page.hasMore;
    } catch (error) {
      if (generation != _loadGeneration) return;
      _showError(_messageFor(error));
    } finally {
      isLoadingMore = false;
      if (!isClosed) update();
    }
  }

  void onSearchChanged(String value) {
    _searchDebounce?.cancel();
    _loadGeneration++;
    update();
    final normalized = normalizeLedgerSearch(value);
    if (serverSearchTerm(normalized).isEmpty) {
      if (filters.search.isNotEmpty) {
        filters = filters.copyWith(search: '');
        loadInitial();
      } else if (statusRequest != StatusRequest.success) {
        loadInitial();
      }
      return;
    }
    _searchDebounce = Timer(serverSearchDebounce, () {
      filters = filters.copyWith(search: normalized);
      loadInitial();
    });
  }

  void submitSearch() {
    _searchDebounce?.cancel();
    final normalized = normalizeLedgerSearch(searchController.text);
    if (serverSearchTerm(normalized).isEmpty) {
      if (filters.search.isNotEmpty) {
        filters = filters.copyWith(search: '');
        loadInitial();
      }
      return;
    }
    filters = filters.copyWith(search: normalized);
    loadInitial();
  }

  void clearSearch() {
    _searchDebounce?.cancel();
    searchController.clear();
    if (filters.search.isEmpty && statusRequest == StatusRequest.success) {
      update();
      return;
    }
    filters = filters.copyWith(search: '');
    loadInitial();
  }

  void setType(String? value) =>
      _setFilters(filters.copyWith(type: value ?? ''));

  void setAccount(String? value) =>
      _setFilters(filters.copyWith(accountKey: value ?? ''));

  void setCustomer(String? value) =>
      _setFilters(filters.copyWith(customerId: value ?? ''));

  void setSalesRep(String? value) =>
      _setFilters(filters.copyWith(salesRepId: value ?? ''));

  void setPaymentMethod(String? value) =>
      _setFilters(filters.copyWith(paymentMethod: value ?? ''));

  void setDateRange(DateTimeRange? range) {
    if (range == null) return;
    _setFilters(filters.copyWith(fromDate: range.start, toDate: range.end));
  }

  void clearFilters() {
    _searchDebounce?.cancel();
    searchController.clear();
    filters = FinancialLedgerFilters.currentMonth();
    loadInitial();
  }

  Future<void> exportAccountingReport() async {
    if (isExporting) return;
    isExporting = true;
    update();
    try {
      final data = await _repository.fetchExportData(
        companyId: companyId,
        filters: filters,
      );
      await _excelService.saveAccountingReport(data: data, filters: filters);
      Get.snackbar('financial_ledger'.tr, 'ledger_export_success'.tr);
    } catch (error) {
      _showError(_messageFor(error));
    } finally {
      isExporting = false;
      if (!isClosed) update();
    }
  }

  Future<void> copyFilteredRows() async {
    if (isCopying) return;
    isCopying = true;
    update();
    try {
      final all = await _repository.fetchAllForExport(
        companyId: companyId,
        filters: filters,
      );
      await _excelService.copyAsTsv(all);
      Get.snackbar('financial_ledger'.tr, 'ledger_copy_success'.tr);
    } catch (error) {
      _showError(_messageFor(error));
    } finally {
      isCopying = false;
      if (!isClosed) update();
    }
  }

  void openOriginal(FinancialLedgerEntry entry) {
    final route = switch (entry.referenceType) {
      'invoice' => AppRoute.invoiceDetailsPath(entry.referenceId),
      'receipt' => AppRoute.receiptDetailsPath(entry.referenceId),
      'expense' => AppRoute.expenseDetailsPath(entry.referenceId),
      'sales_return' => AppRoute.salesReturnDetailsPath(entry.referenceId),
      'customer' when entry.customerId.isNotEmpty =>
        AppRoute.customerStatementPath(entry.customerId),
      'settlement' || 'cash_movement' => AppRoute.cashMovements,
      _ => '',
    };
    if (route.isEmpty) {
      Get.snackbar('financial_ledger'.tr, 'ledger_source_unavailable'.tr);
      return;
    }
    Get.toNamed(route);
  }

  void _setFilters(FinancialLedgerFilters value) {
    filters = value;
    loadInitial();
  }

  StatusRequest _statusFor(Object error) {
    if (error is FirebaseException) {
      return switch (error.code) {
        'permission-denied' || 'unauthenticated' => StatusRequest.unauthorized,
        'unavailable' => StatusRequest.offlinefailure,
        'deadline-exceeded' => StatusRequest.timeout,
        _ => StatusRequest.serverfailure,
      };
    }
    return StatusRequest.serverfailure;
  }

  String _messageFor(Object error) {
    if (error is FinancialLedgerProjectionNotReadyException) {
      return 'ledger_export_projection_not_ready';
    }
    if (error is FirebaseException) {
      return switch (error.code) {
        'permission-denied' || 'unauthenticated' => 'ledger_permission_error',
        'failed-precondition' => 'ledger_index_error',
        'unavailable' => 'ledger_offline_error',
        'deadline-exceeded' => 'ledger_timeout_error',
        _ => 'ledger_load_error',
      };
    }
    if (error is FormatException) return 'ledger_invalid_data';
    return 'ledger_load_error';
  }

  void _showError(String key) {
    Get.snackbar(
      'financial_ledger'.tr,
      key.tr,
      snackPosition: SnackPosition.BOTTOM,
      backgroundColor: AppColor.error,
      colorText: AppColor.surface,
    );
  }
}

class LedgerFilterOption {
  const LedgerFilterOption(this.id, this.label);

  final String id;
  final String label;
}
