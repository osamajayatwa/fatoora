import 'package:fatoora/core/constants/color.dart';
import 'package:fatoora/core/constants/imageassests.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:lottie/lottie.dart';

class EmptyInvoicesWidget extends StatelessWidget {
  const EmptyInvoicesWidget({super.key, required this.searching});

  final bool searching;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 52, horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Lottie.asset(ImageAssest.noData, width: 150, height: 150),
            const SizedBox(height: 12),
            Text(
              (searching ? 'no_search_results' : 'no_invoices_found').tr,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: AppColor.secondaryColor,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
