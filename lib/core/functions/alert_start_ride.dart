import 'dart:io';

import 'package:fatoora/core/constant/color.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';


Future<bool> alertStartRide() {
  Get.defaultDialog(
      title: "Alert".tr,
      titleStyle: const TextStyle(
          color: AppColor.primaryColor, fontWeight: FontWeight.bold),
      middleText: "Do You Want To Start The Ride ?".tr,
      actions: [
        ElevatedButton(
            style: ButtonStyle(
              side: WidgetStateProperty.all(
                  BorderSide(color: AppColor.primaryColor, width: 2)),
            ),
            onPressed: () {
              Get.back();
            },
            child: Text(
              "cancel".tr,
              style: TextStyle(color: AppColor.primaryColor),
            )),
        ElevatedButton(
            style: ButtonStyle(
                backgroundColor:
                    WidgetStateProperty.all(AppColor.primaryColor)),
            onPressed: () {
              exit(0);
            },
            child: Text(
              "Start".tr,
              style: TextStyle(color: AppColor.background),
            )),
      ]);
  return Future.value(true);
}
