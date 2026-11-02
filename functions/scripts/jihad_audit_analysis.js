"use strict";
const {exactAuditUnits: units, formatAuditUnits: format} = require("./integrity_reconciliation");
const {Blocked} = require("./jihad_readonly_reader");
const FINAL = new Set(["confirmed", "accepted"]);
const lineType = (line) => line.lineType || (line.itemId && !line.itemId.startsWith("manual-") ? "catalog" : "custom");
const sum = (rows, field) => rows.reduce((total, row) => total + units(row[field]), 0n);
const add = (map, key, delta) => map.set(key, (map.get(key) || 0n) + delta);
const index = (rows) => new Map(rows.map((row) => [row.id, row]));
function time(value) {
  const match = typeof value === "string" && value.match(/^(.*T\d{2}:\d{2}:\d{2})(?:\.(\d{1,9}))?Z$/);
  if (!match || !Number.isFinite(Date.parse(match[1] + "Z"))) throw new Blocked("MISSING_EVENT_TIMESTAMP");
  return BigInt(Date.parse(match[1] + "Z")) * 1000000n + BigInt((match[2] || "").padEnd(9, "0"));
}
function roundedRatio(n, d) {
  if (d <= 0n) throw new Blocked("INVALID_SOURCE_QUANTITY");
  const sign = n < 0n ? -1n : 1n;
  return sign * ((n * sign + d / 2n) / d);
}
class Findings {
  constructor() {this.findings = []; this.blockers = []; this.checks = []; this.custody = []; this.financial = [];}
  fail(code, refs = {}, expected, actual) {
    this.findings.push({code, refs, certainty: "CONFIRMED_DATA_DISCREPANCY",
      ...(expected !== undefined ? {expected: format(expected), actual: format(actual), difference: format(actual - expected)} : {}),
      cause: "Historical source evidence; deployed code version and physical delivery require separate review.",
      correction: "Separate approval required for linked, idempotent compensation after source/dependency review; never edit balances or replay posting."});
  }
  block(code, refs = {}) {if (!this.blockers.some((b) => b.code === code && JSON.stringify(b.refs) === JSON.stringify(refs))) this.blockers.push({code, refs});}
  compare(code, refs, expected, actual) {
    this.checks.push({code, refs, expected: format(expected), actual: format(actual), pass: expected === actual});
    if (expected !== actual) this.fail(code, refs, expected, actual);
  }
  guarded(refs, callback) {try {callback();} catch (e) {this.block(e instanceof Blocked ? e.code : "INVALID_NUMERIC_OR_SOURCE_DATA", refs);}}
  get status() {return this.blockers.length ? "BLOCKED" : this.findings.length ? "FAIL" : "PASS";}
}
function originalIndex(invoice, returnedLine) {
  if (Number.isInteger(returnedLine.originalIndex) && invoice.items[returnedLine.originalIndex]) return returnedLine.originalIndex;
  const reference = returnedLine.originalInvoiceItemId;
  const matches = invoice.items.map((line, i) => ({i, refs: [`${invoice.id}:${i}`, ...(line.lineId ? [`${invoice.id}:line:${line.lineId}`] : [])]}))
    .filter((row) => row.refs.includes(reference));
  if (matches.length !== 1) throw new Blocked("AMBIGUOUS_RETURN_LINE");
  return matches[0].i;
}
function analyzeInventory(data, rep, result) {
  const invoices = index(data.invoices), transfers = index(data.inventory_transfers), returns = index(data.sales_returns);
  const balances = index(data.rep_inventory_balances), items = index(data.items);
  const actualByItem = new Map(), expectedByItem = new Map(), tracking = new Map();
  const moves = data.rep_inventory_movements;
  const stock = data.stock_movements;
  const sourceMoves = (collection, type, id) => collection.filter((m) => m.referenceType === type && m.referenceId === id);
  const ref = (kind, id, itemId) => ({[kind]: id, itemId});
  for (const m of [...moves, ...stock]) result.guarded({movementId: m.id, itemId: m.itemId}, () => {
    if (!["in", "out"].includes(m.direction) || units(m.quantity) <= 0n) throw new Blocked("INVALID_MOVEMENT");
    result.compare("MOVEMENT_EQUATION", {movementId: m.id, itemId: m.itemId},
      units(m.quantityBefore) + (m.direction === "in" ? units(m.quantity) : -units(m.quantity)), units(m.quantityAfter));
    if (units(m.quantityAfter) < 0n) result.fail("NEGATIVE_INVENTORY", {movementId: m.id, itemId: m.itemId});
  });
  for (const m of moves) result.guarded({movementId: m.id}, () => {
    if (m.salesRepId !== rep.id) throw new Blocked("FOREIGN_CUSTODY_OWNER");
    add(actualByItem, m.itemId, (m.direction === "in" ? 1n : -1n) * units(m.quantity));
    const table = {invoice: invoices, inventoryTransfer: transfers, salesReturn: returns}[m.referenceType];
    if (!table?.has(m.referenceId)) result.block("CUSTODY_SOURCE_HISTORY_INCOMPLETE", {movementId: m.id, itemId: m.itemId});
  });
  function checkEffects(kind, source, expected, repType, warehouseType, destination) {
    const own = sourceMoves(moves, repType, source.id), warehouse = sourceMoves(stock, warehouseType, source.id);
    const allItems = new Set([...expected.keys(), ...own.map((m) => m.itemId), ...warehouse.map((m) => m.itemId)]);
    for (const itemId of allItems) result.guarded(ref(kind, source.id, itemId), () => {
      const e = expected.get(itemId) || {in: 0n, out: 0n};
      for (const direction of ["in", "out"]) {
        const repExpected = destination === "rep" ? e[direction] : 0n;
        const warehouseExpected = destination === "paired" ? e[direction === "in" ? "out" : "in"] : destination === "warehouse" ? e[direction] : 0n;
        const ownExpected = destination === "paired" ? e[direction] : repExpected;
        result.compare(`CUSTODY_${direction.toUpperCase()}`, ref(kind, source.id, itemId), ownExpected,
          sum(own.filter((m) => m.itemId === itemId && m.direction === direction), "quantity"));
        result.compare(`WAREHOUSE_${direction.toUpperCase()}`, ref(kind, source.id, itemId), warehouseExpected,
          sum(warehouse.filter((m) => m.itemId === itemId && m.direction === direction), "quantity"));
        const actualRep = sum(own.filter((m) => m.itemId === itemId && m.direction === direction), "quantity");
        if (direction === "out" && ownExpected > 0n && actualRep > ownExpected) result.fail("EXCESS_OR_DUPLICATED_CUSTODY_DEDUCTION", ref(kind, source.id, itemId), ownExpected, actualRep);
        if (destination === "rep" && warehouse.some((m) => m.itemId === itemId)) result.fail("WRONG_STOCK_ATTRIBUTION", ref(kind, source.id, itemId));
      }
      if (["rep", "paired"].includes(destination)) add(expectedByItem, itemId, e.in - e.out);
    });
    const links = kind === "invoiceId" ? source.inventoryMovementIds : kind === "returnId" ? source.stockMovementIds : undefined;
    if (links !== undefined) {
      if (!Array.isArray(links)) throw new Blocked("INVALID_POSTING_LINKS");
      const actual = [...own, ...warehouse];
      if (new Set(links).size !== links.length || links.some((id) => !actual.some((m) => m.id === id)) || actual.some((m) => !links.includes(m.id))) result.fail("INVENTORY_POSTING_LINKS_MISMATCH", {[kind]: source.id});
    }
  }
  function expectedMap() {return new Map();}
  function expect(map, itemId, direction, quantity) {
    const entry = map.get(itemId) || {in: 0n, out: 0n}; entry[direction] += quantity; map.set(itemId, entry);
  }
  for (const transfer of data.inventory_transfers) result.guarded({transferId: transfer.id}, () => {
    if (transfer.salesRepId !== rep.id) throw new Blocked("TRANSFER_OUTSIDE_REP_SCOPE");
    const expected = expectedMap(), seen = new Set();
    if (transfer.status === "confirmed") {
      if (!["warehouseToRep", "repToWarehouse"].includes(transfer.type) || !Array.isArray(transfer.lines) || !transfer.lines.length) throw new Blocked("UNSUPPORTED_TRANSFER_SOURCE");
      for (const line of transfer.lines) {
        if (seen.has(line.itemId)) result.fail("DUPLICATE_TRANSFER_ITEM", {transferId: transfer.id, itemId: line.itemId});
        seen.add(line.itemId);
        const quantity = units(line.quantity); if (quantity <= 0n) throw new Blocked("INVALID_TRANSFER_QUANTITY");
        expect(expected, line.itemId, transfer.type === "warehouseToRep" ? "in" : "out", quantity);
      }
    }
    checkEffects("transferId", transfer, expected, "inventoryTransfer", "inventory_transfer", "paired");
  });
  for (const invoice of data.invoices) result.guarded({invoiceId: invoice.id}, () => {
    const posted = FINAL.has(invoice.invoiceStatus) && invoice.financialPosted === true;
    if (FINAL.has(invoice.invoiceStatus) && (invoice.financialPosted !== true || invoice.inventoryPosted !== true)) result.fail("PARTIAL_INVOICE_POSTING_FLAGS", {invoiceId: invoice.id});
    const expected = expectedMap();
    if (!posted) {checkEffects("invoiceId", invoice, expected, "invoice", "invoice", "rep"); return;}
    if (!["salesRep", "companyWarehouse"].includes(invoice.stockSourceType)) throw new Blocked("HISTORICAL_STOCK_SOURCE_UNKNOWN");
    if (invoice.createdByRole === "sales_rep" && (invoice.stockSourceType !== "salesRep" || invoice.stockSourceSalesRepId !== invoice.createdByUid || invoice.salesRepId !== invoice.createdByUid)) result.fail("REP_STOCK_SOURCE_AUTHORIZATION_MISMATCH", {invoiceId: invoice.id});
    if (invoice.stockSourceType === "salesRep" && invoice.stockSourceSalesRepId !== rep.id) throw new Blocked("OTHER_REP_STOCK_DEPENDENCY");
    if (!Array.isArray(invoice.items) || !invoice.items.length) throw new Blocked("INVOICE_LINE_HISTORY_MISSING");
    invoice.items.forEach((line, i) => {
      const refs = {invoiceId: invoice.id, itemId: line.itemId, lineIndex: i};
      if (lineType(line) === "custom") {tracking.set(`${invoice.id}:${i}`, false); return;}
      const evidence = [...sourceMoves(moves, "invoice", invoice.id), ...sourceMoves(stock, "invoice", invoice.id)].some((m) => m.itemId === line.itemId && m.direction === "out");
      const tracked = typeof line.stockTrackedAtPosting === "boolean" ? line.stockTrackedAtPosting : evidence ? true : undefined;
      if (tracked === undefined) {
        let recordedFlag = null;
        try {
          const at = time(invoice.inventoryPostedAt || invoice.financialPostedAt);
          const evidence = data.audit_events.filter((event) => event.entityType === "item" && event.entityId === line.itemId && time(event.occurredAt) < at)
            .sort((a, b) => time(a.occurredAt) < time(b.occurredAt) ? -1 : 1);
          for (const event of evidence) for (const change of event.changes || []) if (change.field === "trackStock") recordedFlag = change.after;
        } catch {} // Missing/ambiguous audit time is a gap, never a stock inference.
        if (!result.trackingEvidence) result.trackingEvidence = [];
        result.trackingEvidence.push({...refs, currentFlag: items.get(line.itemId)?.trackStock ?? null,
          lastRecordedFlagBeforePosting: recordedFlag, immutablePostingFlag: null,
          conditionalSaleQuantity: format(units(line.quantity)), recordedCustodySaleOutQuantity: format(sum(sourceMoves(moves, "invoice", invoice.id).filter((m) => m.itemId === line.itemId && m.direction === "out"), "quantity")),
          conclusion: "Historical tracking/delivery evidence required; current flag or incomplete audit trail is not proof of posting-time state."});
        result.block(items.get(line.itemId)?.trackStock === false ? "DISABLED_TRACKING_HISTORICAL_EVIDENCE_NEEDED" : "TRACKING_AT_POSTING_UNKNOWN", refs);
        return;
      }
      tracking.set(`${invoice.id}:${i}`, tracked);
      if (tracked) expect(expected, line.itemId, "out", units(line.quantity));
    });
    checkEffects("invoiceId", invoice, expected, "invoice", "invoice", invoice.stockSourceType === "salesRep" ? "rep" : "warehouse");
    if (items.size && invoice.items.some((line) => lineType(line) === "catalog" && !items.has(line.itemId))) result.block("CATALOG_HISTORY_MISSING", {invoiceId: invoice.id});
  });
  const returned = new Map();
  for (const returnedDoc of [...data.sales_returns].sort((a, b) => String(a.createdAt).localeCompare(String(b.createdAt)))) result.guarded({returnId: returnedDoc.id}, () => {
    const original = invoices.get(returnedDoc.originalInvoiceId);
    if (!original) throw new Blocked("RETURN_INVOICE_OUTSIDE_SCOPE");
    const expected = expectedMap();
    if (returnedDoc.status === "confirmed") {
      if (!returnedDoc.financialPosted || !returnedDoc.inventoryPosted) result.fail("PARTIAL_RETURN_POSTING_FLAGS", {returnId: returnedDoc.id, invoiceId: original.id});
      for (const line of returnedDoc.items || []) {
        const i = originalIndex(original, line), source = original.items[i];
        const key = `${original.id}:${i}`, prior = returned.get(key) || {q: 0n, amount: 0n};
        const q = units(line.returnedQuantity), sold = units(source.quantity);
        if (q <= 0n || prior.q + q > sold) result.fail("RETURN_EXCEEDS_SOLD_QUANTITY", {invoiceId: original.id, returnId: returnedDoc.id, lineIndex: i});
        const net = units(source.subtotal) - units(source.discount), tax = units(source.taxAmount);
        const cumulative = (quantity) => roundedRatio(net * quantity, sold) + roundedRatio(tax * quantity, sold);
        result.compare("RETURN_ROUNDING_ALLOCATION", {invoiceId: original.id, returnId: returnedDoc.id, lineIndex: i}, cumulative(prior.q + q) - cumulative(prior.q), units(line.total));
        returned.set(key, {q: prior.q + q, amount: prior.amount + units(line.total)});
        if (tracking.get(key) === undefined) throw new Blocked("RETURN_TRACKING_EVIDENCE_MISSING");
        if (tracking.get(key)) expect(expected, source.itemId, "in", q);
      }
    }
    checkEffects("returnId", returnedDoc, expected, "salesReturn", "sales_return", original.stockSourceType === "salesRep" ? "rep" : "warehouse");
  });
  for (const invoice of data.invoices) result.guarded({invoiceId: invoice.id}, () => {
    const confirmed = data.sales_returns.filter((row) => row.originalInvoiceId === invoice.id && row.status === "confirmed");
    for (const [field, source] of [["returnedTotal", "grandTotal"], ["returnedReceivableAmount", "receivableReduction"], ["cashRefundAmount", "cashRefundAmount"], ["customerCreditAmount", "customerCreditAmount"]]) {
      if (invoice[field] !== undefined) result.compare("RETURN_CACHED_TOTAL", {invoiceId: invoice.id, component: field}, sum(confirmed, source), units(invoice[field]));
    }
    if (invoice.returnedQuantitiesByItem !== undefined) {
      if (!invoice.returnedQuantitiesByItem || Array.isArray(invoice.returnedQuantitiesByItem)) throw new Blocked("INVALID_RETURN_QUANTITY_CACHE");
      const expected = new Map(), actual = new Map();
      for (const row of confirmed) for (const line of row.items) add(expected, originalIndex(invoice, line), units(line.returnedQuantity));
      for (const [key, quantity] of Object.entries(invoice.returnedQuantitiesByItem)) {
        add(actual, originalIndex(invoice, {originalInvoiceItemId: key}), units(quantity));
      }
      for (const i of new Set([...expected.keys(), ...actual.keys()])) result.compare("RETURN_CACHED_QUANTITY", {invoiceId: invoice.id, lineIndex: i}, expected.get(i) || 0n, actual.get(i) || 0n);
    }
  });
  const itemIds = new Set([...moves.map((m) => m.itemId), ...data.rep_inventory_balances.map((b) => b.itemId), ...expectedByItem.keys()]);
  for (const itemId of itemIds) result.guarded({itemId}, () => {
    const history = moves.filter((m) => m.itemId === itemId).map((m) => ({...m, at: time(m.createdAt)})).sort((a, b) => a.at < b.at ? -1 : a.at > b.at ? 1 : 0);
    let running = 0n, complete = true;
    for (let i = 0; i < history.length;) {
      let end = i + 1; while (end < history.length && history[end].at === history[i].at) end++;
      const group = history.slice(i, end);
      while (group.length) {
        const next = group.findIndex((m) => units(m.quantityBefore) === running);
        if (next < 0) {complete = false; break;}
        running = units(group.splice(next, 1)[0].quantityAfter);
      }
      if (!complete) break;
      i = end;
    }
    const balance = balances.get(`${rep.id}_${itemId}`);
    if (!complete || (!history.length && (!balance || units(balance.quantity) !== 0n))) {result.block("CUSTODY_OPENING_OR_CHAIN_HISTORY_INCOMPLETE", {itemId}); return;}
    if (!balance) {result.fail("CUSTODY_BALANCE_MISSING", {itemId}); return;}
    if (balance.salesRepId !== rep.id || balance.itemId !== itemId) throw new Blocked("CUSTODY_BALANCE_IDENTITY_INVALID");
    result.compare("CUSTODY_MOVEMENT_CLOSING", {itemId}, actualByItem.get(itemId) || 0n, units(balance.quantity));
    if (!result.blockers.length) result.compare("CUSTODY_SOURCE_CLOSING", {itemId}, expectedByItem.get(itemId) || 0n, units(balance.quantity));
    if (balance.hasStock !== (units(balance.quantity) > 0n)) result.fail("CUSTODY_VISIBILITY_PROJECTION", {itemId});
    if (units(balance.quantity) > 0n && items.get(itemId)?.trackStock === false) result.fail("DISABLED_TRACKING_WITH_POSITIVE_CUSTODY", {itemId});
    if (balance.lastMovementId && !history.some((m) => m.id === balance.lastMovementId)) result.fail("CUSTODY_LAST_MOVEMENT_MISSING", {itemId});
    else if (balance.lastMovementId && history.length && !history.some((m) => m.at === history.at(-1).at && m.id === balance.lastMovementId && units(m.quantityAfter) === units(balance.quantity))) result.fail("CUSTODY_LAST_MOVEMENT_STALE", {itemId});
    result.custody.push({itemId, openingBasis: "zero; complete recorded movement chain", expectedFromSources: result.blockers.length ? null : format(expectedByItem.get(itemId) || 0n),
      fromMovements: format(actualByItem.get(itemId) || 0n), persisted: format(units(balance.quantity))});
  });
  return tracking;
}

function analyzeFinance(data, rep, result) {
  const invoices = index(data.invoices), receipts = index(data.receipts);
  const expectedCustomer = new Map(), expectedSales = new Map(), expectedPaid = new Map();
  function sourceRows(collection, source) {return data[collection].filter((row) => row.sourceCollection === source.collection && row.sourceId === source.id);}
  function cashAccount(role, uid) {if (role === "admin") return "company_cash"; if (role === "sales_rep" && uid) return `rep_cash:${uid}`; throw new Blocked("CASH_COLLECTOR_IDENTITY_UNKNOWN");}
  const actualCashKey = (row) => row.cashAccount === "company_cash" ? "company_cash" : row.cashAccount === "rep_cash" && row.salesRepId ? `rep_cash:${row.salesRepId}` : "INVALID";
  function validateSource(source, customerId, debit, credit, pairs, cashEffects, refs) {
    const transactions = sourceRows("customer_transactions", source), ledger = sourceRows("financial_ledger_entries", source), cash = sourceRows("cash_movements", source);
    if (transactions.some((row) => row.customerId !== customerId)) result.fail("CUSTOMER_LEDGER_ATTRIBUTION", refs);
    result.compare("SOURCE_CUSTOMER_DEBITS", refs, debit, sum(transactions, "debitAmount"));
    result.compare("SOURCE_CUSTOMER_CREDITS", refs, credit, sum(transactions, "creditAmount"));
    for (const row of transactions) result.compare("CUSTOMER_MOVEMENT_EQUATION", refs, units(row.balanceBefore) + units(row.debitAmount) - units(row.creditAmount), units(row.balanceAfter));
    const expectedPairs = new Map(), actualPairs = new Map();
    for (const [dr, cr, amount] of pairs) if (amount > 0n) add(expectedPairs, `${dr}|${cr}`, amount);
    for (const entry of ledger) {
      if (entry.customerId !== undefined && entry.customerId !== customerId) result.fail("JOURNAL_CUSTOMER_ATTRIBUTION", refs);
      if (!entry.debitAccountKey || !entry.creditAccountKey || entry.debitAccountKey === entry.creditAccountKey || units(entry.amount) <= 0n) throw new Blocked("INVALID_JOURNAL_PAIR");
      add(actualPairs, `${entry.debitAccountKey}|${entry.creditAccountKey}`, units(entry.amount));
    }
    for (const key of new Set([...expectedPairs.keys(), ...actualPairs.keys()])) result.compare("FINANCIAL_ACCOUNT_PAIR",
      {...refs, ledgerEntryIds: ledger.filter((entry) => `${entry.debitAccountKey}|${entry.creditAccountKey}` === key).map((entry) => entry.id)}, expectedPairs.get(key) || 0n, actualPairs.get(key) || 0n);
    const eCash = new Map(), aCash = new Map();
    for (const [account, direction, amount] of cashEffects) if (amount > 0n) add(eCash, `${account}|${direction}`, amount);
    for (const row of cash) {
      if (row.customerId !== undefined && row.customerId !== customerId) result.fail("CASH_CUSTOMER_ATTRIBUTION", refs);
      if (!["in", "out"].includes(row.direction) || units(row.amount) <= 0n) throw new Blocked("INVALID_CASH_EFFECT");
      add(aCash, `${actualCashKey(row)}|${row.direction}`, units(row.amount));
      result.compare("CASH_MOVEMENT_EQUATION", refs, units(row.balanceBefore) + (row.direction === "in" ? 1n : -1n) * units(row.amount), units(row.balanceAfter));
    }
    for (const key of new Set([...eCash.keys(), ...aCash.keys()])) result.compare("SOURCE_CASH_EFFECT",
      {...refs, cashMovementIds: cash.filter((entry) => `${actualCashKey(entry)}|${entry.direction}` === key).map((entry) => entry.id)}, eCash.get(key) || 0n, aCash.get(key) || 0n);
    add(expectedCustomer, customerId, debit - credit);
    result.financial.push({...refs, expectedCustomerDebit: format(debit), expectedCustomerCredit: format(credit)});
  }
  for (const invoice of data.invoices) result.guarded({invoiceId: invoice.id}, () => {
    const refs = {invoiceId: invoice.id}, source = {collection: "invoices", id: invoice.id};
    if (!FINAL.has(invoice.invoiceStatus) || invoice.financialPosted !== true) {
      if (["customer_transactions", "cash_movements", "financial_ledger_entries"].some((name) => sourceRows(name, source).length)) result.fail("UNPOSTED_INVOICE_FINANCIAL_EFFECTS", refs);
      return;
    }
    const gross = units(invoice.grandTotal), customer = `customer:${invoice.customerId}`;
    invoice.items.forEach((line, i) => {
      const quantity = units(line.quantity), price = units(line.unitPrice), discount = units(line.discount), rate = units(line.taxPercent);
      if (quantity <= 0n || price < 0n || discount < 0n || rate < 0n || rate > 100000n) throw new Blocked("INVALID_INVOICE_LINE_VALUES");
      const subtotal = roundedRatio(quantity * price, 1000n), net = subtotal - discount;
      if (net < 0n) throw new Blocked("INVALID_INVOICE_DISCOUNT");
      const tax = roundedRatio(net * rate, 100000n), refs_ = {...refs, lineIndex: i};
      result.compare("LINE_SUBTOTAL_ARITHMETIC", refs_, subtotal, units(line.subtotal));
      result.compare("LINE_TAX_ARITHMETIC", refs_, tax, units(line.taxAmount));
      result.compare("LINE_TOTAL_ARITHMETIC", refs_, net + tax, units(line.total));
    });
    result.compare("INVOICE_LINE_TOTALS", refs, sum(invoice.items, "total"), gross);
    if (gross <= 0n) throw new Blocked("INVALID_POSTED_INVOICE_TOTAL");
    const initialCredits = sourceRows("customer_transactions", source).filter((row) => units(row.creditAmount) > 0n);
    const initialCash = sourceRows("cash_movements", source).filter((row) => row.direction === "in");
    let paid;
    if (invoice.initialPaidAmount !== undefined) paid = units(invoice.initialPaidAmount);
    else if (initialCredits.length && initialCash.length) {
      paid = sum(initialCredits, "creditAmount"); result.compare("INITIAL_PAYMENT_EVIDENCE", refs, paid, sum(initialCash, "amount"));
    } else if (invoice.paymentType === "credit" && !initialCredits.length && !initialCash.length &&
      sourceRows("financial_ledger_entries", source).some((row) => row.debitAccountKey === customer && units(row.amount) === gross)) paid = 0n;
    else throw new Blocked("INITIAL_PAYMENT_HISTORY_INCOMPLETE");
    if (paid < 0n || paid > gross) throw new Blocked("INVALID_INITIAL_PAYMENT");
    // The draft creator need not be the confirming collector. Use the immutable
    // posting account, never createdByRole, to avoid inventing cash attribution.
    let account = "company_cash";
    if (paid > 0n) {
      if (!["company_cash", "rep_cash"].includes(invoice.initialCashAccount)) throw new Blocked("INITIAL_CASH_ACCOUNT_HISTORY_INCOMPLETE");
      account = invoice.initialCashAccount === "rep_cash" ? cashAccount("sales_rep", invoice.salesRepId) : "company_cash";
    }
    for (const entry of sourceRows("financial_ledger_entries", source)) {
      if (entry.salesRepId === undefined) throw new Blocked("HISTORICAL_JOURNAL_OWNERSHIP_MISSING");
      if (entry.salesRepId !== invoice.salesRepId) result.fail("INVOICE_JOURNAL_ATTRIBUTION_MISMATCH", {...refs, ledgerEntryIds: [entry.id]});
    }
    validateSource(source, invoice.customerId, gross, paid, [[account, "sales", paid], [customer, "sales", gross - paid]], [[account, "in", paid]], refs);
    let allocated = 0n;
    for (const receipt of data.receipts) if (receipt.status !== "cancelled") allocated += units(receipt.invoiceAllocations?.[invoice.id] || 0);
    result.compare("INVOICE_PAID_ALLOCATION", refs, paid + allocated, units(invoice.paidAmount));
    result.compare("INVOICE_REMAINING_ALLOCATION", refs, gross - paid - allocated, units(invoice.remainingAmount));
    add(expectedSales, invoice.customerId, gross); add(expectedPaid, invoice.customerId, paid);
  });
  for (const receipt of data.receipts) result.guarded({receiptId: receipt.id}, () => {
    const refs = {receiptId: receipt.id}, amount = units(receipt.amount), customer = `customer:${receipt.customerId}`;
    if (amount <= 0n || (receipt.status && !["posted", "cancelled"].includes(receipt.status))) throw new Blocked("UNSUPPORTED_RECEIPT_STATE");
    const allocations = receipt.invoiceAllocations;
    if (!allocations || Array.isArray(allocations)) throw new Blocked("RECEIPT_ALLOCATION_HISTORY_MISSING");
    if (Object.keys(allocations).some((id) => !invoices.has(id))) throw new Blocked("RECEIPT_ALLOCATION_OUTSIDE_INVOICE_SCOPE");
    for (const [id, allocated] of Object.entries(allocations)) {
      if (units(allocated) <= 0n) result.fail("NONPOSITIVE_RECEIPT_ALLOCATION", refs);
      if (invoices.get(id).customerId !== receipt.customerId) result.fail("RECEIPT_CUSTOMER_ALLOCATION_MISMATCH", refs);
    }
    if (Object.values(allocations).reduce((n, value) => n + units(value), 0n) > amount) result.fail("RECEIPT_OVERALLOCATION", refs);
    const account = receipt.paymentMethod === "cash" ? cashAccount(receipt.createdByRole, receipt.createdByUid) :
      {bank: "bank_unallocated", check: "check_clearing", cliq: "cliq_clearing"}[receipt.paymentMethod];
    if (!account) throw new Blocked("UNKNOWN_PAYMENT_METHOD_NO_RECLASSIFICATION");
    const cancelled = receipt.status === "cancelled";
    if (cancelled && receipt.cancellationVersion !== 1) throw new Blocked("UNVERIFIED_RECEIPT_CANCELLATION");
    if (receipt.receiptLedgerOwnershipVersion !== 1 || !Array.isArray(receipt.financialLedgerOwnerGroups)) throw new Blocked("RECEIPT_OWNERSHIP_EVIDENCE_MISSING");
    const owners = new Map();
    for (const group of receipt.financialLedgerOwnerGroups) {
      if (typeof group.salesRepId !== "string" || units(group.amount) <= 0n) throw new Blocked("INVALID_RECEIPT_OWNERSHIP_EVIDENCE");
      add(owners, group.salesRepId, units(group.amount));
    }
    result.compare("RECEIPT_OWNERSHIP_TOTAL", refs, amount, [...owners.values()].reduce((a, b) => a + b, 0n));
    const ledgerOwners = new Map(), reverseOwners = new Map();
    for (const entry of sourceRows("financial_ledger_entries", {collection: "receipts", id: receipt.id})) {
      if (typeof entry.salesRepId !== "string") throw new Blocked("HISTORICAL_JOURNAL_OWNERSHIP_MISSING");
      add(entry.isReversal ? reverseOwners : ledgerOwners, entry.salesRepId, units(entry.amount));
    }
    for (const owner of new Set([...owners.keys(), ...ledgerOwners.keys(), ...reverseOwners.keys()])) {
      result.compare("RECEIPT_JOURNAL_ATTRIBUTION", refs, owners.get(owner) || 0n, ledgerOwners.get(owner) || 0n);
      if (cancelled || reverseOwners.size) result.compare("RECEIPT_REVERSAL_ATTRIBUTION", refs, cancelled ? owners.get(owner) || 0n : 0n, reverseOwners.get(owner) || 0n);
    }
    validateSource({collection: "receipts", id: receipt.id}, receipt.customerId, cancelled ? amount : 0n, amount,
      [[account, customer, amount], ...(cancelled ? [[customer, account, amount]] : [])],
      receipt.paymentMethod === "cash" ? [[account, "in", amount], ...(cancelled ? [[account, "out", amount]] : [])] : [], refs);
    if (!cancelled) add(expectedPaid, receipt.customerId, amount);
  });
  for (const returned of data.sales_returns) result.guarded({returnId: returned.id}, () => {
    if (returned.status !== "confirmed") return;
    const original = invoices.get(returned.originalInvoiceId); if (!original) throw new Blocked("RETURN_INVOICE_OUTSIDE_SCOPE");
    if (returned.salesRepId !== original.salesRepId) result.fail("RETURN_REP_ATTRIBUTION_MISMATCH", {returnId: returned.id, invoiceId: original.id});
    for (const entry of sourceRows("financial_ledger_entries", {collection: "sales_returns", id: returned.id})) {
      if (entry.salesRepId === undefined) throw new Blocked("HISTORICAL_JOURNAL_OWNERSHIP_MISSING");
      if (entry.salesRepId !== original.salesRepId) result.fail("RETURN_JOURNAL_ATTRIBUTION_MISMATCH", {returnId: returned.id, invoiceId: original.id, ledgerEntryIds: [entry.id]});
    }
    const gross = units(returned.grandTotal), refund = units(returned.cashRefundAmount), customer = `customer:${returned.customerId}`;
    result.compare("RETURN_COMPONENTS", {returnId: returned.id}, units(returned.receivableReduction) + units(returned.customerCreditAmount) + refund, gross);
    result.compare("RETURN_LINE_TOTALS", {returnId: returned.id}, sum(returned.items, "total"), gross);
    let refundAccount = "company_cash";
    const source = {collection: "sales_returns", id: returned.id};
    if (refund > 0n) {
      const outgoing = sourceRows("cash_movements", source).filter((row) => row.direction === "out");
      if (outgoing.length !== 1) throw new Blocked("REFUND_ACCOUNT_PROVENANCE_MISSING");
      refundAccount = actualCashKey(outgoing[0]);
      const collected = data.cash_movements.filter((row) => row.direction === "in" && actualCashKey(row) === refundAccount &&
        ((row.sourceCollection === "invoices" && row.sourceId === original.id) || (row.sourceCollection === "receipts" &&
          receipts.get(row.sourceId)?.status !== "cancelled" && units(receipts.get(row.sourceId)?.invoiceAllocations?.[original.id] || 0) > 0n)));
      if (!collected.length) throw new Blocked("REFUND_COLLECTION_PROVENANCE_MISSING");
      const cashCollected = collected.reduce((n, row) => n + (row.sourceCollection === "invoices" ? units(row.amount) : units(receipts.get(row.sourceId).invoiceAllocations[original.id])), 0n);
      const refunds = data.sales_returns.filter((r) => r.originalInvoiceId === original.id && r.status === "confirmed" &&
        data.cash_movements.some((m) => m.sourceCollection === "sales_returns" && m.sourceId === r.id && actualCashKey(m) === refundAccount && m.direction === "out"))
        .reduce((n, r) => n + units(r.cashRefundAmount), 0n);
      if (refunds > cashCollected) result.fail("REFUND_EXCEEDS_VERIFIED_CASH", {invoiceId: original.id}, cashCollected, refunds);
    }
    validateSource(source, returned.customerId, refund, gross, [["sales", customer, gross], [customer, refundAccount, refund]], [[refundAccount, "out", refund]], {returnId: returned.id, invoiceId: original.id});
    add(expectedSales, returned.customerId, -gross); add(expectedPaid, returned.customerId, -refund);
  });
  const openings = data.customer_transactions.filter((row) => ["opening_balance", "opening_balance_adjustment"].includes(row.transactionType));
  for (const row of openings) result.guarded({}, () => {
    const debit = units(row.debitAmount), credit = units(row.creditAmount), delta = debit - credit;
    const customer = `customer:${row.customerId}`, amount = delta < 0n ? -delta : delta;
    const entries = data.financial_ledger_entries.filter((e) => e.sourceCollection === "customer_transactions" && e.sourceId === row.id);
    const expectedDr = delta > 0n ? customer : "opening_balance_equity", expectedCr = delta > 0n ? "opening_balance_equity" : customer;
    if (entries.length !== 1 || entries[0].debitAccountKey !== expectedDr || entries[0].creditAccountKey !== expectedCr || units(entries[0].amount) !== amount) result.fail("OPENING_JOURNAL_SOURCE_MISMATCH");
    add(expectedCustomer, row.customerId, delta);
  });
  // A blocked source must not turn an incomplete source sum into a confirmed
  // customer closing discrepancy (for example an unknown payment method).
  if (result.blockers.length) return;
  data.customers.forEach((customer, i) => result.guarded({customerAlias: `C${i + 1}`}, () => {
    const refs = {customerAlias: `C${i + 1}`};
    const rows = data.customer_transactions.filter((row) => row.customerId === customer.id);
    if (data.customerCoverage?.[customer.id] !== true) throw new Blocked("CUSTOMER_HISTORY_OUTSIDE_APPROVED_SCOPE");
    if (!rows.some((row) => units(row.balanceBefore) === 0n)) throw new Blocked("CUSTOMER_OPENING_HISTORY_INCOMPLETE");
    const expected = expectedCustomer.get(customer.id) || 0n;
    result.compare("CUSTOMER_SOURCE_CLOSING", refs, expected, units(customer.currentBalance));
    result.compare("CUSTOMER_LEDGER_CLOSING", refs, expected, sum(rows, "debitAmount") - sum(rows, "creditAmount"));
    if (customer.totalSales !== undefined) result.compare("CUSTOMER_NET_SALES", refs, expectedSales.get(customer.id) || 0n, units(customer.totalSales));
    if (customer.totalPaid !== undefined) result.compare("CUSTOMER_NET_PAID", refs, expectedPaid.get(customer.id) || 0n, units(customer.totalPaid));
  }));
}
module.exports = {Findings, analyzeInventory, analyzeFinance, time, originalIndex, units, format};
