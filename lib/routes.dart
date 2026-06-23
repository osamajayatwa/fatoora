import 'package:fatoora/core/constant/routes.dart';
import 'package:fatoora/core/mymiddleware/middleware.dart';
import 'package:fatoora/modules/auth/admin_login/binding/admin_login_binding.dart';
import 'package:fatoora/modules/auth/admin_login/view/screen/admin_login_screen.dart';
import 'package:fatoora/modules/auth/user_login/binding/user_login_binding.dart';
import 'package:fatoora/modules/auth/user_login/view/screen/user_login_screen.dart';
import 'package:fatoora/modules/auth/user_signup/binding/user_signup_binding.dart';
import 'package:fatoora/modules/auth/user_signup/view/screen/user_signup_screen.dart';
import 'package:fatoora/features/invoices/bindings/invoice_details_binding.dart';
import 'package:fatoora/features/invoices/bindings/invoice_form_binding.dart';
import 'package:fatoora/features/invoices/bindings/invoices_list_binding.dart';
import 'package:fatoora/features/invoices/view/screens/invoice_details_screen.dart';
import 'package:fatoora/features/invoices/view/screens/invoice_form_screen.dart';
import 'package:fatoora/features/invoices/view/screens/invoices_list_screen.dart';
import 'package:fatoora/modules/admin_dashboard/binding/admin_dashboard_binding.dart';
import 'package:fatoora/modules/admin_dashboard/view/screen/admin_home_screen.dart';
import 'package:fatoora/modules/admin_dashboard/view/screen/admin_section_screen.dart';
import 'package:fatoora/modules/admin_dashboard/items/binding/add_item_binding.dart';
import 'package:fatoora/modules/admin_dashboard/items/binding/edit_item_binding.dart';
import 'package:fatoora/modules/admin_dashboard/items/binding/item_details_binding.dart';
import 'package:fatoora/modules/admin_dashboard/items/binding/items_binding.dart';
import 'package:fatoora/modules/admin_dashboard/items/view/screen/add_item_screen.dart';
import 'package:fatoora/modules/admin_dashboard/items/view/screen/edit_item_screen.dart';
import 'package:fatoora/modules/admin_dashboard/items/view/screen/item_details_screen.dart';
import 'package:fatoora/modules/admin_dashboard/items/view/screen/items_screen.dart';
import 'package:fatoora/modules/home/view/screen/home_screen.dart';
import 'package:flutter/material.dart';
import 'package:fatoora/splashscreens/language.dart';
import 'package:fatoora/splashscreens/splash.dart';
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
  GetPage(name: AppRoute.language, page: () => const Language()),
  GetPage(name: AppRoute.splash, page: () => const SplashScreen()),
  GetPage(
    name: AppRoute.adminLogin,
    page: () => const AdminLoginScreen(),
    binding: AdminLoginBinding(),
  ),
  GetPage(name: AppRoute.home, page: () => const HomeScreen()),
  GetPage(
    name: AppRoute.adminHome,
    page: () => const AdminHomeScreen(),
    binding: AdminDashboardBinding(),
    middlewares: [AdminMiddleware()],
  ),
  GetPage(
    name: AppRoute.invoices,
    page: () => const InvoicesListScreen(),
    binding: InvoicesListBinding(),
    middlewares: [AdminMiddleware()],
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
    page: () => const AdminSectionScreen(
      titleKey: 'dashboard_receipts',
      icon: Icons.receipt_outlined,
    ),
    binding: AdminDashboardBinding(),
    middlewares: [AdminMiddleware()],
  ),
  GetPage(
    name: AppRoute.customers,
    page: () => const AdminSectionScreen(
      titleKey: 'dashboard_customers',
      icon: Icons.people_alt_outlined,
    ),
    binding: AdminDashboardBinding(),
    middlewares: [AdminMiddleware()],
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
    middlewares: [AdminMiddleware()],
  ),
  GetPage(
    name: AppRoute.invoiceDetails,
    page: () => const InvoiceDetailsScreen(),
    binding: InvoiceDetailsBinding(),
    middlewares: [AdminMiddleware()],
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
    page: () => const AdminSectionScreen(
      titleKey: 'dashboard_new_receipt',
      icon: Icons.receipt_long_outlined,
    ),
    binding: AdminDashboardBinding(),
    middlewares: [AdminMiddleware()],
  ),
  GetPage(
    name: AppRoute.createCustomer,
    page: () => const AdminSectionScreen(
      titleKey: 'dashboard_new_customer',
      icon: Icons.person_add_alt_1_outlined,
    ),
    binding: AdminDashboardBinding(),
    middlewares: [AdminMiddleware()],
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
