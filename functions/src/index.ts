import { initializeApp } from "firebase-admin/app";
import {
  auditCompanyDocumentWrite,
  auditItemWrite,
  auditUserWrite,
} from "./audit/audit_triggers";
import {confirmInvoice} from "./trusted/confirm_invoice";
import {confirmInventoryTransfer} from "./trusted/confirm_inventory_transfer";
import {confirmSalesReturn} from "./trusted/confirm_sales_return";
import {createCustomer, updateCustomer} from "./trusted/customer_profiles";
import {createReceipt} from "./trusted/create_receipt";
import {approveExpense, createExpense} from "./trusted/expenses";
import {adjustStock, createItem} from "./trusted/inventory";
import {postCustomerOpeningBalance} from "./trusted/post_opening_balance";
import {postCompanyCashOpeningBalance} from "./trusted/post_company_cash_opening_balance";
import {recordCashSettlement} from "./trusted/record_cash_settlement";
import {updateCustomerOpeningBalance} from "./trusted/update_opening_balance";
import {
  getFinancialLedgerSummary,
  projectFinancialLedgerEntry,
  searchFinancialLedger,
} from "./trusted/financial_ledger_reporting";
import {
  getCashOpeningBalance,
  getFinancialLedgerOpeningBalances,
  getReceivableBalances,
  projectFinancialLedgerAccountActivity,
} from "./trusted/financial_ledger_account_reporting";
import {getDashboardSnapshot} from "./trusted/dashboard_reporting";
import {
  projectInventoryTransferSearch,
  projectItemReportingFields,
  projectRepInventoryMovementSearch,
  projectSalesReturnSearch,
  projectStockMovementSearch,
} from "./trusted/operational_search_projection";

initializeApp();

export {
  auditCompanyDocumentWrite,
  auditItemWrite,
  auditUserWrite,
  adjustStock,
  approveExpense,
  confirmInvoice,
  confirmInventoryTransfer,
  confirmSalesReturn,
  createCustomer,
  createExpense,
  createItem,
  createReceipt,
  getFinancialLedgerOpeningBalances,
  getCashOpeningBalance,
  getReceivableBalances,
  getDashboardSnapshot,
  getFinancialLedgerSummary,
  postCustomerOpeningBalance,
  postCompanyCashOpeningBalance,
  recordCashSettlement,
  projectFinancialLedgerEntry,
  projectFinancialLedgerAccountActivity,
  projectInventoryTransferSearch,
  projectItemReportingFields,
  projectRepInventoryMovementSearch,
  projectSalesReturnSearch,
  projectStockMovementSearch,
  searchFinancialLedger,
  updateCustomerOpeningBalance,
  updateCustomer,
};
