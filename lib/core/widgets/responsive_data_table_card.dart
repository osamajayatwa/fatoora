import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:fatoora/core/constants/color.dart';
import 'package:flutter/material.dart';

class ResponsiveDataTableCard extends StatefulWidget {
  const ResponsiveDataTableCard({
    super.key,
    required this.child,
    required this.minWidth,
    this.color,
    this.borderColor,
    this.borderRadius = 18,
  });

  final Widget child;
  final double minWidth;
  final Color? color;
  final Color? borderColor;
  final double borderRadius;

  @override
  State<ResponsiveDataTableCard> createState() =>
      _ResponsiveDataTableCardState();
}

class _ResponsiveDataTableCardState extends State<ResponsiveDataTableCard> {
  final ScrollController _horizontalController = ScrollController();

  @override
  void dispose() {
    _horizontalController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(widget.borderRadius);
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: widget.color ?? AppColor.surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: BorderSide(color: widget.borderColor ?? const Color(0xFFE4E8EF)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          return Scrollbar(
            controller: _horizontalController,
            thumbVisibility: true,
            trackVisibility: true,
            interactive: true,
            notificationPredicate: (notification) =>
                notification.metrics.axis == Axis.horizontal,
            child: SingleChildScrollView(
              controller: _horizontalController,
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: math.max(constraints.maxWidth, widget.minWidth),
                child: widget.child,
              ),
            ),
          );
        },
      ),
    );
  }
}

class BoundedTableText extends StatelessWidget {
  const BoundedTableText(
    this.value, {
    super.key,
    required this.width,
    this.maxLines = 1,
    this.textAlign,
    this.forceLtr = false,
  });

  final String value;
  final double width;
  final int maxLines;
  final TextAlign? textAlign;
  final bool forceLtr;

  @override
  Widget build(BuildContext context) {
    final text = value.trim();
    final child = SizedBox(
      width: width,
      child: Text(
        text,
        maxLines: maxLines,
        overflow: TextOverflow.ellipsis,
        textAlign: textAlign,
        textDirection: forceLtr ? ui.TextDirection.ltr : null,
      ),
    );
    if (text.isEmpty) return child;
    return Tooltip(message: text, child: child);
  }
}

class BoundedTableWidget extends StatelessWidget {
  const BoundedTableWidget({
    super.key,
    required this.width,
    required this.child,
    this.alignment = AlignmentDirectional.centerStart,
  });

  final double width;
  final Widget child;
  final AlignmentGeometry alignment;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Align(
        alignment: alignment,
        child: FittedBox(fit: BoxFit.scaleDown, child: child),
      ),
    );
  }
}
