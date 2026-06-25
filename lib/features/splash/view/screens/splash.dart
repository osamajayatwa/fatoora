import 'package:fatoora/core/constants/color.dart';
import 'package:fatoora/core/constants/imageassests.dart';
import 'package:fatoora/app/routes/app_routes.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final width = size.width;
    final height = size.height;

    final scale = (width + height) / 2;

    return Scaffold(
      backgroundColor: AppColor.primaryColor,
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topRight,
            end: Alignment.bottomRight,
            colors: [
              AppColor.secondaryColor,
              AppColor.primaryColor,
              AppColor.primaryColor,
            ],
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: EdgeInsets.symmetric(vertical: height * 0.05),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // 🔹 Logo & Title
                _buildHeader(scale, width, height),

                SizedBox(height: height * 0.06),

                // 🔹 "Continue as" text
                Text(
                  "continue_as".tr,
                  style: TextStyle(
                    fontSize: scale * 0.028,
                    color: Colors.white,
                    fontWeight: FontWeight.w500,
                  ),
                ),

                SizedBox(height: height * 0.03),

                // 🔹 Buttons
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: width * 0.08),
                  child: Column(
                    children: [
                      _buildRoleButton(
                        context,
                        icon: Icons.admin_panel_settings,
                        title: "admin_portal".tr,
                        subtitle: "admin_portal_subtitle".tr,
                        route: AppRoute.adminLogin,
                        color: Colors.deepOrange,
                        scale: scale,
                      ),
                      SizedBox(height: height * 0.02),
                      _buildRoleButton(
                        context,
                        icon: Icons.person_outline,
                        title: "user_portal".tr,
                        subtitle: "user_portal_subtitle".tr,
                        route: AppRoute.userLogin,
                        color: AppColor.success,
                        scale: scale,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // 🔸 Header (Logo + Title)
  Widget _buildHeader(double scale, double width, double height) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Image.asset(ImageAssest.logo, width: width * 0.5, height: width * 0.5),
        SizedBox(height: height * 0.02),
        Text(
          "Sales system".tr,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: scale * 0.035,
            fontWeight: FontWeight.bold,
            color: Colors.white,
            letterSpacing: 1.2,
          ),
        ),
        SizedBox(height: height * 0.015),
        Text(
          "Safe & Reliable".tr,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: scale * 0.025,
            color: Colors.white.withValues(alpha: 0.9),
          ),
        ),
      ],
    );
  }

  // 🔸 Role Button
  Widget _buildRoleButton(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required String route,
    required Color color,
    required double scale,
  }) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => Get.toNamed(route),
        child: Container(
          padding: EdgeInsets.all(scale * 0.022),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(15),
            border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
          ),
          child: Row(
            children: [
              Container(
                padding: EdgeInsets.all(scale * 0.013),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: scale * 0.035, color: color),
              ),
              SizedBox(width: scale * 0.025),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: scale * 0.026,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                    SizedBox(height: scale * 0.004),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.8),
                        fontSize: scale * 0.022,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.arrow_forward_ios_rounded,
                size: scale * 0.025,
                color: Colors.white.withValues(alpha: 0.6),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
