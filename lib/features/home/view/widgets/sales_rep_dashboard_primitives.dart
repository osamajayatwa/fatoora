import 'package:fatoora/features/shared/dashboard/dashboard_primitives.dart';
import 'package:flutter/material.dart';

class SalesRepDashboardSurface extends StatelessWidget {
  const SalesRepDashboardSurface({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.tint,
    this.borderColor,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? tint;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    return FatooraDashboardSurface(
      padding: padding,
      tint: tint,
      borderColor: borderColor,
      child: child,
    );
  }
}

class SalesRepSectionTitle extends StatelessWidget {
  const SalesRepSectionTitle({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) =>
      FatooraDashboardSectionTitle(title: title);
}

class SalesRepIconBox extends StatelessWidget {
  const SalesRepIconBox({
    super.key,
    required this.icon,
    required this.color,
    this.size = 44,
  });

  final IconData icon;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) =>
      FatooraDashboardIconBox(icon: icon, color: color, size: size);
}

class SalesRepInteractiveCard extends StatelessWidget {
  const SalesRepInteractiveCard({
    super.key,
    required this.child,
    required this.onTap,
    this.tint,
    this.borderColor,
    this.padding = const EdgeInsets.all(14),
    this.semanticLabel,
  });

  final Widget child;
  final VoidCallback onTap;
  final Color? tint;
  final Color? borderColor;
  final EdgeInsetsGeometry padding;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    return FatooraDashboardSurface(
      onTap: onTap,
      semanticLabel: semanticLabel,
      tint: tint,
      borderColor: borderColor,
      padding: padding,
      child: child,
    );
  }
}
