import 'dart:async';

import 'package:fatoora/app/routes/app_routes.dart';
import 'package:fatoora/core/constants/color.dart';
import 'package:fatoora/core/localization/changelocal.dart';
import 'package:fatoora/core/motion/fatoora_motion.dart';
import 'package:fatoora/core/motion/fatoora_motion_widgets.dart';
import 'package:fatoora/core/motion/fatoora_overlays.dart';
import 'package:fatoora/core/services/services.dart';
import 'package:fatoora/core/widgets/fatoora_app_bar.dart';
import 'package:fatoora/features/auth/data/repositories/auth_repository.dart';
import 'package:fatoora/features/auth/utils/auth_session.dart';
import 'package:fatoora/features/invoices/controllers/invoices_list_controller.dart';
import 'package:fatoora/features/shared/navigation/business_navigation_destination.dart';
import 'package:fatoora/features/shared/navigation/business_navigation_router.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

abstract final class AdaptiveShellBreakpoints {
  static const double mobile = 600;
  static const double desktop = 1080;

  static AdaptiveShellLayout forWidth(double width) {
    if (width < mobile) return AdaptiveShellLayout.mobile;
    if (width < desktop) return AdaptiveShellLayout.tablet;
    return AdaptiveShellLayout.desktop;
  }
}

enum AdaptiveShellLayout { mobile, tablet, desktop }

class AdaptiveBusinessShell extends StatefulWidget {
  const AdaptiveBusinessShell({
    super.key,
    required this.child,
    required this.title,
    this.showBackButton = false,
    this.onBack,
    this.navigationAccess,
  });

  final Widget child;
  final String title;
  final bool showBackButton;
  final VoidCallback? onBack;
  final BusinessNavigationAccess? navigationAccess;

  @override
  State<AdaptiveBusinessShell> createState() => _AdaptiveBusinessShellState();
}

class _AdaptiveBusinessShellState extends State<AdaptiveBusinessShell> {
  bool _desktopSidebarVisible = true;
  bool _isLoggingOut = false;

  MyServices get _services => Get.find<MyServices>();

  BusinessNavigationAccess get _access =>
      widget.navigationAccess ??
      BusinessNavigationAccess(
        role: _services.sharedPreferences.getString('role') ?? '',
      );

  bool get _isNavigationRoot {
    final currentPath =
        Uri.tryParse(Get.currentRoute)?.path ?? Get.currentRoute;
    return BusinessNavigationCatalog.desktop(
      _access,
    ).any((destination) => destination.route == currentPath);
  }

  bool get _showBackButton => widget.showBackButton && !_isNavigationRoot;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final layout = AdaptiveShellBreakpoints.forWidth(constraints.maxWidth);
        return switch (layout) {
          AdaptiveShellLayout.mobile => _buildMobile(context),
          AdaptiveShellLayout.tablet => _buildTablet(context),
          AdaptiveShellLayout.desktop => _buildDesktop(context),
        };
      },
    );
  }

  Widget _buildMobile(BuildContext context) {
    final showRootNavigation = !_showBackButton;
    return Scaffold(
      key: const ValueKey('adaptive-shell-mobile'),
      backgroundColor: context.appBackground,
      appBar: _buildHeader(compact: true),
      body: SafeArea(top: false, child: widget.child),
      extendBody: false,
      floatingActionButton: showRootNavigation ? _buildCreateFab() : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      bottomNavigationBar: showRootNavigation
          ? _BusinessBottomNavigation(
              access: _access,
              currentRoute: Get.currentRoute,
              onMore: () => _showMore(context),
              onNavigate: _navigateRoot,
            )
          : null,
    );
  }

  Widget _buildTablet(BuildContext context) {
    return Scaffold(
      key: const ValueKey('adaptive-shell-tablet'),
      backgroundColor: context.appBackground,
      body: Row(
        children: [
          _BusinessNavigationRail(
            access: _access,
            currentRoute: Get.currentRoute,
            onCreateInvoice: _createInvoice,
            onMore: () => _showMore(context),
            onNavigate: _navigateRoot,
          ),
          VerticalDivider(width: 1, color: context.appBorder),
          Expanded(child: _contentPane(compactHeader: false)),
        ],
      ),
    );
  }

  Widget _buildDesktop(BuildContext context) {
    return Scaffold(
      key: const ValueKey('adaptive-shell-desktop'),
      backgroundColor: context.appBackground,
      body: Row(
        children: [
          if (_desktopSidebarVisible)
            SizedBox(
              width: 272,
              child: _BusinessSidebar(
                access: _access,
                currentRoute: Get.currentRoute,
                loggingOut: _isLoggingOut,
                onCollapse: () =>
                    setState(() => _desktopSidebarVisible = false),
                onCreateInvoice: _createInvoice,
                onNavigate: _navigateRoot,
                onLogout: _confirmLogout,
              ),
            ),
          if (_desktopSidebarVisible)
            VerticalDivider(width: 1, color: context.appBorder),
          Expanded(child: _contentPane(compactHeader: false)),
        ],
      ),
    );
  }

  Widget _contentPane({required bool compactHeader}) {
    final header = _buildHeader(
      compact: compactHeader,
      showMenu: !_desktopSidebarVisible,
    );
    return Column(
      children: [
        SizedBox(height: header.preferredSize.height, child: header),
        Expanded(child: SafeArea(top: false, left: false, child: widget.child)),
      ],
    );
  }

  FatooraAppBar _buildHeader({required bool compact, bool showMenu = false}) {
    return FatooraAppBar(
      title: widget.title,
      showBackButton: _showBackButton,
      onBack: widget.onBack,
      leading: showMenu && !_showBackButton
          ? IconButton(
              tooltip: MaterialLocalizations.of(context).openAppDrawerTooltip,
              onPressed: () => setState(() => _desktopSidebarVisible = true),
              icon: const Icon(Icons.menu_rounded),
            )
          : null,
      actions: compact
          ? [
              PopupMenuButton<_HeaderAction>(
                tooltip: 'actions'.tr,
                popUpAnimationStyle: FatooraMotion.overlayStyle(context),
                onSelected: _handleHeaderAction,
                itemBuilder: (_) => [
                  _headerMenuItem(
                    _HeaderAction.language,
                    Icons.language_rounded,
                    'settings_language'.tr,
                  ),
                  _headerMenuItem(
                    _HeaderAction.theme,
                    Icons.brightness_6_outlined,
                    'settings_theme'.tr,
                  ),
                  _headerMenuItem(
                    _HeaderAction.notifications,
                    Icons.notifications_none_rounded,
                    'dashboard_notifications'.tr,
                  ),
                ],
              ),
            ]
          : [
              IconButton(
                tooltip: 'settings_language'.tr,
                onPressed: _toggleLanguage,
                icon: const Icon(Icons.language_rounded),
              ),
              IconButton(
                tooltip: 'settings_theme'.tr,
                onPressed: _toggleTheme,
                icon: Icon(
                  Theme.of(context).brightness == Brightness.dark
                      ? Icons.light_mode_outlined
                      : Icons.dark_mode_outlined,
                ),
              ),
              IconButton(
                tooltip: 'dashboard_notifications'.tr,
                onPressed: _showNotifications,
                icon: const Icon(Icons.notifications_none_rounded),
              ),
            ],
      onProfile: () => Get.toNamed(AppRoute.settings),
      profileLabel: AuthSession.cachedDisplayName(_services),
    );
  }

  PopupMenuItem<_HeaderAction> _headerMenuItem(
    _HeaderAction value,
    IconData icon,
    String label,
  ) {
    return PopupMenuItem<_HeaderAction>(
      value: value,
      child: Row(
        children: [
          Icon(icon, size: 20),
          const SizedBox(width: 12),
          Text(label),
        ],
      ),
    );
  }

  Widget _buildCreateFab() {
    return FatooraMotionReveal(
      scale: true,
      child: FloatingActionButton(
        key: const ValueKey('business-create-invoice-fab'),
        heroTag: 'business-create-invoice',
        onPressed: _createInvoice,
        tooltip: 'create_invoice'.tr,
        elevation: 5,
        highlightElevation: 8,
        backgroundColor: AppColor.primaryColor,
        foregroundColor: Colors.white,
        child: const Icon(Icons.note_add_outlined, size: 24),
      ),
    );
  }

  void _navigateRoot(String route) {
    unawaited(BusinessNavigationRouter.replaceRoot(route));
  }

  Future<void> _createInvoice() async {
    final changed = await BusinessNavigationRouter.openCreateInvoice(_services);
    if (!changed || !Get.isRegistered<InvoicesListController>()) return;
    if (Get.currentRoute == AppRoute.invoices) {
      await Get.find<InvoicesListController>().loadInvoices();
    }
  }

  Future<void> _showMore(BuildContext context) {
    return showFatooraModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => _BusinessMoreSheet(
        access: _access,
        currentRoute: Get.currentRoute,
        loggingOut: _isLoggingOut,
        onNavigate: (route) {
          Navigator.of(sheetContext).pop();
          _navigateRoot(route);
        },
        onLogout: () {
          Navigator.of(sheetContext).pop();
          unawaited(_confirmLogout());
        },
      ),
    );
  }

  void _handleHeaderAction(_HeaderAction action) {
    switch (action) {
      case _HeaderAction.language:
        _toggleLanguage();
        return;
      case _HeaderAction.theme:
        _toggleTheme();
        return;
      case _HeaderAction.notifications:
        _showNotifications();
        return;
    }
  }

  void _toggleLanguage() {
    if (!Get.isRegistered<LocaleController>()) return;
    final controller = Get.find<LocaleController>();
    controller.changeLang(controller.isRtl ? 'en' : 'ar');
  }

  void _toggleTheme() {
    if (!Get.isRegistered<LocaleController>()) return;
    Get.find<LocaleController>().changeThemeMode(
      Theme.of(context).brightness == Brightness.dark ? 'light' : 'dark',
    );
  }

  void _showNotifications() {
    Get.snackbar(
      'dashboard_notifications'.tr,
      'dashboard_notifications_message'.tr,
      snackPosition: SnackPosition.BOTTOM,
      backgroundColor: AppColor.secondaryColor,
      colorText: AppColor.surface,
    );
  }

  Future<void> _confirmLogout() async {
    if (_isLoggingOut) return;
    final confirmed = await showFatooraGetDialog<bool>(
      AlertDialog(
        title: Text('dashboard_logout'.tr),
        content: Text('dashboard_logout_confirmation'.tr),
        actions: [
          TextButton(
            onPressed: () => Get.back(result: false),
            child: Text('dashboard_cancel'.tr),
          ),
          FilledButton(
            onPressed: () => Get.back(result: true),
            style: FilledButton.styleFrom(backgroundColor: AppColor.error),
            child: Text('dashboard_logout'.tr),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _isLoggingOut = true);
    final loginRoute = _access.isAdmin
        ? AppRoute.adminLogin
        : AppRoute.userLogin;
    try {
      await AuthRepository().signOut();
    } catch (_) {
      // Clear local state even when the remote provider is unavailable.
    }
    await AuthSession.clear(_services);
    await _services.secureStorage.deleteAll();
    if (!mounted) return;
    setState(() => _isLoggingOut = false);
    Get.offAllNamed(loginRoute);
  }
}

enum _HeaderAction { language, theme, notifications }

class _BusinessBottomNavigation extends StatelessWidget {
  const _BusinessBottomNavigation({
    required this.access,
    required this.currentRoute,
    required this.onMore,
    required this.onNavigate,
  });

  final BusinessNavigationAccess access;
  final String currentRoute;
  final VoidCallback onMore;
  final ValueChanged<String> onNavigate;

  @override
  Widget build(BuildContext context) {
    final destinations = BusinessNavigationCatalog.primary(access);
    final selectedIndex = BusinessNavigationCatalog.primaryIndex(
      access,
      currentRoute,
    );
    return BottomAppBar(
      key: const ValueKey('business-bottom-navigation'),
      height: 74,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      color: context.appSurface,
      elevation: 12,
      notchMargin: 8,
      shape: const CircularNotchedRectangle(),
      child: Row(
        children: [
          Expanded(
            child: _BottomDestination(
              key: const ValueKey('business-nav-home'),
              destination: destinations[0],
              selected: selectedIndex == 0,
              onTap: () => onNavigate(destinations[0].route),
            ),
          ),
          Expanded(
            child: _BottomDestination(
              key: const ValueKey('business-nav-invoices'),
              destination: destinations[1],
              selected: selectedIndex == 1,
              onTap: () => onNavigate(destinations[1].route),
            ),
          ),
          SizedBox(
            width: 88,
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 5),
                child: Text(
                  'nav_invoice'.tr,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: AppColor.primaryColor,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: _BottomDestination(
              key: const ValueKey('business-nav-customers'),
              destination: destinations[2],
              selected: selectedIndex == 2,
              onTap: () => onNavigate(destinations[2].route),
            ),
          ),
          Expanded(
            child: _BottomDestination.more(
              key: const ValueKey('business-nav-more'),
              selected: selectedIndex == 3,
              onTap: onMore,
            ),
          ),
        ],
      ),
    );
  }
}

class _BottomDestination extends StatelessWidget {
  const _BottomDestination({
    super.key,
    required this.destination,
    required this.selected,
    required this.onTap,
  }) : isMore = false;

  const _BottomDestination.more({
    super.key,
    required this.selected,
    required this.onTap,
  }) : destination = null,
       isMore = true;

  final BusinessNavigationDestination? destination;
  final bool isMore;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final label = isMore ? 'nav_more'.tr : destination!.labelKey.tr;
    final icon = isMore
        ? (selected ? Icons.grid_view_rounded : Icons.grid_view_outlined)
        : (selected ? destination!.selectedIcon : destination!.icon);
    final color = selected ? scheme.primary : context.appMutedText;
    return Semantics(
      selected: selected,
      button: true,
      label: label,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: SizedBox.expand(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 5),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  AnimatedContainer(
                    duration: FatooraMotion.resolve(
                      context,
                      FatooraMotion.quick,
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 13,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: selected
                          ? scheme.primary.withValues(alpha: .12)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Icon(icon, size: 21, color: color),
                  ),
                  const SizedBox(height: 2),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      label,
                      maxLines: 1,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: color,
                        fontWeight: selected
                            ? FontWeight.w800
                            : FontWeight.w600,
                      ),
                    ),
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

class _BusinessNavigationRail extends StatelessWidget {
  const _BusinessNavigationRail({
    required this.access,
    required this.currentRoute,
    required this.onCreateInvoice,
    required this.onMore,
    required this.onNavigate,
  });

  final BusinessNavigationAccess access;
  final String currentRoute;
  final VoidCallback onCreateInvoice;
  final VoidCallback onMore;
  final ValueChanged<String> onNavigate;

  @override
  Widget build(BuildContext context) {
    final destinations = BusinessNavigationCatalog.primary(access);
    final selectedIndex = BusinessNavigationCatalog.primaryIndex(
      access,
      currentRoute,
    );
    return SizedBox(
      width: 72,
      child: NavigationRail(
        key: const ValueKey('business-navigation-rail'),
        minWidth: 72,
        backgroundColor: context.appSurface,
        selectedIndex: selectedIndex,
        labelType: NavigationRailLabelType.none,
        groupAlignment: -0.65,
        leading: Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 12),
          child: FloatingActionButton.small(
            heroTag: 'business-create-invoice-rail',
            tooltip: 'create_invoice'.tr,
            onPressed: onCreateInvoice,
            backgroundColor: AppColor.primaryColor,
            foregroundColor: Colors.white,
            child: const Icon(Icons.note_add_outlined),
          ),
        ),
        onDestinationSelected: (index) {
          if (index == 3) {
            onMore();
          } else {
            onNavigate(destinations[index].route);
          }
        },
        destinations: [
          for (final destination in destinations)
            NavigationRailDestination(
              icon: Tooltip(
                message: destination.labelKey.tr,
                child: Icon(destination.icon),
              ),
              selectedIcon: Icon(destination.selectedIcon),
              label: Text(destination.labelKey.tr),
            ),
          NavigationRailDestination(
            icon: Tooltip(
              message: 'nav_more'.tr,
              child: const Icon(Icons.grid_view_outlined),
            ),
            selectedIcon: const Icon(Icons.grid_view_rounded),
            label: Text('nav_more'.tr),
          ),
        ],
      ),
    );
  }
}

class _BusinessSidebar extends StatelessWidget {
  const _BusinessSidebar({
    required this.access,
    required this.currentRoute,
    required this.loggingOut,
    required this.onCollapse,
    required this.onCreateInvoice,
    required this.onNavigate,
    required this.onLogout,
  });

  final BusinessNavigationAccess access;
  final String currentRoute;
  final bool loggingOut;
  final VoidCallback onCollapse;
  final VoidCallback onCreateInvoice;
  final ValueChanged<String> onNavigate;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    final destinations = BusinessNavigationCatalog.desktop(access);
    return ColoredBox(
      key: const ValueKey('business-desktop-sidebar'),
      color: context.appSurface,
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(20, 18, 8, 14),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      gradient: AppColor.mainGradient,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(
                      Icons.receipt_long_rounded,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'fatoora'.tr,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'close'.tr,
                    onPressed: onCollapse,
                    icon: const Icon(Icons.menu_open_rounded),
                  ),
                ],
              ),
            ),
            // Padding(
            //   padding: const EdgeInsets.symmetric(horizontal: 14),
            //   child: SizedBox(
            //     width: double.infinity,
            //     child: FilledButton.icon(
            //       key: const ValueKey('business-sidebar-create-invoice'),
            //       onPressed: onCreateInvoice,
            //       icon: const Icon(Icons.note_add_outlined),
            //       label: Text('create_invoice'.tr),
            //     ),
            //   ),
            // ),
            const SizedBox(height: 12),
            Divider(height: 1, color: context.appBorder),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 14,
                ),
                itemCount: destinations.length,
                separatorBuilder: (_, _) => const SizedBox(height: 4),
                itemBuilder: (_, index) {
                  final destination = destinations[index];
                  return _SidebarDestination(
                    destination: destination,
                    selected: destination.matches(currentRoute),
                    onTap: () => onNavigate(destination.route),
                  );
                },
              ),
            ),
            Divider(height: 1, color: context.appBorder),
            Padding(
              padding: const EdgeInsets.all(12),
              child: ListTile(
                enabled: !loggingOut,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(13),
                ),
                leading: loggingOut
                    ? const FatooraProgressIndicator(size: 22, strokeWidth: 2)
                    : const Icon(Icons.logout_rounded, color: AppColor.error),
                title: Text(
                  'dashboard_logout'.tr,
                  style: const TextStyle(
                    color: AppColor.error,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                onTap: onLogout,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SidebarDestination extends StatelessWidget {
  const _SidebarDestination({
    required this.destination,
    required this.selected,
    required this.onTap,
  });

  final BusinessNavigationDestination destination;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? Colors.white : context.appText;
    return Material(
      color: selected ? AppColor.primaryColor : Colors.transparent,
      borderRadius: BorderRadius.circular(13),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(13),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Icon(
                selected ? destination.selectedIcon : destination.icon,
                color: color,
                size: 22,
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Text(
                  destination.labelKey.tr,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: color,
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BusinessMoreSheet extends StatelessWidget {
  const _BusinessMoreSheet({
    required this.access,
    required this.currentRoute,
    required this.loggingOut,
    required this.onNavigate,
    required this.onLogout,
  });

  final BusinessNavigationAccess access;
  final String currentRoute;
  final bool loggingOut;
  final ValueChanged<String> onNavigate;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    final destinations = BusinessNavigationCatalog.more(access);
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 680,
          maxHeight: MediaQuery.sizeOf(context).height * .82,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 4, 18, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'nav_more_title'.tr,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'nav_more_subtitle'.tr,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: context.appMutedText),
              ),
              const SizedBox(height: 14),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: destinations.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 4),
                  itemBuilder: (_, index) {
                    final destination = destinations[index];
                    final selected = destination.matches(currentRoute);
                    return ListTile(
                      selected: selected,
                      selectedColor: AppColor.primaryColor,
                      selectedTileColor: AppColor.primaryColor.withValues(
                        alpha: .08,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      leading: Icon(
                        selected ? destination.selectedIcon : destination.icon,
                      ),
                      title: Text(
                        destination.labelKey.tr,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      trailing: selected
                          ? const Icon(Icons.check_rounded)
                          : const Icon(Icons.chevron_right_rounded),
                      onTap: () => onNavigate(destination.route),
                    );
                  },
                ),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: loggingOut ? null : onLogout,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColor.error,
                ),
                icon: loggingOut
                    ? const FatooraProgressIndicator(size: 18, strokeWidth: 2)
                    : const Icon(Icons.logout_rounded),
                label: Text('dashboard_logout'.tr),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
