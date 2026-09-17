import 'package:flutter/material.dart';

/// App-wide motion tokens for restrained, responsive business UI motion.
abstract final class FatooraMotion {
  static const Duration instant = Duration.zero;
  static const Duration quick = Duration(milliseconds: 150);
  static const Duration standard = Duration(milliseconds: 200);
  static const Duration page = Duration(milliseconds: 250);
  static const Duration deliberate = Duration(milliseconds: 300);

  static const double shortDistance = 8;
  static const double mediumDistance = 12;
  static const double entranceScale = .985;

  static const Curve enterCurve = Cubic(.2, .8, .2, 1);
  static const Curve exitCurve = Cubic(.4, 0, 1, 1);
  static const Curve emphasizedCurve = Cubic(.2, 0, 0, 1);

  static bool disabled(BuildContext context) =>
      MediaQuery.maybeOf(context)?.disableAnimations ?? false;

  static Duration resolve(BuildContext context, Duration duration) =>
      disabled(context) ? instant : duration;

  static AnimationStyle overlayStyle(
    BuildContext context, {
    Duration duration = standard,
    Duration reverseDuration = quick,
  }) {
    if (disabled(context)) return AnimationStyle.noAnimation;
    return AnimationStyle(
      duration: duration,
      reverseDuration: reverseDuration,
      curve: enterCurve,
      reverseCurve: exitCurve,
    );
  }
}
