import 'package:fatoora/core/class/statusrequest.dart';
import 'package:fatoora/core/constant/app_feature_flags.dart';
import 'package:fatoora/core/constant/color.dart';
import 'package:fatoora/core/constant/routes.dart';
import 'package:fatoora/core/services/services.dart';
import 'package:fatoora/features/invoices/controllers/invoice_context.dart';
import 'package:fatoora/features/invoices/controllers/invoice_error_mapper.dart';
import 'package:fatoora/features/invoices/controllers/invoice_page_navigation.dart';
import 'package:fatoora/features/invoices/data/models/invoice_customer_snapshot.dart';
import 'package:fatoora/features/invoices/data/models/invoice_enums.dart';
import 'package:fatoora/features/invoices/data/models/invoice_item_snapshot.dart';
import 'package:fatoora/features/invoices/data/models/invoice_model.dart';
import 'package:fatoora/features/invoices/data/repositories/invoice_repository.dart';
import 'package:fatoora/features/invoices/data/services/invoice_number_service.dart';
import 'package:fatoora/features/invoices/data/services/invoice_totals_service.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class InvoiceFormController extends GetxController with InvoicePageNavigation {
  InvoiceFormController({
    required InvoiceRepository repository,
    required InvoiceNumberService numberService,
    required InvoiceTotalsService totalsService,
    required MyServices myServices,
  }) : _repository = repository,
       _numberService = numberService,
       _totalsService = totalsService,
       _myServices = myServices;

  final InvoiceRepository _repository;
  final InvoiceNumberService _numberService;
  final InvoiceTotalsService _totalsService;
  final MyServices _myServices;

  final GlobalKey<FormState> formKey = GlobalKey<FormState>();
  final TextEditingController invoiceNumberController = TextEditingController();
  final TextEditingController notesController = TextEditingController();
  final TextEditingController paymentMethodController = TextEditingController();
  final TextEditingController itemNameController = TextEditingController();
  final TextEditingController itemCodeController = TextEditingController();
  final TextEditingController itemUnitController = TextEditingController(
    text: 'pcs',
  );
  final TextEditingController itemQuantityController = TextEditingController(
    text: '1',
  );
  final TextEditingController itemPriceController = TextEditingController(
    text: '0',
  );
  final TextEditingController itemDiscountController = TextEditingController(
    text: '0',
  );
  final TextEditingController itemTaxController = TextEditingController(
    text: '0',
  );

  StatusRequest statusRequest = StatusRequest.loading;
  String loadErrorMessageKey = 'invoice_load_error';
  String mode = 'create';
  String companyId = '';
  String invoiceId = '';
  InvoiceType invoiceType = InvoiceType.regular;
  InvoiceStatus invoiceStatus = InvoiceStatus.draft;
  DateTime invoiceDate = DateTime.now();
  InvoiceCustomerSnapshot? customerSnapshot;
  List<InvoiceItemSnapshot> items = const [];
  double subtotal = 0;
  double totalDiscount = 0;
  double totalTax = 0;
  double grandTotal = 0;
  bool readOnly = false;
  bool isSaving = false;
  InvoiceModel? loadedInvoice;

  bool get isCreateMode => mode == 'create';
  bool get isEditMode => mode == 'edit';
  bool get isLoading => statusRequest == StatusRequest.loading;
  bool get canUseElectronic =>
      invoiceType == InvoiceType.electronic && AppFeatureFlags.jofotaraEnabled;
  bool get canSubmitElectronic =>
      canUseElectronic && !readOnly && !isSaving && items.isNotEmpty;

  @override
  void onReady() {
    super.onReady();
    initialize();
  }

  Future<void> initialize() async {
    final args = InvoiceContext.arguments(Get.arguments);
    companyId = InvoiceContext.resolveCompanyId(_myServices, args);
    invoiceId = InvoiceContext.readString(args, 'invoiceId');
    mode = InvoiceContext.readString(args, 'mode').isEmpty
        ? 'create'
        : InvoiceContext.readString(args, 'mode');
    invoiceType = invoiceTypeFromValue(args['invoiceType']);

    if (companyId.isEmpty) {
      statusRequest = StatusRequest.unauthorized;
      loadErrorMessageKey = 'invoice_session_error';
      update();
      return;
    }

    if (invoiceType == InvoiceType.electronic &&
        !AppFeatureFlags.jofotaraEnabled) {
      invoiceType = InvoiceType.regular;
      _showInfo('tax_integration_disabled', 'tax_integration_disabled_body');
    }

    if (!isCreateMode && invoiceId.isEmpty) {
      statusRequest = StatusRequest.failure;
      loadErrorMessageKey = 'invoice_not_found';
      update();
      return;
    }

    if (isCreateMode) {
      await _prepareCreateMode();
      return;
    }

    await _loadForEdit();
  }

  Future<void> _prepareCreateMode() async {
    statusRequest = StatusRequest.loading;
    update();
    invoiceNumberController.text = await _numberService.generate(
      companyId: companyId,
      invoiceType: invoiceType,
    );
    paymentMethodController.text = 'Cash';
    statusRequest = StatusRequest.success;
    update();
  }

  Future<void> _loadForEdit() async {
    statusRequest = StatusRequest.loading;
    loadErrorMessageKey = 'invoice_load_error';
    update();
    try {
      final invoice = await _repository.getInvoiceById(
        companyId: companyId,
        invoiceId: invoiceId,
      );
      if (invoice == null) {
        statusRequest = StatusRequest.failure;
        loadErrorMessageKey = 'invoice_not_found';
        update();
        return;
      }
      loadedInvoice = invoice;
      _applyInvoice(invoice);
      readOnly = mode == 'read' || !invoice.canEdit;
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

  void _applyInvoice(InvoiceModel invoice) {
    invoiceId = invoice.id;
    companyId = invoice.companyId;
    invoiceType = invoice.invoiceType;
    invoiceStatus = invoice.invoiceStatus;
    invoiceDate = invoice.invoiceDate;
    customerSnapshot = invoice.customerSnapshot;
    items = invoice.items;
    subtotal = invoice.subtotal;
    totalDiscount = invoice.totalDiscount;
    totalTax = invoice.totalTax;
    grandTotal = invoice.grandTotal;
    invoiceNumberController.text = invoice.invoiceNumber;
    notesController.text = invoice.notes;
    paymentMethodController.text = invoice.paymentMethod;
  }

  void setInvoiceDate(DateTime value) {
    if (readOnly) return;
    invoiceDate = value;
    update();
  }

  void selectCustomerPlaceholder() {
    if (readOnly) return;
    customerSnapshot = const InvoiceCustomerSnapshot(
      id: 'manual-customer',
      name: 'Cash Customer',
      phone: '',
      address: '',
      taxNumber: '',
      nationalNumber: '',
      city: 'Jordan',
    );
    update();
  }

  void addItemFromInputs() {
    if (readOnly) return;
    final itemName = itemNameController.text.trim();
    final quantity = _parseDouble(itemQuantityController.text);
    final price = _parseDouble(itemPriceController.text);
    if (itemName.isEmpty) {
      _showError('item_name_required');
      return;
    }
    if (quantity <= 0) {
      _showError('invalid_quantity');
      return;
    }
    if (price < 0) {
      _showError('invalid_price');
      return;
    }

    final rawItem = InvoiceItemSnapshot(
      itemId: 'manual-${DateTime.now().millisecondsSinceEpoch}',
      itemName: itemName,
      itemCode: itemCodeController.text.trim(),
      unit: itemUnitController.text.trim().isEmpty
          ? 'pcs'
          : itemUnitController.text.trim(),
      quantity: quantity,
      unitPrice: price,
      discount: _parseDouble(itemDiscountController.text),
      taxPercent: _parseDouble(itemTaxController.text),
      subtotal: 0,
      taxAmount: 0,
      total: 0,
    );
    items = [...items, _totalsService.calculateLine(rawItem)];
    _clearItemInputs();
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
    if (readOnly || index < 0 || index >= items.length) return;
    final item = items[index].copyWith(
      quantity: quantity,
      unitPrice: unitPrice,
      discount: discount,
      taxPercent: taxPercent,
    );
    final next = [...items];
    next[index] = _totalsService.calculateLine(item);
    items = next;
    recalculateTotals();
  }

  void recalculateTotals() {
    final totals = _totalsService.calculateInvoice(items);
    items = totals.items;
    subtotal = totals.subtotal;
    totalDiscount = totals.totalDiscount;
    totalTax = totals.totalTax;
    grandTotal = totals.grandTotal;
    update();
  }

  Future<void> saveDraft() => _save(InvoiceStatus.draft);

  Future<void> saveInvoice() {
    final targetStatus = invoiceType == InvoiceType.electronic
        ? InvoiceStatus.draft
        : InvoiceStatus.accepted;
    return _save(targetStatus);
  }

  Future<void> saveAndSubmit() async {
    if (!canSubmitElectronic) return;
    final saved = await _save(InvoiceStatus.draft, stayOnPage: true);
    if (!saved) return;
    await submitElectronicInvoicePlaceholder();
  }

  Future<bool> _save(
    InvoiceStatus targetStatus, {
    bool stayOnPage = false,
  }) async {
    if (readOnly || isSaving) return false;
    if (!_validateForm()) return false;

    isSaving = true;
    statusRequest = StatusRequest.loading;
    update();
    try {
      final wasCreateMode = isCreateMode || invoiceId.isEmpty;
      final invoice = _buildInvoice(targetStatus);
      if (wasCreateMode) {
        invoiceId = await _repository.createInvoice(invoice: invoice);
        mode = 'edit';
      } else {
        await _repository.updateInvoice(invoice: invoice);
      }
      _showSuccess(
        wasCreateMode
            ? 'regular_invoice_created'
            : 'invoice_updated_successfully',
      );
      statusRequest = StatusRequest.success;
      if (!stayOnPage) {
        await leaveInvoicePage(fallbackRoute: AppRoute.invoices, result: true);
      }
      return true;
    } catch (error) {
      statusRequest = InvoiceErrorMapper.status(error);
      _showError(InvoiceErrorMapper.messageKey(error));
      return false;
    } finally {
      isSaving = false;
      if (!isClosed) update();
    }
  }

  Future<void> submitElectronicInvoicePlaceholder() async {
    if (!AppFeatureFlags.jofotaraEnabled ||
        invoiceType != InvoiceType.electronic) {
      _showInfo('tax_integration_disabled', 'tax_integration_disabled_body');
      return;
    }
    if (invoiceId.isEmpty || isSaving) return;

    isSaving = true;
    update();
    try {
      await _repository.submitElectronicInvoicePlaceholder(
        companyId: companyId,
        invoiceId: invoiceId,
      );
      _showSuccess('submission_success');
      await leaveInvoicePage(fallbackRoute: AppRoute.invoices, result: true);
    } catch (error) {
      _showError(
        InvoiceErrorMapper.messageKey(error, fallback: 'submission_failed'),
      );
    } finally {
      isSaving = false;
      if (!isClosed) update();
    }
  }

  Future<void> requestBack() {
    return leaveInvoicePage(fallbackRoute: AppRoute.invoices);
  }

  bool _validateForm() {
    final formValid = formKey.currentState?.validate() ?? true;
    if (!formValid) return false;
    if (invoiceNumberController.text.trim().isEmpty) {
      _showError('invoice_number_required');
      return false;
    }
    if (customerSnapshot == null) {
      _showError('customer_required');
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

  InvoiceModel _buildInvoice(InvoiceStatus targetStatus) {
    final now = DateTime.now();
    final createdAt = loadedInvoice?.createdAt ?? now;
    final createdByUid =
        loadedInvoice?.createdByUid ??
        _myServices.sharedPreferences.getString('uid') ??
        '';
    final createdByName =
        loadedInvoice?.createdByName ??
        _myServices.sharedPreferences.getString('name') ??
        '';
    return InvoiceModel(
      id: invoiceId,
      companyId: companyId,
      invoiceNumber: invoiceNumberController.text.trim(),
      invoiceType: invoiceType,
      invoiceStatus: targetStatus,
      invoiceDate: invoiceDate,
      createdAt: createdAt,
      updatedAt: now,
      createdByUid: createdByUid,
      createdByName: createdByName,
      customerId: customerSnapshot?.id ?? '',
      customerSnapshot: customerSnapshot,
      items: items,
      subtotal: subtotal,
      totalDiscount: totalDiscount,
      totalTax: totalTax,
      grandTotal: grandTotal,
      notes: notesController.text.trim(),
      paymentMethod: paymentMethodController.text.trim(),
      isLocked: loadedInvoice?.isLocked ?? false,
      searchKeywords: const [],
      customerNameLower: '',
      itemNamesLower: const [],
      invoiceNumberLower: '',
      dateString: InvoiceModel.formatDateForSearch(invoiceDate),
      government: loadedInvoice?.government,
    ).withSearchFields();
  }

  double _parseDouble(String value) => double.tryParse(value.trim()) ?? 0;

  void _clearItemInputs() {
    itemNameController.clear();
    itemCodeController.clear();
    itemUnitController.text = 'pcs';
    itemQuantityController.text = '1';
    itemPriceController.text = '0';
    itemDiscountController.text = '0';
    itemTaxController.text = '0';
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

  void _showInfo(String titleKey, String messageKey) {
    Get.snackbar(
      titleKey.tr,
      messageKey.tr,
      snackPosition: SnackPosition.BOTTOM,
      backgroundColor: AppColor.secondaryColor,
      colorText: AppColor.surface,
    );
  }

  @override
  void onClose() {
    invoiceNumberController.dispose();
    notesController.dispose();
    paymentMethodController.dispose();
    itemNameController.dispose();
    itemCodeController.dispose();
    itemUnitController.dispose();
    itemQuantityController.dispose();
    itemPriceController.dispose();
    itemDiscountController.dispose();
    itemTaxController.dispose();
    super.onClose();
  }
}
