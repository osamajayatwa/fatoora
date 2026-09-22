import 'package:fatoora/app/routes/app_routes.dart';
import 'package:fatoora/core/settings/business_permission_resolver.dart';
import 'package:fatoora/features/auth/data/repositories/auth_repository.dart';
import 'package:flutter/material.dart';

class BusinessNavigationAccess {
  const BusinessNavigationAccess({required this.role, this.permissions});

  final String role;
  final EffectiveBusinessPermissions? permissions;

  bool get isAdmin => permissions?.isAdmin ?? role == AuthRepository.adminRole;

  bool get isSalesRep =>
      permissions?.isSalesRep ?? role == AuthRepository.salesRepRole;

  String get homeRoute => isAdmin ? AppRoute.adminHome : AppRoute.home;
}

class BusinessNavigationDestination {
  const BusinessNavigationDestination({
    required this.labelKey,
    required this.icon,
    required this.selectedIcon,
    required this.route,
    this.routePrefixes = const [],
  });

  final String labelKey;
  final IconData icon;
  final IconData selectedIcon;
  final String route;
  final List<String> routePrefixes;

  bool matches(String routeName) {
    final path = Uri.tryParse(routeName)?.path ?? routeName;
    if (path == route) return true;
    return routePrefixes.any(
      (prefix) => path == prefix || path.startsWith('$prefix/'),
    );
  }
}

abstract final class BusinessNavigationCatalog {
  static List<BusinessNavigationDestination> primary(
    BusinessNavigationAccess access,
  ) => [
    BusinessNavigationDestination(
      labelKey: 'dashboard_home',
      icon: Icons.home_outlined,
      selectedIcon: Icons.home_rounded,
      route: access.homeRoute,
    ),
    const BusinessNavigationDestination(
      labelKey: 'dashboard_invoices',
      icon: Icons.receipt_long_outlined,
      selectedIcon: Icons.receipt_long_rounded,
      route: AppRoute.invoices,
      routePrefixes: [AppRoute.invoices],
    ),
    const BusinessNavigationDestination(
      labelKey: 'dashboard_customers',
      icon: Icons.people_alt_outlined,
      selectedIcon: Icons.people_alt_rounded,
      route: AppRoute.customers,
      routePrefixes: [AppRoute.customers],
    ),
  ];

  static List<BusinessNavigationDestination> more(
    BusinessNavigationAccess access,
  ) {
    if (access.isAdmin) return _adminMore;
    if (access.isSalesRep) return _salesRepMore;
    return const [];
  }

  static List<BusinessNavigationDestination> desktop(
    BusinessNavigationAccess access,
  ) => [...primary(access), ...more(access)];

  static bool isMoreRoute(BusinessNavigationAccess access, String routeName) =>
      more(access).any((destination) => destination.matches(routeName));

  static int primaryIndex(BusinessNavigationAccess access, String routeName) {
    final destinations = primary(access);
    for (var index = 0; index < destinations.length; index++) {
      if (destinations[index].matches(routeName)) return index;
    }
    return isMoreRoute(access, routeName) ? 3 : 0;
  }

  static const _adminMore = <BusinessNavigationDestination>[
    BusinessNavigationDestination(
      labelKey: 'dashboard_quotations',
      icon: Icons.request_quote_outlined,
      selectedIcon: Icons.request_quote_rounded,
      route: AppRoute.quotations,
      routePrefixes: [AppRoute.quotations],
    ),
    BusinessNavigationDestination(
      labelKey: 'dashboard_receipts',
      icon: Icons.receipt_outlined,
      selectedIcon: Icons.receipt_rounded,
      route: AppRoute.receipts,
      routePrefixes: [AppRoute.receipts],
    ),
    BusinessNavigationDestination(
      labelKey: 'sales_returns',
      icon: Icons.assignment_return_outlined,
      selectedIcon: Icons.assignment_return_rounded,
      route: AppRoute.salesReturns,
      routePrefixes: [AppRoute.salesReturns],
    ),
    BusinessNavigationDestination(
      labelKey: 'admin_users',
      icon: Icons.manage_accounts_outlined,
      selectedIcon: Icons.manage_accounts_rounded,
      route: AppRoute.adminUsers,
      routePrefixes: [AppRoute.adminUsers],
    ),
    BusinessNavigationDestination(
      labelKey: 'financial_receivables',
      icon: Icons.account_balance_outlined,
      selectedIcon: Icons.account_balance_rounded,
      route: AppRoute.receivables,
    ),
    BusinessNavigationDestination(
      labelKey: 'financial_cash',
      icon: Icons.account_balance_wallet_outlined,
      selectedIcon: Icons.account_balance_wallet_rounded,
      route: AppRoute.cashMovements,
    ),
    BusinessNavigationDestination(
      labelKey: 'financial_ledger',
      icon: Icons.menu_book_outlined,
      selectedIcon: Icons.menu_book_rounded,
      route: AppRoute.financialLedger,
      routePrefixes: [AppRoute.financialLedger],
    ),
    BusinessNavigationDestination(
      labelKey: 'expenses',
      icon: Icons.request_page_outlined,
      selectedIcon: Icons.request_page_rounded,
      route: AppRoute.expenses,
      routePrefixes: [AppRoute.expenses],
    ),
    BusinessNavigationDestination(
      labelKey: 'dashboard_items',
      icon: Icons.inventory_2_outlined,
      selectedIcon: Icons.inventory_2_rounded,
      route: AppRoute.adminItems,
      routePrefixes: ['/items', AppRoute.adminItems],
    ),
    BusinessNavigationDestination(
      labelKey: 'inventory',
      icon: Icons.warehouse_outlined,
      selectedIcon: Icons.warehouse_rounded,
      route: AppRoute.inventory,
      routePrefixes: [AppRoute.inventory],
    ),
    BusinessNavigationDestination(
      labelKey: 'rep_inventory_transfers',
      icon: Icons.swap_horiz_outlined,
      selectedIcon: Icons.swap_horiz_rounded,
      route: AppRoute.repInventoryTransfers,
      routePrefixes: [
        AppRoute.repInventoryTransfers,
        AppRoute.repInventoryTransferForm,
      ],
    ),
    BusinessNavigationDestination(
      labelKey: 'dashboard_account_statement',
      icon: Icons.article_outlined,
      selectedIcon: Icons.article_rounded,
      route: AppRoute.statements,
      routePrefixes: [AppRoute.statements],
    ),
    BusinessNavigationDestination(
      labelKey: 'audit_log_title',
      icon: Icons.manage_history_outlined,
      selectedIcon: Icons.manage_history_rounded,
      route: AppRoute.adminAuditLog,
      routePrefixes: [AppRoute.adminAuditLog],
    ),
    BusinessNavigationDestination(
      labelKey: 'dashboard_settings',
      icon: Icons.settings_outlined,
      selectedIcon: Icons.settings_rounded,
      route: AppRoute.settings,
      routePrefixes: [AppRoute.settings],
    ),
  ];

  static const _salesRepMore = <BusinessNavigationDestination>[
    BusinessNavigationDestination(
      labelKey: 'dashboard_quotations',
      icon: Icons.request_quote_outlined,
      selectedIcon: Icons.request_quote_rounded,
      route: AppRoute.quotations,
      routePrefixes: [AppRoute.quotations],
    ),
    BusinessNavigationDestination(
      labelKey: 'dashboard_receipts',
      icon: Icons.receipt_outlined,
      selectedIcon: Icons.receipt_rounded,
      route: AppRoute.receipts,
      routePrefixes: [AppRoute.receipts],
    ),
    BusinessNavigationDestination(
      labelKey: 'sales_returns',
      icon: Icons.assignment_return_outlined,
      selectedIcon: Icons.assignment_return_rounded,
      route: AppRoute.salesReturns,
      routePrefixes: [AppRoute.salesReturns],
    ),
    BusinessNavigationDestination(
      labelKey: 'financial_receivables',
      icon: Icons.account_balance_outlined,
      selectedIcon: Icons.account_balance_rounded,
      route: AppRoute.receivables,
    ),
    BusinessNavigationDestination(
      labelKey: 'financial_cash',
      icon: Icons.account_balance_wallet_outlined,
      selectedIcon: Icons.account_balance_wallet_rounded,
      route: AppRoute.cashMovements,
    ),
    BusinessNavigationDestination(
      labelKey: 'my_expenses',
      icon: Icons.request_page_outlined,
      selectedIcon: Icons.request_page_rounded,
      route: AppRoute.expenses,
      routePrefixes: [AppRoute.expenses],
    ),
    BusinessNavigationDestination(
      labelKey: 'rep_inventory_my_inventory',
      icon: Icons.inventory_2_outlined,
      selectedIcon: Icons.inventory_2_rounded,
      route: AppRoute.repInventory,
      routePrefixes: [AppRoute.repInventory],
    ),
    BusinessNavigationDestination(
      labelKey: 'dashboard_account_statement',
      icon: Icons.article_outlined,
      selectedIcon: Icons.article_rounded,
      route: AppRoute.statements,
      routePrefixes: [AppRoute.statements],
    ),
    BusinessNavigationDestination(
      labelKey: 'dashboard_settings',
      icon: Icons.settings_outlined,
      selectedIcon: Icons.settings_rounded,
      route: AppRoute.settings,
      routePrefixes: [AppRoute.settings],
    ),
  ];
}
