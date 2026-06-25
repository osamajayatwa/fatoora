import 'package:fatoora/core/constants/color.dart';
import 'package:fatoora/features/auth/approval/controller/approval_status_controller.dart';
import 'package:fatoora/features/auth/approval/view/waiting_approval_screen.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class RejectedApprovalScreen extends GetView<ApprovalStatusController> {
  const RejectedApprovalScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final inactive = controller.isInactiveApproved;
    return ApprovalStatusScaffold(
      icon: Icons.block_rounded,
      iconColor: AppColor.error,
      titleKey: inactive ? 'account_inactive' : 'approval_rejected_title',
      bodyKey: inactive ? 'account_inactive' : 'approval_rejected_body',
      controller: controller,
    );
  }
}
