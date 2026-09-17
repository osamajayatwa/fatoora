import 'package:fatoora/core/motion/fatoora_motion.dart';
import 'package:flutter/material.dart';
import 'package:get/get_navigation/src/routes/custom_transition.dart';

/// A restrained shared-axis transition used by all named GetX routes.
class FatooraPageTransition extends CustomTransition {
  @override
  Widget buildTransition(
    BuildContext context,
    Curve? curve,
    Alignment? alignment,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (FatooraMotion.disabled(context)) return child;

    final direction = Directionality.of(context) == TextDirection.rtl
        ? -1.0
        : 1.0;
    final entrance = CurvedAnimation(
      parent: animation,
      curve: FatooraMotion.emphasizedCurve,
      reverseCurve: FatooraMotion.exitCurve,
    );

    return FadeTransition(
      opacity: Tween<double>(begin: .92, end: 1).animate(entrance),
      child: SlideTransition(
        position: Tween<Offset>(
          begin: Offset(.018 * direction, 0),
          end: Offset.zero,
        ).animate(entrance),
        child: ScaleTransition(
          alignment: alignment ?? Alignment.center,
          scale: Tween<double>(
            begin: FatooraMotion.entranceScale,
            end: 1,
          ).animate(entrance),
          child: child,
        ),
      ),
    );
  }
}
