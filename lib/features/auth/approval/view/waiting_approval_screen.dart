import 'package:fatoora/core/constants/color.dart';
import 'package:fatoora/features/auth/approval/controller/approval_status_controller.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class WaitingApprovalScreen extends GetView<ApprovalStatusController> {
  const WaitingApprovalScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ApprovalStatusScaffold(
      icon: Icons.hourglass_top_rounded,
      iconColor: AppColor.accentYellow,
      titleKey: 'waiting_admin_approval_title',
      bodyKey: 'waiting_admin_approval_body',
      controller: controller,
    );
  }
}

class ApprovalStatusScaffold extends StatelessWidget {
  const ApprovalStatusScaffold({
    super.key,
    required this.icon,
    required this.iconColor,
    required this.titleKey,
    required this.bodyKey,
    required this.controller,
  });

  final IconData icon;
  final Color iconColor;
  final String titleKey;
  final String bodyKey;
  final ApprovalStatusController controller;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColor.background,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Card(
                margin: EdgeInsets.zero,
                elevation: 0,
                color: AppColor.surface,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                  side: const BorderSide(color: Color(0xFFE4E8EF)),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: GetBuilder<ApprovalStatusController>(
                    builder: (controller) => Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 76,
                          height: 76,
                          decoration: BoxDecoration(
                            color: iconColor.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(24),
                          ),
                          child: Icon(icon, color: iconColor, size: 38),
                        ),
                        const SizedBox(height: 22),
                        Text(
                          titleKey.tr,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(
                                color: AppColor.secondaryColor,
                                fontWeight: FontWeight.w800,
                              ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          bodyKey.tr,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(color: AppColor.darkGrey),
                        ),
                        if (controller.email.isNotEmpty ||
                            controller.name.isNotEmpty) ...[
                          const SizedBox(height: 20),
                          _ProfileLine(
                            name: controller.name,
                            email: controller.email,
                          ),
                        ],
                        const SizedBox(height: 26),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: controller.isLoggingOut
                                ? null
                                : controller.logout,
                            style: FilledButton.styleFrom(
                              backgroundColor: AppColor.primaryColor,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                            icon: controller.isLoggingOut
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: AppColor.surface,
                                    ),
                                  )
                                : const Icon(Icons.logout_rounded),
                            label: Text('logout'.tr),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ProfileLine extends StatelessWidget {
  const _ProfileLine({required this.name, required this.email});

  final String name;
  final String email;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColor.background,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            const Icon(Icons.person_outline, color: AppColor.primaryColor),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (name.isNotEmpty)
                    Text(
                      name,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppColor.secondaryColor,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  if (email.isNotEmpty)
                    Text(
                      email,
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(color: AppColor.grey),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
