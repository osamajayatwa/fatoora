"use strict";

// Offline-only reconciliation. No Firebase SDK, credentials, network or writes.
// All arithmetic is in integer thousandths, independently of posting helpers.
const COLLECTIONS = ["items", "invoices", "inventory_transfers", "sales_returns",
  "stock_movements", "rep_inventory_movements", "rep_inventory_balances", "customers",
  "customer_transactions", "receipts", "expenses", "settlements", "cash_movements",
  "cash_balances", "financial_ledger_entries"];

function exactAuditUnits(number) {
  if (typeof number !== "number" || !Number.isFinite(number)) throw new Error("Invalid audit numeric value");
  const scaled = Math.round(number * 1000);
  if (!Number.isSafeInteger(scaled) || Math.abs(number * 1000 - scaled) > 0.0001) throw new Error("Unsupported audit precision/range");
  return BigInt(scaled);
}

function formatAuditUnits(units) {
  const absolute = units < 0n ? -units : units;
  return `${units < 0n ? "-" : ""}${absolute / 1000n}.${String(absolute % 1000n).padStart(3, "0")}`;
}

function reconcileSnapshot(snapshot) {
  const issues = [], warnings = [], checks = [];
  const company = snapshot.companyId;
  if (typeof company !== "string" || !company) throw new Error("companyId is required");
  const data = snapshot.collections || {};
  const issue = (code, collection, id, details = {}) => issues.push({severity: "critical", code,
    path: collection === "items" ? `items/${id}` : `companies/${company}/${collection}/${id}`,
    ...details, repair: "Investigate source evidence; compensating correction requires approval."});
  const warn = (message) => {if (!warnings.includes(message)) warnings.push(message);};
  if (snapshot.fullHistory !== true) warn("Full history including approved opening events is not attested; no historical completeness conclusion is possible.");
  const tables = {};
  for (const name of COLLECTIONS) {
    if (!Array.isArray(data[name])) warn(`Missing collection: ${name}`);
    tables[name] = new Map();
    for (const row of data[name] || []) {
      if (!row.id || tables[name].has(row.id)) {issue("duplicate-or-missing-identity", name, row.id || "?"); continue;}
      if (row.companyId && row.companyId !== company) {issue("foreign-company-record", name, row.id); continue;}
      tables[name].set(row.id, row);
    }
  }
  const rows = (name) => [...tables[name].values()];
  const value = exactAuditUnits;
  const amount = (number) => Number(number) / 1000;
  const add = (map, key, delta) => map.set(key, (map.get(key) || 0n) + delta);
  function compare(code, collection, id, expected, actual) {
    if (expected !== actual) issue(code, collection, id, {expected: amount(expected), actual: amount(actual), difference: amount(actual - expected)});
    checks.push({code, collection, id, expected: amount(expected), actual: amount(actual), pass: expected === actual});
  }
  function guard(collection, row, fn) {
    try {fn();} catch (error) {issue("invalid-source-data", collection, row.id, {message: error.message});}
  }
  const stock = new Map(), custody = new Map(), cash = new Map(), sourceCash = new Map();
  const warehouseStock = new Map(), externalStock = new Map(), companyStock = new Map();
  const customerLedger = new Map(), sourceAR = new Map(), ledgerAR = new Map(), ledgerCash = new Map();
  const cashKey = (row) => {
    if (row.cashAccount === "company_cash") return "company_cash";
    if (row.cashAccount === "rep_cash" && row.salesRepId) return `rep_${row.salesRepId}`;
    throw new Error("Unrecognized cash account/owner");
  };
  const totals = {sales: 0n, receipts: 0n, returns: 0n, expenses: 0n, settlements: 0n};
  for (const collection of ["stock_movements", "rep_inventory_movements", "cash_movements"]) {
    const isCash = collection === "cash_movements", isRep = collection === "rep_inventory_movements";
    for (const row of rows(collection)) guard(collection, row, () => {
      const qty = value(isCash ? row.amount : row.quantity);
      if (qty <= 0n || !["in", "out"].includes(row.direction)) throw new Error("Invalid movement direction/amount");
      const signed = row.direction === "in" ? qty : -qty;
      const before = value(isCash ? row.balanceBefore : row.quantityBefore);
      const after = value(isCash ? row.balanceAfter : row.quantityAfter);
      compare("movement-equation", collection, row.id, before + signed, after);
      if (after < 0n && !isCash) issue("negative-inventory", collection, row.id);
      const key = isCash ? cashKey(row) : isRep ? `${row.salesRepId}_${row.itemId}` : row.itemId;
      add(isCash ? cash : isRep ? custody : stock, key, signed);
      if (!isCash && !isRep) {
        add(warehouseStock, `${row.warehouseId || "default_warehouse"}:${row.itemId}`, signed);
        if (["item", "manual_adjustment"].includes(row.referenceType)) add(externalStock, row.itemId, signed);
      }
      if (!isCash) {
        const source = row.referenceType;
        const collectionName = ["invoice"].includes(source) ? "invoices" :
          ["salesReturn", "sales_return"].includes(source) ? "sales_returns" :
          ["inventoryTransfer", "inventory_transfer"].includes(source) ? "inventory_transfers" : null;
        if (collectionName) {
          const business = tables[collectionName].get(row.referenceId);
          if (!business || (business.invoiceStatus || business.status) !== "confirmed") issue("orphan-or-unposted-movement", collection, row.id);
        } else if (!isRep && ["item", "manual_adjustment"].includes(source)) {
          if (!row.notes && source === "manual_adjustment") issue("undocumented-adjustment", collection, row.id);
        } else warn(`Unmapped inventory movement: ${collection}/${row.id}`);
      }
    });
  }
  for (const [name, reconstructed, field] of [["items", stock, "currentStock"],
    ["rep_inventory_balances", custody, "quantity"], ["cash_balances", cash, "amount"]]) {
    for (const row of rows(name)) guard(name, row, () => {
      compare("balance-from-movements", name, row.id, reconstructed.get(row.id) || 0n, value(row[field]));
      if (name !== "cash_balances") add(companyStock, name === "items" ? row.id : row.itemId, value(row[field]));
      if (name === "items") compare("warehouse-balance-from-movements", name, row.id,
        warehouseStock.get(`${row.warehouseId || "default_warehouse"}:${row.id}`) || 0n, value(row[field]));
    });
    for (const key of reconstructed.keys()) if (!tables[name].has(key)) issue("missing-balance-document", name, key);
  }
  const saleMovements = (invoice) => rows(invoice.stockSourceType === "salesRep" ? "rep_inventory_movements" : "stock_movements")
    .filter((row) => row.referenceType === "invoice" && row.referenceId === invoice.id);
  for (const invoice of rows("invoices")) guard("invoices", invoice, () => {
    const posted = ["confirmed", "accepted"].includes(invoice.invoiceStatus) && invoice.financialPosted === true;
    if (!posted) {
      if (saleMovements(invoice).length || rows("customer_transactions").some((r) => r.sourceCollection === "invoices" && r.sourceId === invoice.id)) issue("unposted-invoice-has-effects", "invoices", invoice.id);
      return;
    }
    const initial = tables.cash_movements.get(`${invoice.id}_cash`);
    const initialPaid = initial ? value(initial.amount) : value(invoice.initialPaidAmount || 0);
    if (invoice.initialPaidAmount !== undefined) {
      compare("initial-invoice-payment", "invoices", invoice.id, value(invoice.initialPaidAmount), initial ? value(initial.amount) : 0n);
    }
    const grand = value(invoice.grandTotal);
    add(sourceAR, invoice.customerId, grand - initialPaid); totals.sales += grand;
    if (initial) add(sourceCash, cashKey(initial), initialPaid);
    if (invoice.inventoryPosted !== true) issue("missing-inventory-posting", "invoices", invoice.id);
    const expected = new Map(), actual = new Map();
    for (const line of invoice.items || []) {
      if (line.lineType === "custom") continue;
      if (typeof line.stockTrackedAtPosting !== "boolean") warn(`Legacy invoice has no immutable tracking snapshot: ${invoice.id}`);
      const tracked = (line.stockTrackedAtPosting === true || (line.stockTrackedAtPosting === undefined && saleMovements(invoice).some((m) => m.itemId === line.itemId)));
      if (tracked) {add(expected, line.itemId, value(line.quantity)); add(externalStock, line.itemId, -value(line.quantity));}
    }
    for (const movement of saleMovements(invoice)) {
      if (invoice.stockSourceType === "salesRep" && movement.salesRepId !== invoice.stockSourceSalesRepId) issue("wrong-custody-source", "invoices", invoice.id);
      add(actual, movement.itemId, value(movement.quantity));
    }
    for (const key of new Set([...expected.keys(), ...actual.keys()])) compare(`invoice-stock:${key}`, "invoices", invoice.id, expected.get(key) || 0n, actual.get(key) || 0n);
    for (const id of invoice.inventoryMovementIds || []) if (!saleMovements(invoice).some((r) => r.id === id)) issue("missing-linked-stock-movement", "invoices", invoice.id, {movementId: id});
  });
  for (const transfer of rows("inventory_transfers")) guard("inventory_transfers", transfer, () => {
    if (transfer.status !== "confirmed") return;
    const seen = new Set();
    for (const line of transfer.lines || []) {
      if (seen.has(line.itemId)) issue("duplicate-transfer-item", "inventory_transfers", transfer.id, {itemId: line.itemId});
      seen.add(line.itemId);
      const warehouse = rows("stock_movements").filter((r) => r.referenceId === transfer.id && r.referenceType === "inventory_transfer" && r.itemId === line.itemId);
      const rep = rows("rep_inventory_movements").filter((r) => r.referenceId === transfer.id && r.referenceType === "inventoryTransfer" && r.itemId === line.itemId);
      const signed = (list) => list.reduce((sum, r) => sum + (r.direction === "in" ? value(r.quantity) : -value(r.quantity)), 0n);
      const qty = value(line.quantity), sign = transfer.type === "warehouseToRep" ? -1n : 1n;
      compare("transfer-warehouse", "inventory_transfers", transfer.id, qty * sign, signed(warehouse));
      compare("transfer-custody", "inventory_transfers", transfer.id, -qty * sign, signed(rep));
      if (warehouse.length !== 1 || rep.length !== 1 || rep[0]?.salesRepId !== transfer.salesRepId) issue("unpaired-transfer", "inventory_transfers", transfer.id);
    }
  });
  for (const receipt of rows("receipts")) guard("receipts", receipt, () => {
    if (receipt.status && !["posted", "cancelled"].includes(receipt.status)) return;
    if (receipt.status === "cancelled") return; // Original plus explicit inverse net to zero.
    const collected = value(receipt.amount); totals.receipts += collected;
    add(sourceAR, receipt.customerId, -collected);
    const allocated = Object.values(receipt.invoiceAllocations || {}).reduce((s, n) => s + value(n), 0n);
    if (allocated > collected) issue("receipt-overallocation", "receipts", receipt.id);
    if (receipt.paymentMethod === "cash") add(sourceCash, receipt.createdByRole === "sales_rep" ? `rep_${receipt.createdByUid}` : "company_cash", collected);
    else if (!["bank", "check", "cliq"].includes(receipt.paymentMethod)) warn(`Unmapped historical payment method: ${receipt.id}/${receipt.paymentMethod}`);
  });
  const returnedLines = new Map();
  for (const returned of rows("sales_returns")) guard("sales_returns", returned, () => {
    if (returned.status !== "confirmed" || returned.financialPosted !== true) return;
    const grand = value(returned.grandTotal), refund = value(returned.cashRefundAmount || 0);
    totals.returns += grand; totals.sales -= grand;
    add(sourceAR, returned.customerId, -grand + refund);
    if (refund) {
      const movement = tables.cash_movements.get((returned.cashMovementIds || [])[0]);
      if (!movement) issue("missing-refund-cash", "sales_returns", returned.id);
      else add(sourceCash, cashKey(movement), -refund);
    }
    const original = tables.invoices.get(returned.originalInvoiceId);
    if (!original) {issue("missing-original-invoice", "sales_returns", returned.id); return;}
    for (const line of returned.items || []) {
      const source = (original.items || [])[line.originalIndex];
      if (!source) {issue("missing-original-line", "sales_returns", returned.id); continue;}
      const key = `${original.id}:${line.originalIndex}`;
      const prior = returnedLines.get(key) || {quantity: 0n, amount: 0n, original, source};
      prior.quantity += value(line.returnedQuantity); prior.amount += value(line.total);
      returnedLines.set(key, prior);
      const tracked = source.stockTrackedAtPosting === true ||
        (source.stockTrackedAtPosting === undefined && saleMovements(original).some((m) => m.itemId === line.itemId));
      if (line.lineType === "custom" || !tracked) continue;
      add(externalStock, line.itemId, value(line.returnedQuantity));
      const movements = rows(original.stockSourceType === "salesRep" ? "rep_inventory_movements" : "stock_movements")
        .filter((m) => m.referenceId === returned.id && m.itemId === line.itemId && m.sourceLineIndex === line.originalIndex && m.direction === "in");
      compare("returned-stock", "sales_returns", returned.id, value(line.returnedQuantity), movements.reduce((s, m) => s + value(m.quantity), 0n));
    }
  });
  for (const [key, line] of returnedLines) guard("invoices", line.original, () => {
    const sold = value(line.source.quantity), total = value(line.source.total);
    if (line.quantity > sold || line.amount > total) issue("return-exceeds-original", "invoices", line.original.id, {line: key});
    if (line.quantity === sold) compare("full-return-financial-total", "invoices", line.original.id, total, line.amount);
  });
  for (const key of new Set([...companyStock.keys(), ...externalStock.keys()])) compare("company-owned-stock", "items", key,
    externalStock.get(key) || 0n, companyStock.get(key) || 0n);
  for (const expense of rows("expenses")) guard("expenses", expense, () => {
    if (!["posted", "approved"].includes(expense.status)) return;
    const spent = value(expense.amount); totals.expenses += spent;
    if (expense.fundingSource === "company_cash") add(sourceCash, "company_cash", -spent);
    else if (expense.fundingSource === "rep_collected_cash") add(sourceCash, `rep_${expense.salesRepId}`, -spent);
    else if (expense.fundingSource !== "personal_cash") warn(`Unmapped expense funding: ${expense.id}`);
    if (expense.category === "other") warn(`Expense classification requires review for owner drawings/personal use: ${expense.id}`);
  });
  for (const settlement of rows("settlements")) guard("settlements", settlement, () => {
    if (settlement.status !== "posted") return;
    const settled = value(settlement.amount); totals.settlements += settled;
    add(sourceCash, "company_cash", settled); add(sourceCash, `rep_${settlement.salesRepId}`, -settled);
    const pair = rows("cash_movements").filter((m) => m.sourceCollection === "settlements" && m.sourceId === settlement.id);
    if (pair.length !== 2 || !pair.some((m) => m.direction === "in" && cashKey(m) === "company_cash" && value(m.amount) === settled) ||
      !pair.some((m) => m.direction === "out" && cashKey(m) === `rep_${settlement.salesRepId}` && value(m.amount) === settled)) issue("unpaired-cash-settlement", "settlements", settlement.id);
  });
  for (const row of rows("cash_movements")) guard("cash_movements", row, () => {
    if (row.movementType === "opening_balance" && row.sourceCollection === "cash_movements") add(sourceCash, cashKey(row), row.direction === "in" ? value(row.amount) : -value(row.amount));
    else if (!["invoices", "receipts", "sales_returns", "settlements", "expenses"].includes(row.sourceCollection)) warn(`Unmapped cash movement: ${row.id}`);
  });
  for (const row of rows("customer_transactions")) guard("customer_transactions", row, () => {
    // Original opening row's signedAmount/amount can be changed by the existing
    // correction workflow. Its immutable debit/credit remain authoritative.
    const delta = value(row.debitAmount) - value(row.creditAmount);
    add(customerLedger, row.customerId, delta);
    if (["opening_balance", "opening_balance_adjustment"].includes(row.transactionType)) add(sourceAR, row.customerId, delta);
  });
  const ledgerMetrics = Object.fromEntries(Object.keys(totals).map((k) => [k, 0n]));
  for (const row of rows("financial_ledger_entries")) guard("financial_ledger_entries", row, () => {
    const posted = value(row.amount);
    if (posted <= 0n || !row.debitAccountKey || !row.creditAccountKey || row.debitAccountKey === row.creditAccountKey) throw new Error("Invalid balanced account pair");
    // Each persisted pair has one equal debit and credit; account reconciliation
    // below is independent and detects economically wrong but balanced pairs.
    for (const [key, sign] of [[row.debitAccountKey, 1n], [row.creditAccountKey, -1n]]) {
      if (key.startsWith("customer:")) add(ledgerAR, key.slice(9), posted * sign);
      if (key === "company_cash" || key.startsWith("rep_cash:")) add(ledgerCash, key === "company_cash" ? key : `rep_${key.slice(9)}`, posted * sign);
    }
    for (const metric of Object.keys(ledgerMetrics)) ledgerMetrics[metric] += value(row[`metric${metric[0].toUpperCase()}${metric.slice(1)}`] || 0);
  });
  for (const customer of rows("customers")) guard("customers", customer, () => {
    const expected = sourceAR.get(customer.id) || 0n;
    compare("receivable-from-sources", "customers", customer.id, expected, value(customer.currentBalance));
    compare("customer-ledger-from-sources", "customers", customer.id, expected, customerLedger.get(customer.id) || 0n);
    compare("general-ledger-receivable", "customers", customer.id, expected, ledgerAR.get(customer.id) || 0n);
  });
  for (const key of new Set([...sourceAR.keys(), ...customerLedger.keys(), ...ledgerAR.keys()])) {
    if (!tables.customers.has(key)) issue("missing-customer-with-postings", "customers", key);
  }
  for (const key of new Set([...cash.keys(), ...sourceCash.keys(), ...ledgerCash.keys()])) {
    compare("cash-from-sources", "cash_balances", key, sourceCash.get(key) || 0n, cash.get(key) || 0n);
    compare("general-ledger-cash", "cash_balances", key, sourceCash.get(key) || 0n, ledgerCash.get(key) || 0n);
  }
  for (const key of Object.keys(totals)) compare(`report-metric:${key}`, "financial_ledger_entries", "all", totals[key], ledgerMetrics[key]);
  if (snapshot.reportTotals) for (const key of Object.keys(totals)) if (key in snapshot.reportTotals) guard("reports", {id: key}, () =>
    compare(`export-metric:${key}`, "reports", key, totals[key], value(snapshot.reportTotals[key])));
  return {schemaVersion: 1, companyId: company, fullHistory: snapshot.fullHistory === true,
    status: issues.length ? "FAIL" : warnings.length ? "BLOCKED" : "PASS", issues, warnings, checks,
    totals: Object.fromEntries(Object.entries(totals).map(([k, n]) => [k, amount(n)])),
    recordCounts: Object.fromEntries(COLLECTIONS.map((n) => [n, tables[n].size]))};
}

module.exports = {COLLECTIONS, reconcileSnapshot, exactAuditUnits, formatAuditUnits};
if (require.main === module) {
  const {readFileSync} = require("node:fs");
  if (process.argv.length !== 3 || process.argv[2].startsWith("--")) {
    process.stderr.write("Usage: node functions/scripts/integrity_reconciliation.js <authorized-snapshot.json>\nNo online reads or apply mode.\n");
    process.exitCode = 2;
  } else {
    const result = reconcileSnapshot(JSON.parse(readFileSync(process.argv[2], "utf8")));
    process.stdout.write(JSON.stringify(result, null, 2) + "\n");
    process.exitCode = result.status === "PASS" ? 0 : result.status === "FAIL" ? 1 : 2;
  }
}
