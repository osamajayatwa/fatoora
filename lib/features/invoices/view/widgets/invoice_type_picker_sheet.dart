import 'package:fatoora/core/constant/app_feature_flags.dart';
import 'package:fatoora/core/constant/color.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class InvoiceTypePickerSheet extends StatelessWidget {
  const InvoiceTypePickerSheet({
    super.key,
    required this.onRegularSelected,
    required this.onElectronicSelected,
    required this.onElectronicDisabledTap,
  });

  final VoidCallback onRegularSelected;
  final VoidCallback? onElectronicSelected;
  final VoidCallback onElectronicDisabledTap;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Container(
          width: double.infinity,
          constraints: const BoxConstraints(maxWidth: 640),
          margin: const EdgeInsets.all(16),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppColor.surface,
            borderRadius: BorderRadius.circular(22),
            boxShadow: const [
              BoxShadow(
                color: Color(0x2618223B),
                blurRadius: 32,
                offset: Offset(0, 16),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'choose_invoice_type'.tr,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: AppColor.secondaryColor,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: Get.back,
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _TypeOption(
                icon: Icons.receipt_long_outlined,
                title: 'regular_invoice'.tr,
                subtitle: 'internal_invoice'.tr,
                enabled: true,
                onTap: onRegularSelected,
              ),
              const SizedBox(height: 12),
              _TypeOption(
                icon: Icons.lock_outline_rounded,
                title: 'electronic_invoice'.tr,
                subtitle: 'tax_integration_disabled'.tr,
                footnote: 'tax_integration_disabled_body'.tr,
                enabled: AppFeatureFlags.jofotaraEnabled,
                onTap: onElectronicSelected ?? onElectronicDisabledTap,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TypeOption extends StatelessWidget {
  const _TypeOption({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.enabled,
    required this.onTap,
    this.footnote,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String? footnote;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final foreground = enabled ? AppColor.secondaryColor : AppColor.grey;
    final border = enabled ? const Color(0xFFE1E5ED) : const Color(0xFFE5E5E5);
    return Material(
      color: enabled ? AppColor.surface : const Color(0xFFF3F4F6),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: border),
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: enabled
                      ? AppColor.primaryLight.withValues(alpha: 0.7)
                      : const Color(0xFFE7E8EC),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  icon,
                  color: enabled ? AppColor.primaryColor : AppColor.grey,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: foreground,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: enabled ? AppColor.darkGrey : AppColor.grey,
                      ),
                    ),
                    if (footnote != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        footnote!,
                        style: Theme.of(
                          context,
                        ).textTheme.labelSmall?.copyWith(color: AppColor.grey),
                      ),
                    ],
                  ],
                ),
              ),
              Icon(
                enabled
                    ? (Directionality.of(context) == TextDirection.rtl
                          ? Icons.chevron_left_rounded
                          : Icons.chevron_right_rounded)
                    : Icons.lock_rounded,
                color: enabled ? AppColor.primaryColor : AppColor.grey,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
