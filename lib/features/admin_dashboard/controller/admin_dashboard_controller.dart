import 'package:fatoora/app/routes/app_routes.dart';
import 'package:fatoora/core/constants/color.dart';
import 'package:fatoora/core/localization/changelocal.dart';
import 'package:fatoora/core/services/services.dart';
import 'package:fatoora/features/admin_dashboard/model/admin_dashboard_models.dart';
import 'package:fatoora/features/auth/data/repositories/admin_auth_repository.dart';
import 'package:fatoora/features/auth/utils/auth_session.dart';
import 'package:fatoora/features/financial/data/models/financial_dashboard_snapshot.dart';
import 'package:fatoora/features/financial/data/repositories/financial_repository.dart';
import 'package:fatoora/features/invoices/data/models/invoice_enums.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

class AdminDashboardController extends GetxController {
  AdminDashboardController({
    required AdminAuthRepository repository,
    required FinancialRepository financialRepository,
    required MyServices myServices,
  }) : _repository = repository,
       _financialRepository = financialRepository,
       _myServices = myServices;

  final AdminAuthRepository _repository;
  final FinancialRepository _financialRepository;
  final MyServices _myServices;

  final TextEditingController searchController = TextEditingController();
  bool isRefreshing = false;
  bool isLoggingOut = false;
  String searchQuery = '';
  FinancialDashboardSnapshot snapshot =
      const FinancialDashboardSnapshot.empty();
  int pendingApprovalsCount = 0;

  String get adminName => AuthSession.cachedDisplayName(_myServices) == 'User'
      ? 'dashboard_admin'.tr
      : AuthSession.cachedDisplayName(_myServices);

  String get adminEmail =>
      _myServices.sharedPreferences.getString('email') ?? '';

  String get companyId =>
      _myServices.sharedPreferences.getString('companyId') ?? 'default_company';

  NumberFormat get _money =>
      NumberFormat.currency(symbol: '', decimalDigits: 3);

  List<DashboardStat> get stats => [
    DashboardStat(
      titleKey: 'dashboard_customers_count',
      value: snapshot.customerCount.toString(),
      captionKey: 'dashboard_customer',
      change: '0%',
      icon: Icons.people_alt_outlined,
      color: const Color(0xFFFF9838),
    ),
    DashboardStat(
      titleKey: 'dashboard_invoices_count',
      value: snapshot.invoiceCount.toString(),
      captionKey: 'dashboard_invoice',
      change: '0%',
      icon: Icons.receipt_long_outlined,
      color: const Color(0xFF35A7FF),
    ),
    DashboardStat(
      titleKey: 'dashboard_invoice_total',
      value: _money.format(snapshot.totalSales),
      captionKey: 'dashboard_jod',
      change: '0%',
      icon: Icons.description_outlined,
      color: const Color(0xFF42C98B),
    ),
    DashboardStat(
      titleKey: 'financial_cash_in_hand',
      value: _money.format(snapshot.cashInHand),
      captionKey: 'dashboard_jod',
      change: '0%',
      icon: Icons.account_balance_wallet_outlined,
      color: const Color(0xFF6657E8),
    ),
    DashboardStat(
      titleKey: 'admin_users_pending',
      value: pendingApprovalsCount.toString(),
      captionKey: 'admin_users_approval_queue',
      change: '0%',
      icon: Icons.manage_accounts_outlined,
      color: const Color(0xFFFFA43A),
    ),
  ];

  List<DashboardInvoice> get invoices => snapshot.recentInvoices
      .map((invoice) {
        return DashboardInvoice(
          customer: invoice.customerSnapshot?.name ?? invoice.customerId,
          number: invoice.invoiceNumber,
          amount: _money.format(invoice.grandTotal),
          statusKey: _paymentStatusKey(invoice.paymentStatus),
          statusColor: _paymentStatusColor(invoice.paymentStatus),
        );
      })
      .toList(growable: false);

  List<DashboardInvoice> get visibleInvoices {
    final query = searchQuery.trim().toLowerCase();
    if (query.isEmpty) return invoices;
    return invoices.where((invoice) {
      return invoice.customer.toLowerCase().contains(query) ||
          invoice.number.toLowerCase().contains(query);
    }).toList();
  }

  List<double> get weeklyInvoiceValues => snapshot.weeklyInvoiceValues;

  List<DashboardQuickAction> get quickActions => const [
    DashboardQuickAction(
      labelKey: 'dashboard_new_invoice',
      icon: Icons.note_add_outlined,
      route: AppRoute.createInvoice,
    ),
    DashboardQuickAction(
      labelKey: 'financial_receivables',
      icon: Icons.account_balance_outlined,
      route: AppRoute.receivables,
    ),
    DashboardQuickAction(
      labelKey: 'financial_cash',
      icon: Icons.account_balance_wallet_outlined,
      route: AppRoute.cashMovements,
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
      labelKey: 'admin_users',
      icon: Icons.manage_accounts_outlined,
      route: AppRoute.adminUsers,
    ),
    DashboardQuickAction(
      labelKey: 'dashboard_open_settings',
      icon: Icons.settings_outlined,
      route: AppRoute.settings,
    ),
  ];

  List<DashboardSummaryItem> get invoiceSummary {
    final total = snapshot.totalSales <= 0 ? 1 : snapshot.totalSales;
    return [
      DashboardSummaryItem(
        labelKey: 'financial_cash_sales',
        amount: _money.format(snapshot.cashSales),
        percentage: snapshot.cashSales / total,
        color: AppColor.success,
      ),
      DashboardSummaryItem(
        labelKey: 'financial_credit_sales',
        amount: _money.format(snapshot.creditSales),
        percentage: snapshot.creditSales / total,
        color: AppColor.error,
      ),
      DashboardSummaryItem(
        labelKey: 'financial_partial_sales',
        amount: _money.format(snapshot.partialSales),
        percentage: snapshot.partialSales / total,
        color: const Color(0xFFFFA43A),
      ),
      DashboardSummaryItem(
        labelKey: 'financial_total_receivables',
        amount: _money.format(snapshot.totalReceivables),
        percentage: snapshot.totalReceivables <= 0
            ? 0
            : (snapshot.totalReceivables / total).clamp(0, 1).toDouble(),
        color: const Color(0xFF6657E8),
      ),
    ];
  }

  List<DashboardCustomer> get topCustomers => snapshot.topCustomers
      .map(
        (item) => DashboardCustomer(
          name: item.customer.name,
          amount: _money.format(item.balance),
        ),
      )
      .toList(growable: false);

  List<DashboardAlert> get alerts => [
    DashboardAlert(
      messageKey: snapshot.totalReceivables > 0
          ? 'financial_alert_receivables'
          : 'financial_alert_no_receivables',
      date: DateFormat('yyyy-MM-dd').format(DateTime.now()),
      icon: Icons.account_balance_outlined,
      color: snapshot.totalReceivables > 0 ? AppColor.error : AppColor.success,
    ),
    DashboardAlert(
      messageKey: 'financial_alert_cash',
      date: DateFormat('yyyy-MM-dd').format(DateTime.now()),
      icon: Icons.account_balance_wallet_outlined,
      color: AppColor.primaryColor,
    ),
  ];

  @override
  void onReady() {
    super.onReady();
    refreshDashboard();
  }

  void onSearchChanged(String value) {
    searchQuery = value;
    update(['invoices']);
  }

  Future<void> refreshDashboard() async {
    if (isRefreshing) return;
    isRefreshing = true;
    update();
    try {
      final loadedSnapshot = await _financialRepository.fetchDashboard(
        companyId: companyId,
      );
      var loadedPendingCount = pendingApprovalsCount;
      try {
        loadedPendingCount = (await _repository.fetchPendingUsers()).length;
      } catch (_) {
        // Approval count is supplemental; keep the dashboard usable.
      }
      snapshot = loadedSnapshot;
      pendingApprovalsCount = loadedPendingCount;
    } catch (_) {
      // Dashboard stays usable with the last loaded snapshot.
    } finally {
      isRefreshing = false;
      if (!isClosed) update();
    }
  }

  void navigateTo(String route) {
    if (Get.currentRoute == route) return;
    Get.toNamed(route);
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

    await AuthSession.clear(_myServices);
    await _myServices.secureStorage.deleteAll();

    isLoggingOut = false;
    if (!isClosed) update();
    Get.offAllNamed(AppRoute.adminLogin);
  }

  String _paymentStatusKey(PaymentStatus status) {
    return switch (status) {
      PaymentStatus.paid => 'dashboard_paid',
      PaymentStatus.partiallyPaid => 'dashboard_partial',
      PaymentStatus.unpaid || PaymentStatus.overdue => 'dashboard_unpaid',
    };
  }

  Color _paymentStatusColor(PaymentStatus status) {
    return switch (status) {
      PaymentStatus.paid => AppColor.success,
      PaymentStatus.partiallyPaid => const Color(0xFFFF9F2E),
      PaymentStatus.unpaid || PaymentStatus.overdue => AppColor.error,
    };
  }

  @override
  void onClose() {
    searchController.dispose();
    super.onClose();
  }
}
