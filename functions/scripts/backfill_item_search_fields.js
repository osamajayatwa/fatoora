#!/usr/bin/env node
"use strict";

const {applicationDefault, initializeApp} = require("firebase-admin/app");
const {getFirestore} = require("firebase-admin/firestore");

function argumentsMap(argv) {
  const result = new Map();
  for (const value of argv) {
    if (!value.startsWith("--")) continue;
    const [key, ...parts] = value.slice(2).split("=");
    result.set(key, parts.length === 0 ? true : parts.join("="));
  }
  return result;
}

function normalize(value) {
  return typeof value === "string" ? value.trim().toLowerCase() : "";
}

function searchKeywords(values) {
  const result = new Set();
  for (const value of values) {
    const text = normalize(value);
    if (!text) continue;
    result.add(text);
    for (const token of text.split(/[\s\-_/]+/u)) {
      if (!token) continue;
      result.add(token);
      for (let index = 1; index <= token.length && index <= 20; index += 1) {
        result.add(token.slice(0, index));
      }
    }
  }
  return [...result].sort();
}

async function main() {
  const args = argumentsMap(process.argv.slice(2));
  const projectId = String(args.get("project") || "").trim();
  const companyId = String(args.get("company") || "").trim();
  const apply = args.has("apply");
  const maxWrites = Number(args.get("max-writes") || 5000);
  if (!projectId || !companyId || !Number.isInteger(maxWrites) || maxWrites < 1) {
    throw new Error("Use --project=<id> --company=<id> [--apply] [--max-writes=<n>].");
  }
  if (apply && (args.get("confirm-project") !== projectId ||
      args.get("confirm-company") !== companyId)) {
    throw new Error("--apply requires matching --confirm-project and --confirm-company.");
  }

  initializeApp({credential: applicationDefault(), projectId});
  const firestore = getFirestore();
  const snapshot = await firestore.collection("items")
    .where("companyId", "==", companyId)
    .get();
  const changes = snapshot.docs.map((document) => {
    const data = document.data();
    const stock = Number.isFinite(data.currentStock) ? data.currentStock : 0;
    const minimum = Number.isFinite(data.minStock) ? data.minStock : 0;
    const cost = Number.isFinite(data.costPrice) ? data.costPrice : 0;
    const trackStock = data.trackStock !== false;
    return {
      reference: document.ref,
      nameLower: normalize(data.name),
      searchKeywords: searchKeywords([
        data.name,
        data.code,
        data.description,
        data.barcode,
        data.category,
      ]),
      inventoryValue: Math.round(stock * cost * 1000) / 1000,
      stockStatus: !trackStock ? "untracked" : stock <= 0 ? "out" :
        stock <= minimum ? "low" : "ok",
    };
  }).filter((next, index) => {
    const data = snapshot.docs[index].data();
    return data.nameLower !== next.nameLower ||
      JSON.stringify(data.searchKeywords || []) !== JSON.stringify(next.searchKeywords) ||
      data.inventoryValue !== next.inventoryValue ||
      data.stockStatus !== next.stockStatus;
  });
  const summary = {
    mode: apply ? "apply" : "dry-run",
    projectId,
    companyId,
    scannedItems: snapshot.size,
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
      batch.update(change.reference, {
        nameLower: change.nameLower,
        searchKeywords: change.searchKeywords,
        inventoryValue: change.inventoryValue,
        stockStatus: change.stockStatus,
      });
    }
    await batch.commit();
  }
  console.log(JSON.stringify({...summary, appliedWrites: changes.length}, null, 2));
}

main().catch((error) => {
  console.error(error instanceof Error ? error.message : error);
  process.exitCode = 1;
});
