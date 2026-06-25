import 'package:fatoora/features/auth/user_signup/controller/user_signup_controller.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class UserSignUpFooter extends StatelessWidget {
  const UserSignUpFooter({super.key, required this.controller});
  final UserSignUpControllerImp controller;

  @override
  Widget build(BuildContext context) => Wrap(
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      Text('already_have_account'.tr),
      TextButton(onPressed: controller.goToLogin, child: Text('login'.tr)),
    ],
  );
}
