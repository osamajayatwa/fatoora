import 'package:fatoora/core/class/statusrequest.dart';
import 'package:fatoora/core/constants/color.dart';
import 'package:fatoora/core/services/services.dart';
import 'package:fatoora/features/sales_returns/controllers/sales_return_context.dart';
import 'package:fatoora/features/sales_returns/controllers/sales_return_error_mapper.dart';
import 'package:fatoora/features/sales_returns/data/models/sales_return_model.dart';
import 'package:fatoora/features/sales_returns/data/repositories/sales_return_repository.dart';
import 'package:fatoora/features/sales_returns/data/services/sales_return_pdf_service.dart';
import 'package:get/get.dart';
import 'package:printing/printing.dart';

class SalesReturnDetailsController extends GetxController {
  SalesReturnDetailsController({
    required SalesReturnRepository repository,
    required MyServices myServices,
  }) : _repository = repository,
       _myServices = myServices;

  final SalesReturnRepository _repository;
  final MyServices _myServices;

  StatusRequest statusRequest = StatusRequest.loading;
  String loadErrorMessageKey = 'sales_return_load_error';
  String companyId = '';
  String returnId = '';
  SalesReturnModel? salesReturn;
  bool isConfirming = false;
  bool isPrinting = false;

  bool get canConfirm => salesReturn?.isDraft == true && !isConfirming;

  @override
  void onReady() {
    super.onReady();
    loadSalesReturn();
  }

  Future<void> loadSalesReturn() async {
    final args = SalesReturnContext.arguments(Get.arguments);
    companyId = SalesReturnContext.resolveCompanyId(_myServices, args);
    returnId = SalesReturnContext.readString(args, 'returnId');
    if (returnId.isEmpty) {
      statusRequest = StatusRequest.failure;
      loadErrorMessageKey = 'sales_return_not_found';
      update();
      return;
    }
    statusRequest = StatusRequest.loading;
    loadErrorMessageKey = 'sales_return_load_error';
    update();
    try {
      salesReturn = await _repository.getSalesReturnById(
        companyId: companyId,
        returnId: returnId,
      );
      if (salesReturn == null) {
        statusRequest = StatusRequest.failure;
        loadErrorMessageKey = 'sales_return_not_found';
      } else {
        statusRequest = StatusRequest.success;
      }
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

  Future<void> confirmReturn() async {
    final current = salesReturn;
    if (current == null || !current.isDraft || isConfirming) return;
    isConfirming = true;
    update();
    try {
      await _repository.confirmSalesReturn(salesReturn: current);
      _showSuccess('return_confirmed_successfully');
      await loadSalesReturn();
      Get.back(result: true);
    } catch (error) {
      final failure = SalesReturnErrorMapper.quantityFailure(error);
      if (failure != null) {
        _showErrorText(
          'cannot_return_more_than_sold_detail'.trParams({
            'item': failure.itemName,
            'requested': _formatQuantity(failure.requestedQuantity),
            'available': _formatQuantity(failure.availableQuantity),
          }),
        );
      } else {
        _showError(SalesReturnErrorMapper.messageKey(error));
      }
    } finally {
      isConfirming = false;
      if (!isClosed) update();
    }
  }

  Future<void> printSalesReturn() async {
    final current = salesReturn;
    if (current == null || isPrinting) return;
    isPrinting = true;
    update();
    try {
      await Printing.layoutPdf(
        name: '${current.returnNumber}.pdf',
        onLayout: (_) => SalesReturnPdfService.build(current),
      );
    } catch (_) {
      _showError('sales_return_pdf_error');
    } finally {
      isPrinting = false;
      if (!isClosed) update();
    }
  }

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

  String _formatQuantity(double value) => value == value.roundToDouble()
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(3);
}
