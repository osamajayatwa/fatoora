import 'package:fatoora/features/admin/audit_log/controllers/audit_log_controller.dart';
import 'package:fatoora/features/admin/audit_log/data/repositories/audit_log_repository.dart';
import 'package:get/get.dart';

class AuditLogBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<AuditLogRepository>(AuditLogRepository.new);
    Get.lazyPut<AuditLogController>(
      () => AuditLogController(repository: Get.find<AuditLogRepository>()),
    );
  }
}
