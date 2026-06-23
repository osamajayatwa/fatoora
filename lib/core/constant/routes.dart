class AppRoute {
  static const String splash = "/splash";
  static const String language = "/language";

  static const String adminLogin = "/admin-login";
  static const String userLogin = "/user-login";
  static const String userSignUp = "/user-sign-up";
  static const String login = adminLogin;
  static const String home = "/home";
  static const String adminHome = "/admin-home";

  static const String customers = "/customers";
  static const String createCustomer = "/create-customer";
  static const String customerDetails = "/customer-details";

  static const String adminItems = "/admin/items";
  static const String adminAddItem = "/admin/items/add";
  static const String adminEditItem = "/admin/items/edit";
  static const String adminItemDetails = "/admin/items/details";

  // Backward-compatible aliases used by the existing dashboard navigation.
  static const String items = adminItems;
  static const String createItem = adminAddItem;
  static const String itemDetails = adminItemDetails;

  static const String invoices = "/invoices";
  static const String createInvoice = "/create-invoice";
  static const String invoiceDetails = "/invoice-details";

  static const String quotations = "/quotations";
  static const String createQuotation = "/create-quotation";

  static const String receipts = "/receipts";
  static const String createReceipt = "/create-receipt";

  static const String statements = "/statements";
  static const String settings = "/settings";
}
