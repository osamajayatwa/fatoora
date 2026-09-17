import 'package:fatoora/core/constants/color.dart';
import 'package:fatoora/core/motion/fatoora_overlays.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

Future<bool> alertExitApp() {
  showFatooraGetDialog<void>(
    AlertDialog(
      title: Text(
        "Alert".tr,
        style: const TextStyle(
          color: AppColor.primaryColor,
          fontWeight: FontWeight.bold,
        ),
      ),
      content: Text("Do You Want To Exit The App ?".tr),
      actions: [
        ElevatedButton(
          style: ButtonStyle(
            side: WidgetStateProperty.all(
              BorderSide(color: AppColor.primaryColor, width: 2),
            ),
          ),
          onPressed: () {
            Get.back();
          },
          child: Text(
            "No".tr,
            style: TextStyle(
              color: AppColor.background,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        ElevatedButton(
          style: ButtonStyle(
            backgroundColor: WidgetStateProperty.all(AppColor.primaryColor),
          ),
          onPressed: () async {
            if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
              await SystemNavigator.pop();
              return;
            }

            // Browsers and Apple platforms do not allow applications to close
            // themselves. Close only the confirmation dialog there.
            Get.back();
          },
          child: Text("Yes".tr, style: TextStyle(color: AppColor.background)),
        ),
      ],
    ),
  );
  return Future.value(true);
}
