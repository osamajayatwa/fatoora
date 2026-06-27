import 'package:fatoora/core/constants/color.dart';
import 'package:fatoora/app/routes/app_routes.dart';
import 'package:fatoora/features/admin_dashboard/controller/admin_dashboard_controller.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class AdminSidebar extends StatelessWidget {
  const AdminSidebar({super.key});

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
        return ColoredBox(
          color: AppColor.surface,
          child: SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 22, 24, 20),
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
                          color: AppColor.surface,
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
                                    color: AppColor.secondaryColor,
                                    fontWeight: FontWeight.w800,
                                  ),
                            ),
                            Text(
                              'dashboard_management_system'.tr,
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(color: AppColor.grey),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1, color: Color(0xFFECEEF3)),
                Expanded(
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 18,
                    ),
                    itemCount: _items.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 6),
                    itemBuilder: (context, index) {
                      final item = _items[index];
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
                      final userRoutes = {
                        AppRoute.adminUsers,
                        AppRoute.pendingUsers,
                        AppRoute.salesReps,
                      };
                      final selected =
                          Get.currentRoute == item.route ||
                          (item.route == AppRoute.adminItems &&
                              itemRoutes.contains(Get.currentRoute)) ||
                          (item.route == AppRoute.inventory &&
                              inventoryRoutes.contains(Get.currentRoute)) ||
                          (item.route == AppRoute.invoices &&
                              invoiceRoutes.contains(Get.currentRoute)) ||
                          (item.route == AppRoute.quotations &&
                              quotationRoutes.contains(Get.currentRoute)) ||
                          (item.route == AppRoute.receipts &&
                              receiptRoutes.contains(Get.currentRoute)) ||
                          (item.route == AppRoute.salesReturns &&
                              salesReturnRoutes.contains(Get.currentRoute)) ||
                          (item.route == AppRoute.adminUsers &&
                              userRoutes.contains(Get.currentRoute));
                      return _SidebarTile(
                        item: item,
                        selected: selected,
                        onTap: () => controller.navigateTo(item.route),
                      );
                    },
                  ),
                ),
                const Divider(height: 1, color: Color(0xFFECEEF3)),
                Padding(
                  padding: const EdgeInsets.all(14),
                  child: _SidebarTile(
                    item: const _SidebarItem(
                      'dashboard_logout',
                      Icons.logout_rounded,
                      '',
                    ),
                    selected: false,
                    danger: true,
                    loading: controller.isLoggingOut,
                    onTap: controller.confirmLogout,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _SidebarTile extends StatelessWidget {
  const _SidebarTile({
    required this.item,
    required this.selected,
    required this.onTap,
    this.danger = false,
    this.loading = false,
  });

  final _SidebarItem item;
  final bool selected;
  final VoidCallback onTap;
  final bool danger;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final foreground = danger
        ? AppColor.error
        : selected
        ? AppColor.surface
        : AppColor.secondaryColor;
    return Material(
      color: selected ? AppColor.primaryColor : Colors.transparent,
      borderRadius: BorderRadius.circular(13),
      child: InkWell(
        borderRadius: BorderRadius.circular(13),
        onTap: loading ? null : onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          child: Row(
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
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: foreground,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                  ),
                ),
              ),
              if (selected)
                Icon(
                  Directionality.of(context) == TextDirection.rtl
                      ? Icons.chevron_left_rounded
                      : Icons.chevron_right_rounded,
                  size: 20,
                  color: foreground,
                ),
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
