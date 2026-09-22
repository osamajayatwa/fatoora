import 'dart:async';

import 'package:fatoora/core/class/statusrequest.dart';
import 'package:fatoora/core/constants/color.dart';
import 'package:fatoora/core/motion/fatoora_overlays.dart';
import 'package:fatoora/core/data/firestore_query_pager.dart';
import 'package:fatoora/app/routes/app_routes.dart';
import 'package:fatoora/core/services/services.dart';
import 'package:fatoora/core/search/server_search_policy.dart';
import 'package:fatoora/features/invoices/controllers/invoice_context.dart';
import 'package:fatoora/features/shared/navigation/business_navigation_router.dart';
import 'package:fatoora/features/invoices/controllers/invoice_error_mapper.dart';
import 'package:fatoora/features/invoices/data/models/invoice_enums.dart';
import 'package:fatoora/features/invoices/data/models/invoice_list_query.dart';
import 'package:fatoora/features/invoices/data/models/invoice_model.dart';
import 'package:fatoora/features/invoices/data/repositories/invoice_repository.dart';
import 'package:fatoora/features/invoices/data/services/invoice_pdf_service.dart';
import 'package:file_saver/file_saver.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:printing/printing.dart';

class InvoicesListController extends GetxController {
  InvoicesListController({
    required InvoiceRepository repository,
    required MyServices myServices,
  }) : _repository = repository,
       _myServices = myServices;

  final InvoiceRepository _repository;
  final MyServices _myServices;
  final TextEditingController searchController = TextEditingController();

  StatusRequest statusRequest = StatusRequest.loading;
  List<InvoiceModel> invoices = const [];
  InvoiceType? typeFilter;
  InvoiceStatus? statusFilter;
  PaymentStatus? paymentStatusFilter;
  InvoiceReturnStatus? returnStatusFilter;
  InvoiceFilterOption? salesRepFilter;
  InvoiceFilterOption? customerFilter;
  DateTime? fromDate;
  DateTime? toDate;
  InvoiceSortField sortField = InvoiceSortField.invoiceDate;
  InvoiceSortDirection sortDirection = InvoiceSortDirection.descending;
  String searchText = '';
  String loadErrorMessageKey = 'invoice_load_error';
  bool isDeleting = false;
  bool isPrinting = false;
  bool isLoadingMore = false;
  bool hasMore = false;
  FirestorePageCursor? _pageCursor;
  int _loadGeneration = 0;
  Timer? _searchDebounce;
  String _appliedSearchText = '';

  bool get isAdmin =>
      _myServices.sharedPreferences.getString('role')?.trim() == 'admin';

  bool get showSalesRepresentative => isAdmin;

  bool get searchIsTooShort => serverSearchIsTooShort(searchText);

  String get appliedSearchText => _appliedSearchText;

  String get companyId {
    final args = InvoiceContext.arguments(Get.arguments);
    return InvoiceContext.resolveCompanyId(_myServices, args);
  }

  bool get hasActiveFilters =>
      typeFilter != null ||
      statusFilter != null ||
      paymentStatusFilter != null ||
      returnStatusFilter != null ||
      salesRepFilter != null ||
      customerFilter != null ||
      fromDate != null ||
      toDate != null;

  bool get hasFilters => hasActiveFilters || _appliedSearchText.isNotEmpty;

  int get activeFilterCount => [
    typeFilter,
    statusFilter,
    paymentStatusFilter,
    returnStatusFilter,
    if (showSalesRepresentative) salesRepFilter,
    customerFilter,
    if (hasDateRange) true,
  ].where((value) => value != null).length;

  bool get hasDateRange => fromDate != null || toDate != null;

  @override
  void onReady() {
    super.onReady();
    loadInvoices();
  }

  Future<void> loadInvoices() async {
    _searchDebounce?.cancel();
    final generation = ++_loadGeneration;
    final requestedSearch = serverSearchTerm(searchText);
    final resolvedCompanyId = companyId;
    if (resolvedCompanyId.isEmpty) {
      statusRequest = StatusRequest.unauthorized;
      loadErrorMessageKey = 'invoice_session_error';
      update();
      return;
    }

    statusRequest = StatusRequest.loading;
    _pageCursor = null;
    hasMore = false;
    loadErrorMessageKey = 'invoice_load_error';
    update();
    try {
      final page = await _repository.getInvoicesPage(
        companyId: resolvedCompanyId,
        type: typeFilter,
        status: statusFilter,
        paymentStatus: paymentStatusFilter,
        returnStatus: returnStatusFilter,
        salesRepId: salesRepFilter?.id,
        customerId: customerFilter?.id,
        fromDate: fromDate,
        toDate: toDate,
        searchText: requestedSearch,
        sortField: sortField,
        sortDirection: sortDirection,
      );
      if (generation != _loadGeneration) return;
      _pageCursor = page.cursor;
      hasMore = page.hasMore;
      invoices = page.items;
      _appliedSearchText = requestedSearch;
      statusRequest = StatusRequest.success;
    } catch (error) {
      if (generation != _loadGeneration) return;
      statusRequest = InvoiceErrorMapper.status(error);
      loadErrorMessageKey = InvoiceErrorMapper.messageKey(
        error,
        fallback: 'invoice_load_error',
      );
      _showError(loadErrorMessageKey);
    }
    if (!isClosed) update();
  }

  Future<void> refreshInvoices() => loadInvoices();

  Future<void> loadMoreInvoices() async {
    if (isLoadingMore || !hasMore || _pageCursor == null) return;
    isLoadingMore = true;
    final generation = _loadGeneration;
    update();
    try {
      final page = await _repository.getInvoicesPage(
        companyId: companyId,
        type: typeFilter,
        status: statusFilter,
        paymentStatus: paymentStatusFilter,
        returnStatus: returnStatusFilter,
        salesRepId: salesRepFilter?.id,
        customerId: customerFilter?.id,
        fromDate: fromDate,
        toDate: toDate,
        searchText: serverSearchTerm(searchText),
        sortField: sortField,
        sortDirection: sortDirection,
        after: _pageCursor,
      );
      if (generation != _loadGeneration) return;
      _pageCursor = page.cursor;
      hasMore = page.hasMore;
      invoices = [...invoices, ...page.items];
    } catch (error) {
      if (generation != _loadGeneration) return;
      _showError(InvoiceErrorMapper.messageKey(error));
    } finally {
      isLoadingMore = false;
      if (!isClosed) update();
    }
  }

  void onSearchChanged(String value) {
    searchText = value;
    _searchDebounce?.cancel();
    _loadGeneration++;
    update();
    if (serverSearchTerm(value).isEmpty) {
      if (_appliedSearchText.isNotEmpty ||
          statusRequest != StatusRequest.success) {
        loadInvoices();
      }
      return;
    }
    _searchDebounce = Timer(serverSearchDebounce, loadInvoices);
  }

  void submitSearch() {
    _searchDebounce?.cancel();
    if (serverSearchTerm(searchText).isEmpty &&
        _appliedSearchText.isEmpty &&
        statusRequest == StatusRequest.success) {
      return;
    }
    loadInvoices();
  }

  void clearSearch() {
    if (searchText.isEmpty && searchController.text.isEmpty) return;
    _searchDebounce?.cancel();
    searchText = '';
    searchController.clear();
    loadInvoices();
  }

  void setTypeFilter(InvoiceType? value) {
    typeFilter = value;
    loadInvoices();
  }

  void setStatusFilter(InvoiceStatus? value) {
    statusFilter = value;
    loadInvoices();
  }

  void setPaymentStatusFilter(PaymentStatus? value) {
    paymentStatusFilter = value;
    loadInvoices();
  }

  void setReturnStatusFilter(InvoiceReturnStatus? value) {
    returnStatusFilter = value;
    loadInvoices();
  }

  void setSalesRepFilter(InvoiceFilterOption? value) {
    salesRepFilter = value;
    loadInvoices();
  }

  void setCustomerFilter(InvoiceFilterOption? value) {
    customerFilter = value;
    loadInvoices();
  }

  Future<List<InvoiceFilterOption>> loadCustomerFilterOptions(
    String searchText,
  ) {
    return _repository.getInvoiceCustomerFilterOptions(
      companyId: companyId,
      searchText: serverSearchTerm(searchText),
    );
  }

  Future<List<InvoiceFilterOption>> loadSalesRepFilterOptions(
    String searchText,
  ) {
    return _repository.getInvoiceSalesRepFilterOptions(
      companyId: companyId,
      searchText: serverSearchTerm(searchText),
    );
  }

  void setDateRange(DateTimeRange? range) {
    fromDate = range?.start;
    toDate = range?.end;
    if (range != null) sortField = InvoiceSortField.invoiceDate;
    loadInvoices();
  }

  void applyFilters({
    required InvoiceType? type,
    required InvoiceStatus? status,
    required PaymentStatus? paymentStatus,
    required InvoiceReturnStatus? returnStatus,
    required InvoiceFilterOption? salesRep,
    required InvoiceFilterOption? customer,
    required DateTimeRange? dateRange,
  }) {
    typeFilter = type;
    statusFilter = status;
    paymentStatusFilter = paymentStatus;
    returnStatusFilter = returnStatus;
    salesRepFilter = showSalesRepresentative ? salesRep : null;
    customerFilter = customer;
    fromDate = dateRange?.start;
    toDate = dateRange?.end;
    if (dateRange != null) sortField = InvoiceSortField.invoiceDate;
    loadInvoices();
  }

  void setSortField(InvoiceSortField value) {
    if (hasDateRange && value != InvoiceSortField.invoiceDate) {
      _showInfo('sort_invoices'.tr, 'date_range_sort_notice'.tr);
      return;
    }
    if (sortField == value) return;
    sortField = value;
    loadInvoices();
  }

  void setSortDirection(InvoiceSortDirection value) {
    if (sortDirection == value) return;
    sortDirection = value;
    loadInvoices();
  }

  void toggleSortDirection() {
    setSortDirection(
      sortDirection == InvoiceSortDirection.ascending
          ? InvoiceSortDirection.descending
          : InvoiceSortDirection.ascending,
    );
  }

  void applySort(InvoiceSortField field, InvoiceSortDirection direction) {
    final effectiveField = hasDateRange ? InvoiceSortField.invoiceDate : field;
    if (sortField == effectiveField && sortDirection == direction) return;
    sortField = effectiveField;
    sortDirection = direction;
    loadInvoices();
  }

  void clearFilters() {
    typeFilter = null;
    statusFilter = null;
    paymentStatusFilter = null;
    returnStatusFilter = null;
    salesRepFilter = null;
    customerFilter = null;
    fromDate = null;
    toDate = null;
    loadInvoices();
  }

  Future<void> openCreateInvoice() async {
    final changed = await BusinessNavigationRouter.openCreateInvoice(
      _myServices,
    );
    if (changed) await loadInvoices();
  }

  Future<void> openDetails(InvoiceModel invoice) async {
    final changed = await Get.toNamed(
      AppRoute.invoiceDetailsPath(invoice.id),
      arguments: {'companyId': invoice.companyId, 'invoiceId': invoice.id},
    );
    if (changed == true) await loadInvoices();
  }

  Future<void> editInvoice(InvoiceModel invoice) async {
    if (!invoice.canEdit) {
      _showError('confirmed_invoice_locked');
      return;
    }
    final changed = await Get.toNamed(
      AppRoute.invoiceEditPath(invoice.id),
      arguments: {
        'mode': 'edit',
        'companyId': invoice.companyId,
        'invoiceId': invoice.id,
      },
    );
    if (changed == true) await loadInvoices();
  }

  Future<void> deleteDraftInvoice(InvoiceModel invoice) async {
    if (!invoice.canDelete || isDeleting) return;
    final confirmed = await showFatooraGetDialog<bool>(
      AlertDialog(
        title: Text('delete_invoice'.tr),
        content: Text('delete_invoice_confirmation'.tr),
        actions: [
          TextButton(
            onPressed: () => Get.back(result: false),
            child: Text('dashboard_cancel'.tr),
          ),
          FilledButton(
            onPressed: () => Get.back(result: true),
            style: FilledButton.styleFrom(backgroundColor: AppColor.error),
            child: Text('delete_invoice'.tr),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    isDeleting = true;
    update();
    try {
      await _repository.deleteDraftInvoice(
        companyId: invoice.companyId,
        invoiceId: invoice.id,
      );
      invoices = invoices.where((item) => item.id != invoice.id).toList();
      _showSuccess('draft_deleted_successfully');
    } catch (error) {
      _showError(InvoiceErrorMapper.messageKey(error));
    } finally {
      isDeleting = false;
      if (!isClosed) update();
    }
  }

  Future<void> printInvoicePdf(InvoiceModel invoice) async {
    if (isPrinting) return;

    isPrinting = true;
    update();

    try {
      final bytes = await InvoicePdfService.build(invoice);
      final fileName = invoice.invoiceNumber;

      if (kIsWeb) {
        await FileSaver.instance.saveFile(
          name: fileName,
          bytes: bytes,
          fileExtension: 'pdf',
          mimeType: MimeType.pdf,
        );
      } else {
        await Printing.layoutPdf(
          name: '$fileName.pdf',
          onLayout: (_) async => bytes,
        );
      }
    } catch (_) {
      _showError('invoice_pdf_error');
    } finally {
      isPrinting = false;
      if (!isClosed) update();
    }
  }

  void _showSuccess(String messageKey) {
    Get.snackbar(
      'invoices'.tr,
      messageKey.tr,
      snackPosition: SnackPosition.BOTTOM,
      backgroundColor: AppColor.success,
      colorText: AppColor.surface,
    );
  }

  void _showError(String messageKey) {
    Get.snackbar(
      'invoices'.tr,
      messageKey.tr,
      snackPosition: SnackPosition.BOTTOM,
      backgroundColor: AppColor.error,
      colorText: AppColor.surface,
    );
  }

  void _showInfo(String title, String message) {
    Get.snackbar(
      title,
      message,
      snackPosition: SnackPosition.BOTTOM,
      backgroundColor: AppColor.secondaryColor,
      colorText: AppColor.surface,
    );
  }

  @override
  void onClose() {
    _searchDebounce?.cancel();
    searchController.dispose();
    super.onClose();
  }
}
