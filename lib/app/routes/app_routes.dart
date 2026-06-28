class AppRoute {
  static const String splash = "/splash";
  static const String language = "/language";

  static const String adminLogin = "/admin-login";
  static const String userLogin = "/user-login";
  static const String userSignUp = "/user-sign-up";
  static const String waitingApproval = "/waiting-approval";
  static const String approvalRejected = "/approval-rejected";
  static const String login = adminLogin;
  static const String home = "/home";
  static const String adminHome = "/admin-home";
  static const String adminUsers = "/admin/users";
  static const String pendingUsers = "/admin/users/pending";
  static const String salesReps = "/admin/users/sales-reps";

  static const String customers = "/customers";
  static const String createCustomer = "/create-customer";
  static const String customerDetails = "/customer-details";
  static const String customerStatement = "/customer-statement";

  static const String adminItems = "/admin/items";
  static const String adminAddItem = "/admin/items/add";
  static const String adminEditItem = "/admin/items/edit";
  static const String adminItemDetails = "/admin/items/details";

  static const String inventory = "/inventory";
  static const String stockMovements = "/inventory/stock-movements";
  static const String inventoryAdjustment = "/inventory/adjustment";
  static const String itemStockDetails = "/inventory/item-stock-details";

  // Backward-compatible aliases used by the existing dashboard navigation.
  static const String items = adminItems;
  static const String createItem = adminAddItem;
  static const String itemDetails = adminItemDetails;

  static const String invoices = "/invoices";
  static const String invoiceForm = "/invoices/form";
  static const String invoiceDetails = "/invoices/details";
  static const String createInvoice = invoiceForm;

  static const String salesReturns = "/sales-returns";
  static const String createSalesReturn = "/sales-returns/create";
  static const String salesReturnDetails = "/sales-returns/details";

  static const String quotations = "/quotations";
  static const String createQuotation = "/quotations/create";
  static const String quotationDetails = "/quotations/details";

  static const String receipts = "/receipts";
  static const String createReceipt = "/create-receipt";
  static const String receiptDetails = "/receipts/details";

  static const String receivables = "/receivables";
  static const String cashMovements = "/cash-movements";

  static const String statements = "/statements";
  static const String settings = "/settings";
  static const String companySettings = "/settings/company";
  static const String documentSettings = "/settings/documents";
  static const String inventorySettings = "/settings/inventory";
  static const String pdfSettings = "/settings/pdf";
  static const String permissionSettings = "/settings/permissions";
  static const String jofotaraSettings = "/settings/jofotara";
  static const String profileSettings = "/settings/profile";
  static const String appPreferencesSettings = "/settings/preferences";
  static const String accountSettings = "/settings/account";
}
