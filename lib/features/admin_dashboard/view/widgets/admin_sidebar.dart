import 'package:fatoora/core/constants/color.dart';
import 'package:fatoora/app/routes/app_routes.dart';
import 'package:fatoora/core/localization/changelocal.dart';
import 'package:fatoora/features/admin_dashboard/controller/admin_dashboard_controller.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class AdminSidebar extends StatelessWidget {
  const AdminSidebar({super.key, this.showCollapseButton = false});

  final bool showCollapseButton;

  static const _items = [
    _SidebarItem('dashboard_home', Icons.home_rounded, AppRoute.adminHome),
    _SidebarItem(
      'dashboard_invoices',
      Icons.receipt_long_outlined,
      AppRoute.invoices,
    ),
    _SidebarItem(
      'dashboard_quotations',
      Icons.request_quote_outlined,
      AppRoute.quotations,
    ),
    _SidebarItem(
      'dashboard_receipts',
      Icons.receipt_outlined,
      AppRoute.receipts,
    ),
    _SidebarItem(
      'sales_returns',
      Icons.assignment_return_outlined,
      AppRoute.salesReturns,
    ),
    _SidebarItem(
      'admin_users',
      Icons.manage_accounts_outlined,
      AppRoute.adminUsers,
    ),
    _SidebarItem(
      'financial_receivables',
      Icons.account_balance_outlined,
      AppRoute.receivables,
    ),
    _SidebarItem(
      'financial_cash',
      Icons.account_balance_wallet_outlined,
      AppRoute.cashMovements,
    ),
    _SidebarItem('expenses', Icons.receipt_long_outlined, AppRoute.expenses),
    _SidebarItem(
      'dashboard_customers',
      Icons.people_alt_outlined,
      AppRoute.customers,
    ),
    _SidebarItem(
      'dashboard_items',
      Icons.inventory_2_outlined,
      AppRoute.adminItems,
    ),
    _SidebarItem('inventory', Icons.warehouse_outlined, AppRoute.inventory),
    _SidebarItem(
      'rep_inventory_transfers',
      Icons.swap_horiz_rounded,
      AppRoute.repInventoryTransfers,
    ),
    _SidebarItem(
      'dashboard_account_statement',
      Icons.article_outlined,
      AppRoute.statements,
    ),
    _SidebarItem(
      'dashboard_settings',
      Icons.settings_outlined,
      AppRoute.settings,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return GetBuilder<AdminDashboardController>(
      builder: (controller) {
        final localeController = Get.isRegistered<LocaleController>()
            ? Get.find<LocaleController>()
            : null;
        Widget sidebar(bool isRtl) => _SidebarContent(
          controller: controller,
          isRtl: isRtl,
          showCollapseButton: showCollapseButton,
        );

        if (localeController == null) {
          return sidebar(Directionality.of(context) == TextDirection.rtl);
        }

        return Obx(() => sidebar(localeController.isRtl));
      },
    );
  }
}

class _SidebarContent extends StatelessWidget {
  const _SidebarContent({
    required this.controller,
    required this.isRtl,
    required this.showCollapseButton,
  });

  final AdminDashboardController controller;
  final bool isRtl;
  final bool showCollapseButton;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: isRtl ? TextDirection.rtl : TextDirection.ltr,
      child: ColoredBox(
        color: context.appSurface,
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: EdgeInsetsDirectional.fromSTEB(
                  24,
                  22,
                  showCollapseButton ? 10 : 24,
                  20,
                ),
                child: Row(
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        gradient: AppColor.mainGradient,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(
                        Icons.receipt_long_rounded,
                        color: Colors.white,
                        size: 25,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'fatoora'.tr,
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(
                                  color: context.appText,
                                  fontWeight: FontWeight.w800,
                                ),
                          ),
                          Text(
                            'dashboard_management_system'.tr,
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(color: context.appMutedText),
                          ),
                        ],
                      ),
                    ),
                    if (showCollapseButton)
                      IconButton(
                        tooltip: 'close'.tr,
                        onPressed: controller.hideSidebar,
                        icon: Transform(
                          alignment: Alignment.center,
                          transform: Matrix4.identity()
                            ..scale(isRtl ? -1.0 : 1.0, 1.0),
                          child: const Icon(Icons.menu_open_rounded),
                        ),
                        color: context.appMutedText,
                      ),
                  ],
                ),
              ),
              Divider(height: 1, color: context.appBorder),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 18,
                  ),
                  itemCount: AdminSidebar._items.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 6),
                  itemBuilder: (context, index) {
                    final item = AdminSidebar._items[index];
                    final itemRoutes = {
                      AppRoute.adminItems,
                      AppRoute.adminAddItem,
                      AppRoute.adminEditItem,
                      AppRoute.adminItemDetails,
                    };
                    final inventoryRoutes = {
                      AppRoute.inventory,
                      AppRoute.stockMovements,
                      AppRoute.inventoryAdjustment,
                      AppRoute.itemStockDetails,
                    };
                    final repInventoryRoutes = {
                      AppRoute.repInventory,
                      AppRoute.repInventoryTransfers,
                      AppRoute.repInventoryTransferForm,
                      AppRoute.repInventoryTransferDetails,
                    };
                    final invoiceRoutes = {
                      AppRoute.invoices,
                      AppRoute.invoiceForm,
                      AppRoute.invoiceDetails,
                    };
                    final quotationRoutes = {
                      AppRoute.quotations,
                      AppRoute.createQuotation,
                      AppRoute.quotationDetails,
                    };
                    final receiptRoutes = {
                      AppRoute.receipts,
                      AppRoute.createReceipt,
                      AppRoute.receiptDetails,
                    };
                    final salesReturnRoutes = {
                      AppRoute.salesReturns,
                      AppRoute.createSalesReturn,
                      AppRoute.salesReturnDetails,
                    };
                    final expenseRoutes = {
                      AppRoute.expenses,
                      AppRoute.createExpense,
                      AppRoute.expenseDetails,
                    };
                    final userRoutes = {
                      AppRoute.adminUsers,
                      AppRoute.pendingUsers,
                      AppRoute.salesReps,
                    };
                    final statementRoutes = {
                      AppRoute.statements,
                      AppRoute.customerStatement,
                    };
                    final selected =
                        Get.currentRoute == item.route ||
                        (item.route == AppRoute.adminItems &&
                            itemRoutes.contains(Get.currentRoute)) ||
                        (item.route == AppRoute.inventory &&
                            inventoryRoutes.contains(Get.currentRoute)) ||
                        (item.route == AppRoute.repInventoryTransfers &&
                            repInventoryRoutes.contains(Get.currentRoute)) ||
                        (item.route == AppRoute.invoices &&
                            invoiceRoutes.contains(Get.currentRoute)) ||
                        (item.route == AppRoute.quotations &&
                            quotationRoutes.contains(Get.currentRoute)) ||
                        (item.route == AppRoute.receipts &&
                            receiptRoutes.contains(Get.currentRoute)) ||
                        (item.route == AppRoute.salesReturns &&
                            salesReturnRoutes.contains(Get.currentRoute)) ||
                        (item.route == AppRoute.expenses &&
                            expenseRoutes.contains(Get.currentRoute)) ||
                        (item.route == AppRoute.adminUsers &&
                            userRoutes.contains(Get.currentRoute)) ||
                        (item.route == AppRoute.statements &&
                            statementRoutes.contains(Get.currentRoute));
                    return _SidebarTile(
                      item: item,
                      selected: selected,
                      isRtl: isRtl,
                      onTap: () {
                        final scaffold = Scaffold.maybeOf(context);
                        if (scaffold?.isDrawerOpen ?? false) {
                          Navigator.of(context).pop();
                        }
                        controller.navigateTo(item.route);
                      },
                    );
                  },
                ),
              ),
              Divider(height: 1, color: context.appBorder),
              Padding(
                padding: const EdgeInsets.all(14),
                child: _SidebarTile(
                  item: const _SidebarItem(
                    'dashboard_logout',
                    Icons.logout_rounded,
                    '',
                  ),
                  selected: false,
                  isRtl: isRtl,
                  danger: true,
                  loading: controller.isLoggingOut,
                  onTap: controller.confirmLogout,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SidebarTile extends StatelessWidget {
  const _SidebarTile({
    required this.item,
    required this.selected,
    required this.isRtl,
    required this.onTap,
    this.danger = false,
    this.loading = false,
  });

  final _SidebarItem item;
  final bool selected;
  final bool isRtl;
  final VoidCallback onTap;
  final bool danger;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final foreground = danger
        ? AppColor.error
        : selected
        ? Colors.white
        : context.appText;
    return Material(
      color: selected ? AppColor.primaryColor : Colors.transparent,
      borderRadius: BorderRadius.circular(13),
      child: InkWell(
        borderRadius: BorderRadius.circular(13),
        onTap: loading ? null : onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          child: Row(
            textDirection: isRtl ? TextDirection.rtl : TextDirection.ltr,
            children: [
              if (loading)
                SizedBox(
                  width: 21,
                  height: 21,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: foreground,
                  ),
                )
              else
                Icon(item.icon, size: 22, color: foreground),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  item.labelKey.tr,
                  textDirection: isRtl ? TextDirection.rtl : TextDirection.ltr,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: foreground,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                  ),
                ),
              ),
              if (selected)
                Icon(Icons.chevron_right_rounded, size: 20, color: foreground),
            ],
          ),
        ),
      ),
    );
  }
}

class _SidebarItem {
  const _SidebarItem(this.labelKey, this.icon, this.route);

  final String labelKey;
  final IconData icon;
  final String route;
}
