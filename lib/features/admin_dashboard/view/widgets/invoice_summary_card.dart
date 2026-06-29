import 'dart:math' as math;

import 'package:fatoora/core/constants/color.dart';
import 'package:fatoora/features/admin_dashboard/controller/admin_dashboard_controller.dart';
import 'package:fatoora/features/admin_dashboard/model/admin_dashboard_models.dart';
import 'package:fatoora/features/admin_dashboard/view/widgets/dashboard_card.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class InvoiceSummaryCard extends StatelessWidget {
  const InvoiceSummaryCard({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<AdminDashboardController>();
    final summary = controller.invoiceSummary;
    return DashboardCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const DashboardSectionTitle(titleKey: 'dashboard_invoice_summary'),
          const SizedBox(height: 20),
          LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 360;
              final chart = SizedBox(
                width: 170,
                height: 170,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    CustomPaint(
                      size: const Size.square(170),
                      painter: _DonutChartPainter(items: summary),
                    ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          controller.stats[2].value,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(
                                color: context.appText,
                                fontWeight: FontWeight.w800,
                              ),
                        ),
                        Text(
                          'dashboard_jod'.tr,
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(color: context.appMutedText),
                        ),
                      ],
                    ),
                  ],
                ),
              );
              final legend = _SummaryLegend(items: summary);
              return compact
                  ? Column(
                      children: [chart, const SizedBox(height: 18), legend],
                    )
                  : Row(
                      children: [
                        Expanded(child: Center(child: chart)),
                        const SizedBox(width: 18),
                        Expanded(child: legend),
                      ],
                    );
            },
          ),
        ],
      ),
    );
  }
}

class _SummaryLegend extends StatelessWidget {
  const _SummaryLegend({required this.items});

  final List<DashboardSummaryItem> items;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: items
          .map(
            (item) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 7),
              child: Row(
                children: [
                  Container(
                    width: 9,
                    height: 9,
                    decoration: BoxDecoration(
                      color: item.color,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      item.labelKey.tr,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: context.appMutedText,
                      ),
                    ),
                  ),
                  Text(
                    '${(item.percentage * 100).round()}%',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: context.appText,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    item.amount,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: context.appText,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          )
          .toList(),
    );
  }
}

class _DonutChartPainter extends CustomPainter {
  const _DonutChartPainter({required this.items});

  final List<DashboardSummaryItem> items;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final strokeWidth = size.shortestSide * 0.14;
    var startAngle = -math.pi / 2;
    final gap = 0.035;
    for (final item in items) {
      final sweep = math.pi * 2 * item.percentage;
      canvas.drawArc(
        rect.deflate(strokeWidth / 2),
        startAngle + gap,
        sweep - gap * 2,
        false,
        Paint()
          ..color = item.color
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth
          ..strokeCap = StrokeCap.round,
      );
      startAngle += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutChartPainter oldDelegate) =>
      oldDelegate.items != items;
}
