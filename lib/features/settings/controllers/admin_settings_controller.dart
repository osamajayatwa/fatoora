import 'package:fatoora/core/constants/color.dart';
import 'package:fatoora/features/settings/data/models/app_settings_model.dart';
import 'package:fatoora/features/settings/data/models/company_settings_model.dart';
import 'package:fatoora/features/settings/data/models/document_settings_model.dart';
import 'package:fatoora/features/settings/data/models/inventory_settings_model.dart';
import 'package:fatoora/features/settings/data/models/pdf_settings_model.dart';
import 'package:fatoora/features/settings/data/models/permission_settings_model.dart';
import 'package:fatoora/features/settings/data/repositories/settings_repository.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class AdminSettingsController extends GetxController {
  AdminSettingsController({required SettingsRepository repository})
    : _repository = repository;

  final SettingsRepository _repository;
  final GlobalKey<FormState> formKey = GlobalKey<FormState>();

  final companyNameController = TextEditingController();
  final countryController = TextEditingController();
  final emailController = TextEditingController();
  final websiteController = TextEditingController();
  final phoneController = TextEditingController();
  final addressController = TextEditingController();
  final invoicePrefixController = TextEditingController();
  final receiptPrefixController = TextEditingController();
  final quotationPrefixController = TextEditingController();
  final salesReturnPrefixController = TextEditingController();
  final defaultDueDaysController = TextEditingController();
  final defaultTaxPercentController = TextEditingController();
  final defaultWarehouseController = TextEditingController();
  final defaultMinStockController = TextEditingController();
  final invoiceFooterController = TextEditingController();
  final quotationTermsController = TextEditingController();
  final receiptFooterController = TextEditingController();
  final statementFooterController = TextEditingController();
  final defaultNotesController = TextEditingController();

  AppSettingsModel settings = AppSettingsModel.defaults;
  bool isSaving = false;
  bool logoEnabled = true;
  bool allowDiscount = true;
  bool allowSalesRepPriceEdit = true;
  bool allowNegativeStock = false;
  bool lowStockAlertsEnabled = true;
  bool trackStockByDefault = true;
  bool showLogo = true;
  bool showCompanyInfo = true;
  String pdfLanguageMode = 'app_language';
  bool allowSalesRepCreateCustomers = true;
  bool allowSalesRepCreateReceipts = true;
  bool allowSalesRepCreateReturns = true;
  bool allowSalesRepCreateQuotations = true;
  bool allowSalesRepPermissionPriceEdit = true;
  bool allowSalesRepDiscount = true;

  void hydrate(AppSettingsModel value) {
    settings = value;
    final company = value.companySettings;
    final documents = value.documentSettings;
    final inventory = value.inventorySettings;
    final pdf = value.pdfSettings;
    final permissions = value.permissionSettings;

    companyNameController.text = company.name;
    countryController.text = company.country;
    emailController.text = company.email;
    websiteController.text = company.website;
    phoneController.text = company.phone;
    addressController.text = company.address;
    logoEnabled = company.logoEnabled;

    invoicePrefixController.text = documents.invoicePrefix;
    receiptPrefixController.text = documents.receiptPrefix;
    quotationPrefixController.text = documents.quotationPrefix;
    salesReturnPrefixController.text = documents.salesReturnPrefix;
    defaultDueDaysController.text = documents.defaultDueDays.toString();
    defaultTaxPercentController.text = _number(documents.defaultTaxPercent);
    allowDiscount = documents.allowDiscount;
    allowSalesRepPriceEdit = documents.allowSalesRepPriceEdit;

    defaultWarehouseController.text = inventory.defaultWarehouseId;
    defaultMinStockController.text = _number(inventory.defaultMinStock);
    allowNegativeStock = inventory.allowNegativeStock;
    lowStockAlertsEnabled = inventory.lowStockAlertsEnabled;
    trackStockByDefault = inventory.trackStockByDefault;

    showLogo = pdf.showLogo;
    showCompanyInfo = pdf.showCompanyInfo;
    pdfLanguageMode = pdf.pdfLanguageMode;
    invoiceFooterController.text = pdf.invoiceFooterText;
    quotationTermsController.text = pdf.quotationTerms;
    receiptFooterController.text = pdf.receiptFooterText;
    statementFooterController.text = pdf.statementFooterText;
    defaultNotesController.text = pdf.defaultNotes;

    allowSalesRepCreateCustomers = permissions.allowSalesRepCreateCustomers;
    allowSalesRepCreateReceipts = permissions.allowSalesRepCreateReceipts;
    allowSalesRepCreateReturns = permissions.allowSalesRepCreateReturns;
    allowSalesRepCreateQuotations = permissions.allowSalesRepCreateQuotations;
    allowSalesRepPermissionPriceEdit = permissions.allowSalesRepPriceEdit;
    allowSalesRepDiscount = permissions.allowSalesRepDiscount;
    if (!isClosed) update();
  }

  void setLogoEnabled(bool value) => _set(() => logoEnabled = value);
  void setAllowDiscount(bool value) => _set(() => allowDiscount = value);
  void setAllowSalesRepPriceEdit(bool value) =>
      _set(() => allowSalesRepPriceEdit = value);
  void setAllowNegativeStock(bool value) =>
      _set(() => allowNegativeStock = value);
  void setLowStockAlertsEnabled(bool value) =>
      _set(() => lowStockAlertsEnabled = value);
  void setTrackStockByDefault(bool value) =>
      _set(() => trackStockByDefault = value);
  void setShowLogo(bool value) => _set(() => showLogo = value);
  void setShowCompanyInfo(bool value) => _set(() => showCompanyInfo = value);
  void setPdfLanguageMode(String? value) {
    if (value == null) return;
    _set(() => pdfLanguageMode = value);
  }

  void setAllowSalesRepCreateCustomers(bool value) =>
      _set(() => allowSalesRepCreateCustomers = value);
  void setAllowSalesRepCreateReceipts(bool value) =>
      _set(() => allowSalesRepCreateReceipts = value);
  void setAllowSalesRepCreateReturns(bool value) =>
      _set(() => allowSalesRepCreateReturns = value);
  void setAllowSalesRepCreateQuotations(bool value) =>
      _set(() => allowSalesRepCreateQuotations = value);
  void setAllowSalesRepPermissionPriceEdit(bool value) =>
      _set(() => allowSalesRepPermissionPriceEdit = value);
  void setAllowSalesRepDiscount(bool value) =>
      _set(() => allowSalesRepDiscount = value);

  Future<void> save() async {
    if (isSaving || !(formKey.currentState?.validate() ?? false)) return;
    isSaving = true;
    update();
    try {
      final next = _buildSettings();
      await _repository.updateAppSettings(next);
      settings = next;
      _show('settings_save_success', AppColor.success);
    } catch (error) {
      final key =
          error is SettingsRepositoryException &&
              error.error == SettingsRepositoryError.permissionDenied
          ? 'settings_permission_denied'
          : 'settings_save_failed';
      _show(key, AppColor.error);
    } finally {
      isSaving = false;
      if (!isClosed) update();
    }
  }

  AppSettingsModel _buildSettings() {
    final company = CompanySettingsModel(
      name: companyNameController.text.trim(),
      country: countryController.text.trim(),
      email: emailController.text.trim(),
      website: websiteController.text.trim(),
      phone: phoneController.text.trim(),
      address: addressController.text.trim(),
      logoEnabled: logoEnabled,
    );
    final documents = DocumentSettingsModel(
      invoicePrefix: invoicePrefixController.text.trim(),
      receiptPrefix: receiptPrefixController.text.trim(),
      quotationPrefix: quotationPrefixController.text.trim(),
      salesReturnPrefix: salesReturnPrefixController.text.trim(),
      defaultDueDays: int.tryParse(defaultDueDaysController.text.trim()) ?? 0,
      defaultTaxPercent:
          double.tryParse(defaultTaxPercentController.text.trim()) ?? 0,
      allowDiscount: allowDiscount,
      allowSalesRepPriceEdit: allowSalesRepPriceEdit,
    );
    final inventory = InventorySettingsModel(
      defaultWarehouseId: defaultWarehouseController.text.trim(),
      allowNegativeStock: allowNegativeStock,
      lowStockAlertsEnabled: lowStockAlertsEnabled,
      defaultMinStock:
          double.tryParse(defaultMinStockController.text.trim()) ?? 0,
      trackStockByDefault: trackStockByDefault,
    );
    final pdf = PdfSettingsModel(
      showLogo: showLogo,
      showCompanyInfo: showCompanyInfo,
      pdfLanguageMode: pdfLanguageMode,
      invoiceFooterText: invoiceFooterController.text.trim(),
      quotationTerms: quotationTermsController.text.trim(),
      receiptFooterText: receiptFooterController.text.trim(),
      statementFooterText: statementFooterController.text.trim(),
      defaultNotes: defaultNotesController.text.trim(),
    );
    final permissions = PermissionSettingsModel(
      allowSalesRepCreateCustomers: allowSalesRepCreateCustomers,
      allowSalesRepCreateReceipts: allowSalesRepCreateReceipts,
      allowSalesRepCreateReturns: allowSalesRepCreateReturns,
      allowSalesRepCreateQuotations: allowSalesRepCreateQuotations,
      allowSalesRepPriceEdit: allowSalesRepPermissionPriceEdit,
      allowSalesRepDiscount: allowSalesRepDiscount,
    );
    return settings.copyWith(
      companySettings: company,
      documentSettings: documents,
      inventorySettings: inventory,
      pdfSettings: pdf,
      permissionSettings: permissions,
      updatedAt: DateTime.now(),
    );
  }

  void _set(VoidCallback change) {
    change();
    update();
  }

  void _show(String key, Color color) {
    Get.snackbar(
      'settings'.tr,
      key.tr,
      snackPosition: SnackPosition.BOTTOM,
      backgroundColor: color,
      colorText: AppColor.surface,
    );
  }

  String _number(double value) => value == value.roundToDouble()
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(3);

  @override
  void onClose() {
    for (final controller in [
      companyNameController,
      countryController,
      emailController,
      websiteController,
      phoneController,
      addressController,
      invoicePrefixController,
      receiptPrefixController,
      quotationPrefixController,
      salesReturnPrefixController,
      defaultDueDaysController,
      defaultTaxPercentController,
      defaultWarehouseController,
      defaultMinStockController,
      invoiceFooterController,
      quotationTermsController,
      receiptFooterController,
      statementFooterController,
      defaultNotesController,
    ]) {
      controller.dispose();
    }
    super.onClose();
  }
}
