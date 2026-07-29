import 'package:fatoora/features/home/view/widgets/sales_rep_dashboard_layout.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('narrow mobile dashboard gives quick actions full width', () {
    expect(SalesRepDashboardLayout.horizontalPadding(320), 16);
    expect(SalesRepDashboardLayout.metricColumns(288), 2);
    expect(SalesRepDashboardLayout.primaryActionColumns(288), 1);
    expect(SalesRepDashboardLayout.secondaryServiceColumns(288), 1);
    expect(SalesRepDashboardLayout.useDesktopColumns(320), isFalse);
  });

  test('normal phone dashboard uses two-column quick actions', () {
    expect(SalesRepDashboardLayout.primaryActionColumns(380), 2);
    expect(SalesRepDashboardLayout.secondaryServiceColumns(380), 2);
  });

  test('tablet dashboard increases compact grid density', () {
    expect(SalesRepDashboardLayout.metricColumns(700), 3);
    expect(SalesRepDashboardLayout.primaryActionColumns(760), 4);
    expect(SalesRepDashboardLayout.secondaryServiceColumns(700), 3);
    expect(SalesRepDashboardLayout.useDesktopColumns(900), isFalse);
  });

  test('desktop dashboard uses constrained two-column composition', () {
    expect(SalesRepDashboardLayout.useDesktopColumns(1050), isTrue);
    expect(SalesRepDashboardLayout.metricColumns(1180), 4);
    expect(
      SalesRepDashboardLayout.maxContentWidth,
      inInclusiveRange(1180, 1280),
    );
  });

  test('large text scale increases fixed grid card heights', () {
    expect(
      SalesRepDashboardLayout.metricHeight(1.3),
      greaterThan(SalesRepDashboardLayout.metricHeight(1)),
    );
    expect(
      SalesRepDashboardLayout.primaryActionHeight(1.3),
      greaterThan(SalesRepDashboardLayout.primaryActionHeight(1)),
    );
    expect(
      SalesRepDashboardLayout.secondaryServiceHeight(2),
      greaterThanOrEqualTo(100),
    );
    expect(SalesRepDashboardLayout.metricHeight(2), greaterThanOrEqualTo(175));
    expect(
      SalesRepDashboardLayout.primaryActionHeight(2),
      greaterThanOrEqualTo(195),
    );
    expect(
      SalesRepDashboardLayout.primaryActionHeight(2, columns: 1),
      greaterThanOrEqualTo(140),
    );
  });

  test('extreme text scaling is capped to keep the dashboard practical', () {
    expect(
      SalesRepDashboardLayout.metricHeight(3),
      SalesRepDashboardLayout.metricHeight(2),
    );
    expect(
      SalesRepDashboardLayout.primaryActionHeight(3),
      SalesRepDashboardLayout.primaryActionHeight(2),
    );
  });
}
