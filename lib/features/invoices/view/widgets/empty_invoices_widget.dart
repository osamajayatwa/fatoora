import 'package:fatoora/features/shared/business/business_page_widgets.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class EmptyInvoicesWidget extends StatelessWidget {
  const EmptyInvoicesWidget({super.key, required this.searching});

  final bool searching;

  @override
  Widget build(BuildContext context) {
    return BusinessEmptyState(
      icon: Icons.receipt_long_outlined,
      title: (searching ? 'no_search_results' : 'no_invoices_found').tr,
    );
  }
}
