import {getApps, initializeApp} from "firebase-admin/app";
import {
  DocumentData,
  DocumentSnapshot,
  FieldPath,
  Firestore,
  Query,
  QueryDocumentSnapshot,
  Timestamp,
  getFirestore,
} from "firebase-admin/firestore";
import {FINANCIAL_LEDGER_SCHEMA_VERSION} from "../trusted/financial_ledger";
import {
  ExpenseFundingSource,
  buildCompanyCashOpeningFinancialLedgerEntry,
  buildCustomerOpeningFinancialLedgerEntry,
  buildExpenseFinancialLedgerEntry,
  buildInvoiceFinancialLedgerEntries,
  buildReceiptFinancialLedgerEntries,
  buildSalesReturnFinancialLedgerEntries,
  buildSettlementFinancialLedgerEntry,
  receiptAllocationGroups,
} from "../trusted/financial_ledger_mappings";
import {
  buildLedgerDerivedProjection,
  reconcileFinancialLedgerProjection,
} from "../trusted/financial_ledger_reporting";

const SOURCE_COLLECTIONS = [
  "invoices",
  "receipts",
  "expenses",
  "sales_returns",
  "settlements",
  "customer_transactions",
  "cash_movements",
] as const;
const LEDGER_COLLECTION = "financial_ledger_entries";
const SEARCH_COLLECTION = "financial_ledger_search_entries";
const STATE_COLLECTION = "financial_ledger_projection_states";
const BUSINESS_TIME_ZONE = "Asia/Amman";

type SourceCollection = typeof SOURCE_COLLECTIONS[number];
type MetricName =
  "sales" | "cashSales" | "creditSales" | "receipts" | "expenses" |
  "returns" | "settlements" | "receivables" | "companyCash" |
  "repCashIn" | "repCashOut" | "repCashNet";

interface Options {
  projectId: string;
  companyId: string;
  from?: Timestamp;
  to?: Timestamp;
  fromText: string;
  toText: string;
  apply: boolean;
  confirmProject: string;
  confirmCompany: string;
  pageSize: number;
  maxWrites: number;
}

interface SourceStats {
  scanned: number;
  eligible: number;
  inRange: number;
  excluded: number;
  outsideRange: number;
  invalid: number;
  unresolved: number;
  expectedLedgerEntries: number;
}

interface Anomaly {
  severity: "warning" | "error";
  category: "invalid" | "unresolved" | "conflict" | "unexpected";
  sourcePath: string;
  reason: string;
}

interface EntryPlan {
  id: string;
  entry: DocumentData;
  sourcePath: string;
  missing: boolean;
  correct: boolean;
  conflict: boolean;
  projectionNeeded: boolean;
  searchCurrent: boolean;
  stateCurrent: boolean;
  summaryWrites: number;
  projectionWrites: number;
}

interface Context {
  firestore: Firestore;
  options: Options;
  entries: Map<string, DocumentData>;
  entrySources: Map<string, string>;
  observedDocuments: Map<string, string>;
  sourceStats: Record<SourceCollection, SourceStats>;
  anomalies: Anomaly[];
  authoritativeTotals: Totals;
  authoritativeMonthly: Map<string, Totals>;
  projectionTotals: Totals;
  projectionMonthly: Map<string, Totals>;
}

type Totals = Record<MetricName, number>;

interface AuditResult {
  context: Context;
  plans: EntryPlan[];
  existingLedgerCount: number;
  unexpectedExistingIds: string[];
  plannedWrites: {
    ledgerCreates: number;
    searchWrites: number;
    projectionStateWrites: number;
    dailySummaryWrites: number;
    total: number;
  };
  reconciliation: {
    totals: Record<MetricName, {authoritative: number; projected: number; difference: number}>;
    byMonth: Record<string, Record<MetricName, {
      authoritative: number;
      projected: number;
      difference: number;
    }>>;
    balanced: boolean;
  };
}

export async function runHistoricalLedgerBackfill(
  options: Options,
  firestore?: Firestore,
): Promise<DocumentData> {
  if (!firestore && getApps().length === 0) initializeApp({projectId: options.projectId});
  const context = createContext(firestore ?? getFirestore(), options);
  await scanSource(context, "invoices", buildInvoiceEntries);
  await scanSource(context, "receipts", buildReceiptEntries);
  await scanSource(context, "expenses", buildExpenseEntries);
  await scanSource(context, "sales_returns", buildSalesReturnEntries);
  await scanSource(context, "settlements", buildSettlementEntries);
  await scanSource(context, "customer_transactions", buildCustomerOpeningEntries);
  await scanSource(context, "cash_movements", buildCompanyCashOpeningEntries);
  const audit = await auditDerivedCollections(context);
  const errorCount = context.anomalies.filter((item) => item.severity === "error").length;
  const safe = errorCount === 0 && audit.reconciliation.balanced;
  if (options.apply) {
    validateApply(audit, safe);
    await assertObservedDocumentsUnchanged(context);
    await createMissingLedgerEntries(context, audit.plans);
    await reconcileProjections(context, audit.plans);
  }
  return buildReport(audit, safe);
}

async function main(): Promise<void> {
  const options = parseOptions(process.argv.slice(2));
  const report = await runHistoricalLedgerBackfill(options);
  process.stdout.write(`${JSON.stringify(report, null, 2)}\n`);
}

function createContext(firestore: Firestore, options: Options): Context {
  return {
    firestore,
    options,
    entries: new Map(),
    entrySources: new Map(),
    observedDocuments: new Map(),
    sourceStats: Object.fromEntries(
      SOURCE_COLLECTIONS.map((collection) => [collection, emptySourceStats()]),
    ) as Record<SourceCollection, SourceStats>,
    anomalies: [],
    authoritativeTotals: emptyTotals(),
    authoritativeMonthly: new Map(),
    projectionTotals: emptyTotals(),
    projectionMonthly: new Map(),
  };
}

async function buildInvoiceEntries(
  context: Context,
  document: QueryDocumentSnapshot,
): Promise<void> {
  const data = document.data();
  const stats = context.sourceStats.invoices;
  if (data.financialPosted !== true || data.invoiceStatus !== "confirmed") {
    stats.excluded += 1;
    return;
  }
  stats.eligible += 1;
  const date = authoritativeTimestamp(data.invoiceDate);
  if (!date) return invalid(context, stats, document.ref.path, "Posted invoice has no invoiceDate Timestamp.");
  if (!inDateRange(context.options, date)) {
    stats.outsideRange += 1;
    return;
  }
  stats.inRange += 1;
  const grandTotal = positiveMoney(data.grandTotal);
  const salesRepId = scalarString(data.salesRepId);
  const customerId = scalarString(data.customerId);
  if (!grandTotal) return invalid(context, stats, document.ref.path, "Posted invoice has no positive grandTotal.");
  if (!salesRepId) return unresolved(context, stats, document.ref.path, "Posted invoice has no authoritative invoice.salesRepId.");
  if (!customerId) return invalid(context, stats, document.ref.path, "Posted invoice has no customerId.");

  const expectedMovementId = `${document.id}_cash`;
  const movementIds = stringArray(data.cashMovementIds);
  if (movementIds.length > 1 || (movementIds.length === 1 && movementIds[0] !== expectedMovementId)) {
    return invalid(context, stats, document.ref.path, "Invoice cashMovementIds do not match the trusted deterministic ID.");
  }
  const cashSnapshot = await readDocument(
    context,
    businessPath(context, "cash_movements", expectedMovementId),
  );
  const cashData = cashSnapshot.data() ?? {};
  let cashAmount = 0;
  let initialCashAccount = "company_cash";
  if (cashSnapshot.exists) {
    cashAmount = positiveMoney(cashData.amount);
    initialCashAccount = scalarString(cashData.cashAccount);
    if (
      !cashAmount || cashAmount > grandTotal ||
      !["company_cash", "rep_cash"].includes(initialCashAccount) ||
      cashData.direction !== "in" ||
      scalarString(cashData.sourceId) !== document.id
    ) {
      return invalid(context, stats, document.ref.path, "Invoice cash movement is incompatible with the trusted posting evidence.");
    }
  } else if (movementIds.length > 0) {
    return invalid(context, stats, document.ref.path, "Invoice references a missing cash movement.");
  }
  const creditAmount = money(grandTotal - cashAmount);
  const customerName = nestedString(data.customerSnapshot, "name") || scalarString(data.customerName);
  const salesRepName = scalarString(data.salesRepName);
  const entries = buildInvoiceFinancialLedgerEntries({
    companyId: context.options.companyId,
    invoiceId: document.id,
    invoiceNumber: scalarString(data.invoiceNumber) || document.id,
    invoiceDate: date,
    grandTotal,
    initialCashAmount: cashAmount,
    initialCashAccount,
    customerId,
    customerName,
    salesRepId,
    salesRepName,
    notes: scalarString(data.notes),
  });
  recordAuthoritativeMetrics(context, date, {
    sales: grandTotal,
    cashSales: cashAmount,
    creditSales: creditAmount,
    receivables: creditAmount,
    companyCash: initialCashAccount === "company_cash" ? cashAmount : 0,
    repCashIn: initialCashAccount === "rep_cash" ? cashAmount : 0,
  });
  addEntries(context, stats, document.ref.path, entries);
}

async function buildReceiptEntries(
  context: Context,
  document: QueryDocumentSnapshot,
): Promise<void> {
  const data = document.data();
  const stats = context.sourceStats.receipts;
  stats.eligible += 1;
  const date = authoritativeTimestamp(data.receiptDate);
  if (!date) return invalid(context, stats, document.ref.path, "Receipt has no receiptDate Timestamp.");
  if (!inDateRange(context.options, date)) {
    stats.outsideRange += 1;
    return;
  }
  stats.inRange += 1;
  const amount = positiveMoney(data.amount);
  const customerId = scalarString(data.customerId);
  const paymentMethod = scalarString(data.paymentMethod) || "cash";
  if (!amount) return invalid(context, stats, document.ref.path, "Receipt has no positive amount.");
  if (!customerId) return invalid(context, stats, document.ref.path, "Receipt has no customerId.");
  if (!["cash", "bank", "check", "cliq"].includes(paymentMethod)) {
    return invalid(context, stats, document.ref.path, "Receipt paymentMethod is unsupported by the trusted mapping.");
  }
  const allocations = plainObject(data.invoiceAllocations);
  const allocationEntries: Array<{
    id: string;
    amount: number;
    data: Record<string, unknown>;
  }> = [];
  let allocated = 0;
  for (const [invoiceId, rawAmount] of Object.entries(allocations)) {
    const allocationAmount = positiveMoney(rawAmount);
    if (!allocationAmount) {
      return invalid(context, stats, document.ref.path, `Receipt allocation ${invoiceId} is not positive.`);
    }
    const invoiceSnapshot = await readDocument(
      context,
      businessPath(context, "invoices", invoiceId),
    );
    if (!invoiceSnapshot.exists) {
      return invalid(context, stats, document.ref.path, `Allocated invoice ${invoiceId} is missing.`);
    }
    allocated = money(allocated + allocationAmount);
    allocationEntries.push({
      id: invoiceId,
      amount: allocationAmount,
      data: invoiceSnapshot.data() ?? {},
    });
  }
  if (allocated > amount) {
    return invalid(context, stats, document.ref.path, "Receipt allocations exceed its amount.");
  }
  const unallocated = money(amount - allocated);
  const groups = receiptAllocationGroups(
    allocationEntries,
    unallocated,
    scalarString(data.salesRepId),
    scalarString(data.salesRepName),
  );
  if (groups.length === 0 || money(groups.reduce((sum, group) => sum + group.amount, 0)) !== amount) {
    return invalid(context, stats, document.ref.path, "Receipt ownership groups do not reconcile to the receipt amount.");
  }
  if (groups.some((group) => !group.salesRepId)) {
    unresolved(context, stats, document.ref.path, "Receipt contains an unassigned amount with no authoritative salesRepId.");
  }

  let cashAccount = "";
  let cashAccountSalesRepId = "";
  let cashAccountSalesRepName = "";
  if (paymentMethod === "cash") {
    const movementIds = stringArray(data.cashMovementIds);
    if (movementIds.length !== 1) {
      return invalid(context, stats, document.ref.path, "Cash receipt must reference exactly one cash movement.");
    }
    const movementSnapshot = await readDocument(
      context,
      businessPath(context, "cash_movements", movementIds[0]),
    );
    const movement = movementSnapshot.data() ?? {};
    cashAccount = scalarString(movement.cashAccount);
    cashAccountSalesRepId = scalarString(movement.salesRepId);
    cashAccountSalesRepName = scalarString(movement.salesRepName);
    if (
      !movementSnapshot.exists || !["company_cash", "rep_cash"].includes(cashAccount) ||
      movement.direction !== "in" || money(movement.amount) !== amount ||
      scalarString(movement.sourceId) !== document.id
    ) {
      return invalid(context, stats, document.ref.path, "Receipt cash movement is incompatible with the trusted posting evidence.");
    }
    if (cashAccount === "rep_cash" && !cashAccountSalesRepId) {
      return unresolved(context, stats, document.ref.path, "Representative cash receipt movement has no salesRepId.");
    }
  }
  const entries = buildReceiptFinancialLedgerEntries({
    companyId: context.options.companyId,
    receiptId: document.id,
    receiptNumber: scalarString(data.receiptNumber) || document.id,
    receiptDate: date,
    paymentMethod,
    cashAccount,
    cashAccountSalesRepId,
    cashAccountSalesRepName,
    customerId,
    customerName: nestedString(data.customerSnapshot, "name") || scalarString(data.customerName),
    notes: scalarString(data.notes),
    groups,
  });
  recordAuthoritativeMetrics(context, date, {
    receipts: amount,
    receivables: -amount,
    companyCash: paymentMethod === "cash" && cashAccount === "company_cash" ? amount : 0,
    repCashIn: paymentMethod === "cash" && cashAccount === "rep_cash" ? amount : 0,
  });
  addEntries(context, stats, document.ref.path, entries);
}

async function buildExpenseEntries(
  context: Context,
  document: QueryDocumentSnapshot,
): Promise<void> {
  const data = document.data();
  const stats = context.sourceStats.expenses;
  if (data.status !== "posted" && data.status !== "approved") {
    stats.excluded += 1;
    return;
  }
  stats.eligible += 1;
  const date = authoritativeTimestamp(data.expenseDate);
  if (!date) return invalid(context, stats, document.ref.path, "Posted expense has no expenseDate Timestamp.");
  if (!inDateRange(context.options, date)) {
    stats.outsideRange += 1;
    return;
  }
  stats.inRange += 1;
  const amount = positiveMoney(data.amount);
  const fundingSource = scalarString(data.fundingSource) as ExpenseFundingSource;
  const salesRepId = scalarString(data.salesRepId);
  if (!amount) return invalid(context, stats, document.ref.path, "Posted expense has no positive amount.");
  if (!["company_cash", "personal_cash", "rep_collected_cash"].includes(fundingSource)) {
    return invalid(context, stats, document.ref.path, "Expense fundingSource is unsupported.");
  }
  if (fundingSource !== "company_cash" && !salesRepId) {
    return unresolved(context, stats, document.ref.path, "Representative-funded expense has no expense.salesRepId.");
  }
  if (fundingSource !== "personal_cash") {
    const movementId = scalarString(data.cashMovementId) || `${document.id}_cash_out`;
    const movementSnapshot = await readDocument(
      context,
      businessPath(context, "cash_movements", movementId),
    );
    const movement = movementSnapshot.data() ?? {};
    const expectedAccount = fundingSource === "company_cash" ? "company_cash" : "rep_cash";
    if (
      !movementSnapshot.exists || movement.cashAccount !== expectedAccount ||
      movement.direction !== "out" || money(movement.amount) !== amount ||
      scalarString(movement.sourceId) !== document.id
    ) {
      return invalid(context, stats, document.ref.path, "Expense cash movement is incompatible with the trusted posting evidence.");
    }
  }
  const description = fundingSource === "company_cash"
    ? scalarString(data.description) || scalarString(data.category)
    : scalarString(data.description) || scalarString(data.notes);
  const entry = buildExpenseFinancialLedgerEntry({
    companyId: context.options.companyId,
    expenseId: document.id,
    expenseDate: date,
    amount,
    fundingSource,
    description,
    salesRepId,
    salesRepName: scalarString(data.salesRepName),
    notes: fundingSource === "company_cash"
      ? scalarString(data.description)
      : scalarString(data.description) || scalarString(data.notes),
  });
  recordAuthoritativeMetrics(context, date, {
    expenses: amount,
    companyCash: fundingSource === "company_cash" ? -amount : 0,
    repCashOut: fundingSource === "rep_collected_cash" ? amount : 0,
  });
  addEntries(context, stats, document.ref.path, [entry]);
}

async function buildSalesReturnEntries(
  context: Context,
  document: QueryDocumentSnapshot,
): Promise<void> {
  const data = document.data();
  const stats = context.sourceStats.sales_returns;
  if (data.status !== "confirmed" || data.financialPosted !== true) {
    stats.excluded += 1;
    return;
  }
  stats.eligible += 1;
  const date = authoritativeTimestamp(data.returnDate);
  if (!date) return invalid(context, stats, document.ref.path, "Posted sales return has no returnDate Timestamp.");
  if (!inDateRange(context.options, date)) {
    stats.outsideRange += 1;
    return;
  }
  stats.inRange += 1;
  const grandTotal = positiveMoney(data.grandTotal);
  const originalInvoiceId = scalarString(data.originalInvoiceId);
  if (!grandTotal) return invalid(context, stats, document.ref.path, "Posted sales return has no positive grandTotal.");
  if (!originalInvoiceId) return invalid(context, stats, document.ref.path, "Sales return has no originalInvoiceId.");
  const invoiceSnapshot = await readDocument(
    context,
    businessPath(context, "invoices", originalInvoiceId),
  );
  const invoice = invoiceSnapshot.data() ?? {};
  if (!invoiceSnapshot.exists) return invalid(context, stats, document.ref.path, "Sales return original invoice is missing.");
  const salesRepId = scalarString(invoice.salesRepId);
  if (!salesRepId) return unresolved(context, stats, document.ref.path, "Original invoice has no authoritative salesRepId.");
  if (scalarString(data.salesRepId) && scalarString(data.salesRepId) !== salesRepId) {
    return invalid(context, stats, document.ref.path, "Sales return salesRepId disagrees with the original invoice.");
  }
  const customerId = scalarString(data.customerId) || scalarString(invoice.customerId);
  if (!customerId) return invalid(context, stats, document.ref.path, "Sales return has no customerId.");
  const cashRefundAmount = money(data.cashRefundAmount);
  let refundCashAccount = "";
  let refundCashSalesRepId = "";
  if (cashRefundAmount < 0 || cashRefundAmount > grandTotal) {
    return invalid(context, stats, document.ref.path, "Sales return cashRefundAmount is invalid.");
  }
  if (cashRefundAmount > 0) {
    const movementIds = stringArray(data.cashMovementIds);
    if (movementIds.length !== 1) {
      return invalid(context, stats, document.ref.path, "Cash refund must reference exactly one cash movement.");
    }
    const movementSnapshot = await readDocument(
      context,
      businessPath(context, "cash_movements", movementIds[0]),
    );
    const movement = movementSnapshot.data() ?? {};
    refundCashAccount = scalarString(movement.cashAccount);
    refundCashSalesRepId = scalarString(movement.salesRepId);
    if (
      !movementSnapshot.exists || !["company_cash", "rep_cash"].includes(refundCashAccount) ||
      movement.direction !== "out" || money(movement.amount) !== cashRefundAmount ||
      scalarString(movement.sourceId) !== document.id
    ) {
      return invalid(context, stats, document.ref.path, "Refund cash movement is incompatible with the trusted posting evidence.");
    }
    if (refundCashAccount === "rep_cash" && !refundCashSalesRepId) {
      return unresolved(context, stats, document.ref.path, "Representative cash refund movement has no salesRepId.");
    }
  }
  const quantity = money(
    Array.isArray(data.items)
      ? data.items.reduce((sum: number, raw: unknown) => sum + numberValue(plainObject(raw).returnedQuantity), 0)
      : 0,
  );
  const entries = buildSalesReturnFinancialLedgerEntries({
    companyId: context.options.companyId,
    returnId: document.id,
    returnNumber: scalarString(data.returnNumber) || document.id,
    returnDate: date,
    grandTotal,
    cashRefundAmount,
    refundType: scalarString(data.refundType),
    refundCashAccount,
    refundCashSalesRepId,
    customerId,
    customerName: nestedString(data.customerSnapshot, "name") ||
      nestedString(invoice.customerSnapshot, "name") || scalarString(data.customerName),
    salesRepId,
    salesRepName: scalarString(invoice.salesRepName) || scalarString(data.salesRepName),
    quantity,
    reason: scalarString(data.reason),
  });
  recordAuthoritativeMetrics(context, date, {
    sales: -grandTotal,
    returns: grandTotal,
    receivables: money(-grandTotal + cashRefundAmount),
    companyCash: refundCashAccount === "company_cash" ? -cashRefundAmount : 0,
    repCashOut: refundCashAccount === "rep_cash" ? cashRefundAmount : 0,
  });
  addEntries(context, stats, document.ref.path, entries);
}

async function buildSettlementEntries(
  context: Context,
  document: QueryDocumentSnapshot,
): Promise<void> {
  const data = document.data();
  const stats = context.sourceStats.settlements;
  if (data.status !== "posted") {
    stats.excluded += 1;
    return;
  }
  stats.eligible += 1;
  const date = authoritativeTimestamp(data.settlementDate);
  if (!date) return invalid(context, stats, document.ref.path, "Posted settlement has no settlementDate Timestamp.");
  if (!inDateRange(context.options, date)) {
    stats.outsideRange += 1;
    return;
  }
  stats.inRange += 1;
  const amount = positiveMoney(data.amount);
  const salesRepId = scalarString(data.salesRepId);
  if (!amount) return invalid(context, stats, document.ref.path, "Posted settlement has no positive amount.");
  if (!salesRepId) return unresolved(context, stats, document.ref.path, "Posted settlement has no settlement.salesRepId.");
  const movementChecks: Array<[string, string, string]> = [
    [scalarString(data.repMovementId), "rep_cash", "out"],
    [scalarString(data.companyMovementId), "company_cash", "in"],
  ];
  for (const [movementId, account, direction] of movementChecks) {
    if (!movementId) return invalid(context, stats, document.ref.path, "Settlement movement pair is incomplete.");
    const snapshot = await readDocument(
      context,
      businessPath(context, "cash_movements", movementId),
    );
    const movement = snapshot.data() ?? {};
    if (
      !snapshot.exists || movement.cashAccount !== account ||
      movement.direction !== direction || money(movement.amount) !== amount ||
      scalarString(movement.sourceId) !== document.id
    ) {
      return invalid(context, stats, document.ref.path, "Settlement movement pair is incompatible with the trusted posting evidence.");
    }
  }
  const entry = buildSettlementFinancialLedgerEntry({
    companyId: context.options.companyId,
    settlementId: document.id,
    settlementNumber: scalarString(data.settlementNumber) || document.id,
    settlementDate: date,
    amount,
    salesRepId,
    salesRepName: scalarString(data.salesRepName),
    notes: scalarString(data.notes),
  });
  recordAuthoritativeMetrics(context, date, {
    settlements: amount,
    companyCash: amount,
    repCashOut: amount,
  });
  addEntries(context, stats, document.ref.path, [entry]);
}

async function buildCustomerOpeningEntries(
  context: Context,
  document: QueryDocumentSnapshot,
): Promise<void> {
  const data = document.data();
  const stats = context.sourceStats.customer_transactions;
  const type = scalarString(data.transactionType) || scalarString(data.type);
  if (type !== "opening_balance" && type !== "opening_balance_adjustment") {
    stats.excluded += 1;
    return;
  }
  stats.eligible += 1;
  const date = authoritativeTimestamp(data.transactionDate);
  if (!date) return invalid(context, stats, document.ref.path, "Opening balance row has no transactionDate Timestamp; createdAt is not accepted.");
  if (!inDateRange(context.options, date)) {
    stats.outsideRange += 1;
    return;
  }
  stats.inRange += 1;
  const debit = money(data.debitAmount);
  const credit = money(data.creditAmount);
  const signed = type === "opening_balance"
    ? money(debit - credit)
    : nonZeroMoney(data.difference) || nonZeroMoney(data.signedAmount) || money(debit - credit);
  const customerId = scalarString(data.customerId);
  if (!signed) return invalid(context, stats, document.ref.path, "Opening balance row has no non-zero authoritative amount.");
  if (!customerId) return invalid(context, stats, document.ref.path, "Opening balance row has no customerId.");
  const openingBalanceType = type === "opening_balance"
    ? signed > 0 ? "customer_owes" : "customer_credit"
    : scalarString(data.newOpeningBalanceType) || scalarString(data.openingBalanceType);
  const entry = buildCustomerOpeningFinancialLedgerEntry({
    companyId: context.options.companyId,
    transactionId: document.id,
    transactionDate: date,
    transactionType: type,
    openingBalanceType,
    signedAmount: signed,
    customerId,
    customerName: scalarString(data.customerName),
    salesRepId: scalarString(data.salesRepId),
    salesRepName: scalarString(data.salesRepName),
    notes: scalarString(data.notes),
  });
  recordAuthoritativeMetrics(context, date, {receivables: signed});
  addEntries(context, stats, document.ref.path, [entry]);
}

async function buildCompanyCashOpeningEntries(
  context: Context,
  document: QueryDocumentSnapshot,
): Promise<void> {
  const data = document.data();
  const stats = context.sourceStats.cash_movements;
  const type = scalarString(data.movementType) || scalarString(data.type);
  if (type !== "opening_balance" || data.cashAccount !== "company_cash") {
    stats.excluded += 1;
    return;
  }
  stats.eligible += 1;
  const date = authoritativeTimestamp(data.effectiveDate) || authoritativeTimestamp(data.movementDate);
  if (!date) return invalid(context, stats, document.ref.path, "Company cash opening row has no effectiveDate/movementDate Timestamp.");
  if (!inDateRange(context.options, date)) {
    stats.outsideRange += 1;
    return;
  }
  stats.inRange += 1;
  const amount = positiveMoney(data.amount);
  if (!amount || data.direction !== "in") {
    return invalid(context, stats, document.ref.path, "Company cash opening row has invalid amount or direction.");
  }
  const entry = buildCompanyCashOpeningFinancialLedgerEntry({
    companyId: context.options.companyId,
    movementId: document.id,
    effectiveDate: date,
    amount,
    referenceNumber: scalarString(data.referenceNumber) || "OPENING",
    notes: scalarString(data.notes),
  });
  recordAuthoritativeMetrics(context, date, {companyCash: amount});
  addEntries(context, stats, document.ref.path, [entry]);
}

async function auditDerivedCollections(context: Context): Promise<AuditResult> {
  const ids = [...context.entries.keys()];
  const [ledgerDocuments, searchDocuments, stateDocuments] = await Promise.all([
    readDocumentsByIds(context, LEDGER_COLLECTION, ids, false),
    readDocumentsByIds(context, SEARCH_COLLECTION, ids, false),
    readDocumentsByIds(context, STATE_COLLECTION, ids, false),
  ]);
  const plans: EntryPlan[] = [];
  for (const id of ids) {
    const entry = context.entries.get(id)!;
    const sourcePath = context.entrySources.get(id)!;
    const ledger = ledgerDocuments.get(id);
    const search = searchDocuments.get(id);
    const state = stateDocuments.get(id);
    const missing = !ledger?.exists;
    const correct = !!ledger?.exists && dataEqual(ledger.data() ?? {}, entry);
    const conflict = !!ledger?.exists && !correct;
    if (conflict) {
      anomaly(context, "error", "conflict", ledger!.ref.path, `Existing ledger row differs from authoritative schema-v${FINANCIAL_LEDGER_SCHEMA_VERSION} mapping for ${sourcePath}.`);
    }
    const derived = buildLedgerDerivedProjection(id, entry);
    const searchCurrent = !!search?.exists && dataEqual(search.data() ?? {}, derived.searchDocument);
    const expectedState = {
      schemaVersion: FINANCIAL_LEDGER_SCHEMA_VERSION,
      ledgerEntryId: id,
      fingerprint: derived.fingerprint,
      queryKeys: derived.queryKeys,
      dayKey: derived.dayKey,
      summaryShard: derived.summaryShard,
      salesRepId: derived.salesRepId,
      metrics: derived.metrics,
    };
    const stateCurrent = !!state?.exists && objectContains(state.data() ?? {}, expectedState);
    if (missing && (search?.exists || state?.exists)) {
      anomaly(context, "error", "conflict", sourcePath, "Missing ledger row has orphaned search/projection state.");
    }
    let summaryWrites = 0;
    let searchWrites = searchCurrent ? 0 : 1;
    let stateWrites = stateCurrent ? 0 : 1;
    if (!stateCurrent) {
      summaryWrites = projectionSummaryWriteCount(derived.queryKeys, derived.salesRepId);
      if (state?.exists) {
        const previous = parsePreviousProjectionShape(state.data() ?? {});
        if (!previous) {
          anomaly(context, "error", "conflict", state.ref.path, "Existing projection state cannot be safely reversed.");
        } else {
          summaryWrites += projectionSummaryWriteCount(previous.queryKeys, previous.salesRepId);
        }
      }
    } else {
      stateWrites = 0;
      summaryWrites = 0;
    }
    if (stateCurrent && searchCurrent) searchWrites = 0;
    const projectionNeeded = !conflict && (!stateCurrent || !searchCurrent || missing);
    plans.push({
      id,
      entry,
      sourcePath,
      missing,
      correct,
      conflict,
      projectionNeeded,
      searchCurrent,
      stateCurrent,
      summaryWrites,
      projectionWrites: projectionNeeded ? searchWrites + stateWrites : 0,
    });
  }

  let existingLedgerCount = 0;
  const unexpectedExistingIds: string[] = [];
  await scanCollection(context, LEDGER_COLLECTION, async (document) => {
    existingLedgerCount += 1;
    const date = authoritativeTimestamp(document.data().occurredAt);
    if (date && inDateRange(context.options, date) && !context.entries.has(document.id)) {
      unexpectedExistingIds.push(document.id);
      anomaly(context, "error", "unexpected", document.ref.path, "Ledger row is in range but has no eligible authoritative source mapping.");
    }
  }, false);

  const ledgerCreates = plans.filter((plan) => plan.missing).length;
  const searchWrites = plans.reduce(
    (sum, plan) => sum + (plan.projectionNeeded && !plan.searchCurrent ? 1 : 0),
    0,
  );
  const projectionStateWrites = plans.reduce(
    (sum, plan) => sum + (plan.projectionNeeded && !plan.stateCurrent ? 1 : 0),
    0,
  );
  const dailySummaryWrites = plans.reduce((sum, plan) => sum + plan.summaryWrites, 0);
  const reconciliation = reconcileTotals(context);
  return {
    context,
    plans,
    existingLedgerCount,
    unexpectedExistingIds,
    plannedWrites: {
      ledgerCreates,
      searchWrites,
      projectionStateWrites,
      dailySummaryWrites,
      total: ledgerCreates + searchWrites + projectionStateWrites + dailySummaryWrites,
    },
    reconciliation,
  };
}

function addEntries(
  context: Context,
  stats: SourceStats,
  sourcePath: string,
  entries: DocumentData[],
): void {
  for (const entry of entries) {
    const id = scalarString(entry.id);
    const existingSource = context.entrySources.get(id);
    if (!id) {
      anomaly(context, "error", "invalid", sourcePath, "Trusted mapper returned an entry without an ID.");
      stats.invalid += 1;
      continue;
    }
    if (existingSource && existingSource !== sourcePath) {
      anomaly(context, "error", "conflict", sourcePath, `Ledger ID ${id} conflicts with ${existingSource}.`);
      stats.invalid += 1;
      continue;
    }
    context.entries.set(id, entry);
    context.entrySources.set(id, sourcePath);
    stats.expectedLedgerEntries += 1;
    const date = entry.occurredAt as Timestamp;
    const metrics = metricsFromEntry(entry);
    addTotals(context.projectionTotals, metrics);
    addMonthlyTotals(context.projectionMonthly, date, metrics);
  }
}

function recordAuthoritativeMetrics(
  context: Context,
  date: Timestamp,
  values: Partial<Totals>,
): void {
  const normalized = withRepCashNet(values);
  addTotals(context.authoritativeTotals, normalized);
  addMonthlyTotals(context.authoritativeMonthly, date, normalized);
}

function metricsFromEntry(entry: DocumentData): Partial<Totals> {
  const values: Partial<Totals> = {
    sales: money(entry.metricSales),
    cashSales: money(entry.metricCashSales),
    creditSales: money(entry.metricCreditSales),
    receipts: money(entry.metricReceipts),
    expenses: money(entry.metricExpenses),
    returns: money(entry.metricReturns),
    settlements: money(entry.metricSettlements),
    receivables: money(entry.metricReceivables),
    companyCash: money(entry.metricCompanyCashNet),
    repCashIn: money(entry.metricRepCashIn),
    repCashOut: money(entry.metricRepCashOut),
  };
  return withRepCashNet(values);
}

function withRepCashNet(values: Partial<Totals>): Partial<Totals> {
  return {
    ...values,
    repCashNet: money((values.repCashIn ?? 0) - (values.repCashOut ?? 0)),
  };
}

function reconcileTotals(context: Context): AuditResult["reconciliation"] {
  const totals = compareTotals(context.authoritativeTotals, context.projectionTotals);
  const months = new Set([
    ...context.authoritativeMonthly.keys(),
    ...context.projectionMonthly.keys(),
  ]);
  const byMonth: AuditResult["reconciliation"]["byMonth"] = {};
  for (const month of [...months].sort()) {
    byMonth[month] = compareTotals(
      context.authoritativeMonthly.get(month) ?? emptyTotals(),
      context.projectionMonthly.get(month) ?? emptyTotals(),
    );
  }
  const balanced = Object.values(totals).every((value) => value.difference === 0) &&
    Object.values(byMonth).every((month) =>
      Object.values(month).every((value) => value.difference === 0));
  return {totals, byMonth, balanced};
}

function compareTotals(
  authoritative: Totals,
  projected: Totals,
): Record<MetricName, {authoritative: number; projected: number; difference: number}> {
  return Object.fromEntries(
    (Object.keys(authoritative) as MetricName[]).map((name) => [name, {
      authoritative: authoritative[name],
      projected: projected[name],
      difference: money(projected[name] - authoritative[name]),
    }]),
  ) as Record<MetricName, {authoritative: number; projected: number; difference: number}>;
}

async function createMissingLedgerEntries(
  context: Context,
  plans: EntryPlan[],
): Promise<void> {
  const missing = plans.filter((plan) => plan.missing && !plan.conflict);
  for (let start = 0; start < missing.length; start += 200) {
    const batch = context.firestore.batch();
    for (const plan of missing.slice(start, start + 200)) {
      batch.create(
        context.firestore.doc(businessPath(context, LEDGER_COLLECTION, plan.id)),
        plan.entry,
      );
    }
    await batch.commit();
  }
}

async function reconcileProjections(context: Context, plans: EntryPlan[]): Promise<void> {
  for (const plan of plans.filter((item) => item.projectionNeeded && !item.conflict)) {
    await reconcileFinancialLedgerProjection(
      context.firestore,
      context.options.companyId,
      plan.id,
    );
  }
}

async function assertObservedDocumentsUnchanged(context: Context): Promise<void> {
  const paths = [...context.observedDocuments.keys()];
  for (let start = 0; start < paths.length; start += 200) {
    const slice = paths.slice(start, start + 200);
    const snapshots = await context.firestore.getAll(
      ...slice.map((path) => context.firestore.doc(path)),
    );
    for (const snapshot of snapshots) {
      const expected = context.observedDocuments.get(snapshot.ref.path);
      const actual = snapshot.exists ? updateTimeKey(snapshot) : "missing";
      if (expected !== actual) {
        throw new Error(`Source changed after audit: ${snapshot.ref.path}. Re-run dry-run.`);
      }
    }
  }
}

function validateApply(audit: AuditResult, safe: boolean): void {
  const options = audit.context.options;
  if (options.confirmProject !== options.projectId || options.confirmCompany !== options.companyId) {
    throw new Error("Apply requires exact --confirm-project and --confirm-company values.");
  }
  if (!safe) throw new Error("Apply is blocked while source/projection reconciliation errors exist.");
  if (audit.plannedWrites.total > options.maxWrites) {
    throw new Error(`Planned ${audit.plannedWrites.total} writes exceed --max-writes=${options.maxWrites}.`);
  }
}

function buildReport(audit: AuditResult, safe: boolean): DocumentData {
  const {context, plans} = audit;
  const errors = context.anomalies.filter((item) => item.severity === "error");
  const unresolved = context.anomalies.filter((item) => item.category === "unresolved");
  return {
    mode: context.options.apply ? "apply" : "dry-run",
    projectId: context.options.projectId,
    companyId: context.options.companyId,
    dateRange: {
      from: context.options.fromText || "unbounded",
      to: context.options.toText || "unbounded",
      timezone: BUSINESS_TIME_ZONE,
    },
    sourceOfTruth: {
      invoices: "confirmed + financialPosted; invoiceDate; invoice.salesRepId; deterministic initial cash movement",
      receipts: "atomically posted receipt; receiptDate; allocated invoice owner; stored owner only for trusted unallocated remainder",
      expenses: "posted/approved; expenseDate; fundingSource and expense.salesRepId",
      salesReturns: "confirmed + financialPosted; returnDate; original invoice owner; refund cash movement",
      settlements: "posted; settlementDate; settlement.salesRepId; paired cash movements",
      customerOpeningBalances: "opening rows only; transactionDate; immutable debit/credit for initial row and difference for adjustment",
      companyCashOpeningBalance: "company_cash opening movement; effectiveDate/movementDate",
    },
    doubleCountingGuards: [
      "Ordinary cash_movements are evidence only; only company_cash opening_balance is a source.",
      "Ordinary customer_transactions are evidence only; only opening_balance/opening_balance_adjustment are sources.",
      "Receipt allocations are projected from receipts, not receipt customer-ledger rows.",
      "A settlement movement pair maps to one settlement entry.",
      "A sales return maps once from sales_returns; its customer/cash side effects are not reposted.",
    ],
    documentsScanned: context.sourceStats,
    ledger: {
      expectedEntries: context.entries.size,
      existingEntriesInCollection: audit.existingLedgerCount,
      alreadyCorrectSchemaV3: plans.filter((plan) => plan.correct).length,
      missingEntries: plans.filter((plan) => plan.missing).length,
      conflictingEntries: plans.filter((plan) => plan.conflict).length,
      unexpectedExistingEntriesInRange: audit.unexpectedExistingIds.length,
      unexpectedExistingIds: audit.unexpectedExistingIds.slice(0, 100),
    },
    projections: {
      searchAlreadyCurrent: plans.filter((plan) => plan.searchCurrent).length,
      stateAlreadyCurrent: plans.filter((plan) => plan.stateCurrent).length,
      entriesNeedingProjectionReconciliation: plans.filter((plan) => plan.projectionNeeded).length,
      plannedWrites: audit.plannedWrites,
    },
    reconciliation: audit.reconciliation,
    applyWritesOnly: [
      `companies/${context.options.companyId}/${LEDGER_COLLECTION}/<deterministicId> (create-only)`,
      `companies/${context.options.companyId}/${SEARCH_COLLECTION}/<sameId>`,
      `companies/${context.options.companyId}/${STATE_COLLECTION}/<sameId>`,
      `companies/${context.options.companyId}/financial_ledger_summary_scopes/.../query_keys/.../days/...`,
    ],
    businessSourceWrites: 0,
    anomalyCount: context.anomalies.length,
    errorCount: errors.length,
    unresolvedCount: unresolved.length,
    anomalies: context.anomalies.slice(0, 200),
    truncatedAnomalies: Math.max(context.anomalies.length - 200, 0),
    maxWrites: context.options.maxWrites,
    safeForControlledBackfill: safe,
    conclusion: safe
      ? "SAFE FOR CONTROLLED HISTORICAL BACKFILL"
      : "NOT SAFE — DATA RECONCILIATION REQUIRED",
  };
}

async function scanSource(
  context: Context,
  collection: SourceCollection,
  builder: (context: Context, document: QueryDocumentSnapshot) => Promise<void>,
): Promise<void> {
  await scanCollection(context, collection, async (document) => {
    try {
      await builder(context, document);
    } catch (error) {
      context.sourceStats[collection].invalid += 1;
      anomaly(context, "error", "invalid", document.ref.path, `Trusted mapper failed: ${errorMessage(error)}`);
    }
  });
}

async function scanCollection(
  context: Context,
  collection: string,
  visitor: (document: QueryDocumentSnapshot) => Promise<void>,
  observe = true,
): Promise<void> {
  let cursor: QueryDocumentSnapshot | undefined;
  do {
    let query: Query = context.firestore
      .collection(`companies/${context.options.companyId}/${collection}`)
      .orderBy(FieldPath.documentId())
      .limit(context.options.pageSize);
    if (cursor) query = query.startAfter(cursor);
    const snapshot = await query.get();
    for (const document of snapshot.docs) {
      if (observe) {
        observeDocument(context, document);
        if (SOURCE_COLLECTIONS.includes(collection as SourceCollection)) {
          context.sourceStats[collection as SourceCollection].scanned += 1;
        }
      }
      await visitor(document);
    }
    cursor = snapshot.size === context.options.pageSize
      ? snapshot.docs[snapshot.docs.length - 1]
      : undefined;
  } while (cursor);
}

async function readDocument(context: Context, path: string): Promise<DocumentSnapshot> {
  const snapshot = await context.firestore.doc(path).get();
  observeDocument(context, snapshot);
  return snapshot;
}

async function readDocumentsByIds(
  context: Context,
  collection: string,
  ids: string[],
  observe: boolean,
): Promise<Map<string, DocumentSnapshot>> {
  const result = new Map<string, DocumentSnapshot>();
  for (let start = 0; start < ids.length; start += 200) {
    const slice = ids.slice(start, start + 200);
    const snapshots = await context.firestore.getAll(
      ...slice.map((id) => context.firestore.doc(businessPath(context, collection, id))),
    );
    for (const snapshot of snapshots) {
      result.set(snapshot.id, snapshot);
      if (observe) observeDocument(context, snapshot);
    }
  }
  return result;
}

function observeDocument(context: Context, snapshot: DocumentSnapshot): void {
  const next = snapshot.exists ? updateTimeKey(snapshot) : "missing";
  const previous = context.observedDocuments.get(snapshot.ref.path);
  if (previous && previous !== next) {
    anomaly(context, "error", "conflict", snapshot.ref.path, "Source changed during the audit scan.");
  }
  context.observedDocuments.set(snapshot.ref.path, next);
}

function updateTimeKey(snapshot: DocumentSnapshot): string {
  return snapshot.updateTime
    ? `${snapshot.updateTime.seconds}:${snapshot.updateTime.nanoseconds}`
    : "exists-without-update-time";
}

function invalid(
  context: Context,
  stats: SourceStats,
  path: string,
  reason: string,
): void {
  stats.invalid += 1;
  anomaly(context, "error", "invalid", path, reason);
}

function unresolved(
  context: Context,
  stats: SourceStats,
  path: string,
  reason: string,
): void {
  stats.unresolved += 1;
  anomaly(context, "error", "unresolved", path, reason);
}

function anomaly(
  context: Context,
  severity: Anomaly["severity"],
  category: Anomaly["category"],
  sourcePath: string,
  reason: string,
): void {
  context.anomalies.push({severity, category, sourcePath, reason});
}

function emptySourceStats(): SourceStats {
  return {
    scanned: 0,
    eligible: 0,
    inRange: 0,
    excluded: 0,
    outsideRange: 0,
    invalid: 0,
    unresolved: 0,
    expectedLedgerEntries: 0,
  };
}

function emptyTotals(): Totals {
  return {
    sales: 0,
    cashSales: 0,
    creditSales: 0,
    receipts: 0,
    expenses: 0,
    returns: 0,
    settlements: 0,
    receivables: 0,
    companyCash: 0,
    repCashIn: 0,
    repCashOut: 0,
    repCashNet: 0,
  };
}

function addTotals(target: Totals, values: Partial<Totals>): void {
  for (const name of Object.keys(target) as MetricName[]) {
    target[name] = money(target[name] + (values[name] ?? 0));
  }
}

function addMonthlyTotals(
  target: Map<string, Totals>,
  date: Timestamp,
  values: Partial<Totals>,
): void {
  const key = monthKey(date);
  const totals = target.get(key) ?? emptyTotals();
  addTotals(totals, values);
  target.set(key, totals);
}

function monthKey(timestamp: Timestamp): string {
  const parts = new Intl.DateTimeFormat("en-CA", {
    timeZone: BUSINESS_TIME_ZONE,
    year: "numeric",
    month: "2-digit",
  }).formatToParts(timestamp.toDate());
  const year = parts.find((part) => part.type === "year")?.value ?? "0000";
  const month = parts.find((part) => part.type === "month")?.value ?? "00";
  return `${year}-${month}`;
}

function projectionSummaryWriteCount(queryKeys: string[], salesRepId: string): number {
  return queryKeys.length * (salesRepId ? 2 : 1);
}

function parsePreviousProjectionShape(data: DocumentData): {
  queryKeys: string[];
  salesRepId: string;
} | null {
  const queryKeys = stringArray(data.queryKeys);
  if (queryKeys.length === 0 || queryKeys.length !== (Array.isArray(data.queryKeys) ? data.queryKeys.length : -1)) {
    return null;
  }
  return {queryKeys, salesRepId: scalarString(data.salesRepId)};
}

function objectContains(actual: DocumentData, expected: DocumentData): boolean {
  return Object.entries(expected).every(([key, value]) => dataEqual(actual[key], value));
}

function dataEqual(left: unknown, right: unknown): boolean {
  return JSON.stringify(normalizeData(left)) === JSON.stringify(normalizeData(right));
}

function normalizeData(value: unknown): unknown {
  if (value instanceof Timestamp) return {seconds: value.seconds, nanoseconds: value.nanoseconds};
  if (Array.isArray(value)) return value.map(normalizeData);
  if (value && typeof value === "object") {
    return Object.fromEntries(
      Object.entries(value as Record<string, unknown>)
        .sort(([left], [right]) => left.localeCompare(right))
        .map(([key, item]) => [key, normalizeData(item)]),
    );
  }
  return value;
}

function businessPath(context: Context, collection: string, id: string): string {
  return `companies/${context.options.companyId}/${collection}/${id}`;
}

function authoritativeTimestamp(value: unknown): Timestamp | undefined {
  return value instanceof Timestamp ? value : undefined;
}

function inDateRange(options: Options, date: Timestamp): boolean {
  return (!options.from || date.toMillis() >= options.from.toMillis()) &&
    (!options.to || date.toMillis() <= options.to.toMillis());
}

function scalarString(value: unknown): string {
  return typeof value === "string" ? value.trim() : "";
}

function stringArray(value: unknown): string[] {
  return Array.isArray(value) ? value.map(scalarString).filter(Boolean) : [];
}

function plainObject(value: unknown): Record<string, unknown> {
  return value && typeof value === "object" && !Array.isArray(value)
    ? value as Record<string, unknown>
    : {};
}

function nestedString(value: unknown, key: string): string {
  return scalarString(plainObject(value)[key]);
}

function numberValue(value: unknown): number {
  const parsed = typeof value === "number" ? value : Number(value ?? 0);
  return Number.isFinite(parsed) ? parsed : 0;
}

function money(value: unknown): number {
  return Math.round(numberValue(value) * 1000) / 1000;
}

function positiveMoney(value: unknown): number {
  const result = money(value);
  return result > 0 ? result : 0;
}

function nonZeroMoney(value: unknown): number {
  const result = money(value);
  return result !== 0 ? result : 0;
}

function parseOptions(args: string[]): Options {
  const values = new Map<string, string>();
  let apply = false;
  for (const arg of args) {
    if (arg === "--apply") apply = true;
    else if (arg.startsWith("--") && arg.includes("=")) {
      const separator = arg.indexOf("=");
      values.set(arg.slice(2, separator), arg.slice(separator + 1));
    } else {
      throw new Error(`Unsupported argument: ${arg}`);
    }
  }
  const projectId = values.get("project") ?? "";
  const companyId = values.get("company") ?? "";
  if (!projectId || !companyId) throw new Error("--project and --company are required.");
  const fromText = values.get("from") ?? "";
  const toText = values.get("to") ?? "";
  const from = fromText ? parseBusinessDate(fromText, false) : undefined;
  const to = toText ? parseBusinessDate(toText, true) : undefined;
  if (from && to && from.toMillis() > to.toMillis()) throw new Error("--from must be on or before --to.");
  return {
    projectId,
    companyId,
    from,
    to,
    fromText,
    toText,
    apply,
    confirmProject: values.get("confirm-project") ?? "",
    confirmCompany: values.get("confirm-company") ?? "",
    pageSize: positiveInteger(values.get("page-size"), 200),
    maxWrites: positiveInteger(values.get("max-writes"), 500),
  };
}

function parseBusinessDate(value: string, endOfDay: boolean): Timestamp {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(value)) throw new Error("Dates must use YYYY-MM-DD.");
  const suffix = endOfDay ? "T23:59:59.999+03:00" : "T00:00:00.000+03:00";
  const date = new Date(`${value}${suffix}`);
  if (Number.isNaN(date.getTime()) || date.toISOString().slice(0, 10) !== value) {
    throw new Error(`Invalid business date: ${value}`);
  }
  return Timestamp.fromDate(date);
}

function positiveInteger(value: string | undefined, fallback: number): number {
  const parsed = Number(value ?? fallback);
  if (!Number.isInteger(parsed) || parsed <= 0) throw new Error("Numeric options must be positive integers.");
  return parsed;
}

function errorMessage(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}

if (require.main === module) {
  void main().catch((error) => {
    process.stderr.write(`${errorMessage(error)}\n`);
    process.exitCode = 1;
  });
}
