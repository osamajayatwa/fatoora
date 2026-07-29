import 'package:fatoora/core/constants/color.dart';
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
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: tint ?? scheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: borderColor ?? context.appBorder),
        boxShadow: [
          BoxShadow(
            color: scheme.shadow.withValues(alpha: 0.035),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}

class SalesRepSectionTitle extends StatelessWidget {
  const SalesRepSectionTitle({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsetsDirectional.only(start: 2, bottom: 11),
    child: Row(
      children: [
        Container(
          width: 4,
          height: 20,
          decoration: BoxDecoration(
            color: AppColor.primaryColor,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: context.appText,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.15,
            ),
          ),
        ),
      ],
    ),
  );
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
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.11),
      borderRadius: BorderRadius.circular(13),
    ),
    alignment: Alignment.center,
    child: Icon(icon, size: size * 0.5, color: color),
  );
}

class SalesRepInteractiveCard extends StatefulWidget {
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
  State<SalesRepInteractiveCard> createState() =>
      _SalesRepInteractiveCardState();
}

class _SalesRepInteractiveCardState extends State<SalesRepInteractiveCard> {
  bool _hovered = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final highlighted = _hovered || _focused;
    return Semantics(
      button: true,
      label: widget.semanticLabel,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: FocusableActionDetector(
          onShowFocusHighlight: (value) => setState(() => _focused = value),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeOut,
            transform: Matrix4.translationValues(0, highlighted ? -2 : 0, 0),
            decoration: BoxDecoration(
              color: widget.tint ?? scheme.surface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: highlighted
                    ? (widget.borderColor ?? scheme.primary)
                    : (widget.borderColor ?? context.appBorder),
                width: widget.borderColor == null || highlighted ? 1 : 1.2,
              ),
              boxShadow: [
                BoxShadow(
                  color: scheme.shadow.withValues(
                    alpha: highlighted ? 0.075 : 0.025,
                  ),
                  blurRadius: highlighted ? 18 : 12,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(18),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: widget.onTap,
                borderRadius: BorderRadius.circular(18),
                child: Padding(padding: widget.padding, child: widget.child),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
