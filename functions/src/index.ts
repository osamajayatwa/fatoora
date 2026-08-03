import { initializeApp } from "firebase-admin/app";
import { submitInvoiceToJoFotara } from "./submit_invoice_to_jofotara";
import {
  auditCompanyDocumentWrite,
  auditItemWrite,
  auditUserWrite,
} from "./audit/audit_triggers";

initializeApp();

export {
  submitInvoiceToJoFotara,
  auditCompanyDocumentWrite,
  auditItemWrite,
  auditUserWrite,
};
