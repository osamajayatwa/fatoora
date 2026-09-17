import 'package:fatoora/core/motion/fatoora_motion.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

/// A one-shot, composited entrance for small or bounded UI surfaces.
///
/// Do not wrap rows in a large list or a full DataTable with this widget.
class FatooraMotionReveal extends StatelessWidget {
  const FatooraMotionReveal({
    super.key,
    required this.child,
    this.duration = FatooraMotion.standard,
    this.offset = FatooraMotion.shortDistance,
    this.scale = false,
  });

  final Widget child;
  final Duration duration;
  final double offset;
  final bool scale;

  @override
  Widget build(BuildContext context) {
    if (FatooraMotion.disabled(context)) return child;

    final effects = <Effect<dynamic>>[
      FadeEffect(duration: duration, curve: FatooraMotion.enterCurve),
      MoveEffect(
        begin: Offset(0, offset),
        end: Offset.zero,
        duration: duration,
        curve: FatooraMotion.enterCurve,
      ),
      if (scale)
        ScaleEffect(
          begin: const Offset(
            FatooraMotion.entranceScale,
            FatooraMotion.entranceScale,
          ),
          end: const Offset(1, 1),
          duration: duration,
          curve: FatooraMotion.enterCurve,
        ),
    ];

    return Animate(effects: effects, child: child);
  }
}

/// A consistent fade/short-slide transition for bounded state changes.
class FatooraMotionSwitcher extends StatelessWidget {
  const FatooraMotionSwitcher({
    super.key,
    required this.child,
    this.duration = FatooraMotion.standard,
    this.reverseDuration = FatooraMotion.quick,
    this.offset = FatooraMotion.shortDistance,
    this.layoutBuilder = AnimatedSwitcher.defaultLayoutBuilder,
  });

  final Widget child;
  final Duration duration;
  final Duration reverseDuration;
  final double offset;
  final AnimatedSwitcherLayoutBuilder layoutBuilder;

  @override
  Widget build(BuildContext context) {
    final animationsDisabled = FatooraMotion.disabled(context);
    return AnimatedSwitcher(
      duration: animationsDisabled ? Duration.zero : duration,
      reverseDuration: animationsDisabled ? Duration.zero : reverseDuration,
      switchInCurve: Curves.linear,
      switchOutCurve: Curves.linear,
      layoutBuilder: layoutBuilder,
      transitionBuilder: (child, animation) {
        if (animationsDisabled) return child;
        final curved = CurvedAnimation(
          parent: animation,
          curve: FatooraMotion.enterCurve,
          reverseCurve: FatooraMotion.exitCurve,
        );
        return FadeTransition(
          opacity: curved,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: Offset(0, offset / 400),
              end: Offset.zero,
            ).animate(curved),
            child: child,
          ),
        );
      },
      child: child,
    );
  }
}

/// Progress treatment that becomes static when reduced motion is requested.
class FatooraProgressIndicator extends StatelessWidget {
  const FatooraProgressIndicator({
    super.key,
    this.size,
    this.strokeWidth = 2.5,
    this.color,
  });

  /// Optional compact dimension for constrained contexts such as buttons.
  /// Leave null for the standard standalone loader.
  final double? size;
  final double strokeWidth;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final indicatorColor = color ?? Theme.of(context).colorScheme.primary;
    final indicator = FatooraMotion.disabled(context)
        ? Icon(Icons.hourglass_top_rounded, size: size, color: indicatorColor)
        : CircularProgressIndicator(
            strokeWidth: strokeWidth,
            color: indicatorColor,
          );

    if (size == null) return indicator;
    return SizedBox.square(dimension: size, child: indicator);
  }
}
