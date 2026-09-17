#!/usr/bin/env node
"use strict";

const {applicationDefault, initializeApp} = require("firebase-admin/app");
const {getFirestore} = require("firebase-admin/firestore");

function parseArgs(values) {
  const result = new Map();
  for (const value of values) {
    if (!value.startsWith("--")) continue;
    const [key, ...rest] = value.slice(2).split("=");
    result.set(key, rest.length === 0 ? true : rest.join("="));
  }
  return result;
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const projectId = String(args.get("project") || "").trim();
  const companyId = String(args.get("company") || "").trim();
  const apply = args.has("apply");
  const maxWrites = Number(args.get("max-writes") || 5000);
  if (!projectId || !companyId || !Number.isInteger(maxWrites) || maxWrites < 1) {
    throw new Error("Use --project=<id> --company=<id> [--apply] [--max-writes=<n>].");
  }
  if (apply && (args.get("confirm-project") !== projectId ||
      args.get("confirm-company") !== companyId)) {
    throw new Error("--apply requires matching project and company confirmations.");
  }
  initializeApp({credential: applicationDefault(), projectId});
  const firestore = getFirestore();
  const returns = await firestore.collection(
    `companies/${companyId}/sales_returns`,
  ).get();
  const missing = returns.docs.filter((document) =>
    !["cash", "credit", "partial"].includes(document.data().originalPaymentType));
  const invoiceIds = [...new Set(missing.map((document) =>
    String(document.data().originalInvoiceId || "").trim()).filter(Boolean))];
  const types = new Map();
  for (let start = 0; start < invoiceIds.length; start += 100) {
    const references = invoiceIds.slice(start, start + 100).map((id) =>
      firestore.doc(`companies/${companyId}/invoices/${id}`));
    const invoices = references.length ? await firestore.getAll(...references) : [];
    for (const invoice of invoices) {
      const type = String(invoice.data()?.paymentType || "").trim();
      if (["cash", "credit", "partial"].includes(type)) types.set(invoice.id, type);
    }
  }
  const changes = missing.map((document) => ({
    reference: document.ref,
    paymentType: types.get(String(document.data().originalInvoiceId || "").trim()),
  })).filter((change) => change.paymentType);
  const summary = {
    mode: apply ? "apply" : "dry-run",
    projectId,
    companyId,
    scannedReturns: returns.size,
    missingReportingField: missing.length,
    plannedWrites: changes.length,
    unresolved: missing.length - changes.length,
    maxWrites,
  };
  console.log(JSON.stringify(summary, null, 2));
  if (!apply) return;
  if (changes.length > maxWrites) {
    throw new Error(`Planned writes ${changes.length} exceed --max-writes=${maxWrites}.`);
  }
  for (let start = 0; start < changes.length; start += 400) {
    const batch = firestore.batch();
    for (const change of changes.slice(start, start + 400)) {
      batch.update(change.reference, {originalPaymentType: change.paymentType});
    }
    await batch.commit();
  }
  console.log(JSON.stringify({...summary, appliedWrites: changes.length}, null, 2));
}

main().catch((error) => {
  console.error(error instanceof Error ? error.message : error);
  process.exitCode = 1;
});
