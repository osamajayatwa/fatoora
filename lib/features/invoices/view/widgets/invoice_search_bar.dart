import 'package:fatoora/core/constants/color.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class InvoiceSearchBar extends StatelessWidget {
  const InvoiceSearchBar({
    super.key,
    required this.controller,
    required this.onChanged,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      decoration: InputDecoration(
        hintText: 'search_invoices'.tr,
        prefixIcon: const Icon(Icons.search_rounded),
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
    );
  }
}
