import 'package:fatoora/core/constants/color.dart';
import 'package:fatoora/core/motion/fatoora_motion.dart';
import 'package:flutter/material.dart';

class FatooraDashboardSurface extends StatefulWidget {
  const FatooraDashboardSurface({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.tint,
    this.borderColor,
    this.onTap,
    this.semanticLabel,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? tint;
  final Color? borderColor;
  final VoidCallback? onTap;
  final String? semanticLabel;

  @override
  State<FatooraDashboardSurface> createState() =>
      _FatooraDashboardSurfaceState();
}

class _FatooraDashboardSurfaceState extends State<FatooraDashboardSurface> {
  bool _highlighted = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final interactive = widget.onTap != null;
    final decoration = BoxDecoration(
      color: widget.tint ?? scheme.surface,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(
        color: _highlighted && interactive
            ? (widget.borderColor ?? scheme.primary)
            : (widget.borderColor ?? context.appBorder),
      ),
      boxShadow: [
        BoxShadow(
          color: scheme.shadow.withValues(alpha: .045),
          blurRadius: 16,
          offset: const Offset(0, 5),
        ),
      ],
    );
    final content = Padding(padding: widget.padding, child: widget.child);
    if (!interactive) {
      return DecoratedBox(decoration: decoration, child: content);
    }
    return Semantics(
      button: true,
      label: widget.semanticLabel,
      child: MouseRegion(
        onEnter: (_) => setState(() => _highlighted = true),
        onExit: (_) => setState(() => _highlighted = false),
        child: FocusableActionDetector(
          onShowFocusHighlight: (value) => setState(() => _highlighted = value),
          child: AnimatedContainer(
            duration: FatooraMotion.resolve(context, FatooraMotion.quick),
            curve: FatooraMotion.enterCurve,
            transform: Matrix4.translationValues(0, _highlighted ? -2 : 0, 0),
            decoration: decoration,
            child: Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(18),
              clipBehavior: Clip.antiAlias,
              child: InkWell(onTap: widget.onTap, child: content),
            ),
          ),
        ),
      ),
    );
  }
}

class FatooraDashboardSectionTitle extends StatelessWidget {
  const FatooraDashboardSectionTitle({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsetsDirectional.only(start: 2, bottom: 10),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 4,
          height: 20,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primary,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: context.appText,
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 3),
                Text(
                  subtitle!,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: context.appMutedText),
                ),
              ],
            ],
          ),
        ),
        if (trailing != null) ...[const SizedBox(width: 8), trailing!],
      ],
    ),
  );
}

class FatooraDashboardIconBox extends StatelessWidget {
  const FatooraDashboardIconBox({
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
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: color.withValues(alpha: .11),
      borderRadius: BorderRadius.circular(13),
    ),
    child: Icon(icon, size: size * .5, color: color),
  );
}
