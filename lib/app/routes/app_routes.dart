class AppRoute {
  static const String notFound = "/not-found";
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
  static const String adminSalesRepDetails = "/admin/sales-reps/details";
  static const String adminAuditLog = "/admin/audit-log";

  static const String customers = "/customers";
  static const String createCustomer = "/customers/create";
  static const String customerDetails = "/customers/:customerId";
  static const String customerEdit = "/customers/:customerId/edit";
  static const String customerStatement = "/customers/:customerId/statement";

  static const String adminItems = "/admin/items";
  static const String adminAddItem = "/items/add";
  static const String adminEditItem = "/items/:itemId/edit";
  static const String adminItemDetails = "/items/:itemId";

  static const String inventory = "/inventory";
  static const String stockMovements = "/inventory/stock-movements";
  static const String inventoryAdjustment = "/inventory/adjustment";
  static const String itemStockDetails = "/inventory/item-stock-details";
  static const String repInventory = "/rep-inventory";
  static const String repInventoryTransfers = "/inventory-transfers";
  static const String repInventoryTransferForm = "/inventory-transfers/create";
  static const String repInventoryTransferDetails =
      "/inventory-transfers/:transferId";

  // Backward-compatible aliases used by the existing dashboard navigation.
  static const String items = adminItems;
  static const String createItem = adminAddItem;
  static const String itemDetails = adminItemDetails;

  static const String invoices = "/invoices";
  static const String invoiceForm = "/invoices/create";
  static const String invoiceEdit = "/invoices/:invoiceId/edit";
  static const String invoiceDetails = "/invoices/:invoiceId";
  static const String createInvoice = invoiceForm;

  static const String salesReturns = "/sales-returns";
  static const String createSalesReturn = "/sales-returns/create";
  static const String salesReturnDetails = "/sales-returns/:returnId";

  static const String quotations = "/quotations";
  static const String createQuotation = "/quotations/create";
  static const String quotationEdit = "/quotations/:quotationId/edit";
  static const String quotationDetails = "/quotations/:quotationId";

  static const String receipts = "/receipts";
  static const String createReceipt = "/receipts/create";
  static const String receiptDetails = "/receipts/:receiptId";

  static const String receivables = "/receivables";
  static const String cashMovements = "/cash-movements";
  static const String expenses = "/expenses";
  static const String createExpense = "/expenses/create";
  static const String expenseDetails = "/expenses/:expenseId";

  static const String statements = "/statements";
  static const String settings = "/settings";
  static const String companySettings = "/settings/company";
  static const String documentSettings = "/settings/documents";
  static const String inventorySettings = "/settings/inventory";
  static const String financialSettings = "/settings/financial";
  static const String openingBalances = "/settings/financial/opening-balances";
  static const String pdfSettings = "/settings/pdf";
  static const String permissionSettings = "/settings/permissions";
  static const String jofotaraSettings = "/settings/jofotara";
  static const String profileSettings = "/settings/profile";
  static const String appPreferencesSettings = "/settings/preferences";
  static const String accountSettings = "/settings/account";

  static String customerDetailsPath(String id) => '/customers/${_segment(id)}';
  static String customerEditPath(String id) =>
      '/customers/${_segment(id)}/edit';
  static String customerStatementPath(String id) =>
      '/customers/${_segment(id)}/statement';
  static String itemDetailsPath(String id) => '/items/${_segment(id)}';
  static String itemEditPath(String id) => '/items/${_segment(id)}/edit';
  static String invoiceDetailsPath(String id) => '/invoices/${_segment(id)}';
  static String invoiceEditPath(String id) => '/invoices/${_segment(id)}/edit';
  static String quotationDetailsPath(String id) =>
      '/quotations/${_segment(id)}';
  static String quotationEditPath(String id) =>
      '/quotations/${_segment(id)}/edit';
  static String receiptDetailsPath(String id) => '/receipts/${_segment(id)}';
  static String salesReturnDetailsPath(String id) =>
      '/sales-returns/${_segment(id)}';
  static String expenseDetailsPath(String id) => '/expenses/${_segment(id)}';
  static String inventoryTransferDetailsPath(String id) =>
      '/inventory-transfers/${_segment(id)}';

  static String _segment(String value) => Uri.encodeComponent(value.trim());
}
