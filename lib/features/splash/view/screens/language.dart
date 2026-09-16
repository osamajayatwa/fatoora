import 'package:fatoora/core/constants/color.dart';
import 'package:fatoora/app/routes/app_routes.dart';
import 'package:fatoora/core/localization/changelocal.dart';
import 'package:fatoora/core/services/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:get/get.dart';
import 'package:glassmorphism_ui/glassmorphism_ui.dart';

class Language extends GetView<LocaleController> {
  const Language({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final media = MediaQuery.of(context);
    final height = media.size.height;
    final width = media.size.width;
    final isPortrait = media.orientation == Orientation.portrait;
    final panelWidth = (isPortrait ? width * .9 : width * .72)
        .clamp(280.0, 680.0)
        .toDouble();
    final panelHeight = (height - 32).clamp(260.0, 720.0).toDouble();
    final contentPadding = (panelWidth * .07).clamp(16.0, 42.0).toDouble();

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: Stack(
        children: [
          // 🩸 Gradient background based on theme colors
          AnimatedContainer(
            duration: const Duration(milliseconds: 800),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [colorScheme.primary, AppColor.primaryDark],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),

          // 🌫️ Soft overlay highlight
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.white.withValues(alpha: 0.18),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),

          // 🧊 Glass container
          Center(
            child:
                GlassContainer(
                      height: panelHeight,
                      width: panelWidth,
                      blur: 25,
                      color: colorScheme.surface.withValues(alpha: 0.05),
                      gradient: LinearGradient(
                        colors: [
                          Colors.white.withValues(alpha: 0.1),
                          Colors.white.withValues(alpha: 0.05),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(30),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.15),
                        width: 1,
                      ),
                      shadowStrength: 6,
                      shadowColor: Colors.white.withValues(alpha: 0.2),
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: contentPadding,
                          vertical: (height * .05).clamp(16.0, 36.0).toDouble(),
                        ),
                        child: SingleChildScrollView(
                          physics: const BouncingScrollPhysics(),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _buildTitle(panelWidth, colorScheme),
                              SizedBox(
                                height: (height * .05)
                                    .clamp(18.0, 34.0)
                                    .toDouble(),
                              ),
                              _buildLanguageOptions(panelWidth, colorScheme),
                              SizedBox(
                                height: (height * .06)
                                    .clamp(20.0, 40.0)
                                    .toDouble(),
                              ),
                              _buildContinueButton(panelWidth, colorScheme),
                            ],
                          ),
                        ),
                      ),
                    )
                    .animate()
                    .fadeIn(duration: 600.ms)
                    .scale(begin: const Offset(0.9, 0.9)),
          ),
        ],
      ),
    );
  }

  // 🔹 Title section
  Widget _buildTitle(double width, ColorScheme colorScheme) {
    return Column(
      children: [
        Icon(
          Icons.language_rounded,
          size: (width * .15).clamp(48.0, 86.0).toDouble(),
          color: Colors.white,
        ),
        const SizedBox(height: 12),
        Text(
          "Choose Language".tr,
          style: TextStyle(
            fontSize: (width * .065).clamp(24.0, 38.0).toDouble(),
            color: Colors.white,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.2,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 5),
        Text(
          "Select your preferred language".tr,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.9),
            fontSize: (width * .035).clamp(14.0, 20.0).toDouble(),
            fontWeight: FontWeight.w400,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    ).animate().fadeIn(delay: 150.ms).slideY(begin: -0.1);
  }

  // 🔹 Language list
  Widget _buildLanguageOptions(double width, ColorScheme colorScheme) {
    return Column(
      children: [
        _buildLanguageOption(
          langCode: "en",
          label: "English",
          flag: "🇬🇧",
          description: "International English",
          delay: 250,
          colorScheme: colorScheme,
        ),
        SizedBox(height: (width * .05).clamp(14.0, 28.0).toDouble()),
        _buildLanguageOption(
          langCode: "ar",
          label: "العربية",
          flag: "🇸🇦",
          description: "اللغة العربية",
          isRTL: true,
          delay: 350,
          colorScheme: colorScheme,
        ),
      ],
    );
  }

  // 🔹 Single language option
  Widget _buildLanguageOption({
    required String langCode,
    required String label,
    required String flag,
    required String description,
    required ColorScheme colorScheme,
    bool isRTL = false,
    int delay = 0,
  }) {
    final controller = Get.find<LocaleController>();
    return Obx(
      () => AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
        margin: const EdgeInsets.symmetric(vertical: 5),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        decoration: BoxDecoration(
          color: controller.activeLang.value == langCode
              ? Colors.white.withValues(alpha: 0.25)
              : Colors.white.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: controller.activeLang.value == langCode
                ? Colors.white.withValues(alpha: 0.8)
                : Colors.transparent,
            width: 1.2,
          ),
          boxShadow: controller.activeLang.value == langCode
              ? [
                  BoxShadow(
                    color: Colors.white.withValues(alpha: 0.3),
                    blurRadius: 10,
                    spreadRadius: 1,
                  ),
                ]
              : [],
        ),
        child: ListTile(
          onTap: () => controller.changeLang(langCode),
          leading: Text(flag, style: const TextStyle(fontSize: 34)),
          title: Text(
            label,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
            textDirection: isRTL ? TextDirection.rtl : TextDirection.ltr,
          ),
          subtitle: Text(
            description,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.9),
              fontSize: 14,
            ),
            textDirection: isRTL ? TextDirection.rtl : TextDirection.ltr,
          ),
          trailing: controller.activeLang.value == langCode
              ? const Icon(Icons.check_circle_rounded, color: Colors.white)
              : null,
        ),
      ).animate().fadeIn(delay: delay.ms).slideX(begin: 0.15),
    );
  }

  // 🔹 Continue button
  Widget _buildContinueButton(double width, ColorScheme colorScheme) {
    final MyServices myServices = Get.find();

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: ElevatedButton(
        onPressed: () {
          myServices.sharedPreferences.setString(
            "lang",
            controller.activeLang.value,
          );
          Get.toNamed(AppRoute.splash);
        },
        style: ElevatedButton.styleFrom(
          elevation: 8,
          backgroundColor: colorScheme.surface,
          shadowColor: Colors.white.withValues(alpha: 0.4),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
          ),
          padding: EdgeInsets.symmetric(
            horizontal: (width * .15).clamp(20.0, 56.0).toDouble(),
            vertical: (width * .04).clamp(12.0, 20.0).toDouble(),
          ),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final responsiveFontSize = (constraints.maxWidth * 0.05)
                .clamp(14.0, 22.0)
                .toDouble();

            return Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.arrow_forward_rounded,
                  color: colorScheme.primary,
                  size: responsiveFontSize * 1.1,
                ),
                SizedBox(width: constraints.maxWidth * 0.015),
                Text(
                  "Continue".tr,
                  style: TextStyle(
                    color: colorScheme.primary,
                    fontSize: responsiveFontSize,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.1,
                  ),
                ),
              ],
            );
          },
        ),
      ).animate().fadeIn(delay: 400.ms).slideY(begin: 0.15),
    );
  }
}
