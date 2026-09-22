import 'package:fatoora/core/constants/color.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class InvoiceSearchBar extends StatelessWidget {
  const InvoiceSearchBar({
    super.key,
    required this.controller,
    required this.onChanged,
    required this.onSubmitted,
    required this.onClear,
    this.showMinimumLengthHint = false,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSubmitted;
  final VoidCallback onClear;
  final bool showMinimumLengthHint;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          key: const ValueKey('invoice-search-field'),
          controller: controller,
          onChanged: onChanged,
          onSubmitted: onSubmitted,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: 'search_invoices'.tr,
            prefixIcon: const Icon(Icons.search_rounded),
            suffixIcon: controller.text.isEmpty
                ? null
                : IconButton(
                    tooltip: 'clear_search'.tr,
                    onPressed: onClear,
                    icon: const Icon(Icons.close_rounded),
                  ),
            filled: true,
            fillColor: AppColor.surface,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Color(0xFFE1E5ED)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Color(0xFFE1E5ED)),
            ),
          ),
        ),
        if (showMinimumLengthHint) ...[
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 12),
            child: Text(
              'invoice_search_minimum_hint'.tr,
              key: const ValueKey('invoice-search-minimum-hint'),
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: AppColor.grey),
            ),
          ),
        ],
      ],
    );
  }
}
