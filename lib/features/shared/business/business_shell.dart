import 'package:fatoora/features/shared/navigation/adaptive_business_shell.dart';
import 'package:flutter/material.dart';

class BusinessShell extends StatelessWidget {
  const BusinessShell({
    super.key,
    required this.child,
    required this.title,
    this.showBackButton = false,
    this.onBack,
  });

  final Widget child;
  final String title;
  final bool showBackButton;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    return AdaptiveBusinessShell(
      title: title,
      showBackButton: showBackButton,
      onBack: onBack,
      child: child,
    );
  }
}
