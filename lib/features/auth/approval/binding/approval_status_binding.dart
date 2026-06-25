import 'package:fatoora/core/services/services.dart';
import 'package:fatoora/features/auth/approval/controller/approval_status_controller.dart';
import 'package:get/get.dart';

class ApprovalStatusBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<ApprovalStatusController>(
      () => ApprovalStatusController(myServices: Get.find<MyServices>()),
    );
  }
}
