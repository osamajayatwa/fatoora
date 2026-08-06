import 'package:fatoora/app/routes/app_routes.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class NotFoundScreen extends StatelessWidget {
  const NotFoundScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.explore_off_rounded,
                    size: 72,
                    color: colors.primary,
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'page_not_found_title'.tr,
                    style: Theme.of(context).textTheme.headlineMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'page_not_found_body'.tr,
                    style: Theme.of(context).textTheme.bodyLarge,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 28),
                  FilledButton.icon(
                    onPressed: () {
                      if (Get.key.currentState?.canPop() ?? false) {
                        Get.back<void>();
                      } else {
                        Get.offAllNamed(AppRoute.splash);
                      }
                    },
                    icon: const Icon(Icons.arrow_back_rounded),
                    label: Text('go_back'.tr),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
