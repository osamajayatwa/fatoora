"use strict";
// Production entry point: user ADC, fixed project, read-only RPC facade only.
const fs = require("node:fs");
const path = require("node:path");
const {randomBytes} = require("node:crypto");
const {PROJECT, LIMITS, Blocked, documentId, eq, oneOf, combine, productionReader} = require("./jihad_readonly_reader");
const {Findings, analyzeInventory, analyzeFinance} = require("./jihad_audit_analysis");
const ALIASES = ["Jihad", "jihad", "JIHAD", "Jehad", "jehad", "JEHAD", "جهاد"];
const PRIMARY = ["invoices", "rep_inventory_movements", "rep_inventory_balances", "inventory_transfers", "sales_returns", "stock_movements", "items", "audit_events",
  "receipts", "customers", "customer_transactions", "cash_movements", "financial_ledger_entries"];
const posted = (row) => ["confirmed", "accepted"].includes(row.invoiceStatus) && row.financialPosted === true;
const chunks = (values, size = 10) => Array.from({length: Math.ceil(values.length / size)}, (_, i) => values.slice(i * size, (i + 1) * size));
const unique = (values) => [...new Set(values)];
function linkedIds(rows, field, cap) {
  const ids = [];
  for (const row of rows) {
    if (row[field] === undefined) continue;
    if (!Array.isArray(row[field])) throw new Blocked("INVALID_SOURCE_LINK_ARRAY");
    for (const id of row[field]) ids.push(documentId(id));
  }
  const result = unique(ids); if (result.length > cap) throw new Blocked("LINKED_RECORD_LIMIT"); return result;
}
function merge(data, name, rows, company) {
  const map = new Map(data[name].map((row) => [row.id, row]));
  for (const row of rows) {
    if (row.companyId !== undefined && row.companyId !== company) throw new Blocked("FOREIGN_COMPANY_RECORD");
    map.set(row.id, row);
  }
  if (map.size > (LIMITS[name] || 1000)) throw new Blocked(`${name.toUpperCase()}_LIMIT`);
  data[name] = [...map.values()];
}
async function queryIds(reader, data, collection, field, ids, extra) {
  for (const batch of chunks(unique(ids))) {
    const filters = [oneOf(field, batch), ...(extra ? [extra] : [])];
    const rows = await reader.scan(collection, combine("AND", filters), (LIMITS[collection] || 1000) - data[collection].length);
    merge(data, collection, rows, reader.company);
  }
}
async function getLinked(reader, data, collection, ids, required = true) {
  const known = new Set(data[collection].map((row) => row.id));
  const missing = unique(ids).filter((id) => !known.has(id));
  if (known.size + missing.length > (LIMITS[collection] || 1000)) throw new Blocked(`${collection.toUpperCase()}_LIMIT`);
  const rows = await reader.getMany(collection, missing);
  merge(data, collection, rows, reader.company);
  if (required && rows.length !== missing.length) throw new Blocked(`MISSING_LINKED_${collection.toUpperCase()}`);
}
function targetName(name) {
  return typeof name === "string" && /^(jihad|jehad|جهاد)$/u.test(name.normalize("NFKD").replace(/[\p{M}\u0640]/gu, "").trim().toLowerCase().split(/[\s-]+/u)[0]);
}
async function identify(reader) {
  const candidates = new Map(); let remaining = LIMITS.profiles;
  for (const alias of ALIASES) {
    const where = combine("AND", [
      {fieldFilter: {field: {fieldPath: "name"}, op: "GREATER_THAN_OR_EQUAL", value: {stringValue: alias}}},
      {fieldFilter: {field: {fieldPath: "name"}, op: "LESS_THAN_OR_EQUAL", value: {stringValue: alias + "\uf8ff"}}},
    ]);
    const rows = await reader.scan("users", where, remaining, {orderField: "name"}); remaining -= rows.length;
    for (const row of rows) if (row.role === "sales_rep" && targetName(row.name)) candidates.set(row.id, row);
    if (candidates.size > 1) throw new Blocked("AMBIGUOUS_JIHAD_IDENTITY");
  }
  if (candidates.size !== 1) throw new Blocked("JIHAD_IDENTITY_NOT_FOUND_REQUEST_EXACT_STORED_NAME_OR_UID");
  const rep = [...candidates.values()][0];
  if (rep.uid !== undefined && rep.uid !== rep.id) throw new Blocked("REP_PROFILE_UID_MISMATCH");
  documentId(rep.id); documentId(rep.companyId); reader.company = rep.companyId;
  return rep;
}
function safeCode(error) {
  if (error instanceof Blocked) return error.code;
  const code = error.response?.status || error.code;
  if (code === 401 || code === 16) return "AUTHENTICATION_FAILED";
  if (code === 403 || code === 7) return "PERMISSION_DENIED";
  if (code === 400 || code === 9) return "QUERY_OR_READ_TIME_NOT_SUPPORTED_CHECK_INDEXES";
  if (["EACCES", "EPERM"].includes(code)) return "NETWORK_ACCESS_DENIED";
  return "READ_FAILED_NO_AUTH_OR_POLICY_WORKAROUND";
}
async function audit(reader) {
  const result = new Findings();
  const data = Object.fromEntries(PRIMARY.map((name) => [name, []]));
  let rep; let stage = "identity";
  const report = {formatVersion: 1, runId: randomBytes(12).toString("hex"), generatedAt: new Date().toISOString(),
    project: reader.project, environment: reader.emulator ? "SYNTHETIC_EMULATOR" : "PRODUCTION_READ_ONLY",
    limits: LIMITS, status: "BLOCKED", stage, localFixDeployment: "NOT_QUERIED_OR_ASSUMED",
    scope: {representative: "Jihad", invoiceCount: 0},
    coverage: {inventory: "NOT_RUN", associatedFinance: "NOT_RUN", customerReceivables: "NOT_RUN",
      globalWarehouseClosing: "OUTSIDE_APPROVED_SCOPE", companyAndRepCashClosing: "OUTSIDE_APPROVED_SCOPE"},
    productionWritesPerformed: false, rawExportsWritten: false};
  try {
    rep = await identify(reader);
    report.scope.representativeId = rep.id; report.scope.companyId = rep.companyId;
    stage = "inventory_reads";
    for (const name of ["rep_inventory_balances", "rep_inventory_movements", "inventory_transfers"]) {
      merge(data, name, await reader.scan(name, eq("salesRepId", rep.id), LIMITS[name]), reader.company);
    }
    const associated = combine("OR", [eq("salesRepId", rep.id), eq("createdByUid", rep.id), eq("stockSourceSalesRepId", rep.id)]);
    merge(data, "invoices", await reader.scan("invoices", associated, LIMITS.invoices), reader.company);
    await getLinked(reader, data, "invoices", data.rep_inventory_movements.filter((m) => m.referenceType === "invoice").map((m) => m.referenceId));
    if (!data.invoices.length) throw new Blocked("NO_RELEVANT_INVOICES");
    // Prioritize confirmed sources for the remaining work; preserve attribution.
    data.invoices.sort((a, b) => Number(posted(b)) - Number(posted(a)) || a.id.localeCompare(b.id));
    await getLinked(reader, data, "inventory_transfers", data.rep_inventory_movements.filter((m) => m.referenceType === "inventoryTransfer").map((m) => m.referenceId));
    const invoiceIds = data.invoices.map((row) => row.id);
    await queryIds(reader, data, "sales_returns", "originalInvoiceId", invoiceIds);
    await getLinked(reader, data, "sales_returns", unique([
      ...linkedIds(data.invoices, "returnInvoiceIds", LIMITS.sales_returns),
      ...data.rep_inventory_movements.filter((m) => m.referenceType === "salesReturn").map((m) => m.referenceId),
    ]));
    if (data.sales_returns.some((row) => !invoiceIds.includes(row.originalInvoiceId))) throw new Blocked("RETURN_INVOICE_OUTSIDE_APPROVED_COHORT");
    await queryIds(reader, data, "stock_movements", "referenceId", [...invoiceIds, ...data.inventory_transfers.map((row) => row.id), ...data.sales_returns.map((row) => row.id)]);
    if (data.stock_movements.some((m) => !["invoice", "inventory_transfer", "sales_return"].includes(m.referenceType))) throw new Blocked("WAREHOUSE_MOVEMENT_SOURCE_KIND_UNKNOWN");
    const itemIds = unique([...data.rep_inventory_movements.map((row) => row.itemId), ...data.rep_inventory_balances.map((row) => row.itemId),
      ...data.invoices.flatMap((row) => (row.items || []).filter((line) => line.itemId && line.lineType !== "custom" && !line.itemId.startsWith("manual-")).map((line) => line.itemId))]);
    if (itemIds.length > LIMITS.items) throw new Blocked("ITEM_LIMIT");
    await getLinked(reader, data, "items", itemIds, false);
    for (const [entityType, ids] of [["invoice", invoiceIds], ["inventory_transfer", data.inventory_transfers.map((r) => r.id)], ["sales_return", data.sales_returns.map((r) => r.id)], ["item", itemIds]]) {
      for (const batch of chunks(ids)) {
        const rows = await reader.scan("audit_events", combine("AND", [eq("entityType", entityType), oneOf("entityId", batch)]), LIMITS.audit_events - data.audit_events.length, {itemAudit: entityType === "item"});
        merge(data, "audit_events", rows, reader.company);
      }
    }
    stage = "inventory_analysis";
    analyzeInventory(data, rep, result);
    report.coverage.inventory = result.blockers.length ? "INCOMPLETE" : "COMPLETE_WITHIN_BOUNDED_RECORDED_HISTORY";
    if (result.blockers.length) throw new Blocked("INVENTORY_HISTORY_REQUIRES_REVIEW_STOPPED");
    stage = "financial_reads";
    await getLinked(reader, data, "receipts", unique([...linkedIds(data.invoices, "receiptIds", LIMITS.receipts), ...linkedIds(data.invoices, "cancelledReceiptIds", LIMITS.receipts)]));
    const customerIds = unique(data.invoices.filter(posted).map((row) => documentId(row.customerId)));
    await getLinked(reader, data, "customers", customerIds);
    if (data.receipts.some((row) => !customerIds.includes(row.customerId) || Object.keys(row.invoiceAllocations || {}).some((id) => !invoiceIds.includes(id)))) throw new Blocked("RECEIPT_ALLOCATION_OUTSIDE_APPROVED_COHORT");
    for (const [sourceCollection, rows] of [["invoices", data.invoices], ["receipts", data.receipts], ["sales_returns", data.sales_returns]]) {
      for (const name of ["customer_transactions", "cash_movements", "financial_ledger_entries"]) {
        await queryIds(reader, data, name, "sourceId", rows.map((row) => row.id), eq("sourceCollection", sourceCollection));
      }
      await getLinked(reader, data, "customer_transactions", unique([...linkedIds(rows, "customerTransactionIds", LIMITS.customer_transactions), ...linkedIds(rows, "cancellationCustomerTransactionIds", LIMITS.customer_transactions)]));
      await getLinked(reader, data, "cash_movements", unique([...linkedIds(rows, "cashMovementIds", LIMITS.cash_movements), ...linkedIds(rows, "cancellationCashMovementIds", LIMITS.cash_movements)]));
    }
    for (const batch of chunks(customerIds)) {
      const rows = await reader.scan("customer_transactions", combine("AND", [oneOf("customerId", batch), oneOf("transactionType", ["opening_balance", "opening_balance_adjustment"])]), LIMITS.customer_transactions - data.customer_transactions.length);
      merge(data, "customer_transactions", rows, reader.company);
    }
    const openingIds = data.customer_transactions.filter((row) => ["opening_balance", "opening_balance_adjustment"].includes(row.transactionType)).map((row) => row.id);
    await queryIds(reader, data, "financial_ledger_entries", "sourceId", openingIds, eq("sourceCollection", "customer_transactions"));
    // Count-only coverage gates: do not fetch other reps' invoices/receipts to
    // make a partial customer history appear complete.
    data.customerCoverage = {};
    for (const batch of chunks(customerIds)) {
      for (const [collection, extra, known] of [
        ["customer_transactions", null, data.customer_transactions.filter((row) => batch.includes(row.customerId))],
        ["invoices", eq("financialPosted", true), data.invoices.filter((row) => batch.includes(row.customerId) && row.financialPosted === true)],
        ["receipts", null, data.receipts.filter((row) => batch.includes(row.customerId))],
        ["sales_returns", eq("status", "confirmed"), data.sales_returns.filter((row) => batch.includes(row.customerId) && row.status === "confirmed")],
      ]) {
        const count = await reader.count(collection, combine("AND", [oneOf("customerId", batch), ...(extra ? [extra] : [])]));
        if (count !== known.length) throw new Blocked("CUSTOMER_HISTORY_OUTSIDE_APPROVED_SCOPE");
      }
      batch.forEach((id) => {data.customerCoverage[id] = true;});
    }
    const sourceSets = new Map([["invoices", new Set(invoiceIds)], ["receipts", new Set(data.receipts.map((r) => r.id))], ["sales_returns", new Set(data.sales_returns.map((r) => r.id))], ["customer_transactions", new Set(openingIds)]]);
    for (const name of ["customer_transactions", "cash_movements", "financial_ledger_entries"]) for (const row of data[name]) {
      if (name === "customer_transactions" && ["opening_balance", "opening_balance_adjustment"].includes(row.transactionType)) continue;
      if (!sourceSets.get(row.sourceCollection)?.has(row.sourceId)) throw new Blocked("LEGACY_FINANCIAL_SOURCE_LINK_UNRESOLVED");
    }
    for (const [collection, sources] of [["invoices", data.invoices], ["receipts", data.receipts], ["sales_returns", data.sales_returns]]) {
      for (const source of sources) for (const [name, fields] of [
        ["customer_transactions", ["customerTransactionIds", "cancellationCustomerTransactionIds"]],
        ["cash_movements", ["cashMovementIds", "cancellationCashMovementIds"]],
      ]) {
        const declared = fields.flatMap((field) => source[field] || []);
        if (new Set(declared).size !== declared.length || declared.some((id) => !data[name].some((row) => row.id === id && row.sourceCollection === collection && row.sourceId === source.id))) {
          result.fail("FINANCIAL_POSTING_LINK_MISMATCH", {sourceCollection: collection, sourceId: source.id, postingCollection: name});
        }
      }
    }
    stage = "financial_analysis";
    analyzeFinance(data, rep, result);
    report.coverage.associatedFinance = report.coverage.customerReceivables = result.blockers.length ? "INCOMPLETE" : "COMPLETE_WITHIN_APPROVED_SOURCES";
    stage = "complete";
  } catch (error) {result.block(safeCode(error));}
  report.stage = stage;
  report.status = result.status;
  report.scope.invoiceCount = reader.seenInvoices.size;
  report.invoiceReview = data.invoices.map((invoice) => ({invoiceId: invoice.id, status: invoice.invoiceStatus,
    attributedSalesRepId: invoice.salesRepId ?? null, createdByTarget: invoice.createdByUid === rep?.id,
    declaredStockSource: invoice.stockSourceType ?? null, stockSourceSalesRepId: invoice.stockSourceSalesRepId ?? null,
    inventoryPosted: invoice.inventoryPosted === true, financialPosted: invoice.financialPosted === true,
    postingTimestamp: invoice.inventoryPostedAt || invoice.financialPostedAt || null,
    immutableTrackingSnapshotPresent: Array.isArray(invoice.items) && invoice.items.every((line) => line.lineType === "custom" || typeof line.stockTrackedAtPosting === "boolean"),
    initialPaymentSnapshotPresent: invoice.initialPaidAmount !== undefined,
    customerAlias: data.customers.some((c) => c.id === invoice.customerId) ? `C${data.customers.findIndex((c) => c.id === invoice.customerId) + 1}` : null}));
  report.uniqueScopedRecordCounts = Object.fromEntries(PRIMARY.map((name) => [name, data[name].length]));
  report.readTime = reader.readTime; report.readCounts = reader.counts;
  report.confirmedFindings = result.findings; report.blockers = result.blockers;
  report.checks = result.checks; report.custody = result.custody; report.associatedFinancialEffects = result.financial;
  report.trackingEvidence = result.trackingEvidence || [];
  report.auditRecordCount = data.audit_events.length;
  report.interpretation = "Findings concern recorded historical source data only. Current item flags and locally fixed code do not prove historical flag state or deployed code version. No production verification is claimed for emulator results.";
  return report;
}
function shareable(report) {
  const countCodes = (rows) => rows.reduce((counts, row) => {counts[row.code] = (counts[row.code] || 0) + 1; return counts;}, {});
  return {formatVersion: report.formatVersion, runId: report.runId, environment: report.environment, status: report.status,
    readTime: report.readTime, stage: report.stage, invoiceCount: report.scope.invoiceCount,
    recordsReturned: report.readCounts.documents, missingDocuments: report.readCounts.missing,
    uniqueScopedRecordCounts: report.uniqueScopedRecordCounts,
    coverage: report.coverage, comparisons: report.checks.length,
    findingCountsByCode: countCodes(report.confirmedFindings), blockerCountsByCode: countCodes(report.blockers),
    auditRecordCount: report.auditRecordCount, productionWritesPerformed: false, rawExportsWritten: false,
    localFixDeployment: report.localFixDeployment};
}
function outsideGit(outputDir) {
  if (!path.isAbsolute(outputDir)) throw new Blocked("ABSOLUTE_PRIVATE_OUTPUT_REQUIRED");
  const workspace = fs.realpathSync(path.resolve(__dirname, "../.."));
  let existing = path.resolve(outputDir), suffix = [];
  while (!fs.existsSync(existing)) {suffix.unshift(path.basename(existing)); const parent = path.dirname(existing); if (parent === existing) throw new Blocked("INVALID_OUTPUT_DIRECTORY"); existing = parent;}
  const resolved = path.join(fs.realpathSync(existing), ...suffix);
  const relative = path.relative(workspace, resolved);
  if (!relative || (!relative.startsWith(".." + path.sep) && relative !== ".." && !path.isAbsolute(relative))) throw new Blocked("REPORT_OUTPUT_INSIDE_REPOSITORY");
  for (let current = fs.realpathSync(existing);; current = path.dirname(current)) {
    if (fs.existsSync(path.join(current, ".git"))) throw new Blocked("REPORT_OUTPUT_INSIDE_GIT");
    if (path.dirname(current) === current) break;
  }
  return resolved;
}
function writeReports(report, outputDir) {
  const directory = outsideGit(outputDir);
  fs.mkdirSync(directory, {recursive: true, mode: 0o700});
  // Recheck after creation, including symlinks/junctions and nested repositories.
  outsideGit(fs.realpathSync(directory));
  for (const [name, value] of [["findings.private.json", report], ["summary.shareable.json", shareable(report)]]) {
    const descriptor = fs.openSync(path.join(directory, name), "wx", 0o600);
    try {fs.writeFileSync(descriptor, JSON.stringify(value, null, 2) + "\n");} finally {fs.closeSync(descriptor);}
  }
  return directory;
}
async function main() {
  const args = process.argv.slice(2);
  if (args.length === 1 && args[0] === "--help") {
    process.stdout.write("Usage: node scripts/audit_jihad_readonly.js --project=fatoora-6b192 [--output-dir=<absolute private directory outside Git>]\nExisting user ADC only; no writes; 200-invoice ceiling. Exit 0 PASS, 1 FAIL, 2 BLOCKED.\n"); return;
  }
  if (!args.includes(`--project=${PROJECT}`) || args.some((arg) => arg !== `--project=${PROJECT}` && !arg.startsWith("--output-dir=")) || args.filter((a) => a.startsWith("--output-dir=")).length > 1) throw new Blocked("INVALID_ARGUMENTS");
  const base = process.env.LOCALAPPDATA; if (!base) throw new Blocked("PRIVATE_OUTPUT_BASE_UNAVAILABLE");
  const outputDir = args.find((a) => a.startsWith("--output-dir="))?.slice("--output-dir=".length) ||
    path.join(base, "Fatoora", "PrivateAudits", new Date().toISOString().replace(/[:.]/g, "-") + "-" + randomBytes(6).toString("hex"));
  outsideGit(outputDir); // Reject unsafe output before authentication or reads.
  const reader = await productionReader();
  const report = await audit(reader);
  const directory = writeReports(report, outputDir);
  process.stdout.write(JSON.stringify({...shareable(report), privateReportDirectory: directory}, null, 2) + "\n");
  process.exitCode = report.status === "PASS" ? 0 : report.status === "FAIL" ? 1 : 2;
}
if (require.main === module) main().catch((error) => {process.stdout.write(JSON.stringify({status: "BLOCKED", code: safeCode(error), productionVerification: false}) + "\n"); process.exitCode = 2;});
module.exports = {audit, identify, targetName, shareable, writeReports, outsideGit, safeCode};
