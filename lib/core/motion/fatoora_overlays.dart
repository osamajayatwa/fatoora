import 'package:fatoora/core/motion/fatoora_motion.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

Future<T?> showFatooraDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
  Color? barrierColor,
  String? barrierLabel,
  bool useSafeArea = true,
  bool useRootNavigator = true,
  RouteSettings? routeSettings,
  Offset? anchorPoint,
  bool? requestFocus,
}) {
  return showDialog<T>(
    context: context,
    builder: builder,
    barrierDismissible: barrierDismissible,
    barrierColor: barrierColor,
    barrierLabel: barrierLabel,
    useSafeArea: useSafeArea,
    useRootNavigator: useRootNavigator,
    routeSettings: routeSettings,
    anchorPoint: anchorPoint,
    requestFocus: requestFocus,
    animationStyle: FatooraMotion.overlayStyle(context),
  );
}

Future<T?> showFatooraModalBottomSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  Color? backgroundColor,
  Color? barrierColor,
  double? elevation,
  ShapeBorder? shape,
  Clip? clipBehavior,
  BoxConstraints? constraints,
  bool isScrollControlled = false,
  double scrollControlDisabledMaxHeightRatio = 9.0 / 16.0,
  bool useRootNavigator = false,
  bool isDismissible = true,
  bool enableDrag = true,
  bool? showDragHandle,
  bool useSafeArea = false,
  RouteSettings? routeSettings,
  Offset? anchorPoint,
  bool? requestFocus,
}) {
  return showModalBottomSheet<T>(
    context: context,
    builder: builder,
    backgroundColor: backgroundColor,
    barrierColor: barrierColor,
    elevation: elevation,
    shape: shape,
    clipBehavior: clipBehavior,
    constraints: constraints,
    isScrollControlled: isScrollControlled,
    scrollControlDisabledMaxHeightRatio: scrollControlDisabledMaxHeightRatio,
    useRootNavigator: useRootNavigator,
    isDismissible: isDismissible,
    enableDrag: enableDrag,
    showDragHandle: showDragHandle,
    useSafeArea: useSafeArea,
    routeSettings: routeSettings,
    anchorPoint: anchorPoint,
    requestFocus: requestFocus,
    sheetAnimationStyle: FatooraMotion.overlayStyle(
      context,
      duration: FatooraMotion.deliberate,
      reverseDuration: FatooraMotion.standard,
    ),
  );
}

Future<T?> showFatooraGetDialog<T>(
  Widget dialog, {
  bool barrierDismissible = true,
  Color? barrierColor,
  bool useSafeArea = true,
  GlobalKey<NavigatorState>? navigatorKey,
  Object? arguments,
  String? name,
  RouteSettings? routeSettings,
}) {
  final context = Get.context ?? Get.overlayContext!;
  final animationsDisabled = FatooraMotion.disabled(context);
  final theme = Theme.of(context);
  return Get.generalDialog<T>(
    pageBuilder: (buildContext, animation, secondaryAnimation) {
      Widget child = Theme(data: theme, child: dialog);
      if (useSafeArea) child = SafeArea(child: child);
      return child;
    },
    barrierDismissible: barrierDismissible,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: barrierColor ?? Colors.black54,
    navigatorKey: navigatorKey,
    transitionDuration: animationsDisabled
        ? Duration.zero
        : FatooraMotion.standard,
    transitionBuilder: (buildContext, animation, secondaryAnimation, child) {
      if (animationsDisabled) return child;
      final curved = CurvedAnimation(
        parent: animation,
        curve: FatooraMotion.enterCurve,
        reverseCurve: FatooraMotion.exitCurve,
      );
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(
            begin: FatooraMotion.entranceScale,
            end: 1,
          ).animate(curved),
          child: child,
        ),
      );
    },
    routeSettings:
        routeSettings ?? RouteSettings(arguments: arguments, name: name),
  );
}

Future<T?> showFatooraGetBottomSheet<T>(
  Widget bottomSheet, {
  Color? backgroundColor,
  double? elevation,
  bool persistent = true,
  ShapeBorder? shape,
  Clip? clipBehavior,
  Color? barrierColor,
  bool? ignoreSafeArea,
  bool isScrollControlled = false,
  bool useRootNavigator = false,
  bool isDismissible = true,
  bool enableDrag = true,
  RouteSettings? settings,
}) {
  final context = Get.context ?? Get.overlayContext;
  final animationsDisabled = context != null && FatooraMotion.disabled(context);
  return Get.bottomSheet<T>(
    bottomSheet,
    backgroundColor: backgroundColor,
    elevation: elevation,
    persistent: persistent,
    shape: shape,
    clipBehavior: clipBehavior,
    barrierColor: barrierColor,
    ignoreSafeArea: ignoreSafeArea,
    isScrollControlled: isScrollControlled,
    useRootNavigator: useRootNavigator,
    isDismissible: isDismissible,
    enableDrag: enableDrag,
    settings: settings,
    enterBottomSheetDuration: animationsDisabled
        ? Duration.zero
        : FatooraMotion.deliberate,
    exitBottomSheetDuration: animationsDisabled
        ? Duration.zero
        : FatooraMotion.standard,
  );
}
