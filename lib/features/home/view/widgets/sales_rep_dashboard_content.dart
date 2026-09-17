import 'package:fatoora/core/class/handilingdataview.dart';
import 'package:fatoora/core/class/statusrequest.dart';
import 'package:fatoora/core/constants/color.dart';
import 'package:fatoora/core/motion/fatoora_motion.dart';
import 'package:fatoora/core/motion/fatoora_motion_widgets.dart';
import 'package:fatoora/features/financial/controllers/sales_rep_dashboard_controller.dart';
import 'package:fatoora/features/home/view/widgets/sales_rep_dashboard_actions.dart';
import 'package:fatoora/features/home/view/widgets/sales_rep_dashboard_header.dart';
import 'package:fatoora/features/home/view/widgets/sales_rep_dashboard_layout.dart';
import 'package:fatoora/features/home/view/widgets/sales_rep_dashboard_panels.dart';
import 'package:fatoora/features/home/view/widgets/sales_rep_dashboard_primitives.dart';
import 'package:fatoora/features/home/view/widgets/sales_rep_overview_metrics.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class SalesRepDashboardBody extends StatelessWidget {
  const SalesRepDashboardBody({
    super.key,
    required this.name,
    required this.controller,
  });

  final String name;
  final SalesRepDashboardController controller;

  @override
  Widget build(BuildContext context) {
    final child = switch (controller.statusRequest) {
      StatusRequest.loading => const _DashboardSkeleton(
        key: ValueKey('loading'),
      ),
      StatusRequest.success || StatusRequest.none => _DashboardContent(
        key: const ValueKey('content'),
        name: name,
        controller: controller,
      ),
      _ => HandilingDataView(
        key: const ValueKey('error'),
        statusrequest: controller.statusRequest,
        errorMessage: controller.loadErrorMessageKey.tr,
        retryLabel: 'items_retry'.tr,
        onRetry: controller.loadDashboard,
        widget: const SizedBox.shrink(),
      ),
    };
    return FatooraMotionSwitcher(
      duration: FatooraMotion.standard,
      reverseDuration: FatooraMotion.quick,
      child: child,
    );
  }
}

class _DashboardContent extends StatelessWidget {
  const _DashboardContent({
    super.key,
    required this.name,
    required this.controller,
  });

  final String name;
  final SalesRepDashboardController controller;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      color: Theme.of(context).colorScheme.primary,
      onRefresh: controller.refreshDashboard,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final horizontalPadding = SalesRepDashboardLayout.horizontalPadding(
            constraints.maxWidth,
          );
          return SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.fromLTRB(
              horizontalPadding,
              16,
              horizontalPadding,
              40,
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: SalesRepDashboardLayout.maxContentWidth,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SalesRepDashboardHeader(name: name, controller: controller),
                    const SizedBox(height: 20),
                    SalesRepOverviewMetrics(controller: controller),
                    const SizedBox(height: 20),
                    if (SalesRepDashboardLayout.useDesktopColumns(
                      constraints.maxWidth,
                    ))
                      _DesktopDashboardColumns(controller: controller)
                    else
                      _MobileDashboardSections(controller: controller),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _DesktopDashboardColumns extends StatelessWidget {
  const _DesktopDashboardColumns({required this.controller});

  final SalesRepDashboardController controller;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 2,
          child: Column(
            children: [
              SalesRepPrimaryActions(controller: controller),
              const SizedBox(height: 20),
              SalesRepSecondaryServices(controller: controller),
            ],
          ),
        ),
        const SizedBox(width: 20),
        Expanded(
          child: Column(
            children: [
              SalesRepNeedsAttentionPanel(controller: controller),
              const SizedBox(height: 20),
              SalesRepRecentActivityPanel(controller: controller),
            ],
          ),
        ),
      ],
    );
  }
}

class _MobileDashboardSections extends StatelessWidget {
  const _MobileDashboardSections({required this.controller});

  final SalesRepDashboardController controller;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SalesRepPrimaryActions(controller: controller),
        const SizedBox(height: 20),
        SalesRepSecondaryServices(controller: controller),
        const SizedBox(height: 20),
        SalesRepNeedsAttentionPanel(controller: controller),
        const SizedBox(height: 20),
        SalesRepRecentActivityPanel(controller: controller),
      ],
    );
  }
}

class _DashboardSkeleton extends StatelessWidget {
  const _DashboardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: SalesRepDashboardLayout.maxContentWidth,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _SkeletonBlock(height: 80),
              const SizedBox(height: 20),
              const _SkeletonLine(width: 150),
              const SizedBox(height: 10),
              LayoutBuilder(
                builder: (context, constraints) {
                  final columns = SalesRepDashboardLayout.metricColumns(
                    constraints.maxWidth,
                  );
                  return GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: 4,
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: columns,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                      mainAxisExtent: SalesRepDashboardLayout.metricHeight(
                        MediaQuery.textScalerOf(context).scale(1),
                      ),
                    ),
                    itemBuilder: (_, _) => const _SkeletonBlock(height: 118),
                  );
                },
              ),
              const SizedBox(height: 20),
              const _SkeletonLine(width: 130),
              const SizedBox(height: 10),
              LayoutBuilder(
                builder: (context, constraints) => GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: 4,
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount:
                        SalesRepDashboardLayout.primaryActionColumns(
                          constraints.maxWidth,
                        ),
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    mainAxisExtent: SalesRepDashboardLayout.primaryActionHeight(
                      MediaQuery.textScalerOf(context).scale(1),
                      columns: SalesRepDashboardLayout.primaryActionColumns(
                        constraints.maxWidth,
                      ),
                    ),
                  ),
                  itemBuilder: (_, _) => const _SkeletonBlock(height: 132),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SkeletonBlock extends StatelessWidget {
  const _SkeletonBlock({required this.height});

  final double height;

  @override
  Widget build(BuildContext context) => SalesRepDashboardSurface(
    padding: EdgeInsets.zero,
    child: SizedBox(
      height: height,
      child: ColoredBox(color: context.appSurfaceMuted),
    ),
  );
}

class _SkeletonLine extends StatelessWidget {
  const _SkeletonLine({required this.width});

  final double width;

  @override
  Widget build(BuildContext context) => Align(
    alignment: AlignmentDirectional.centerStart,
    child: Container(
      width: width,
      height: 18,
      decoration: BoxDecoration(
        color: context.appSurfaceRaised,
        borderRadius: BorderRadius.circular(8),
      ),
    ),
  );
}
