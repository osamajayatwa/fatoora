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
    return Padding(
      padding: EdgeInsets.fromLTRB(18, 4, 18, 18 + bottomInset),
      child: Center(
        heightFactor: 1,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
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
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: context.appMutedText),
              ),
              const SizedBox(height: 18),
              LayoutBuilder(
                builder: (context, constraints) {
                  final columns = constraints.maxWidth >= 560 ? 4 : 2;
                  return GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: actions.length,
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: columns,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                      childAspectRatio: columns == 4 ? 1.08 : 1.35,
                    ),
                    itemBuilder: (context, index) => QuickActionTile(
                      action: actions[index],
                      onTap: () {
                        Navigator.of(context).pop();
                        onSelected(actions[index].route);
                      },
                    ),
                  );
                },
              ),
            ],
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
            mainAxisAlignment: MainAxisAlignment.center,
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
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
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
