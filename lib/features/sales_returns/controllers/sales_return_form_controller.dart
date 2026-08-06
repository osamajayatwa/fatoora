import 'dart:math' as math;

import 'package:fatoora/app/routes/app_routes.dart';
import 'package:fatoora/core/class/statusrequest.dart';
import 'package:fatoora/core/constants/color.dart';
import 'package:fatoora/core/services/services.dart';
import 'package:fatoora/core/settings/business_permission_resolver.dart';
import 'package:fatoora/features/invoices/data/models/invoice_enums.dart';
import 'package:fatoora/features/invoices/data/models/invoice_item_snapshot.dart';
import 'package:fatoora/features/invoices/data/models/invoice_model.dart';
import 'package:fatoora/features/invoices/data/repositories/invoice_repository.dart';
import 'package:fatoora/features/sales_returns/controllers/sales_return_context.dart';
import 'package:fatoora/features/sales_returns/controllers/sales_return_error_mapper.dart';
import 'package:fatoora/features/sales_returns/data/models/sales_return_enums.dart';
import 'package:fatoora/features/sales_returns/data/models/sales_return_item_model.dart';
import 'package:fatoora/features/sales_returns/data/models/sales_return_model.dart';
import 'package:fatoora/features/sales_returns/data/repositories/sales_return_repository.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class SalesReturnFormController extends GetxController {
  SalesReturnFormController({
    required SalesReturnRepository repository,
    required InvoiceRepository invoiceRepository,
    required MyServices myServices,
    required BusinessPermissionResolver permissionResolver,
  }) : _repository = repository,
       _invoiceRepository = invoiceRepository,
       _myServices = myServices,
       _permissionResolver = permissionResolver;

  final SalesReturnRepository _repository;
  final InvoiceRepository _invoiceRepository;
  final MyServices _myServices;
  final BusinessPermissionResolver _permissionResolver;
  final reasonController = TextEditingController();
  final Map<String, TextEditingController> quantityControllers = {};
  final Map<String, String> quantityErrors = {};

  StatusRequest statusRequest = StatusRequest.loading;
  String loadErrorMessageKey = 'sales_return_load_error';
  String companyId = '';
  String originalInvoiceId = '';
  InvoiceModel? originalInvoice;
  List<SalesReturnItemModel> items = const [];
  Map<String, double> availableByLineId = const {};
  RefundType refundType = RefundType.creditCustomerBalance;
  DateTime returnDate = DateTime.now();
  bool isSaving = false;
  EffectiveBusinessPermissions permissions =
      EffectiveBusinessPermissions.denied;

  double get subtotal =>
      _round(items.fold<double>(0, (total, item) => total + item.subtotal));
  double get totalDiscount => _round(
    items.fold<double>(0, (total, item) => total + item.discountAmount),
  );
  double get totalTax =>
      _round(items.fold<double>(0, (total, item) => total + item.taxAmount));
  double get grandTotal => _round(subtotal + totalTax);
  bool get hasSelectedItems => items.any((item) => item.returnedQuantity > 0);

  @override
  void onReady() {
    super.onReady();
    initialize();
  }

  Future<void> initialize() async {
    final args = SalesReturnContext.arguments(Get.arguments);
    companyId = SalesReturnContext.resolveCompanyId(_myServices, args);
    originalInvoiceId = SalesReturnContext.readString(
      args,
      'originalInvoiceId',
    );
    permissions = await _permissionResolver.resolve(companyId);
    if (!permissions.createReturns) {
      statusRequest = StatusRequest.unauthorized;
      loadErrorMessageKey = 'sales_rep_return_create_disabled';
      _showError(loadErrorMessageKey);
      update();
      return;
    }
    if (originalInvoiceId.isEmpty) {
      statusRequest = StatusRequest.failure;
      loadErrorMessageKey = 'select_invoice_to_return';
      update();
      return;
    }
    statusRequest = StatusRequest.loading;
    loadErrorMessageKey = 'sales_return_load_error';
    update();
    try {
      final invoice = await _invoiceRepository.getInvoiceById(
        companyId: companyId,
        invoiceId: originalInvoiceId,
      );
      if (invoice == null) {
        statusRequest = StatusRequest.failure;
        loadErrorMessageKey = 'sales_return_original_invoice_not_found';
        update();
        return;
      }
      if (invoice.invoiceStatus != InvoiceStatus.confirmed) {
        statusRequest = StatusRequest.failure;
        loadErrorMessageKey = 'sales_return_invoice_not_eligible';
        update();
        return;
      }
      originalInvoice = invoice;
      final returned = await _repository.getConfirmedReturnedQuantities(
        companyId: companyId,
        originalInvoiceId: invoice.id,
      );
      availableByLineId = {
        for (var index = 0; index < invoice.items.length; index++)
          originalInvoiceItemId(invoice.id, index): _round(
            math
                .max(
                  invoice.items[index].quantity -
                      (returned[originalInvoiceItemId(invoice.id, index)] ?? 0),
                  0,
                )
                .toDouble(),
          ),
      };
      items = [
        for (var index = 0; index < invoice.items.length; index++)
          _emptyReturnItem(
            invoice.items[index],
            originalInvoiceItemId(invoice.id, index),
          ),
      ];
      for (final item in items) {
        quantityControllers[item.originalInvoiceItemId] = TextEditingController(
          text: '0',
        );
      }
      statusRequest = StatusRequest.success;
    } catch (error) {
      statusRequest = SalesReturnErrorMapper.status(error);
      loadErrorMessageKey = SalesReturnErrorMapper.messageKey(
        error,
        fallback: 'sales_return_load_error',
      );
      _showError(loadErrorMessageKey);
    }
    if (!isClosed) update();
  }

  void setRefundType(RefundType value) {
    refundType = value;
    update();
  }

  void setReturnDate(DateTime value) {
    returnDate = value;
    update();
  }

  void updateReturnedQuantity(String lineId, String value) {
    final index = items.indexWhere(
      (item) => item.originalInvoiceItemId == lineId,
    );
    if (index < 0) return;
    final quantity = _round(double.tryParse(value.trim()) ?? 0);
    final available = availableByLineId[lineId] ?? 0;
    if (quantity < 0) {
      quantityErrors[lineId] = 'returned_quantity_must_be_positive';
    } else if (quantity > available) {
      quantityErrors[lineId] = 'cannot_return_more_than_sold';
    } else {
      quantityErrors.remove(lineId);
    }
    final current = items[index];
    final subtotal = _round(math.max(quantity, 0) * current.unitPrice);
    final next = [...items];
    next[index] = current.copyWith(
      returnedQuantity: quantity,
      discountAmount: _round(math.max(quantity, 0) * current.discountPerUnit),
      subtotal: subtotal,
      taxAmount: _round(subtotal * current.taxPercent / 100),
      total: _round(subtotal + (subtotal * current.taxPercent / 100)),
    );
    items = next;
    update();
  }

  Future<void> saveDraft() => _save(confirm: false);

  Future<void> confirmReturn() => _save(confirm: true);

  Future<void> _save({required bool confirm}) async {
    if (!permissions.createReturns) {
      _showError('sales_rep_return_create_disabled');
      return;
    }
    if (isSaving || !hasSelectedItems) {
      _showError('return_items_required');
      return;
    }
    if (reasonController.text.trim().isEmpty) {
      _showError('return_reason_required');
      return;
    }
    if (quantityErrors.isNotEmpty) {
      _showError('cannot_return_more_than_sold');
      return;
    }
    final invoice = originalInvoice;
    if (invoice == null) return;
    isSaving = true;
    update();
    try {
      final draft = _buildReturn(invoice);
      final saved = confirm
          ? await _repository.confirmSalesReturn(salesReturn: draft)
          : await _repository.saveDraft(salesReturn: draft);
      _showSuccess(
        confirm ? 'return_confirmed_successfully' : 'return_draft_saved',
      );
      if (confirm) {
        await Get.offNamed(
          AppRoute.salesReturnDetailsPath(saved.id),
          arguments: {'companyId': saved.companyId, 'returnId': saved.id},
        );
      } else {
        Get.back(result: true);
      }
    } catch (error) {
      final quantityFailure = SalesReturnErrorMapper.quantityFailure(error);
      if (quantityFailure != null) {
        _showErrorText(
          'cannot_return_more_than_sold_detail'.trParams({
            'item': quantityFailure.itemName,
            'requested': _formatQuantity(quantityFailure.requestedQuantity),
            'available': _formatQuantity(quantityFailure.availableQuantity),
          }),
        );
      } else {
        _showError(SalesReturnErrorMapper.messageKey(error));
      }
    } finally {
      isSaving = false;
      if (!isClosed) update();
    }
  }

  SalesReturnModel _buildReturn(InvoiceModel invoice) {
    final now = DateTime.now();
    return SalesReturnModel(
      id: '',
      companyId: companyId,
      returnNumber: '',
      originalInvoiceId: invoice.id,
      originalInvoiceNumber: invoice.invoiceNumber,
      originalInvoiceDate: invoice.invoiceDate,
      customerId: invoice.customerId,
      customerSnapshot: invoice.customerSnapshot,
      items: items.where((item) => item.returnedQuantity > 0).toList(),
      subtotal: subtotal,
      totalDiscount: totalDiscount,
      totalTax: totalTax,
      grandTotal: grandTotal,
      refundType: refundType,
      returnDate: returnDate,
      reason: reasonController.text.trim(),
      status: SalesReturnStatus.draft,
      salesRepId: invoice.salesRepId,
      salesRepName: invoice.salesRepName,
      createdByUid: '',
      createdByName: '',
      createdByRole: '',
      financialPosted: false,
      inventoryPosted: false,
      stockMovementIds: const [],
      customerTransactionIds: const [],
      cashMovementIds: const [],
      createdAt: now,
      updatedAt: now,
    );
  }

  SalesReturnItemModel _emptyReturnItem(
    InvoiceItemSnapshot invoiceItem,
    String lineId,
  ) {
    final unitPrice = invoiceItem.quantity <= 0
        ? 0.0
        : _round(
            math.max(invoiceItem.subtotal - invoiceItem.discount, 0) /
                invoiceItem.quantity,
          );
    return SalesReturnItemModel(
      itemId: invoiceItem.itemId,
      itemName: invoiceItem.itemName,
      itemCode: invoiceItem.itemCode,
      unit: invoiceItem.unit,
      returnedQuantity: 0,
      unitPrice: unitPrice,
      discountPerUnit: invoiceItem.quantity <= 0
          ? 0
          : _round(invoiceItem.discount / invoiceItem.quantity),
      discountAmount: 0,
      taxPercent: invoiceItem.taxPercent,
      subtotal: 0,
      taxAmount: 0,
      total: 0,
      originalInvoiceItemId: lineId,
    );
  }

  double availableFor(SalesReturnItemModel item) =>
      availableByLineId[item.originalInvoiceItemId] ?? 0;

  void _showSuccess(String messageKey) {
    Get.snackbar(
      'sales_returns'.tr,
      messageKey.tr,
      snackPosition: SnackPosition.BOTTOM,
      backgroundColor: AppColor.success,
      colorText: AppColor.surface,
    );
  }

  void _showError(String messageKey) => _showErrorText(messageKey.tr);

  void _showErrorText(String message) {
    Get.snackbar(
      'sales_returns'.tr,
      message,
      snackPosition: SnackPosition.BOTTOM,
      backgroundColor: AppColor.error,
      colorText: AppColor.surface,
    );
  }

  double _round(double value) {
    if (!value.isFinite) return 0;
    return (value * 1000).roundToDouble() / 1000;
  }

  String _formatQuantity(double value) {
    final rounded = _round(value);
    return rounded == rounded.roundToDouble()
        ? rounded.toStringAsFixed(0)
        : rounded.toStringAsFixed(3);
  }

  @override
  void onClose() {
    reasonController.dispose();
    for (final controller in quantityControllers.values) {
      controller.dispose();
    }
    super.onClose();
  }
}
