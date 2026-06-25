import 'package:fatoora/app/routes/app_routes.dart';
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
import 'package:fatoora/features/admin_dashboard/binding/admin_dashboard_binding.dart';
import 'package:fatoora/features/admin_dashboard/view/screen/admin_home_screen.dart';
import 'package:fatoora/features/admin_dashboard/view/screen/admin_section_screen.dart';
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
import 'package:fatoora/features/receipts/bindings/receipts_binding.dart';
import 'package:fatoora/features/receipts/view/screens/receipt_details_screen.dart';
import 'package:fatoora/features/receipts/view/screens/receipt_form_screen.dart';
import 'package:fatoora/features/receipts/view/screens/receipts_list_screen.dart';
import 'package:flutter/material.dart';
import 'package:fatoora/features/splash/view/screens/language.dart';
import 'package:fatoora/features/splash/view/screens/splash.dart';
import 'package:get/get_navigation/src/routes/get_route.dart';

List<GetPage<dynamic>> routes = [
  GetPage(
    name: '/',
    page: () => const Language(),
    middlewares: [MyMiddleware()],
  ),
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
    name: AppRoute.invoices,
    page: () => const InvoicesListScreen(),
    binding: InvoicesListBinding(),
    middlewares: [ApprovedUserMiddleware()],
  ),
  GetPage(
    name: AppRoute.quotations,
    page: () => const AdminSectionScreen(
      titleKey: 'dashboard_quotations',
      icon: Icons.request_quote_outlined,
    ),
    binding: AdminDashboardBinding(),
    middlewares: [AdminMiddleware()],
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
    name: AppRoute.adminItems,
    page: () => const ItemsScreen(),
    binding: ItemsBinding(),
    middlewares: [AdminMiddleware()],
  ),
  GetPage(
    name: AppRoute.statements,
    page: () => const AdminSectionScreen(
      titleKey: 'dashboard_account_statement',
      icon: Icons.article_outlined,
    ),
    binding: AdminDashboardBinding(),
    middlewares: [AdminMiddleware()],
  ),
  GetPage(
    name: AppRoute.settings,
    page: () => const AdminSectionScreen(
      titleKey: 'dashboard_settings',
      icon: Icons.settings_outlined,
    ),
    binding: AdminDashboardBinding(),
    middlewares: [AdminMiddleware()],
  ),
  GetPage(
    name: AppRoute.invoiceForm,
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
    name: AppRoute.createQuotation,
    page: () => const AdminSectionScreen(
      titleKey: 'dashboard_new_quotation',
      icon: Icons.sell_outlined,
    ),
    binding: AdminDashboardBinding(),
    middlewares: [AdminMiddleware()],
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
    name: AppRoute.createCustomer,
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
];

GetPage<dynamic> unknownRoute = GetPage(
  name: '/not-found',
  page: () => const Language(),
);
