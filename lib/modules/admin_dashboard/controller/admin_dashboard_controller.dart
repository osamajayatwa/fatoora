import 'package:fatoora/core/constant/color.dart';
import 'package:fatoora/core/constant/routes.dart';
import 'package:fatoora/core/localization/changelocal.dart';
import 'package:fatoora/core/services/services.dart';
import 'package:fatoora/data/repositories/admin_auth_repository.dart';
import 'package:fatoora/modules/admin_dashboard/model/admin_dashboard_models.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class AdminDashboardController extends GetxController {
  AdminDashboardController({
    required AdminAuthRepository repository,
    required MyServices myServices,
  }) : _repository = repository,
       _myServices = myServices;

  final AdminAuthRepository _repository;
  final MyServices _myServices;

  final TextEditingController searchController = TextEditingController();
  bool isRefreshing = false;
  bool isLoggingOut = false;
  String searchQuery = '';

  String get adminName =>
      _myServices.sharedPreferences.getString('name') ?? 'dashboard_admin'.tr;

  String get adminEmail =>
      _myServices.sharedPreferences.getString('email') ?? '';

  List<DashboardStat> get stats => const [
    DashboardStat(
      titleKey: 'dashboard_customers_count',
      value: '156',
      captionKey: 'dashboard_customer',
      change: '+5%',
      icon: Icons.people_alt_outlined,
      color: Color(0xFFFF9838),
    ),
    DashboardStat(
      titleKey: 'dashboard_invoices_count',
      value: '42',
      captionKey: 'dashboard_invoice',
      change: '+5%',
      icon: Icons.receipt_long_outlined,
      color: Color(0xFF35A7FF),
    ),
    DashboardStat(
      titleKey: 'dashboard_invoice_total',
      value: '24,320.00',
      captionKey: 'dashboard_jod',
      change: '+8%',
      icon: Icons.description_outlined,
      color: Color(0xFF42C98B),
    ),
    DashboardStat(
      titleKey: 'dashboard_received_total',
      value: '18,540.00',
      captionKey: 'dashboard_jod',
      change: '+12%',
      icon: Icons.account_balance_wallet_outlined,
      color: Color(0xFF6657E8),
    ),
  ];

  List<DashboardInvoice> get invoices => const [
    DashboardInvoice(
      customer: 'Al Amal Trading',
      number: '#INV-1001',
      amount: '1,250.00',
      statusKey: 'dashboard_paid',
      statusColor: AppColor.success,
    ),
    DashboardInvoice(
      customer: 'Al Ebdaa Foundation',
      number: '#INV-1002',
      amount: '850.00',
      statusKey: 'dashboard_partial',
      statusColor: Color(0xFFFF9F2E),
    ),
    DashboardInvoice(
      customer: 'Smart Store',
      number: '#INV-1003',
      amount: '2,300.00',
      statusKey: 'dashboard_paid',
      statusColor: AppColor.success,
    ),
    DashboardInvoice(
      customer: 'Future Company',
      number: '#INV-1004',
      amount: '1,100.00',
      statusKey: 'dashboard_unpaid',
      statusColor: AppColor.error,
    ),
    DashboardInvoice(
      customer: 'Al Najah Foundation',
      number: '#INV-1005',
      amount: '950.00',
      statusKey: 'dashboard_paid',
      statusColor: AppColor.success,
    ),
  ];

  List<DashboardInvoice> get visibleInvoices {
    final query = searchQuery.trim().toLowerCase();
    if (query.isEmpty) return invoices;
    return invoices.where((invoice) {
      return invoice.customer.toLowerCase().contains(query) ||
          invoice.number.toLowerCase().contains(query);
    }).toList();
  }

  List<double> get weeklyInvoiceValues => const [
    3.4,
    2.2,
    4.4,
    7.6,
    5.4,
    3.8,
    2.5,
  ];

  List<DashboardQuickAction> get quickActions => const [
    DashboardQuickAction(
      labelKey: 'dashboard_new_invoice',
      icon: Icons.note_add_outlined,
      route: AppRoute.createInvoice,
    ),
    DashboardQuickAction(
      labelKey: 'dashboard_new_quotation',
      icon: Icons.sell_outlined,
      route: AppRoute.createQuotation,
    ),
    DashboardQuickAction(
      labelKey: 'dashboard_new_receipt',
      icon: Icons.receipt_outlined,
      route: AppRoute.createReceipt,
    ),
    DashboardQuickAction(
      labelKey: 'dashboard_new_customer',
      icon: Icons.person_add_alt_1_outlined,
      route: AppRoute.createCustomer,
    ),
    DashboardQuickAction(
      labelKey: 'dashboard_new_item',
      icon: Icons.inventory_2_outlined,
      route: AppRoute.createItem,
    ),
    DashboardQuickAction(
      labelKey: 'dashboard_open_settings',
      icon: Icons.settings_outlined,
      route: AppRoute.settings,
    ),
  ];

  List<DashboardSummaryItem> get invoiceSummary => const [
    DashboardSummaryItem(
      labelKey: 'dashboard_invoices',
      amount: '14,592.00',
      percentage: 0.60,
      color: Color(0xFF6657E8),
    ),
    DashboardSummaryItem(
      labelKey: 'dashboard_receipts',
      amount: '6,080.00',
      percentage: 0.25,
      color: Color(0xFF42C98B),
    ),
    DashboardSummaryItem(
      labelKey: 'dashboard_quotations',
      amount: '2,432.00',
      percentage: 0.10,
      color: Color(0xFFFFA43A),
    ),
    DashboardSummaryItem(
      labelKey: 'dashboard_other',
      amount: '1,216.00',
      percentage: 0.05,
      color: Color(0xFFAFB7C7),
    ),
  ];

  List<DashboardCustomer> get topCustomers => const [
    DashboardCustomer(name: 'Al Amal Trading', amount: '8,250.00'),
    DashboardCustomer(name: 'Smart Store', amount: '6,150.00'),
    DashboardCustomer(name: 'Al Ebdaa Foundation', amount: '4,320.00'),
  ];

  List<DashboardAlert> get alerts => const [
    DashboardAlert(
      messageKey: 'dashboard_alert_unpaid',
      date: '2026-06-22',
      icon: Icons.receipt_long_outlined,
      color: AppColor.error,
    ),
    DashboardAlert(
      messageKey: 'dashboard_alert_sales',
      date: '2026-06-21',
      icon: Icons.trending_down_rounded,
      color: Color(0xFFFF9838),
    ),
    DashboardAlert(
      messageKey: 'dashboard_alert_customer',
      date: '2026-06-20',
      icon: Icons.person_add_alt_1_outlined,
      color: AppColor.success,
    ),
  ];

  void onSearchChanged(String value) {
    searchQuery = value;
    update(['invoices']);
  }

  Future<void> refreshDashboard() async {
    if (isRefreshing) return;
    isRefreshing = true;
    update();
    await Future<void>.delayed(const Duration(milliseconds: 450));
    isRefreshing = false;
    update();
  }

  void navigateTo(String route) {
    if (Get.currentRoute == route) return;
    Get.offAllNamed(route);
  }

  void showNotifications() {
    Get.snackbar(
      'dashboard_notifications'.tr,
      'dashboard_notifications_message'.tr,
      snackPosition: SnackPosition.BOTTOM,
      backgroundColor: AppColor.secondaryColor,
      colorText: AppColor.surface,
    );
  }

  void toggleLanguage() {
    final localeController = Get.find<LocaleController>();
    localeController.changeLang(localeController.isRtl ? 'en' : 'ar');
  }

  Future<void> confirmLogout() async {
    if (isLoggingOut) return;
    final confirmed = await Get.dialog<bool>(
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
    if (confirmed == true) await logout();
  }

  Future<void> logout() async {
    if (isLoggingOut) return;
    isLoggingOut = true;
    update();
    try {
      await _repository.signOut();
    } catch (_) {
      // Local authentication state is still cleared to prevent stale sessions.
    }

    final preferences = _myServices.sharedPreferences;
    await preferences.remove('step');
    await preferences.remove('uid');
    await preferences.remove('role');
    await preferences.remove('name');
    await preferences.remove('email');
    await _myServices.secureStorage.deleteAll();

    isLoggingOut = false;
    if (!isClosed) update();
    Get.offAllNamed(AppRoute.adminLogin);
  }

  @override
  void onClose() {
    searchController.dispose();
    super.onClose();
  }
}
