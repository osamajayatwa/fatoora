import 'dart:math' as math;

import 'package:fatoora/core/constants/color.dart';
import 'package:fatoora/features/admin_dashboard/view/widgets/dashboard_card.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class InvoiceLineChartCard extends StatelessWidget {
  const InvoiceLineChartCard({super.key, required this.values});

  final List<double> values;

  @override
  Widget build(BuildContext context) {
    const dayKeys = [
      'dashboard_sun',
      'dashboard_mon',
      'dashboard_tue',
      'dashboard_wed',
      'dashboard_thu',
      'dashboard_fri',
      'dashboard_sat',
    ];

    return DashboardCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DashboardSectionTitle(
            titleKey: 'dashboard_invoice_chart',
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFE3E7EF)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.calendar_today_outlined, size: 14),
                  const SizedBox(width: 6),
                  Text(
                    'dashboard_last_7_days'.tr,
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            height: 215,
            child: CustomPaint(
              painter: _LineChartPainter(
                values: values,
                lineColor: AppColor.primaryColor,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: dayKeys
                .map(
                  (key) => Expanded(
                    child: Text(
                      key.tr,
                      textAlign: TextAlign.center,
                      style: Theme.of(
                        context,
                      ).textTheme.labelSmall?.copyWith(color: AppColor.grey),
                    ),
                  ),
                )
                .toList(),
          ),
        ],
      ),
    );
  }
}

class _LineChartPainter extends CustomPainter {
  const _LineChartPainter({required this.values, required this.lineColor});

  final List<double> values;
  final Color lineColor;

  @override
  void paint(Canvas canvas, Size size) {
    final chartRect = Rect.fromLTWH(12, 8, size.width - 24, size.height - 16);
    final gridPaint = Paint()
      ..color = const Color(0xFFE9ECF3)
      ..strokeWidth = 1;

    for (var i = 0; i <= 4; i++) {
      final y = chartRect.top + chartRect.height * i / 4;
      canvas.drawLine(
        Offset(chartRect.left, y),
        Offset(chartRect.right, y),
        gridPaint,
      );
    }

    if (values.length < 2) return;
    final maximum = math.max(values.reduce(math.max), 1.0);
    final points = <Offset>[];
    for (var i = 0; i < values.length; i++) {
      final x = chartRect.left + chartRect.width * i / (values.length - 1);
      final y = chartRect.bottom - chartRect.height * values[i] / maximum;
      points.add(Offset(x, y));
    }

    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (var i = 0; i < points.length - 1; i++) {
      final current = points[i];
      final next = points[i + 1];
      final midpoint = (current.dx + next.dx) / 2;
      path.cubicTo(midpoint, current.dy, midpoint, next.dy, next.dx, next.dy);
    }

    final fillPath = Path.from(path)
      ..lineTo(points.last.dx, chartRect.bottom)
      ..lineTo(points.first.dx, chartRect.bottom)
      ..close();
    canvas.drawPath(
      fillPath,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            lineColor.withValues(alpha: 0.22),
            lineColor.withValues(alpha: 0.01),
          ],
        ).createShader(chartRect),
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = lineColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.6
        ..strokeCap = StrokeCap.round,
    );

    for (final point in points) {
      canvas.drawCircle(point, 5, Paint()..color = AppColor.surface);
      canvas.drawCircle(point, 3.3, Paint()..color = lineColor);
    }
  }

  @override
  bool shouldRepaint(covariant _LineChartPainter oldDelegate) {
    return oldDelegate.values != values || oldDelegate.lineColor != lineColor;
  }
}
