import 'package:fatoora/core/class/statusrequest.dart';
import 'package:fatoora/core/services/services.dart';
import 'package:fatoora/features/auth/data/repositories/auth_repository.dart';
import 'package:fatoora/features/receipts/controllers/receipt_error_mapper.dart';
import 'package:fatoora/features/receipts/data/models/receipt_model.dart';
import 'package:fatoora/features/receipts/data/repositories/receipt_repository.dart';
import 'package:get/get.dart';

class ReceiptDetailsController extends GetxController {
  ReceiptDetailsController({
    required ReceiptRepository repository,
    required MyServices myServices,
  }) : _repository = repository,
       _myServices = myServices;

  final ReceiptRepository _repository;
  final MyServices _myServices;

  StatusRequest statusRequest = StatusRequest.loading;
  String loadErrorMessageKey = 'receipts_load_error';
  ReceiptModel? receipt;

  String get companyId {
    final args = Get.arguments;
    if (args is Map && args['companyId'] is String) {
      return (args['companyId'] as String).trim();
    }
    return _myServices.sharedPreferences.getString('companyId') ??
        AuthRepository.defaultCompanyId;
  }

  String get receiptId {
    final args = Get.arguments;
    if (args is Map && args['receiptId'] is String) {
      return (args['receiptId'] as String).trim();
    }
    return '';
  }

  @override
  void onReady() {
    super.onReady();
    loadReceipt();
  }

  Future<void> loadReceipt() async {
    if (receiptId.isEmpty) {
      statusRequest = StatusRequest.failure;
      loadErrorMessageKey = 'receipts_not_found';
      update();
      return;
    }
    statusRequest = StatusRequest.loading;
    update();
    try {
      receipt = await _repository.getReceiptById(
        companyId: companyId,
        receiptId: receiptId,
      );
      if (receipt == null) {
        statusRequest = StatusRequest.failure;
        loadErrorMessageKey = 'receipts_not_found';
      } else {
        statusRequest = StatusRequest.success;
      }
    } catch (error) {
      statusRequest = ReceiptErrorMapper.status(error);
      loadErrorMessageKey = ReceiptErrorMapper.messageKey(
        error,
        fallback: 'receipts_load_error',
      );
    }
    if (!isClosed) update();
  }
}
