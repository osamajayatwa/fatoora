import { initializeApp } from "firebase-admin/app";
import {
  auditCompanyDocumentWrite,
  auditItemWrite,
  auditUserWrite,
} from "./audit/audit_triggers";
import {confirmInvoice} from "./trusted/confirm_invoice";
import {confirmSalesReturn} from "./trusted/confirm_sales_return";
import {createCustomer, updateCustomer} from "./trusted/customer_profiles";
import {createReceipt} from "./trusted/create_receipt";
import {approveExpense, createExpense} from "./trusted/expenses";
import {createItem} from "./trusted/inventory";
import {postCustomerOpeningBalance} from "./trusted/post_opening_balance";
import {recordCashSettlement} from "./trusted/record_cash_settlement";

initializeApp();

export {
  auditCompanyDocumentWrite,
  auditItemWrite,
  auditUserWrite,
  approveExpense,
  confirmInvoice,
  confirmSalesReturn,
  createCustomer,
  createExpense,
  createItem,
  createReceipt,
  postCustomerOpeningBalance,
  recordCashSettlement,
  updateCustomer,
};
