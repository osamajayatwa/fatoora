import 'package:fatoora/core/constant/color.dart';
import 'package:fatoora/core/constant/imageassests.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:lottie/lottie.dart';

class ItemEmptyState extends StatelessWidget {
  const ItemEmptyState({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 44, horizontal: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Lottie.asset(ImageAssest.noData, width: 180, height: 180),
            Text(
              'items_no_results'.tr,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: AppColor.secondaryColor,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'items_no_results_hint'.tr,
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: AppColor.grey),
            ),
          ],
        ),
      ),
    );
  }
}
