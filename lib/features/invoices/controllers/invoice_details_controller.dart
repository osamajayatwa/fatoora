import 'package:fatoora/core/class/statusrequest.dart';
import 'package:fatoora/core/constant/app_feature_flags.dart';
import 'package:fatoora/core/constant/color.dart';
import 'package:fatoora/core/constant/routes.dart';
import 'package:fatoora/core/services/services.dart';
import 'package:fatoora/features/invoices/controllers/invoice_context.dart';
import 'package:fatoora/features/invoices/controllers/invoice_error_mapper.dart';
import 'package:fatoora/features/invoices/controllers/invoice_page_navigation.dart';
import 'package:fatoora/features/invoices/data/models/invoice_enums.dart';
import 'package:fatoora/features/invoices/data/models/invoice_model.dart';
import 'package:fatoora/features/invoices/data/repositories/invoice_repository.dart';
import 'package:get/get.dart';

class InvoiceDetailsController extends GetxController
    with InvoicePageNavigation {
  InvoiceDetailsController({
    required InvoiceRepository repository,
    required MyServices myServices,
  }) : _repository = repository,
       _myServices = myServices;

  final InvoiceRepository _repository;
  final MyServices _myServices;

  StatusRequest statusRequest = StatusRequest.loading;
  String loadErrorMessageKey = 'invoice_load_error';
  String companyId = '';
  String invoiceId = '';
  InvoiceModel? invoice;
  bool isSubmitting = false;

  bool get canEdit => invoice?.canEdit ?? false;
  bool get canSubmit =>
      AppFeatureFlags.jofotaraEnabled &&
      invoice?.invoiceType == InvoiceType.electronic &&
      (invoice?.invoiceStatus == InvoiceStatus.draft ||
          invoice?.invoiceStatus == InvoiceStatus.rejected);

  @override
  void onReady() {
    super.onReady();
    loadInvoice();
  }

  Future<void> loadInvoice() async {
    final args = InvoiceContext.arguments(Get.arguments);
    companyId = InvoiceContext.resolveCompanyId(_myServices, args);
    invoiceId = InvoiceContext.readString(args, 'invoiceId');
    if (companyId.isEmpty || invoiceId.isEmpty) {
      statusRequest = StatusRequest.failure;
      loadErrorMessageKey = 'invoice_not_found';
      update();
      return;
    }

    statusRequest = StatusRequest.loading;
    loadErrorMessageKey = 'invoice_load_error';
    update();
    try {
      invoice = await _repository.getInvoiceById(
        companyId: companyId,
        invoiceId: invoiceId,
      );
      if (invoice == null) {
        statusRequest = StatusRequest.failure;
        loadErrorMessageKey = 'invoice_not_found';
      } else {
        statusRequest = StatusRequest.success;
      }
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

  Future<void> editInvoice() async {
    final current = invoice;
    if (current == null) return;
    if (!current.canEdit) {
      _showError('accepted_invoice_cannot_be_edited');
      return;
    }
    final changed = await Get.toNamed(
      AppRoute.invoiceForm,
      arguments: {
        'mode': 'edit',
        'companyId': current.companyId,
        'invoiceId': current.id,
      },
    );
    if (changed == true) await loadInvoice();
  }

  Future<void> submitElectronicInvoicePlaceholder() async {
    final current = invoice;
    if (current == null || !canSubmit || isSubmitting) return;
    isSubmitting = true;
    update();
    try {
      await _repository.submitElectronicInvoicePlaceholder(
        companyId: current.companyId,
        invoiceId: current.id,
      );
      _showSuccess('submission_success');
      await loadInvoice();
    } catch (error) {
      _showError(
        InvoiceErrorMapper.messageKey(error, fallback: 'submission_failed'),
      );
    } finally {
      isSubmitting = false;
      if (!isClosed) update();
    }
  }

  void printOrExportPlaceholder() {
    _showInfo('invoice_details'.tr, 'print_export_placeholder'.tr);
  }

  Future<void> requestBack() {
    return leaveInvoicePage(fallbackRoute: AppRoute.invoices, result: true);
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
}
