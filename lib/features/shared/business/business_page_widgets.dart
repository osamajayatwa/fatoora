import 'package:fatoora/core/constants/color.dart';
import 'package:fatoora/features/admin_dashboard/view/widgets/dashboard_card.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class BusinessPageHeader extends StatelessWidget {
  const BusinessPageHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
    this.contained = false,
    this.stretchTrailingOnCompact = true,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;
  final bool contained;
  final bool stretchTrailingOnCompact;

  @override
  Widget build(BuildContext context) {
    final content = LayoutBuilder(
      builder: (context, constraints) {
        final compact =
            constraints.maxWidth < 650 ||
            MediaQuery.textScalerOf(context).scale(1) > 1.3;
        final heading = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: context.appText,
                fontWeight: FontWeight.w900,
              ),
            ),
            if (subtitle != null && subtitle!.trim().isNotEmpty) ...[
              const SizedBox(height: 5),
              Text(
                subtitle!,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: context.appMutedText),
              ),
            ],
          ],
        );
        if (compact) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              heading,
              if (trailing != null) ...[
                const SizedBox(height: 14),
                if (stretchTrailingOnCompact)
                  SizedBox(width: double.infinity, child: trailing)
                else
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: trailing,
                  ),
              ],
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(child: heading),
            if (trailing != null) ...[const SizedBox(width: 18), trailing!],
          ],
        );
      },
    );
    return contained ? DashboardCard(child: content) : content;
  }
}

class BusinessPrimaryActionButton extends StatelessWidget {
  const BusinessPrimaryActionButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
    this.loading = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: loading ? null : onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: AppColor.primaryColor,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      icon: loading
          ? const SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          : Icon(icon),
      label: Text(label),
    );
  }
}

class BusinessSecondaryActionButton extends StatelessWidget {
  const BusinessSecondaryActionButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
    this.loading = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: loading ? null : onPressed,
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      icon: loading
          ? const SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(icon),
      label: Text(label),
    );
  }
}

class BusinessLoadMoreButton extends StatelessWidget {
  const BusinessLoadMoreButton({
    super.key,
    required this.loading,
    required this.onPressed,
  });

  final bool loading;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: FilledButton.tonalIcon(
        onPressed: loading ? null : onPressed,
        icon: loading
            ? const SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.expand_more_rounded),
        label: Text(
          loading ? 'loading_more_records'.tr : 'load_more_records'.tr,
        ),
      ),
    );
  }
}

class BusinessEmptyState extends StatelessWidget {
  const BusinessEmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.action,
    this.contained = true,
  });

  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;
  final bool contained;

  @override
  Widget build(BuildContext context) {
    final content = Padding(
      padding: const EdgeInsets.symmetric(vertical: 38, horizontal: 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 44, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: context.appText,
              fontWeight: FontWeight.w800,
            ),
          ),
          if (message != null && message!.trim().isNotEmpty) ...[
            const SizedBox(height: 7),
            Text(
              message!,
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: context.appMutedText),
            ),
          ],
          if (action != null) ...[const SizedBox(height: 18), action!],
        ],
      ),
    );
    return contained ? DashboardCard(child: content) : content;
  }
}
