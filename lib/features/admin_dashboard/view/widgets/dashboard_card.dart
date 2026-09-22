import 'package:fatoora/core/constants/color.dart';
import 'package:fatoora/features/shared/dashboard/dashboard_primitives.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class DashboardCard extends StatelessWidget {
  const DashboardCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.onTap,
    this.semanticLabel,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    return FatooraDashboardSurface(
      padding: padding,
      onTap: onTap,
      semanticLabel: semanticLabel,
      child: child,
    );
  }
}

class DashboardSectionTitle extends StatelessWidget {
  const DashboardSectionTitle({
    super.key,
    required this.titleKey,
    this.subtitleKey,
    this.trailing,
  });

  final String titleKey;
  final String? subtitleKey;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return FatooraDashboardSectionTitle(
      title: titleKey.tr,
      subtitle: subtitleKey?.tr,
      trailing: trailing,
    );
  }
}

class DashboardEmptyState extends StatelessWidget {
  const DashboardEmptyState({
    super.key,
    required this.icon,
    required this.messageKey,
  });

  final IconData icon;
  final String messageKey;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 34),
      child: Column(
        children: [
          Icon(icon, size: 42, color: context.appMutedText),
          const SizedBox(height: 10),
          Text(
            messageKey.tr,
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: context.appMutedText),
          ),
        ],
      ),
    );
  }
}
