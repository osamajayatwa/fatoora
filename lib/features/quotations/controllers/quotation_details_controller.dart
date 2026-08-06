import 'package:fatoora/app/routes/app_routes.dart';
import 'package:fatoora/core/class/statusrequest.dart';
import 'package:fatoora/core/constants/color.dart';
import 'package:fatoora/core/services/services.dart';
import 'package:fatoora/features/auth/data/repositories/auth_repository.dart';
import 'package:fatoora/features/quotations/controllers/quotation_error_mapper.dart';
import 'package:fatoora/features/quotations/data/models/quotation_model.dart';
import 'package:fatoora/features/quotations/data/models/quotation_status.dart';
import 'package:fatoora/features/quotations/data/repositories/quotation_repository.dart';
import 'package:fatoora/features/quotations/data/services/quotation_pdf_service.dart';
import 'package:get/get.dart';
import 'package:printing/printing.dart';

class QuotationDetailsController extends GetxController {
  QuotationDetailsController({
    required QuotationRepository repository,
    required MyServices myServices,
  }) : _repository = repository,
       _myServices = myServices;

  final QuotationRepository _repository;
  final MyServices _myServices;

  StatusRequest statusRequest = StatusRequest.loading;
  String loadErrorMessageKey = 'quotation_load_error';
  String companyId = AuthRepository.defaultCompanyId;
  String quotationId = '';
  QuotationModel? quotation;
  bool isSavingStatus = false;
  bool isConverting = false;
  bool isPrinting = false;

  bool get canEdit => quotation?.canEdit == true && !isSavingStatus;
  bool get canConvert => quotation?.canConvert == true && !isConverting;

  @override
  void onReady() {
    super.onReady();
    loadQuotation();
  }

  Future<void> loadQuotation() async {
    final args = Get.arguments;
    if (args is Map) {
      companyId =
          (args['companyId'] as String?) ??
          _myServices.sharedPreferences.getString('companyId') ??
          AuthRepository.defaultCompanyId;
    }
    quotationId =
        (Get.parameters['quotationId'] ??
                (args is Map ? args['quotationId'] as String? : null) ??
                '')
            .trim();
    if (quotationId.isEmpty) {
      statusRequest = StatusRequest.failure;
      loadErrorMessageKey = 'quotation_not_found';
      update();
      return;
    }
    statusRequest = StatusRequest.loading;
    loadErrorMessageKey = 'quotation_load_error';
    update();
    try {
      quotation = await _repository.getQuotationById(
        companyId: companyId,
        quotationId: quotationId,
      );
      if (quotation == null) {
        statusRequest = StatusRequest.failure;
        loadErrorMessageKey = 'quotation_not_found';
      } else {
        statusRequest = StatusRequest.success;
      }
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

  Future<void> editQuotation() async {
    final current = quotation;
    if (current == null || !current.canEdit) return;
    final changed = await Get.toNamed(
      AppRoute.quotationEditPath(current.id),
      arguments: {
        'mode': 'edit',
        'companyId': current.companyId,
        'quotationId': current.id,
      },
    );
    if (changed == true) await loadQuotation();
  }

  Future<void> updateStatus(QuotationStatus status) async {
    final current = quotation;
    if (current == null || isSavingStatus) return;
    isSavingStatus = true;
    update();
    try {
      await _repository.updateStatus(
        companyId: current.companyId,
        quotationId: current.id,
        status: status,
      );
      _showSuccess('quotation_updated_successfully');
      await loadQuotation();
    } catch (error) {
      _showError(QuotationErrorMapper.messageKey(error));
    } finally {
      isSavingStatus = false;
      if (!isClosed) update();
    }
  }

  Future<void> convertToInvoice() async {
    final current = quotation;
    if (current == null || !current.canConvert || isConverting) return;
    isConverting = true;
    update();
    try {
      final result = await _repository.convertToInvoiceDraft(
        companyId: current.companyId,
        quotationId: current.id,
      );
      _showSuccess('quotation_converted_successfully');
      await loadQuotation();
      await Get.toNamed(
        AppRoute.invoiceDetailsPath(result.invoiceId),
        arguments: {
          'companyId': current.companyId,
          'invoiceId': result.invoiceId,
        },
      );
    } catch (error) {
      _showError(QuotationErrorMapper.messageKey(error));
    } finally {
      isConverting = false;
      if (!isClosed) update();
    }
  }

  Future<void> printQuotation() async {
    final current = quotation;
    if (current == null || isPrinting) return;
    isPrinting = true;
    update();
    try {
      await Printing.layoutPdf(
        name: '${current.quotationNumber}.pdf',
        onLayout: (_) => QuotationPdfService.build(current),
      );
    } catch (_) {
      _showError('quotation_pdf_error');
    } finally {
      isPrinting = false;
      if (!isClosed) update();
    }
  }

  Future<void> requestBack() async {
    Get.back(result: true);
  }

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
}
