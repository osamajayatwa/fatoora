import 'package:fatoora/core/constants/color.dart';
import 'package:fatoora/features/admin_dashboard/model/admin_dashboard_models.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class QuickActionsButton extends StatelessWidget {
  const QuickActionsButton({
    super.key,
    required this.actions,
    required this.onSelected,
    this.light = false,
  });

  final List<DashboardQuickAction> actions;
  final ValueChanged<String> onSelected;
  final bool light;

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: () => QuickActionsSheet.show(
        context,
        actions: actions,
        onSelected: onSelected,
      ),
      style: FilledButton.styleFrom(
        backgroundColor: light ? Colors.white : AppColor.primaryColor,
        foregroundColor: light ? AppColor.primaryColor : Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
      icon: const Icon(Icons.bolt_rounded, size: 20),
      label: Text('dashboard_quick_actions'.tr),
    );
  }
}

class QuickActionsSheet extends StatelessWidget {
  const QuickActionsSheet({
    super.key,
    required this.actions,
    required this.onSelected,
  });

  final List<DashboardQuickAction> actions;
  final ValueChanged<String> onSelected;

  static Future<void> show(
    BuildContext context, {
    required List<DashboardQuickAction> actions,
    required ValueChanged<String> onSelected,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) =>
          QuickActionsSheet(actions: actions, onSelected: onSelected),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final maxHeight = MediaQuery.sizeOf(context).height * 0.9;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(18, 4, 18, 18 + bottomInset),
        child: Center(
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: 680, maxHeight: maxHeight),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'dashboard_quick_actions'.tr,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    'dashboard_choose_action'.tr,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: context.appMutedText,
                    ),
                  ),
                  const SizedBox(height: 18),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final columns = constraints.maxWidth >= 560
                          ? 4
                          : constraints.maxWidth >= 360
                          ? 2
                          : 1;
                      const spacing = 12.0;
                      final tileWidth =
                          (constraints.maxWidth - (columns - 1) * spacing) /
                          columns;
                      return Wrap(
                        spacing: spacing,
                        runSpacing: spacing,
                        children: [
                          for (final action in actions)
                            SizedBox(
                              width: tileWidth,
                              child: QuickActionTile(
                                action: action,
                                onTap: () {
                                  Navigator.of(context).pop();
                                  onSelected(action.route);
                                },
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class QuickActionTile extends StatelessWidget {
  const QuickActionTile({super.key, required this.action, required this.onTap});

  final DashboardQuickAction action;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: context.appSurfaceMuted,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(17),
        side: BorderSide(color: context.appBorder),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(17),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(action.icon, color: scheme.primary, size: 23),
              ),
              const SizedBox(height: 10),
              Text(
                action.labelKey.tr,
                softWrap: true,
                textAlign: TextAlign.center,
                style: Theme.of(
                  context,
                ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
