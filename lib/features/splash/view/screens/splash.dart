import 'package:fatoora/app/routes/app_routes.dart';
import 'package:fatoora/core/constants/color.dart';
import 'package:fatoora/core/constants/imageassests.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:get/get.dart';

const _canvasColor = Color(0xFFFAF8F5);
const _inkColor = Color(0xFF241F20);
const _mutedInkColor = Color(0xFF746D6F);
const _dividerColor = Color(0xFFE3DEDA);

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);

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

              final hero = _SplashHero(compact: !isWide);
              const access = _AccessChoices();
              final content = isWide
                  ? Row(
                      key: const Key('splash_wide_layout'),
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(child: hero),
                        const SizedBox(width: 42),
                        Container(width: 1, height: 300, color: _dividerColor),
                        const SizedBox(width: 54),
                        const Expanded(child: access),
                      ],
                    )
                  : Column(
                      key: const Key('splash_compact_layout'),
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        hero,
                        const SizedBox(height: 30),
                        const Divider(color: _dividerColor, height: 1),
                        const SizedBox(height: 30),
                        access,
                      ],
                    );

              final visibleContent = media.disableAnimations
                  ? content
                  : content
                        .animate()
                        .fadeIn(duration: 360.ms, curve: Curves.easeOut)
                        .slideY(
                          begin: .018,
                          duration: 420.ms,
                          curve: Curves.easeOutCubic,
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
                  color: AppColor.primaryColor.withValues(alpha: .07),
                  width: 54,
                ),
              ),
            ),
          ),
        ),
        PositionedDirectional(
          bottom: -120,
          start: -90,
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

class _SplashHero extends StatelessWidget {
  const _SplashHero({required this.compact});

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
          SizedBox(height: compact ? 16 : 26),
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
          const SizedBox(height: 14),
          Container(
            constraints: const BoxConstraints(maxWidth: 380),
            padding: const EdgeInsetsDirectional.only(start: 14),
            decoration: const BoxDecoration(
              border: BorderDirectional(
                start: BorderSide(color: AppColor.primaryColor, width: 3),
              ),
            ),
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
        ],
      ),
    );
  }
}

class _AccessChoices extends StatelessWidget {
  const _AccessChoices();

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return KeyedSubtree(
      key: const Key('splash_access_panel'),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'FATOORA ACCESS',
            style: textTheme.labelMedium?.copyWith(
              color: AppColor.primaryColor,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'continue_as'.tr,
            style: textTheme.headlineSmall?.copyWith(
              color: _inkColor,
              fontWeight: FontWeight.w800,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 26),
          const Divider(color: _dividerColor, height: 1),
          _RoleRow(
            key: const Key('admin_portal_option'),
            icon: Icons.admin_panel_settings_outlined,
            title: 'admin_portal'.tr,
            subtitle: 'admin_portal_subtitle'.tr,
            accent: AppColor.primaryColor,
            onTap: () => Get.toNamed(AppRoute.adminLogin),
          ),
          const Divider(color: _dividerColor, height: 1),
          _RoleRow(
            key: const Key('user_portal_option'),
            icon: Icons.badge_outlined,
            title: 'user_portal'.tr,
            subtitle: 'user_portal_subtitle'.tr,
            accent: AppColor.secondaryColor,
            onTap: () => Get.toNamed(AppRoute.userLogin),
          ),
          const Divider(color: _dividerColor, height: 1),
        ],
      ),
    );
  }
}

class _RoleRow extends StatelessWidget {
  const _RoleRow({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.accent,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Semantics(
      button: true,
      excludeSemantics: true,
      label: '$title. $subtitle',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          hoverColor: accent.withValues(alpha: .035),
          focusColor: accent.withValues(alpha: .05),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 18),
            child: Row(
              children: [
                SizedBox(width: 54, child: Icon(icon, color: accent, size: 30)),
                const SizedBox(width: 12),
                Expanded(
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
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: textTheme.bodySmall?.copyWith(
                          color: _mutedInkColor,
                          height: 1.45,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 14),
                Icon(
                  Icons.arrow_forward_rounded,
                  color: _mutedInkColor.withValues(alpha: .65),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
