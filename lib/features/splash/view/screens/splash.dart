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

    final scale = ((width + height) / 2).clamp(280.0, 620.0).toDouble();
    final contentWidth = width.clamp(0.0, 680.0).toDouble();

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
          child: LayoutBuilder(
            builder: (context, _) => SingleChildScrollView(
              padding: EdgeInsets.symmetric(
                vertical: (height * .05).clamp(16.0, 44.0).toDouble(),
              ),
              child: Center(
                child: SizedBox(
                  width: contentWidth,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // 🔹 Logo & Title
                      _buildHeader(scale, width, height),

                      SizedBox(
                        height: (height * .06).clamp(18.0, 46.0).toDouble(),
                      ),

                      // 🔹 "Continue as" text
                      Text(
                        "continue_as".tr,
                        style: TextStyle(
                          fontSize: (scale * .028).clamp(16.0, 22.0).toDouble(),
                          color: Colors.white,
                          fontWeight: FontWeight.w500,
                        ),
                      ),

                      SizedBox(
                        height: (height * .03).clamp(12.0, 28.0).toDouble(),
                      ),

                      // 🔹 Buttons
                      Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: (contentWidth * .08)
                              .clamp(16.0, 48.0)
                              .toDouble(),
                        ),
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
                            SizedBox(
                              height: (height * .02)
                                  .clamp(10.0, 20.0)
                                  .toDouble(),
                            ),
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
        Image.asset(
          ImageAssest.logo,
          width: (width * .5).clamp(110.0, 220.0).toDouble(),
          height: (width * .5).clamp(110.0, 220.0).toDouble(),
        ),
        SizedBox(height: (height * .02).clamp(8.0, 18.0).toDouble()),
        Text(
          "Sales system".tr,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: (scale * .035).clamp(20.0, 30.0).toDouble(),
            fontWeight: FontWeight.bold,
            color: Colors.white,
            letterSpacing: 1.2,
          ),
        ),
        SizedBox(height: (height * .015).clamp(6.0, 14.0).toDouble()),
        Text(
          "Safe & Reliable".tr,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: (scale * .025).clamp(14.0, 20.0).toDouble(),
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
          padding: EdgeInsets.all((scale * .022).clamp(12.0, 18.0).toDouble()),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(15),
            border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
          ),
          child: Row(
            children: [
              Container(
                padding: EdgeInsets.all(
                  (scale * .013).clamp(8.0, 12.0).toDouble(),
                ),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  icon,
                  size: (scale * .035).clamp(20.0, 28.0).toDouble(),
                  color: color,
                ),
              ),
              SizedBox(width: (scale * .025).clamp(10.0, 16.0).toDouble()),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: (scale * .026).clamp(16.0, 21.0).toDouble(),
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                    SizedBox(height: (scale * .004).clamp(2.0, 5.0).toDouble()),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.8),
                        fontSize: (scale * .022).clamp(13.0, 17.0).toDouble(),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.arrow_forward_ios_rounded,
                size: (scale * .025).clamp(16.0, 22.0).toDouble(),
                color: Colors.white.withValues(alpha: 0.6),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
