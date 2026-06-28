import 'package:fatoora/app/routes/app_routes.dart';
import 'package:fatoora/core/class/statusrequest.dart';
import 'package:fatoora/core/constants/color.dart';
import 'package:fatoora/core/services/services.dart';
import 'package:fatoora/features/auth/data/repositories/auth_repository.dart';
import 'package:fatoora/features/auth/utils/auth_session.dart';
import 'package:fatoora/features/customers/data/models/customer_model.dart';
import 'package:fatoora/features/invoices/data/models/invoice_customer_snapshot.dart';
import 'package:fatoora/features/invoices/data/models/invoice_item_snapshot.dart';
import 'package:fatoora/features/invoices/data/services/invoice_totals_service.dart';
import 'package:fatoora/features/items/data/models/item_model.dart';
import 'package:fatoora/features/quotations/controllers/quotation_error_mapper.dart';
import 'package:fatoora/features/quotations/data/models/quotation_item_model.dart';
import 'package:fatoora/features/quotations/data/models/quotation_model.dart';
import 'package:fatoora/features/quotations/data/models/quotation_status.dart';
import 'package:fatoora/features/quotations/data/repositories/quotation_repository.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class QuotationFormController extends GetxController {
  QuotationFormController({
    required QuotationRepository repository,
    required InvoiceTotalsService totalsService,
    required MyServices myServices,
  }) : _repository = repository,
       _totalsService = totalsService,
       _myServices = myServices;

  final QuotationRepository _repository;
  final InvoiceTotalsService _totalsService;
  final MyServices _myServices;

  final GlobalKey<FormState> formKey = GlobalKey<FormState>();
  final TextEditingController quotationNumberController =
      TextEditingController();
  final TextEditingController notesController = TextEditingController();
  final TextEditingController termsController = TextEditingController();

  StatusRequest statusRequest = StatusRequest.loading;
  String loadErrorMessageKey = 'quotation_load_error';
  String mode = 'create';
  String companyId = '';
  String quotationId = '';
  DateTime quotationDate = DateTime.now();
  DateTime validUntil = DateTime.now().add(const Duration(days: 14));
  InvoiceCustomerSnapshot? customerSnapshot;
  List<QuotationItemModel> items = const [];
  double subtotal = 0;
  double totalDiscount = 0;
  double totalTax = 0;
  double grandTotal = 0;
  bool readOnly = false;
  bool isSaving = false;
  QuotationModel? loadedQuotation;

  bool get isCreateMode => mode == 'create';
  List<InvoiceItemSnapshot> get invoiceItems =>
      items.map((item) => item.toInvoiceItem()).toList(growable: false);

  @override
  void onReady() {
    super.onReady();
    initialize();
  }

  Future<void> initialize() async {
    final args = Get.arguments;
    if (args is Map) {
      companyId =
          (args['companyId'] as String?) ??
          _myServices.sharedPreferences.getString('companyId') ??
          AuthRepository.defaultCompanyId;
      quotationId = (args['quotationId'] as String?)?.trim() ?? '';
      mode = (args['mode'] as String?)?.trim().isEmpty ?? true
          ? 'create'
          : (args['mode'] as String).trim();
    } else {
      companyId =
          _myServices.sharedPreferences.getString('companyId') ??
          AuthRepository.defaultCompanyId;
    }

    if (isCreateMode) {
      quotationNumberController.text = 'auto_number'.tr;
      statusRequest = StatusRequest.success;
      update();
      return;
    }

    if (quotationId.isEmpty) {
      statusRequest = StatusRequest.failure;
      loadErrorMessageKey = 'quotation_not_found';
      update();
      return;
    }

    statusRequest = StatusRequest.loading;
    update();
    try {
      final quotation = await _repository.getQuotationById(
        companyId: companyId,
        quotationId: quotationId,
      );
      if (quotation == null) {
        statusRequest = StatusRequest.failure;
        loadErrorMessageKey = 'quotation_not_found';
        update();
        return;
      }
      _applyQuotation(quotation);
      readOnly = !quotation.canEdit;
      statusRequest = StatusRequest.success;
    } catch (error) {
      statusRequest = QuotationErrorMapper.status(error);
      loadErrorMessageKey = QuotationErrorMapper.messageKey(
        error,
        fallback: 'quotation_load_error',
      );
      _showError(loadErrorMessageKey);
    }
    if (!isClosed) update();
  }

  void _applyQuotation(QuotationModel quotation) {
    loadedQuotation = quotation;
    quotationId = quotation.id;
    companyId = quotation.companyId;
    quotationDate = quotation.quotationDate;
    validUntil = quotation.validUntil;
    customerSnapshot = quotation.customerSnapshot;
    items = quotation.items;
    subtotal = quotation.subtotal;
    totalDiscount = quotation.totalDiscount;
    totalTax = quotation.totalTax;
    grandTotal = quotation.grandTotal;
    quotationNumberController.text = quotation.quotationNumber;
    notesController.text = quotation.notes;
    termsController.text = quotation.terms;
  }

  void setQuotationDate(DateTime value) {
    if (readOnly) return;
    quotationDate = value;
    if (validUntil.isBefore(_dateOnly(value))) validUntil = value;
    update();
  }

  void setValidUntil(DateTime value) {
    if (readOnly) return;
    validUntil = value;
    update();
  }

  void selectCustomer(CustomerModel customer) {
    if (readOnly) return;
    customerSnapshot = customer.toInvoiceSnapshot();
    update();
  }

  void addCatalogItem(ItemModel item) {
    if (readOnly || !item.active || item.deleted) return;
    final rawItem = InvoiceItemSnapshot(
      itemId: item.id,
      itemName: item.name,
      itemCode: item.code,
      unit: item.unit,
      quantity: 1,
      unitPrice: item.price,
      discount: 0,
      taxPercent: item.taxRate,
      subtotal: 0,
      taxAmount: 0,
      total: 0,
    );
    final line = _totalsService.calculateLine(rawItem);
    items = [...items, QuotationItemModel.fromInvoiceItem(line)];
    recalculateTotals();
  }

  void removeItem(int index) {
    if (readOnly || index < 0 || index >= items.length) return;
    items = [...items]..removeAt(index);
    recalculateTotals();
  }

  void updateItem({
    required int index,
    double? quantity,
    double? unitPrice,
    double? discount,
    double? taxPercent,
  }) {
    // TODO(settings-stage-2c): enforce discount and sales-rep price controls.
    if (readOnly || index < 0 || index >= items.length) return;
    final updated = items[index].toInvoiceItem().copyWith(
      quantity: quantity,
      unitPrice: unitPrice,
      discount: discount,
      taxPercent: taxPercent,
    );
    final next = [...items];
    next[index] = QuotationItemModel.fromInvoiceItem(
      _totalsService.calculateLine(updated),
    );
    items = next;
    recalculateTotals();
  }

  void recalculateTotals() {
    final totals = _totalsService.calculateInvoice(invoiceItems);
    items = totals.items
        .map(QuotationItemModel.fromInvoiceItem)
        .toList(growable: false);
    subtotal = totals.subtotal;
    totalDiscount = totals.totalDiscount;
    totalTax = totals.totalTax;
    grandTotal = totals.grandTotal;
    update();
  }

  Future<void> saveDraft() async {
    if (readOnly || isSaving) return;
    if (!_validate()) return;
    isSaving = true;
    statusRequest = StatusRequest.loading;
    update();
    try {
      final quotation = _buildQuotation();
      final id = await _repository.saveQuotation(quotation: quotation);
      _showSuccess(
        isCreateMode
            ? 'quotation_saved_successfully'
            : 'quotation_updated_successfully',
      );
      if (isCreateMode) {
        await Get.offNamed(
          AppRoute.quotationDetails,
          arguments: {'companyId': companyId, 'quotationId': id},
        );
      } else {
        Get.back(result: true);
      }
    } catch (error) {
      statusRequest = QuotationErrorMapper.status(error);
      _showError(QuotationErrorMapper.messageKey(error));
    } finally {
      isSaving = false;
      if (!isClosed) update();
    }
  }

  bool _validate() {
    final formValid = formKey.currentState?.validate() ?? true;
    if (!formValid) return false;
    if (customerSnapshot == null) {
      _showError('customer_required');
      return false;
    }
    if (_dateOnly(validUntil).isBefore(_dateOnly(quotationDate))) {
      _showError('quotation_valid_until_invalid');
      return false;
    }
    if (items.isEmpty) {
      _showError('items_required');
      return false;
    }
    for (final item in items) {
      if (item.quantity <= 0) {
        _showError('invalid_quantity');
        return false;
      }
      if (item.unitPrice < 0) {
        _showError('invalid_price');
        return false;
      }
    }
    recalculateTotals();
    return true;
  }

  QuotationModel _buildQuotation() {
    final now = DateTime.now();
    final createdAt = loadedQuotation?.createdAt ?? now;
    final createdByUid =
        loadedQuotation?.createdByUid ??
        _myServices.sharedPreferences.getString('uid') ??
        '';
    final createdByName =
        loadedQuotation?.createdByName ??
        AuthSession.cachedDisplayName(_myServices);
    return QuotationModel(
      id: quotationId,
      companyId: companyId,
      quotationNumber: loadedQuotation?.quotationNumber ?? '',
      quotationDate: quotationDate,
      validUntil: validUntil,
      customerId: customerSnapshot?.id ?? '',
      customerSnapshot: customerSnapshot,
      items: items,
      subtotal: subtotal,
      totalDiscount: totalDiscount,
      totalTax: totalTax,
      grandTotal: grandTotal,
      notes: notesController.text.trim(),
      terms: termsController.text.trim(),
      status: QuotationStatus.draft,
      salesRepId: loadedQuotation?.salesRepId ?? createdByUid,
      salesRepName: loadedQuotation?.salesRepName ?? createdByName,
      createdByUid: createdByUid,
      createdByName: createdByName,
      createdByRole:
          loadedQuotation?.createdByRole ??
          _myServices.sharedPreferences.getString('role') ??
          '',
      convertedInvoiceId: loadedQuotation?.convertedInvoiceId ?? '',
      convertedInvoiceNumber: loadedQuotation?.convertedInvoiceNumber ?? '',
      createdAt: createdAt,
      updatedAt: now,
      searchKeywords: const [],
    ).withSearchFields();
  }

  Future<void> requestBack() async {
    Get.back(result: false);
  }

  DateTime _dateOnly(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  void _showSuccess(String messageKey) {
    Get.snackbar(
      'quotations'.tr,
      messageKey.tr,
      snackPosition: SnackPosition.BOTTOM,
      backgroundColor: AppColor.success,
      colorText: AppColor.surface,
    );
  }

  void _showError(String messageKey) {
    Get.snackbar(
      'quotations'.tr,
      messageKey.tr,
      snackPosition: SnackPosition.BOTTOM,
      backgroundColor: AppColor.error,
      colorText: AppColor.surface,
    );
  }

  @override
  void onClose() {
    quotationNumberController.dispose();
    notesController.dispose();
    termsController.dispose();
    super.onClose();
  }
}
