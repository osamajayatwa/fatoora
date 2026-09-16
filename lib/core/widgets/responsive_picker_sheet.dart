import 'package:fatoora/core/constants/color.dart';
import 'package:flutter/material.dart';

/// A bounded picker surface that remains usable when the on-screen keyboard
/// leaves too little height for a fixed header, search field, and result list.
class ResponsivePickerSheet extends StatelessWidget {
  const ResponsivePickerSheet({
    super.key,
    required this.header,
    required this.search,
    required this.body,
    this.footer,
  });

  final Widget header;
  final Widget search;
  final Widget body;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 720),
      child: Material(
        color: AppColor.surface,
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: LayoutBuilder(
              builder: (context, constraints) {
                if (constraints.maxHeight < 260) {
                  return ListView(
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    children: [
                      header,
                      const SizedBox(height: 12),
                      search,
                      const SizedBox(height: 12),
                      SizedBox(height: 240, child: body),
                      if (footer != null) ...[
                        const SizedBox(height: 12),
                        footer!,
                      ],
                    ],
                  );
                }

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    header,
                    const SizedBox(height: 12),
                    search,
                    const SizedBox(height: 12),
                    Expanded(child: body),
                    if (footer != null) ...[
                      const SizedBox(height: 12),
                      footer!,
                    ],
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
