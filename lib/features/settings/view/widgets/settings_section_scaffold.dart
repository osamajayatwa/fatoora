import 'package:fatoora/app/routes/app_routes.dart';
import 'package:fatoora/core/class/handilingdataview.dart';
import 'package:fatoora/core/constants/color.dart';
import 'package:fatoora/features/settings/controllers/settings_controller.dart';
import 'package:fatoora/features/shared/business/business_shell.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class SettingsSectionScaffold extends StatelessWidget {
  const SettingsSectionScaffold({
    super.key,
    required this.titleKey,
    required this.subtitleKey,
    required this.icon,
    required this.child,
    this.adminOnly = false,
  });

  final String titleKey;
  final String subtitleKey;
  final IconData icon;
  final Widget child;
  final bool adminOnly;

  @override
  Widget build(BuildContext context) {
    return BusinessShell(
      title: titleKey.tr,
      showBackButton: true,
      onBack: _goBack,
      child: GetBuilder<SettingsController>(
        builder: (controller) {
          if (adminOnly && !controller.isAdmin) {
            return _AccessDenied(onBack: _goBack);
          }
          return HandilingDataView(
            statusrequest: controller.statusRequest,
            errorMessage: controller.loadErrorMessageKey.tr,
            retryLabel: 'settings_retry'.tr,
            onRetry: controller.loadSettings,
            widget: _SectionContent(
              title: titleKey.tr,
              subtitle: subtitleKey.tr,
              icon: icon,
              showPageHeader: controller.isAdmin,
              onBack: _goBack,
              child: child,
            ),
          );
        },
      ),
    );
  }

  void _goBack() {
    if (Get.key.currentState?.canPop() ?? false) {
      Get.back<void>();
      return;
    }
    Get.offNamed<void>(AppRoute.settings);
  }
}

class _SectionContent extends StatelessWidget {
  const _SectionContent({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.showPageHeader,
    required this.onBack,
    required this.child,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final bool showPageHeader;
  final VoidCallback onBack;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 600;
    return SingleChildScrollView(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 14 : 24,
        vertical: compact ? 16 : 24,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 820),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (showPageHeader) ...[
                _PageHeader(
                  title: title,
                  subtitle: subtitle,
                  icon: icon,
                  onBack: onBack,
                ),
                const SizedBox(height: 18),
              ],
              Card(
                margin: EdgeInsets.zero,
                elevation: 0,
                color: context.appSurface,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                  side: BorderSide(color: context.appBorder),
                ),
                child: Padding(
                  padding: EdgeInsets.all(compact ? 16 : 24),
                  child: child,
                ),
              ),
              const SizedBox(height: 28),
            ],
          ),
        ),
      ),
    );
  }
}

class _PageHeader extends StatelessWidget {
  const _PageHeader({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onBack,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        IconButton.filledTonal(
          tooltip: 'settings_back_to_settings'.tr,
          onPressed: onBack,
          icon: Icon(
            Directionality.of(context) == TextDirection.rtl
                ? Icons.arrow_forward_rounded
                : Icons.arrow_back_rounded,
          ),
        ),
        const SizedBox(width: 12),
        Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: Theme.of(
              context,
            ).colorScheme.primary.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(13),
          ),
          child: Icon(icon, color: AppColor.primaryColor),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: context.appText,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: context.appMutedText),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _AccessDenied extends StatelessWidget {
  const _AccessDenied({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.lock_outline_rounded,
              size: 54,
              color: AppColor.error,
            ),
            const SizedBox(height: 14),
            Text(
              'settings_permission_denied'.tr,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: onBack,
              icon: const Icon(Icons.settings_outlined),
              label: Text('settings_back_to_settings'.tr),
            ),
          ],
        ),
      ),
    );
  }
}
