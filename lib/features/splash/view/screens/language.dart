import 'package:fatoora/app/routes/app_routes.dart';
import 'package:fatoora/core/constants/color.dart';
import 'package:fatoora/core/constants/imageassests.dart';
import 'package:fatoora/core/localization/changelocal.dart';
import 'package:fatoora/core/motion/fatoora_motion.dart';
import 'package:fatoora/core/motion/fatoora_motion_widgets.dart';
import 'package:fatoora/core/services/services.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

const _canvasColor = Color(0xFFFAF8F5);
const _inkColor = Color(0xFF241F20);
const _mutedInkColor = Color(0xFF746D6F);
const _dividerColor = Color(0xFFE3DEDA);

class Language extends GetView<LocaleController> {
  const Language({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _canvasColor,
      body: _OnboardingCanvas(
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth >= 700;
              final horizontalPadding = constraints.maxWidth < 360
                  ? 18.0
                  : isWide
                  ? 52.0
                  : 26.0;
              final verticalPadding = constraints.maxHeight < 650 ? 18.0 : 34.0;

              final brand = _LanguageBrand(compact: !isWide);
              final selector = _LanguageSelector(controller: controller);
              final content = isWide
                  ? Row(
                      key: const Key('language_wide_layout'),
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(child: brand),
                        const SizedBox(width: 42),
                        Container(width: 1, height: 300, color: _dividerColor),
                        const SizedBox(width: 54),
                        Expanded(child: selector),
                      ],
                    )
                  : Column(
                      key: const Key('language_compact_layout'),
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        brand,
                        const SizedBox(height: 30),
                        const Divider(color: _dividerColor, height: 1),
                        const SizedBox(height: 30),
                        selector,
                      ],
                    );

              final visibleContent = FatooraMotionReveal(
                duration: FatooraMotion.deliberate,
                child: content,
              );

              return SingleChildScrollView(
                physics: const ClampingScrollPhysics(),
                padding: EdgeInsets.symmetric(
                  horizontal: horizontalPadding,
                  vertical: verticalPadding,
                ),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: constraints.maxHeight - (verticalPadding * 2),
                  ),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1080),
                      child: visibleContent,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _OnboardingCanvas extends StatelessWidget {
  const _OnboardingCanvas({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        const ColoredBox(color: _canvasColor),
        PositionedDirectional(
          top: 0,
          bottom: 0,
          start: 0,
          child: Container(width: 6, color: AppColor.primaryColor),
        ),
        PositionedDirectional(
          top: -150,
          end: -150,
          child: IgnorePointer(
            child: Container(
              width: 360,
              height: 360,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: AppColor.primaryColor.withValues(alpha: .09),
                  width: 54,
                ),
              ),
            ),
          ),
        ),
        PositionedDirectional(
          bottom: -120,
          start: -75,
          child: IgnorePointer(
            child: Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: AppColor.secondaryColor.withValues(alpha: .045),
                  width: 38,
                ),
              ),
            ),
          ),
        ),
        const PositionedDirectional(
          top: 40,
          start: 34,
          child: IgnorePointer(child: _AccentDots()),
        ),
        const PositionedDirectional(
          bottom: 42,
          end: 38,
          child: IgnorePointer(child: _BrandLines()),
        ),
        child,
      ],
    );
  }
}

class _AccentDots extends StatelessWidget {
  const _AccentDots();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 40,
      child: Wrap(
        spacing: 9,
        runSpacing: 9,
        children: List.generate(
          9,
          (_) => Container(
            width: 4,
            height: 4,
            decoration: BoxDecoration(
              color: AppColor.primaryColor.withValues(alpha: .2),
              shape: BoxShape.circle,
            ),
          ),
        ),
      ),
    );
  }
}

class _BrandLines extends StatelessWidget {
  const _BrandLines();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Container(
          width: 58,
          height: 2,
          color: AppColor.primaryColor.withValues(alpha: .28),
        ),
        const SizedBox(height: 7),
        Container(
          width: 36,
          height: 2,
          color: AppColor.secondaryColor.withValues(alpha: .22),
        ),
      ],
    );
  }
}

class _LanguageBrand extends StatelessWidget {
  const _LanguageBrand({required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final alignment = compact
        ? CrossAxisAlignment.center
        : CrossAxisAlignment.start;
    final textAlign = compact ? TextAlign.center : TextAlign.start;

    return Semantics(
      header: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: alignment,
        children: [
          SizedBox(
            width: compact ? 170 : 250,
            height: compact ? 116 : 165,
            child: Image.asset(
              ImageAssest.logo,
              cacheWidth: 512,
              cacheHeight: 512,
              fit: BoxFit.contain,
              filterQuality: FilterQuality.medium,
            ),
          ),
          SizedBox(height: compact ? 14 : 24),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(width: 28, height: 3, color: AppColor.primaryColor),
              const SizedBox(width: 10),
              Text(
                'FATOORA',
                style: textTheme.labelLarge?.copyWith(
                  color: _mutedInkColor,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 2.8,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            'Sales system'.tr,
            textAlign: textAlign,
            style: textTheme.headlineLarge?.copyWith(
              color: _inkColor,
              fontWeight: FontWeight.w800,
              height: 1.15,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  'Safe & Reliable'.tr,
                  textAlign: textAlign,
                  style: textTheme.titleMedium?.copyWith(
                    color: _mutedInkColor,
                    fontWeight: FontWeight.w500,
                    height: 1.45,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Container(width: 28, height: 3, color: AppColor.primaryColor),
            ],
          ),
        ],
      ),
    );
  }
}

class _LanguageSelector extends StatelessWidget {
  const _LanguageSelector({required this.controller});

  final LocaleController controller;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return KeyedSubtree(
      key: const Key('language_selection_panel'),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'LANGUAGE  /  اللغة',
            style: textTheme.labelMedium?.copyWith(
              color: AppColor.primaryColor,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Choose Language'.tr,
            style: textTheme.headlineSmall?.copyWith(
              color: _inkColor,
              fontWeight: FontWeight.w800,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Select your preferred language'.tr,
            style: textTheme.bodyLarge?.copyWith(
              color: _mutedInkColor,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 26),
          const Divider(color: _dividerColor, height: 1),
          Obx(
            () => _LanguageRow(
              key: const Key('language_option_en'),
              code: 'en',
              monogram: 'EN',
              title: 'English',
              subtitle: 'English (International)',
              textDirection: TextDirection.ltr,
              selected: controller.activeLang.value == 'en',
              onTap: () => controller.changeLang('en'),
            ),
          ),
          const Divider(color: _dividerColor, height: 1),
          Obx(
            () => _LanguageRow(
              key: const Key('language_option_ar'),
              code: 'ar',
              monogram: 'ع',
              title: 'العربية',
              subtitle: 'اللغة العربية',
              textDirection: TextDirection.rtl,
              selected: controller.activeLang.value == 'ar',
              onTap: () => controller.changeLang('ar'),
            ),
          ),
          const Divider(color: _dividerColor, height: 1),
          const SizedBox(height: 28),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: _ContinueButton(controller: controller),
          ),
        ],
      ),
    );
  }
}

class _LanguageRow extends StatelessWidget {
  const _LanguageRow({
    super.key,
    required this.code,
    required this.monogram,
    required this.title,
    required this.subtitle,
    required this.textDirection,
    required this.selected,
    required this.onTap,
  });

  final String code;
  final String monogram;
  final String title;
  final String subtitle;
  final TextDirection textDirection;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Semantics(
      button: true,
      selected: selected,
      excludeSemantics: true,
      label: '$title. $subtitle',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          hoverColor: AppColor.primaryColor.withValues(alpha: .035),
          focusColor: AppColor.primaryColor.withValues(alpha: .05),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Row(
              children: [
                AnimatedContainer(
                  duration: FatooraMotion.resolve(
                    context,
                    FatooraMotion.standard,
                  ),
                  curve: FatooraMotion.enterCurve,
                  width: 4,
                  height: 52,
                  color: selected ? AppColor.primaryColor : Colors.transparent,
                ),
                const SizedBox(width: 16),
                SizedBox(
                  width: 48,
                  child: Text(
                    monogram,
                    textAlign: TextAlign.center,
                    textDirection: textDirection,
                    style: textTheme.titleLarge?.copyWith(
                      color: selected ? AppColor.primaryColor : _mutedInkColor,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Directionality(
                    textDirection: textDirection,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: textTheme.titleMedium?.copyWith(
                            color: _inkColor,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          subtitle,
                          style: textTheme.bodySmall?.copyWith(
                            color: _mutedInkColor,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                FatooraMotionSwitcher(
                  duration: FatooraMotion.quick,
                  child: selected
                      ? const Icon(
                          Icons.check_rounded,
                          key: ValueKey('selected'),
                          color: AppColor.primaryColor,
                        )
                      : Icon(
                          Icons.arrow_forward_rounded,
                          key: ValueKey('$code-unselected'),
                          color: _mutedInkColor.withValues(alpha: .55),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ContinueButton extends StatelessWidget {
  const _ContinueButton({required this.controller});

  final LocaleController controller;

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      key: const Key('language_continue_button'),
      onPressed: () {
        final services = Get.find<MyServices>();
        services.sharedPreferences.setString(
          'lang',
          controller.activeLang.value,
        );
        Get.toNamed(AppRoute.splash);
      },
      style: FilledButton.styleFrom(
        backgroundColor: AppColor.primaryColor,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 15),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      iconAlignment: IconAlignment.end,
      icon: const Icon(Icons.arrow_forward_rounded, size: 21),
      label: Text(
        'Continue'.tr,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
          color: Colors.white,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}
