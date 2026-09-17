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

function text(value) {
  return typeof value === "string" ? value.trim().toLowerCase() : "";
}

function keywords(values) {
  const result = new Set();
  for (const value of values) {
    const normalized = text(value);
    if (!normalized) continue;
    result.add(normalized);
    for (const token of normalized.split(/[\s\-_/]+/u)) {
      if (!token) continue;
      result.add(token);
      for (let index = 1; index <= token.length && index <= 20; index += 1) {
        result.add(token.slice(0, index));
      }
    }
  }
  return [...result].sort();
}

function projectedKeywords(collection, data) {
  if (collection === "receipts") {
    return keywords([
      data.receiptNumber,
      data.customerSnapshot?.name,
      data.salesRepName,
      data.paymentMethod,
    ]);
  }
  if (collection === "sales_returns") {
    return keywords([
      data.returnNumber,
      data.originalInvoiceNumber,
      data.customerSnapshot?.name,
      data.salesRepName,
    ]);
  }
  if (collection === "inventory_transfers") {
    return keywords([
      data.transferNumber,
      data.salesRepNameSnapshot,
      ...(Array.isArray(data.lines) ? data.lines.flatMap((line) => [
        line?.modelSnapshot,
        line?.itemNameSnapshot,
      ]) : []),
    ]);
  }
  if (collection === "stock_movements") {
    return keywords([
      data.itemName,
      data.itemCode,
      data.referenceNumber,
      data.sourceNumber,
    ]);
  }
  if (collection === "rep_inventory_movements") {
    return keywords([
      data.itemNameSnapshot,
      data.modelSnapshot,
      data.transferNumber,
      data.salesRepNameSnapshot,
    ]);
  }
  return keywords([
    data.id,
    data.description,
    data.customCategoryName,
    data.category,
    data.paidByName,
  ]);
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
  const collections = [
    "receipts",
    "sales_returns",
    "expenses",
    "inventory_transfers",
    "stock_movements",
    "rep_inventory_movements",
  ];
  const changes = [];
  const scanned = {};
  for (const collection of collections) {
    const snapshot = await firestore.collection(
      `companies/${companyId}/${collection}`,
    ).get();
    scanned[collection] = snapshot.size;
    for (const document of snapshot.docs) {
      const next = projectedKeywords(collection, document.data());
      if (JSON.stringify(document.data().searchKeywords || []) !== JSON.stringify(next)) {
        changes.push({reference: document.ref, searchKeywords: next});
      }
    }
  }
  const summary = {
    mode: apply ? "apply" : "dry-run",
    projectId,
    companyId,
    scanned,
    plannedWrites: changes.length,
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
      batch.update(change.reference, {searchKeywords: change.searchKeywords});
    }
    await batch.commit();
  }
  console.log(JSON.stringify({...summary, appliedWrites: changes.length}, null, 2));
}

main().catch((error) => {
  console.error(error instanceof Error ? error.message : error);
  process.exitCode = 1;
});
