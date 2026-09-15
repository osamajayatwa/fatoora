const assert = require("node:assert/strict");
const {test} = require("node:test");
const {Timestamp} = require("firebase-admin/firestore");

const {
  FINANCIAL_LEDGER_SCHEMA_VERSION,
  LEDGER_QUERY_KEY_HASH_BYTES,
  LEDGER_SEARCH_TOKEN_HASH_BYTES,
  MAX_LEDGER_QUERY_KEYS,
  buildFinancialLedgerEntry,
  buildLedgerQueryKeys,
  buildLedgerSearchTokens,
  canonicalLedgerQueryKey,
  companyCashAccount,
  customerAccount,
  isLedgerQueryKeyHash,
  ledgerQueryKeyHash,
  ledgerSearchTokenHash,
  normalizeLedgerQueryKeysForSchemaV3,
  openingBalanceEquityAccount,
  salesAccount,
} = require("../lib/trusted/financial_ledger");
const {
  buildLedgerDerivedProjection,
  ledgerSummaryShard,
} = require("../lib/trusted/financial_ledger_reporting");
const {
  ACCOUNT_ACTIVITY_PROJECTION_VERSION,
  buildFinancialLedgerAccountActivity,
  businessDayKey,
  combineOpeningActivity,
} = require("../lib/trusted/financial_ledger_account_reporting");
const {
  receiptAllocationGroups,
} = require("../lib/trusted/create_receipt");
const {
  buildCustomerOpeningFinancialLedgerEntry,
  buildInvoiceFinancialLedgerEntries,
  buildSalesReturnFinancialLedgerEntries,
} = require("../lib/trusted/financial_ledger_mappings");

test("ledger query keys combine only type, account, customer, and payment", () => {
  const entry = buildFinancialLedgerEntry({
    id: "invoice_i1_sales_cash",
    companyId: "company",
    occurredAt: Timestamp.fromDate(new Date("2026-08-05T10:00:00.000Z")),
    type: "invoice_sale",
    component: "cash_sale",
    description: "Invoice INV-1",
    amount: 25,
    debit: companyCashAccount(),
    credit: salesAccount(),
    referenceType: "invoice",
    referenceId: "i1",
    referenceNumber: "INV-1",
    sourceCollection: "invoices",
    sourceId: "i1",
    customerId: "customer-1",
    customerName: "عميل النور",
    salesRepId: "rep-laith",
    salesRepName: "Laith",
    ownershipSource: "invoice.salesRepId",
    paymentMethod: "cash",
    metrics: {sales: 25, cashSales: 25, companyCashNet: 25},
  });

  const key = canonicalLedgerQueryKey({
    type: "invoice_sale",
    accountKey: "company_cash",
    customerId: "customer-1",
    paymentMethod: "cash",
  });
  assert.equal(entry.salesRepId, "rep-laith");
  assert.equal(entry.schemaVersion, FINANCIAL_LEDGER_SCHEMA_VERSION);
  assert.equal(entry.schemaVersion, 3);
  assert.equal(entry.metricSales, 25);
  assert.equal(entry.metricCashSales, 25);
  assert.ok(entry.queryKeys.includes(ledgerQueryKeyHash(key)));
  assert.ok(entry.queryKeys.includes(ledgerQueryKeyHash("all")));
  assert.ok(entry.queryKeys.every(isLedgerQueryKeyHash));
  assert.ok(entry.queryKeys.every((item) => Buffer.byteLength(item, "utf8") ===
    LEDGER_QUERY_KEY_HASH_BYTES));
  assert.equal(entry.queryKeys.length, 24);
  assert.ok(entry.queryKeys.every((item) => !item.includes("search")));
});

test("ledger SHA-256 query hashes match the Flutter cross-platform vectors", () => {
  assert.equal(
    ledgerQueryKeyHash("all"),
    "v3:XvXvA2S2k5xMph80s5P3s2jRvoYZZHqvg9WzlZGatik",
  );
  assert.equal(
    ledgerQueryKeyHash(
      "type=invoice_sale|account=rep_cash%3Arep-laith|" +
      "customer=customer-1|payment=cash",
    ),
    "v3:0_40QribO6XScU3frayH3EdACMI-LVY3ffGyvPPmGRA",
  );
  assert.equal(
    ledgerSearchTokenHash("inv"),
    "v3s:iScKUDQbuOg3NO4GJgPGPCGTIO1KQPufuMJ5I1hUjoo",
  );
});

test("schema-v3 query and search guards enforce compact fixed-width arrays", () => {
  assert.throws(
    () => normalizeLedgerQueryKeysForSchemaV3(["all", ["nested"]]),
    /only non-empty strings/,
  );
  assert.throws(
    () => normalizeLedgerQueryKeysForSchemaV3(
      Array.from({length: MAX_LEDGER_QUERY_KEYS + 1}, (_, index) => `key-${index}`),
    ),
    /key limit/,
  );
  const existing = ledgerQueryKeyHash("all");
  assert.deepEqual(normalizeLedgerQueryKeysForSchemaV3([existing]), [existing]);
  const searchTokens = buildLedgerSearchTokens([
    "INV-2026-000001",
    "Customer Name",
    "Invoice description",
  ]);
  assert.ok(searchTokens.length <= 96);
  assert.ok(searchTokens.every((item) => item.startsWith("v3s:")));
  assert.ok(searchTokens.every((item) => Buffer.byteLength(item, "utf8") ===
    LEDGER_SEARCH_TOKEN_HASH_BYTES));
});

test("base query key maximum remains 24 regardless of searchable text", () => {
  const keys = buildLedgerQueryKeys({
    type: "invoice_sale",
    accountKeys: ["rep_cash:rep-laith", "sales"],
    customerId: "customer-1",
    paymentMethod: "cash",
  });
  assert.equal(keys.length, 24);
});

test("derived projection separates bounded search tokens from compact query keys", () => {
  const entry = buildFinancialLedgerEntry({
    id: "invoice_i1_sales_cash",
    companyId: "company",
    occurredAt: Timestamp.fromDate(new Date("2026-08-05T10:00:00.000Z")),
    type: "invoice_sale",
    component: "cash_sale",
    description: "Invoice INV-1",
    amount: 25,
    debit: companyCashAccount(),
    credit: salesAccount(),
    referenceType: "invoice",
    referenceId: "i1",
    referenceNumber: "INV-1",
    sourceCollection: "invoices",
    sourceId: "i1",
    customerId: "customer-1",
    customerName: "Customer Name",
    salesRepId: "rep-laith",
    salesRepName: "Laith",
    paymentMethod: "cash",
  });
  const projection = buildLedgerDerivedProjection(entry.id, entry);
  assert.equal(projection.queryKeys.length, 24);
  assert.ok(projection.searchTokens.includes(ledgerSearchTokenHash("inv")));
  assert.ok(projection.searchTokens.length <= 96);
  assert.equal(projection.searchDocument.salesRepId, "rep-laith");
  assert.match(projection.summaryShard, /^s(?:0[0-9]|1[0-5])$/);
  assert.equal(projection.summaryShard, ledgerSummaryShard(entry.id));
});

test("account activity projection creates balanced debit and credit activity", () => {
  const entry = buildFinancialLedgerEntry({
    id: "invoice_i1_sales_cash",
    companyId: "company",
    occurredAt: Timestamp.fromDate(new Date("2026-08-05T21:30:00.000Z")),
    type: "invoice_sale",
    component: "cash_sale",
    description: "Invoice INV-1",
    amount: 25,
    debit: companyCashAccount(),
    credit: salesAccount(),
    referenceType: "invoice",
    referenceId: "i1",
    referenceNumber: "INV-1",
    sourceCollection: "invoices",
    sourceId: "i1",
    salesRepId: "rep-laith",
    salesRepName: "Laith",
  });
  const projection = buildFinancialLedgerAccountActivity(entry.id, entry);

  assert.equal(ACCOUNT_ACTIVITY_PROJECTION_VERSION, 1);
  assert.equal(projection.dayKey, "2026-08-06");
  assert.equal(projection.monthKey, "2026-08");
  assert.equal(projection.salesRepId, "rep-laith");
  assert.equal(projection.activities.length, 2);
  assert.equal(
    projection.activities.reduce((sum, activity) => sum + activity.debit, 0),
    25,
  );
  assert.equal(
    projection.activities.reduce((sum, activity) => sum + activity.credit, 0),
    25,
  );
  assert.equal(
    projection.activities.reduce((sum, activity) => sum + activity.netChange, 0),
    0,
  );
  assert.match(projection.postingId, /^2026-08-06_/);
});

test("opening balance combines monthly, daily, and same-day projected activity", () => {
  const opening = combineOpeningActivity("company_cash", [
    {
      accountKey: "company_cash",
      accountType: "cash",
      accountName: "Cash",
      debitTotal: 100,
      creditTotal: 20,
    },
    {
      accountKey: "company_cash",
      accountType: "cash",
      accountName: "Cash",
      debitTotal: 10,
      creditTotal: 5,
    },
    {
      accountKey: "company_cash",
      accountType: "cash",
      accountName: "Cash",
      debit: 3,
      credit: 1,
    },
  ]);

  assert.deepEqual(opening, {
    accountKey: "company_cash",
    accountType: "cash",
    accountName: "Cash",
    debit: 113,
    credit: 26,
    balance: 87,
  });
  assert.equal(
    businessDayKey(Timestamp.fromDate(new Date("2026-08-05T21:30:00.000Z"))),
    "2026-08-06",
  );
});

test("one ledger row carries equal debit and credit amounts without guessing ownership", () => {
  const entry = buildFinancialLedgerEntry({
    id: "opening_balance_customer-1_posted",
    companyId: "company",
    occurredAt: Timestamp.now(),
    type: "opening_balance",
    component: "customer_owes",
    description: "Opening balance",
    amount: 100,
    debit: customerAccount("customer-1", "Customer"),
    credit: openingBalanceEquityAccount(),
    referenceType: "customer",
    referenceId: "customer-1",
    referenceNumber: "OPENING",
    sourceCollection: "customer_transactions",
    sourceId: "customer-1_opening_balance",
  });
  assert.equal(entry.amount, 100);
  assert.equal(entry.debitAccountKey, "customer:customer-1");
  assert.equal(entry.creditAccountKey, "opening_balance_equity");
  assert.equal(entry.salesRepId, "");
  assert.equal(entry.ownershipSource, "");
});

test("admin-created receipts inherit financial ownership from allocated invoices", () => {
  const groups = receiptAllocationGroups([
    {
      id: "invoice-laith-1",
      amount: 40,
      data: {salesRepId: "rep-laith", salesRepName: "Laith"},
    },
    {
      id: "invoice-laith-2",
      amount: 10,
      data: {salesRepId: "rep-laith", salesRepName: "Laith"},
    },
    {
      id: "invoice-other",
      amount: 20,
      data: {salesRepId: "rep-other", salesRepName: "Other"},
    },
  ], 0, "", "");

  assert.deepEqual(groups, [
    {
      salesRepId: "rep-laith",
      salesRepName: "Laith",
      amount: 50,
      ownershipSource: "receipt.invoiceAllocations.salesRepId",
    },
    {
      salesRepId: "rep-other",
      salesRepName: "Other",
      amount: 20,
      ownershipSource: "receipt.invoiceAllocations.salesRepId",
    },
  ]);
});

test("shared invoice mapping preserves deterministic cash and credit components", () => {
  const entries = buildInvoiceFinancialLedgerEntries({
    companyId: "company",
    invoiceId: "invoice-1",
    invoiceNumber: "INV-1",
    invoiceDate: Timestamp.fromDate(new Date("2026-08-01T08:00:00.000Z")),
    grandTotal: 100,
    initialCashAmount: 40,
    initialCashAccount: "rep_cash",
    customerId: "customer-1",
    customerName: "Customer",
    salesRepId: "rep-1",
    salesRepName: "Representative",
    notes: "",
  });
  assert.deepEqual(entries.map((entry) => entry.id), [
    "invoice_invoice-1_sales_cash",
    "invoice_invoice-1_sales_receivable",
  ]);
  assert.equal(entries[0].metricCashSales, 40);
  assert.equal(entries[0].metricRepCashIn, 40);
  assert.equal(entries[1].metricCreditSales, 60);
  assert.equal(entries[1].metricReceivables, 60);
});

test("shared opening mapping keeps initial and adjustment semantics distinct", () => {
  const date = Timestamp.fromDate(new Date("2026-08-02T08:00:00.000Z"));
  const initial = buildCustomerOpeningFinancialLedgerEntry({
    companyId: "company",
    transactionId: "customer-1_opening_balance",
    transactionDate: date,
    transactionType: "opening_balance",
    openingBalanceType: "customer_credit",
    signedAmount: -100,
    customerId: "customer-1",
    customerName: "Customer",
    salesRepId: "",
    salesRepName: "",
    notes: "",
  });
  const adjustment = buildCustomerOpeningFinancialLedgerEntry({
    companyId: "company",
    transactionId: "adjustment-1",
    transactionDate: date,
    transactionType: "opening_balance_adjustment",
    openingBalanceType: "customer_owes",
    signedAmount: 25,
    customerId: "customer-1",
    customerName: "Customer",
    salesRepId: "rep-1",
    salesRepName: "Representative",
    notes: "reason",
  });
  assert.equal(initial.component, "customer_credit");
  assert.equal(initial.metricReceivables, -100);
  assert.equal(adjustment.component, "increase_receivable");
  assert.equal(adjustment.metricReceivables, 25);
  assert.equal(adjustment.ownershipSource, "postingSalesRep.uid");
});

test("shared sales-return mapping preserves quantity and net metrics", () => {
  const entries = buildSalesReturnFinancialLedgerEntries({
    companyId: "company",
    returnId: "return-1",
    returnNumber: "RET-1",
    returnDate: Timestamp.fromDate(new Date("2026-08-03T08:00:00.000Z")),
    grandTotal: 30,
    cashRefundAmount: 10,
    refundType: "cash_refund",
    refundCashAccount: "company_cash",
    refundCashSalesRepId: "",
    customerId: "customer-1",
    customerName: "Customer",
    salesRepId: "rep-1",
    salesRepName: "Representative",
    quantity: 3,
    reason: "return",
  });
  assert.equal(entries.length, 2);
  assert.equal(entries[0].quantity, 3);
  assert.equal(entries[0].metricSales, -30);
  assert.equal(entries[0].metricReturns, 30);
  assert.equal(entries[1].metricCompanyCashNet, -10);
});
