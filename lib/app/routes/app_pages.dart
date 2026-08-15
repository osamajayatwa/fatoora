import 'package:fatoora/app/routes/app_routes.dart';
import 'package:fatoora/app/routes/not_found_screen.dart';
import 'package:fatoora/core/middleware/middleware.dart';
import 'package:fatoora/features/auth/approval/binding/approval_status_binding.dart';
import 'package:fatoora/features/auth/approval/view/rejected_approval_screen.dart';
import 'package:fatoora/features/auth/approval/view/waiting_approval_screen.dart';
import 'package:fatoora/features/auth/admin_login/binding/admin_login_binding.dart';
import 'package:fatoora/features/auth/admin_login/view/screen/admin_login_screen.dart';
import 'package:fatoora/features/auth/admin_users/binding/admin_users_binding.dart';
import 'package:fatoora/features/auth/admin_users/view/screen/admin_users_screen.dart';
import 'package:fatoora/features/auth/user_login/binding/user_login_binding.dart';
import 'package:fatoora/features/auth/user_login/view/screen/user_login_screen.dart';
import 'package:fatoora/features/auth/user_signup/binding/user_signup_binding.dart';
import 'package:fatoora/features/auth/user_signup/view/screen/user_signup_screen.dart';
import 'package:fatoora/features/customers/bindings/customers_binding.dart';
import 'package:fatoora/features/customers/view/screens/customer_details_screen.dart';
import 'package:fatoora/features/customers/view/screens/customer_form_screen.dart';
import 'package:fatoora/features/customers/view/screens/customer_statement_screen.dart';
import 'package:fatoora/features/customers/view/screens/customers_list_screen.dart';
import 'package:fatoora/features/invoices/bindings/invoice_details_binding.dart';
import 'package:fatoora/features/invoices/bindings/invoice_form_binding.dart';
import 'package:fatoora/features/invoices/bindings/invoices_list_binding.dart';
import 'package:fatoora/features/invoices/view/screens/invoice_details_screen.dart';
import 'package:fatoora/features/invoices/view/screens/invoice_form_screen.dart';
import 'package:fatoora/features/invoices/view/screens/invoices_list_screen.dart';
import 'package:fatoora/features/inventory/bindings/inventory_binding.dart';
import 'package:fatoora/features/inventory/view/screens/inventory_adjustment_screen.dart';
import 'package:fatoora/features/inventory/view/screens/inventory_dashboard_screen.dart';
import 'package:fatoora/features/inventory/view/screens/item_stock_details_screen.dart';
import 'package:fatoora/features/inventory/view/screens/stock_movements_screen.dart';
import 'package:fatoora/features/admin_dashboard/binding/admin_dashboard_binding.dart';
import 'package:fatoora/features/admin_dashboard/view/screen/admin_home_screen.dart';
import 'package:fatoora/features/admin_dashboard/view/screen/admin_sales_rep_details_screen.dart';
import 'package:fatoora/features/admin/audit_log/bindings/audit_log_binding.dart';
import 'package:fatoora/features/admin/audit_log/presentation/pages/audit_log_page.dart';
import 'package:fatoora/features/expenses/bindings/expenses_binding.dart';
import 'package:fatoora/features/expenses/view/screens/expense_details_screen.dart';
import 'package:fatoora/features/expenses/view/screens/expense_form_screen.dart';
import 'package:fatoora/features/expenses/view/screens/expenses_list_screen.dart';
import 'package:fatoora/features/financial/bindings/financial_binding.dart';
import 'package:fatoora/features/financial/view/screens/cash_movements_screen.dart';
import 'package:fatoora/features/financial/view/screens/receivables_screen.dart';
import 'package:fatoora/features/items/binding/add_item_binding.dart';
import 'package:fatoora/features/items/binding/edit_item_binding.dart';
import 'package:fatoora/features/items/binding/item_details_binding.dart';
import 'package:fatoora/features/items/binding/items_binding.dart';
import 'package:fatoora/features/items/view/screen/add_item_screen.dart';
import 'package:fatoora/features/items/view/screen/edit_item_screen.dart';
import 'package:fatoora/features/items/view/screen/item_details_screen.dart';
import 'package:fatoora/features/items/view/screen/items_screen.dart';
import 'package:fatoora/features/home/view/screen/home_screen.dart';
import 'package:fatoora/features/quotations/bindings/quotations_binding.dart';
import 'package:fatoora/features/quotations/view/screens/quotation_details_screen.dart';
import 'package:fatoora/features/quotations/view/screens/quotation_form_screen.dart';
import 'package:fatoora/features/quotations/view/screens/quotations_list_screen.dart';
import 'package:fatoora/features/receipts/bindings/receipts_binding.dart';
import 'package:fatoora/features/receipts/view/screens/receipt_details_screen.dart';
import 'package:fatoora/features/receipts/view/screens/receipt_form_screen.dart';
import 'package:fatoora/features/receipts/view/screens/receipts_list_screen.dart';
import 'package:fatoora/features/rep_inventory/bindings/rep_inventory_binding.dart';
import 'package:fatoora/features/rep_inventory/view/screens/rep_inventory_screens.dart';
import 'package:fatoora/features/sales_returns/bindings/sales_returns_binding.dart';
import 'package:fatoora/features/sales_returns/view/screens/sales_return_details_screen.dart';
import 'package:fatoora/features/sales_returns/view/screens/sales_return_form_screen.dart';
import 'package:fatoora/features/sales_returns/view/screens/sales_returns_list_screen.dart';
import 'package:fatoora/features/settings/bindings/settings_binding.dart';
import 'package:fatoora/features/settings/view/screens/settings_screen.dart';
import 'package:fatoora/features/settings/view/screens/admin_settings_screens.dart';
import 'package:fatoora/features/settings/view/screens/user_settings_screens.dart';
import 'package:fatoora/features/settings/view/screens/financial_settings_screens.dart';
import 'package:fatoora/features/statements/bindings/statements_binding.dart';
import 'package:fatoora/features/statements/view/screens/statements_screen.dart';
import 'package:fatoora/features/splash/view/screens/language.dart';
import 'package:fatoora/features/splash/view/screens/splash.dart';
import 'package:get/get_navigation/src/routes/get_route.dart';

List<GetPage<dynamic>> routes = _guardRoutes([
  GetPage(
    name: AppRoute.adminAuditLog,
    page: () => const AuditLogPage(),
    binding: AuditLogBinding(),
    middlewares: [AdminMiddleware()],
  ),
  GetPage(
    name: '/',
    page: () => const Language(),
    middlewares: [MyMiddleware()],
  ),
  GetPage(name: AppRoute.notFound, page: () => const NotFoundScreen()),
  GetPage(
    name: AppRoute.userLogin,
    page: () => const UserLoginScreen(),
    binding: UserLoginBinding(),
  ),
  GetPage(
    name: AppRoute.userSignUp,
    page: () => const UserSignUpScreen(),
    binding: UserSignUpBinding(),
  ),
  GetPage(
    name: AppRoute.waitingApproval,
    page: () => const WaitingApprovalScreen(),
    binding: ApprovalStatusBinding(),
  ),
  GetPage(
    name: AppRoute.approvalRejected,
    page: () => const RejectedApprovalScreen(),
    binding: ApprovalStatusBinding(),
  ),
  GetPage(name: AppRoute.language, page: () => const Language()),
  GetPage(name: AppRoute.splash, page: () => const SplashScreen()),
  GetPage(
    name: AppRoute.adminLogin,
    page: () => const AdminLoginScreen(),
    binding: AdminLoginBinding(),
  ),
  GetPage(
    name: AppRoute.home,
    page: () => const HomeScreen(),
    binding: SalesRepDashboardBinding(),
    middlewares: [SalesRepMiddleware()],
  ),
  GetPage(
    name: AppRoute.adminHome,
    page: () => const AdminHomeScreen(),
    binding: AdminDashboardBinding(),
    middlewares: [AdminMiddleware()],
  ),
  GetPage(
    name: AppRoute.adminUsers,
    page: () => const AdminUsersScreen(),
    binding: AdminUsersBinding(),
    middlewares: [AdminMiddleware()],
  ),
  GetPage(
    name: AppRoute.pendingUsers,
    page: () => const AdminUsersScreen(initialTab: 0),
    binding: AdminUsersBinding(),
    middlewares: [AdminMiddleware()],
  ),
  GetPage(
    name: AppRoute.salesReps,
    page: () => const AdminUsersScreen(initialTab: 1),
    binding: AdminUsersBinding(),
    middlewares: [AdminMiddleware()],
  ),
  GetPage(
    name: AppRoute.adminSalesRepDetails,
    page: () => const AdminSalesRepDetailsScreen(),
    binding: AdminDashboardBinding(),
    middlewares: [AdminMiddleware()],
  ),
  GetPage(
    name: AppRoute.invoices,
    page: () => const InvoicesListScreen(),
    binding: InvoicesListBinding(),
    middlewares: [ApprovedUserMiddleware()],
  ),
  GetPage(
    name: AppRoute.salesReturns,
    page: () => const SalesReturnsListScreen(),
    binding: SalesReturnsBinding(),
    middlewares: [ApprovedUserMiddleware()],
  ),
  GetPage(
    name: AppRoute.quotations,
    page: () => const QuotationsListScreen(),
    binding: QuotationsBinding(),
    middlewares: [ApprovedUserMiddleware()],
  ),
  GetPage(
    name: AppRoute.receipts,
    page: () => const ReceiptsListScreen(),
    binding: ReceiptsBinding(),
    middlewares: [ApprovedUserMiddleware()],
  ),
  GetPage(
    name: AppRoute.customers,
    page: () => const CustomersListScreen(),
    binding: CustomersBinding(),
    middlewares: [ApprovedUserMiddleware()],
  ),
  GetPage(
    name: AppRoute.receivables,
    page: () => const ReceivablesScreen(),
    binding: ReceivablesBinding(),
    middlewares: [ApprovedUserMiddleware()],
  ),
  GetPage(
    name: AppRoute.cashMovements,
    page: () => const CashMovementsScreen(),
    binding: CashMovementsBinding(),
    middlewares: [ApprovedUserMiddleware()],
  ),
  GetPage(
    name: AppRoute.expenses,
    page: () => const ExpensesListScreen(),
    binding: ExpensesBinding(),
    middlewares: [ApprovedUserMiddleware()],
  ),
  GetPage(
    name: AppRoute.adminItems,
    page: () => const ItemsScreen(),
    binding: ItemsBinding(),
    middlewares: [AdminMiddleware()],
  ),
  GetPage(
    name: AppRoute.inventory,
    page: () => const InventoryDashboardScreen(),
    binding: InventoryDashboardBinding(),
    middlewares: [AdminMiddleware()],
  ),
  GetPage(
    name: AppRoute.stockMovements,
    page: () => const StockMovementsScreen(),
    binding: StockMovementsBinding(),
    middlewares: [AdminMiddleware()],
  ),
  GetPage(
    name: AppRoute.inventoryAdjustment,
    page: () => const InventoryAdjustmentScreen(),
    binding: InventoryAdjustmentBinding(),
    middlewares: [AdminMiddleware()],
  ),
  GetPage(
    name: AppRoute.itemStockDetails,
    page: () => const ItemStockDetailsScreen(),
    binding: ItemStockDetailsBinding(),
    middlewares: [AdminMiddleware()],
  ),
  GetPage(
    name: AppRoute.repInventory,
    page: () => const RepInventoryScreen(),
    binding: RepInventoryBinding(),
    middlewares: [ApprovedUserMiddleware()],
  ),
  GetPage(
    name: AppRoute.repInventoryTransfers,
    page: () => const InventoryTransfersScreen(),
    binding: InventoryTransfersBinding(),
    middlewares: [AdminMiddleware()],
  ),
  GetPage(
    name: AppRoute.repInventoryTransferForm,
    page: () => const InventoryTransferFormScreen(),
    binding: InventoryTransferFormBinding(),
    middlewares: [AdminMiddleware()],
  ),
  GetPage(
    name: AppRoute.repInventoryTransferDetails,
    page: () => const InventoryTransferDetailsScreen(),
    binding: InventoryTransferDetailsBinding(),
    middlewares: [ApprovedUserMiddleware()],
  ),
  GetPage(
    name: AppRoute.statements,
    page: () => const StatementsScreen(),
    binding: StatementsBinding(),
    middlewares: [ApprovedUserMiddleware()],
  ),
  GetPage(
    name: AppRoute.settings,
    page: () => const SettingsScreen(),
    binding: SettingsBinding(),
    middlewares: [ApprovedUserMiddleware()],
  ),
  GetPage(
    name: AppRoute.companySettings,
    page: () => const CompanySettingsScreen(),
    binding: SettingsBinding(),
    middlewares: [ApprovedUserMiddleware(), AdminSettingsMiddleware()],
  ),
  GetPage(
    name: AppRoute.documentSettings,
    page: () => const DocumentSettingsScreen(),
    binding: SettingsBinding(),
    middlewares: [ApprovedUserMiddleware(), AdminSettingsMiddleware()],
  ),
  GetPage(
    name: AppRoute.inventorySettings,
    page: () => const InventorySettingsScreen(),
    binding: SettingsBinding(),
    middlewares: [ApprovedUserMiddleware(), AdminSettingsMiddleware()],
  ),
  GetPage(
    name: AppRoute.financialSettings,
    page: () => const FinancialSettingsScreen(),
    binding: SettingsBinding(),
    middlewares: [ApprovedUserMiddleware(), AdminSettingsMiddleware()],
  ),
  GetPage(
    name: AppRoute.openingBalances,
    page: () => const OpeningBalancesScreen(),
    bindings: [SettingsBinding(), CompanyCashOpeningBalanceBinding()],
    middlewares: [ApprovedUserMiddleware(), AdminSettingsMiddleware()],
  ),
  GetPage(
    name: AppRoute.pdfSettings,
    page: () => const PdfSettingsScreen(),
    binding: SettingsBinding(),
    middlewares: [ApprovedUserMiddleware(), AdminSettingsMiddleware()],
  ),
  GetPage(
    name: AppRoute.permissionSettings,
    page: () => const PermissionSettingsScreen(),
    binding: SettingsBinding(),
    middlewares: [ApprovedUserMiddleware(), AdminSettingsMiddleware()],
  ),
  GetPage(
    name: AppRoute.jofotaraSettings,
    page: () => const JofotaraSettingsScreen(),
    binding: SettingsBinding(),
    middlewares: [ApprovedUserMiddleware(), AdminSettingsMiddleware()],
  ),
  GetPage(
    name: AppRoute.profileSettings,
    page: () => const ProfileSettingsScreen(),
    binding: SettingsBinding(),
    middlewares: [ApprovedUserMiddleware()],
  ),
  GetPage(
    name: AppRoute.appPreferencesSettings,
    page: () => const AppPreferencesSettingsScreen(),
    binding: SettingsBinding(),
    middlewares: [ApprovedUserMiddleware()],
  ),
  GetPage(
    name: AppRoute.accountSettings,
    page: () => const AccountSettingsScreen(),
    binding: SettingsBinding(),
    middlewares: [ApprovedUserMiddleware()],
  ),
  GetPage(
    name: AppRoute.invoiceForm,
    page: () => const InvoiceFormScreen(),
    binding: InvoiceFormBinding(),
    middlewares: [ApprovedUserMiddleware()],
  ),
  GetPage(
    name: AppRoute.invoiceEdit,
    page: () => const InvoiceFormScreen(),
    binding: InvoiceFormBinding(),
    middlewares: [ApprovedUserMiddleware()],
  ),
  GetPage(
    name: AppRoute.invoiceDetails,
    page: () => const InvoiceDetailsScreen(),
    binding: InvoiceDetailsBinding(),
    middlewares: [ApprovedUserMiddleware()],
  ),
  GetPage(
    name: AppRoute.createSalesReturn,
    page: () => const SalesReturnFormScreen(),
    binding: SalesReturnFormBinding(),
    middlewares: [ApprovedUserMiddleware()],
  ),
  GetPage(
    name: AppRoute.salesReturnDetails,
    page: () => const SalesReturnDetailsScreen(),
    binding: SalesReturnDetailsBinding(),
    middlewares: [ApprovedUserMiddleware()],
  ),
  GetPage(
    name: AppRoute.createQuotation,
    page: () => const QuotationFormScreen(),
    binding: QuotationFormBinding(),
    middlewares: [ApprovedUserMiddleware()],
  ),
  GetPage(
    name: AppRoute.quotationEdit,
    page: () => const QuotationFormScreen(),
    binding: QuotationFormBinding(),
    middlewares: [ApprovedUserMiddleware()],
  ),
  GetPage(
    name: AppRoute.quotationDetails,
    page: () => const QuotationDetailsScreen(),
    binding: QuotationDetailsBinding(),
    middlewares: [ApprovedUserMiddleware()],
  ),
  GetPage(
    name: AppRoute.createReceipt,
    page: () => const ReceiptFormScreen(),
    binding: ReceiptFormBinding(),
    middlewares: [ApprovedUserMiddleware()],
  ),
  GetPage(
    name: AppRoute.receiptDetails,
    page: () => const ReceiptDetailsScreen(),
    binding: ReceiptDetailsBinding(),
    middlewares: [ApprovedUserMiddleware()],
  ),
  GetPage(
    name: AppRoute.createExpense,
    page: () => const ExpenseFormScreen(),
    binding: ExpenseFormBinding(),
    middlewares: [ApprovedUserMiddleware()],
  ),
  GetPage(
    name: AppRoute.expenseDetails,
    page: () => const ExpenseDetailsScreen(),
    binding: ExpenseDetailsBinding(),
    middlewares: [ApprovedUserMiddleware()],
  ),
  GetPage(
    name: AppRoute.createCustomer,
    page: () => const CustomerFormScreen(),
    binding: CustomerFormBinding(),
    middlewares: [ApprovedUserMiddleware()],
  ),
  GetPage(
    name: AppRoute.customerEdit,
    page: () => const CustomerFormScreen(),
    binding: CustomerFormBinding(),
    middlewares: [ApprovedUserMiddleware()],
  ),
  GetPage(
    name: AppRoute.customerDetails,
    page: () => const CustomerDetailsScreen(),
    binding: CustomerDetailsBinding(),
    middlewares: [ApprovedUserMiddleware()],
  ),
  GetPage(
    name: AppRoute.customerStatement,
    page: () => const CustomerStatementScreen(),
    binding: CustomerStatementBinding(),
    middlewares: [ApprovedUserMiddleware()],
  ),
  GetPage(
    name: AppRoute.adminAddItem,
    page: () => const AddItemScreen(),
    binding: AddItemBinding(),
    middlewares: [AdminMiddleware()],
  ),
  GetPage(
    name: AppRoute.adminEditItem,
    page: () => const EditItemScreen(),
    binding: EditItemBinding(),
    middlewares: [AdminMiddleware()],
  ),
  GetPage(
    name: AppRoute.adminItemDetails,
    page: () => const ItemDetailsScreen(),
    binding: ItemDetailsBinding(),
    middlewares: [AdminMiddleware()],
  ),
]);

List<GetPage<dynamic>> _guardRoutes(List<GetPage<dynamic>> pages) {
  return pages
      .map(
        (page) => page.copy(
          middlewares: [ExactRouteMiddleware(), ...?page.middlewares],
        ),
      )
      .toList(growable: false);
}

GetPage<dynamic> unknownRoute = GetPage(
  name: AppRoute.notFound,
  page: () => const NotFoundScreen(),
);
