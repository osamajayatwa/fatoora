import 'package:fatoora/features/shared/navigation/adaptive_business_shell.dart';

class SalesRepDashboardLayout {
  const SalesRepDashboardLayout._();

  static const double maxContentWidth = 1240;
  static const double sectionGap = 20;

  static double horizontalPadding(double width) =>
      width < AdaptiveShellBreakpoints.mobile ? 12 : 24;
  static bool useDesktopColumns(double width) =>
      width >= AdaptiveShellBreakpoints.desktop;

  static int metricColumns(double width) {
    if (width >= 820) return 4;
    if (width >= 600) return 3;
    return 2;
  }

  static int primaryActionColumns(double width) {
    if (width >= 720) return 4;
    if (width < 360) return 1;
    return 2;
  }

  static int secondaryServiceColumns(double width) {
    if (width >= 590) return 3;
    if (width < 330) return 1;
    return 2;
  }

  static double metricHeight(double textScale) {
    final scale = textScale.clamp(1.0, 2.0);
    return 118 + ((scale - 1) * 62);
  }

  static double primaryActionHeight(double textScale, {int columns = 2}) {
    final scale = textScale.clamp(1.0, 2.0);
    if (columns == 1) return 96 + ((scale - 1) * 46);
    return 132 + ((scale - 1) * 66);
  }

  static double secondaryServiceHeight(double textScale) {
    final scale = textScale.clamp(1.0, 2.0);
    return 72 + ((scale - 1) * 34);
  }
}
