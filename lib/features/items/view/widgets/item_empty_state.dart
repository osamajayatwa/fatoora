import 'package:fatoora/features/shared/business/business_page_widgets.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class ItemEmptyState extends StatelessWidget {
  const ItemEmptyState({super.key});

  @override
  Widget build(BuildContext context) {
    return BusinessEmptyState(
      icon: Icons.inventory_2_outlined,
      title: 'items_no_results'.tr,
      message: 'items_no_results_hint'.tr,
      contained: false,
    );
  }
}
