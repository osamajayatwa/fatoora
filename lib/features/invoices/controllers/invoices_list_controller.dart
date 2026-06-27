import 'dart:async';

import 'package:fatoora/core/class/statusrequest.dart';
import 'package:fatoora/core/constants/app_feature_flags.dart';
import 'package:fatoora/core/constants/color.dart';
import 'package:fatoora/app/routes/app_routes.dart';
import 'package:fatoora/core/services/services.dart';
import 'package:fatoora/features/invoices/controllers/invoice_context.dart';
import 'package:fatoora/features/invoices/controllers/invoice_error_mapper.dart';
import 'package:fatoora/features/invoices/data/models/invoice_enums.dart';
import 'package:fatoora/features/invoices/data/models/invoice_model.dart';
import 'package:fatoora/features/invoices/data/repositories/invoice_repository.dart';
import 'package:fatoora/features/invoices/data/services/invoice_pdf_service.dart';
import 'package:fatoora/features/invoices/view/widgets/invoice_type_picker_sheet.dart';
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
  DateTime? fromDate;
  DateTime? toDate;
  String searchText = '';
  String loadErrorMessageKey = 'invoice_load_error';
  bool isDeleting = false;
  bool isPrinting = false;
  Timer? _searchDebounce;

  String get companyId {
    final args = InvoiceContext.arguments(Get.arguments);
    return InvoiceContext.resolveCompanyId(_myServices, args);
  }

  bool get hasFilters =>
      typeFilter != null ||
      statusFilter != null ||
      fromDate != null ||
      toDate != null ||
      searchText.trim().isNotEmpty;

  @override
  void onReady() {
    super.onReady();
    loadInvoices();
  }

  Future<void> loadInvoices() async {
    final resolvedCompanyId = companyId;
    if (resolvedCompanyId.isEmpty) {
      statusRequest = StatusRequest.unauthorized;
      loadErrorMessageKey = 'invoice_session_error';
      update();
      return;
    }

    statusRequest = StatusRequest.loading;
    loadErrorMessageKey = 'invoice_load_error';
    update();
    try {
      invoices = await _repository.getInvoices(
        companyId: resolvedCompanyId,
        type: typeFilter,
        status: statusFilter,
        fromDate: fromDate,
        toDate: toDate,
        searchText: searchText,
      );
      statusRequest = StatusRequest.success;
    } catch (error) {
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

  void onSearchChanged(String value) {
    searchText = value;
    update();
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 350), loadInvoices);
  }

  void setTypeFilter(InvoiceType? value) {
    typeFilter = value;
    loadInvoices();
  }

  void setStatusFilter(InvoiceStatus? value) {
    statusFilter = value;
    loadInvoices();
  }

  void setDateRange(DateTimeRange? range) {
    fromDate = range?.start;
    toDate = range?.end;
    loadInvoices();
  }

  void clearFilters() {
    typeFilter = null;
    statusFilter = null;
    fromDate = null;
    toDate = null;
    searchText = '';
    searchController.clear();
    loadInvoices();
  }

  void openInvoiceTypePicker() {
    Get.bottomSheet<void>(
      InvoiceTypePickerSheet(
        onRegularSelected: () {
          Get.back<void>();
          openCreateForm(InvoiceType.regular);
        },
        onElectronicSelected: AppFeatureFlags.jofotaraEnabled
            ? () {
                Get.back<void>();
                openCreateForm(InvoiceType.electronic);
              }
            : null,
        onElectronicDisabledTap: () => _showInfo(
          'electronic_invoice'.tr,
          'tax_integration_disabled_body'.tr,
        ),
      ),
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
    );
  }

  Future<void> openCreateForm(InvoiceType type) async {
    final changed = await Get.toNamed(
      AppRoute.invoiceForm,
      arguments: {
        'mode': 'create',
        'companyId': companyId,
        'invoiceType': type.value,
      },
    );
    if (changed == true) await loadInvoices();
  }

  Future<void> openDetails(InvoiceModel invoice) async {
    final changed = await Get.toNamed(
      AppRoute.invoiceDetails,
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
      AppRoute.invoiceForm,
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
    final confirmed = await Get.dialog<bool>(
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
      await Printing.layoutPdf(
        name: '${invoice.invoiceNumber}.pdf',
        onLayout: (_) => InvoicePdfService.build(invoice),
      );
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
