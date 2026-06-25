import 'dart:io';

import 'package:fatoora/core/constants/color.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

Future<bool> alertExitApp() {
  Get.defaultDialog(
    title: "Alert".tr,
    titleStyle: const TextStyle(
      color: AppColor.primaryColor,
      fontWeight: FontWeight.bold,
    ),
    middleText: "Do You Want To Exit The App ?".tr,
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
        onPressed: () {
          exit(0);
        },
        child: Text("Yes".tr, style: TextStyle(color: AppColor.background)),
      ),
    ],
  );
  return Future.value(true);
}
