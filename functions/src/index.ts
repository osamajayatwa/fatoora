import { initializeApp } from "firebase-admin/app";
import { submitInvoiceToJoFotara } from "./submit_invoice_to_jofotara";

initializeApp();

export { submitInvoiceToJoFotara };
