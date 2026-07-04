import 'package:fatoora/core/class/statusrequest.dart';
import 'package:fatoora/core/constants/app_feature_flags.dart';
import 'package:fatoora/core/constants/color.dart';
import 'package:fatoora/app/routes/app_routes.dart';
import 'package:fatoora/core/services/services.dart';
import 'package:fatoora/core/settings/business_settings_defaults.dart';
import 'package:fatoora/core/settings/business_settings_resolver.dart';
import 'package:fatoora/core/settings/business_permission_resolver.dart';
import 'package:fatoora/features/auth/utils/auth_session.dart';
import 'package:fatoora/features/customers/data/models/customer_model.dart';
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
import 'package:fatoora/features/items/data/models/item_model.dart';
import 'package:fatoora/features/settings/data/models/app_settings_model.dart';
import 'package:fatoora/features/settings/data/models/user_preferences_model.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class InvoiceFormController extends GetxController with InvoicePageNavigation {
  InvoiceFormController({
    required InvoiceRepository repository,
    required InvoiceNumberService numberService,
    required InvoiceTotalsService totalsService,
    required MyServices myServices,
    required BusinessSettingsResolver settingsResolver,
    required BusinessPermissionResolver permissionResolver,
  }) : _repository = repository,
       _numberService = numberService,
       _totalsService = totalsService,
       _myServices = myServices,
       _settingsResolver = settingsResolver,
       _permissionResolver = permissionResolver;

  final InvoiceRepository _repository;
  final InvoiceNumberService _numberService;
  final InvoiceTotalsService _totalsService;
  final MyServices _myServices;
  final BusinessSettingsResolver _settingsResolver;
  final BusinessPermissionResolver _permissionResolver;

  final GlobalKey<FormState> formKey = GlobalKey<FormState>();
  final TextEditingController invoiceNumberController = TextEditingController();
  final TextEditingController notesController = TextEditingController();
  final TextEditingController paymentMethodController = TextEditingController();
  final TextEditingController paidAmountController = TextEditingController(
    text: '0',
  );
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
  PaymentType paymentType = PaymentType.credit;
  PaymentStatus paymentStatus = PaymentStatus.unpaid;
  DateTime invoiceDate = DateTime.now();
  DateTime dueDate = DateTime.now();
  InvoiceCustomerSnapshot? customerSnapshot;
  List<InvoiceItemSnapshot> items = const [];
  double subtotal = 0;
  double totalDiscount = 0;
  double totalTax = 0;
  double grandTotal = 0;
  double paidAmount = 0;
  double remainingAmount = 0;
  bool hasReceivedPayment = false;
  bool readOnly = false;
  bool isSaving = false;
  InvoiceModel? loadedInvoice;
  int _defaultDueDays = 0;
  double _defaultTaxPercent = 0;
  bool _dueDateManuallyChanged = false;
  EffectiveBusinessPermissions permissions =
      EffectiveBusinessPermissions.denied;

  bool get isCreateMode => mode == 'create';
  bool get isEditMode => mode == 'edit';
  bool get isLoading => statusRequest == StatusRequest.loading;
  bool get canUseElectronic =>
      invoiceType == InvoiceType.electronic && AppFeatureFlags.jofotaraEnabled;
  bool get canSubmitElectronic =>
      canUseElectronic && !readOnly && !isSaving && items.isNotEmpty;
  bool get canEditCatalogPrice => !readOnly && permissions.editCatalogPrice;
  bool get canApplyDiscount => !readOnly && permissions.applyDiscount;

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
    final uid = _myServices.sharedPreferences.getString('uid') ?? '';
    final values = await Future.wait<Object>([
      _settingsResolver.loadAppSettings(companyId),
      _settingsResolver.loadUserPreferences(uid),
      _permissionResolver.resolve(companyId),
    ]);
    final appSettings = values[0] as AppSettingsModel;
    final preferences = values[1] as UserPreferencesModel;
    permissions = values[2] as EffectiveBusinessPermissions;
    final documents = appSettings.documentSettings;
    _defaultDueDays = documents.defaultDueDays;
    _defaultTaxPercent = BusinessSettingsDefaults.taxPercent(
      existingTaxPercent: null,
      defaultTaxPercent: documents.defaultTaxPercent,
    );
    invoiceNumberController.text = await _numberService.generate(
      companyId: companyId,
      invoiceType: invoiceType,
      settings: documents,
    );
    dueDate = BusinessSettingsDefaults.invoiceDueDate(
      invoiceDate,
      _defaultDueDays,
    );
    itemTaxController.text = BusinessSettingsDefaults.inputNumber(
      _defaultTaxPercent,
    );
    notesController.text = BusinessSettingsDefaults.prefilledNote(
      currentNote: notesController.text,
      defaultNote: preferences.defaultInvoiceNote,
    );
    hasReceivedPayment = false;
    _syncPaymentAmounts(updateView: false);
    statusRequest = StatusRequest.success;
    update();
  }

  Future<void> _loadForEdit() async {
    statusRequest = StatusRequest.loading;
    loadErrorMessageKey = 'invoice_load_error';
    update();
    try {
      final values = await Future.wait<Object?>([
        _repository.getInvoiceById(companyId: companyId, invoiceId: invoiceId),
        _permissionResolver.resolve(companyId),
      ]);
      final invoice = values[0] as InvoiceModel?;
      permissions = values[1] as EffectiveBusinessPermissions;
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
    paymentType = invoice.paymentType;
    paymentStatus = invoice.paymentStatus;
    hasReceivedPayment = invoice.hasReceivedPayment;
    invoiceDate = invoice.invoiceDate;
    dueDate = invoice.dueDate;
    customerSnapshot = invoice.customerSnapshot;
    items = invoice.items;
    subtotal = invoice.subtotal;
    totalDiscount = invoice.totalDiscount;
    totalTax = invoice.totalTax;
    grandTotal = invoice.grandTotal;
    paidAmount = invoice.paidAmount;
    remainingAmount = invoice.remainingAmount;
    invoiceNumberController.text = invoice.invoiceNumber;
    notesController.text = invoice.notes;
    paymentMethodController.text = invoice.paymentType.value;
    paidAmountController.text = _formatInputAmount(invoice.paidAmount);
  }

  void setInvoiceDate(DateTime value) {
    if (readOnly) return;
    invoiceDate = value;
    if (isCreateMode && !_dueDateManuallyChanged) {
      dueDate = BusinessSettingsDefaults.invoiceDueDate(value, _defaultDueDays);
    } else if (dueDate.isBefore(_dateOnly(value))) {
      dueDate = value;
    }
    update();
  }

  void setDueDate(DateTime value) {
    if (readOnly) return;
    dueDate = value;
    _dueDateManuallyChanged = true;
    update();
  }

  void setHasReceivedPayment(bool value) {
    if (readOnly) return;
    hasReceivedPayment = value;
    if (!value) {
      paidAmountController.text = '0';
    }
    _syncPaymentAmounts(updateView: true);
  }

  void onPaidAmountChanged(String value) {
    paidAmount = _parseDouble(value);
    _syncPaymentAmounts(updateView: true, keepReceivedInput: true);
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
    items = [...items, _totalsService.calculateLine(rawItem)];
    recalculateTotals();
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
    final discount = _parseDouble(itemDiscountController.text);
    if (!canApplyDiscount && discount > 0) {
      _showError('sales_rep_discount_disabled');
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
      discount: canApplyDiscount ? discount : 0,
      taxPercent: BusinessSettingsDefaults.taxPercent(
        existingTaxPercent: double.tryParse(itemTaxController.text.trim()),
        defaultTaxPercent: _defaultTaxPercent,
      ),
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
    if (unitPrice != null && !canEditCatalogPrice) {
      _showError('sales_rep_price_edit_disabled');
      return;
    }
    if (discount != null && !canApplyDiscount) {
      _showError('sales_rep_discount_disabled');
      return;
    }
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
    _syncPaymentAmounts(updateView: false);
    update();
  }

  Future<void> saveDraft() => _save(InvoiceStatus.draft);

  Future<void> confirmInvoice() => _save(InvoiceStatus.confirmed);

  Future<void> saveInvoice() => confirmInvoice();

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
        targetStatus == InvoiceStatus.draft
            ? 'invoice_saved_as_draft'
            : 'invoice_confirmed_successfully',
      );
      statusRequest = StatusRequest.success;
      if (!stayOnPage) {
        await leaveInvoicePage(fallbackRoute: AppRoute.invoices, result: true);
      }
      return true;
    } catch (error) {
      statusRequest = InvoiceErrorMapper.status(error);
      final stockFailure = InvoiceErrorMapper.insufficientStock(error);
      if (stockFailure == null) {
        _showError(InvoiceErrorMapper.messageKey(error));
      } else {
        _showErrorText(
          'stock_not_enough'.trParams({
            'item': stockFailure.itemName,
            'requested': _formatQuantity(stockFailure.requestedQuantity),
            'available': _formatQuantity(stockFailure.availableQuantity),
          }),
        );
      }
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
    if (_dateOnly(dueDate).isBefore(_dateOnly(invoiceDate))) {
      _showError('invoice_due_date_invalid');
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
    if (!_validatePayment()) return false;
    return true;
  }

  bool _validatePayment() {
    _syncPaymentAmounts(updateView: false, keepReceivedInput: true);
    if (paidAmount < 0) {
      _showError('paid_amount_invalid');
      return false;
    }
    if (paidAmount > grandTotal) {
      _showError('paid_amount_greater_than_total');
      return false;
    }
    if (!hasReceivedPayment && paidAmount != 0) {
      _showError('paid_amount_invalid');
      return false;
    }
    if (hasReceivedPayment && paidAmount <= 0) {
      _showError('paid_amount_invalid');
      return false;
    }
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
        AuthSession.cachedDisplayName(_myServices);
    final salesRepId = loadedInvoice?.salesRepId ?? createdByUid;
    final salesRepName = loadedInvoice?.salesRepName ?? createdByName;
    return InvoiceModel(
      id: invoiceId,
      companyId: companyId,
      invoiceNumber: invoiceNumberController.text.trim(),
      invoiceType: invoiceType,
      invoiceStatus: targetStatus,
      paymentType: paymentType,
      paymentStatus: paymentStatus,
      hasReceivedPayment: hasReceivedPayment,
      invoiceDate: invoiceDate,
      dueDate: dueDate,
      createdAt: createdAt,
      updatedAt: now,
      createdByUid: createdByUid,
      createdByName: createdByName,
      createdByRole: _myServices.sharedPreferences.getString('role') ?? '',
      salesRepId: salesRepId,
      salesRepName: salesRepName,
      customerId: customerSnapshot?.id ?? '',
      customerSnapshot: customerSnapshot,
      items: items,
      subtotal: subtotal,
      totalDiscount: totalDiscount,
      totalTax: totalTax,
      grandTotal: grandTotal,
      paidAmount: paidAmount,
      remainingAmount: remainingAmount,
      notes: notesController.text.trim(),
      paymentMethod: paymentType.value,
      isLocked: loadedInvoice?.isLocked ?? false,
      financialPosted: loadedInvoice?.financialPosted ?? false,
      financialPostedAt: loadedInvoice?.financialPostedAt,
      financialPostedByUid: loadedInvoice?.financialPostedByUid ?? '',
      financialPostedByName: loadedInvoice?.financialPostedByName ?? '',
      customerTransactionIds: loadedInvoice?.customerTransactionIds ?? const [],
      cashMovementIds: loadedInvoice?.cashMovementIds ?? const [],
      inventoryPosted: loadedInvoice?.inventoryPosted ?? false,
      inventoryPostedAt: loadedInvoice?.inventoryPostedAt,
      inventoryPostedByUid: loadedInvoice?.inventoryPostedByUid ?? '',
      inventoryPostedByName: loadedInvoice?.inventoryPostedByName ?? '',
      inventoryMovementIds: loadedInvoice?.inventoryMovementIds ?? const [],
      searchKeywords: const [],
      customerNameLower: '',
      itemNamesLower: const [],
      invoiceNumberLower: '',
      dateString: InvoiceModel.formatDateForSearch(invoiceDate),
      government: loadedInvoice?.government,
    ).withSearchFields();
  }

  double _parseDouble(String value) => double.tryParse(value.trim()) ?? 0;

  void _syncPaymentAmounts({
    bool updateView = true,
    bool keepReceivedInput = false,
  }) {
    if (!hasReceivedPayment) {
      paidAmount = 0;
      remainingAmount = grandTotal;
      paymentType = PaymentType.credit;
      paymentStatus = PaymentStatus.unpaid;
      paymentMethodController.text = paymentType.value;
      paidAmountController.text = '0';
    } else {
      if (!keepReceivedInput) {
        paidAmount = _parseDouble(paidAmountController.text);
      }
      paidAmount = _totalsService.round(paidAmount);
      final rawRemaining = grandTotal - paidAmount;
      remainingAmount = _totalsService.round(
        rawRemaining > 0 ? rawRemaining : 0,
      );
      if (paidAmount >= grandTotal && grandTotal > 0) {
        paymentType = PaymentType.cash;
        paymentStatus = PaymentStatus.paid;
      } else if (paidAmount > 0) {
        paymentType = PaymentType.partial;
        paymentStatus = PaymentStatus.partiallyPaid;
      } else {
        paymentType = PaymentType.partial;
        paymentStatus = PaymentStatus.unpaid;
      }
      paymentMethodController.text = paymentType.value;
    }
    paidAmount = _totalsService.round(paidAmount);
    remainingAmount = _totalsService.round(remainingAmount);
    if (updateView && !isClosed) update();
  }

  DateTime _dateOnly(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  String _formatInputAmount(double value) {
    final rounded = _totalsService.round(value);
    if (rounded == rounded.roundToDouble()) return rounded.toStringAsFixed(0);
    return rounded.toStringAsFixed(3);
  }

  String _formatQuantity(double value) {
    final rounded = _totalsService.round(value);
    if (rounded == rounded.roundToDouble()) return rounded.toStringAsFixed(0);
    return rounded.toStringAsFixed(3);
  }

  void _clearItemInputs() {
    itemNameController.clear();
    itemCodeController.clear();
    itemUnitController.text = 'pcs';
    itemQuantityController.text = '1';
    itemPriceController.text = '0';
    itemDiscountController.text = '0';
    itemTaxController.text = BusinessSettingsDefaults.inputNumber(
      _defaultTaxPercent,
    );
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
    _showErrorText(messageKey.tr);
  }

  void _showErrorText(String message) {
    Get.snackbar(
      'invoices'.tr,
      message,
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
    paidAmountController.dispose();
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
