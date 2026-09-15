import {
  DocumentData,
  Firestore,
  Timestamp,
  Transaction,
} from "firebase-admin/firestore";
import {createHash} from "node:crypto";
import {businessPath, roundMoney} from "./common";

export const FINANCIAL_LEDGER_SCHEMA_VERSION = 3;
export const MAX_LEDGER_QUERY_KEYS = 24;
export const LEDGER_QUERY_KEY_HASH_BYTES = 46;
export const MAX_LEDGER_QUERY_KEY_INDEXED_VALUE_BYTES =
  MAX_LEDGER_QUERY_KEYS * (LEDGER_QUERY_KEY_HASH_BYTES + 1);
export const MAX_LEDGER_SEARCH_TOKENS = 96;
export const LEDGER_SEARCH_TOKEN_HASH_BYTES = 47;
export const MAX_LEDGER_SEARCH_TOKEN_INDEXED_VALUE_BYTES =
  MAX_LEDGER_SEARCH_TOKENS * (LEDGER_SEARCH_TOKEN_HASH_BYTES + 1);

const LEDGER_QUERY_KEY_HASH_PATTERN = /^v3:[A-Za-z0-9_-]{43}$/;
const LEDGER_SEARCH_TOKEN_HASH_PATTERN = /^v3s:[A-Za-z0-9_-]{43}$/;

export interface LedgerAccount {
  type: string;
  key: string;
  id: string;
  name: string;
}

export interface LedgerMetrics {
  sales?: number;
  cashSales?: number;
  creditSales?: number;
  receipts?: number;
  expenses?: number;
  returns?: number;
  settlements?: number;
  receivables?: number;
  companyCashNet?: number;
  repCashIn?: number;
  repCashOut?: number;
}

export interface FinancialLedgerEntryInput {
  id: string;
  companyId: string;
  occurredAt: Timestamp;
  type: string;
  component: string;
  description: string;
  amount: number;
  debit: LedgerAccount;
  credit: LedgerAccount;
  referenceType: string;
  referenceId: string;
  referenceNumber: string;
  sourceCollection: string;
  sourceId: string;
  customerId?: string;
  customerName?: string;
  salesRepId?: string;
  salesRepName?: string;
  ownershipSource?: string;
  paymentMethod?: string;
  quantity?: number;
  unitPrice?: number;
  notes?: string;
  operationId?: string;
  metrics?: LedgerMetrics;
}

export function companyCashAccount(): LedgerAccount {
  return account("cash", "company_cash", "", "Company cash");
}

export function repCashAccount(salesRepId: string, name: string): LedgerAccount {
  return account("cash", `rep_cash:${salesRepId}`, salesRepId, name || "Representative cash");
}

export function customerAccount(customerId: string, name: string): LedgerAccount {
  return account("customer", `customer:${customerId}`, customerId, name || "Customer");
}

export function salesAccount(): LedgerAccount {
  return account("sales", "sales", "", "Sales");
}

export function expensesAccount(): LedgerAccount {
  return account("expense", "expenses", "", "Expenses");
}

export function openingBalanceEquityAccount(): LedgerAccount {
  return account("equity", "opening_balance_equity", "", "Opening balance equity");
}

export function repPayableAccount(salesRepId: string, name: string): LedgerAccount {
  return account("liability", `rep_payable:${salesRepId}`, salesRepId, name || "Representative payable");
}

export function collectionAccount(paymentMethod: string): LedgerAccount {
  if (paymentMethod === "cash") return companyCashAccount();
  if (paymentMethod === "check") {
    return account("clearing", "check_clearing", "", "Checks in collection");
  }
  if (paymentMethod === "cliq") {
    return account("clearing", "cliq_clearing", "", "CliQ clearing");
  }
  return account("bank", "bank_unallocated", "", "Unallocated bank account");
}

export function cashAccount(
  value: unknown,
  salesRepId: string,
  salesRepName: string,
): LedgerAccount {
  return value === "rep_cash"
    ? repCashAccount(salesRepId, salesRepName)
    : companyCashAccount();
}

export function buildFinancialLedgerEntry(
  input: FinancialLedgerEntryInput,
): DocumentData {
  const amount = roundMoney(input.amount);
  if (amount <= 0) throw new Error("Financial ledger amount must be positive.");
  const customerId = input.customerId ?? "";
  const customerName = input.customerName ?? "";
  const salesRepId = input.salesRepId ?? "";
  const salesRepName = input.salesRepName ?? "";
  const paymentMethod = input.paymentMethod ?? "";
  const notes = input.notes ?? "";
  const metrics = input.metrics ?? {};
  const accountKeys = [...new Set([input.debit.key, input.credit.key])];
  return {
    id: input.id,
    companyId: input.companyId,
    schemaVersion: FINANCIAL_LEDGER_SCHEMA_VERSION,
    occurredAt: input.occurredAt,
    postedAt: input.occurredAt,
    type: input.type,
    component: input.component,
    description: input.description,
    amount,
    quantity: input.quantity ?? 0,
    unitPrice: input.unitPrice ?? 0,
    debitAccountType: input.debit.type,
    debitAccountKey: input.debit.key,
    debitAccountId: input.debit.id,
    debitAccountName: input.debit.name,
    creditAccountType: input.credit.type,
    creditAccountKey: input.credit.key,
    creditAccountId: input.credit.id,
    creditAccountName: input.credit.name,
    accountKeys,
    customerId,
    customerName,
    salesRepId,
    salesRepName,
    ownershipSource: input.ownershipSource ?? "",
    paymentMethod,
    referenceType: input.referenceType,
    referenceId: input.referenceId,
    referenceNumber: input.referenceNumber,
    sourceCollection: input.sourceCollection,
    sourceId: input.sourceId,
    sourcePath: businessPath(input.companyId, input.sourceCollection, input.sourceId),
    operationId: input.operationId ?? input.referenceId,
    notes,
    queryKeys: buildLedgerQueryKeys({
      type: input.type,
      accountKeys,
      customerId,
      paymentMethod,
    }),
    metricSales: roundMoney(metrics.sales ?? 0),
    metricCashSales: roundMoney(metrics.cashSales ?? 0),
    metricCreditSales: roundMoney(metrics.creditSales ?? 0),
    metricReceipts: roundMoney(metrics.receipts ?? 0),
    metricExpenses: roundMoney(metrics.expenses ?? 0),
    metricReturns: roundMoney(metrics.returns ?? 0),
    metricSettlements: roundMoney(metrics.settlements ?? 0),
    metricReceivables: roundMoney(metrics.receivables ?? 0),
    metricCompanyCashNet: roundMoney(metrics.companyCashNet ?? 0),
    metricRepCashIn: roundMoney(metrics.repCashIn ?? 0),
    metricRepCashOut: roundMoney(metrics.repCashOut ?? 0),
  };
}

export function writeFinancialLedgerEntries(
  transaction: Transaction,
  firestore: Firestore,
  entries: DocumentData[],
): void {
  for (const entry of entries) {
    const id = String(entry.id ?? "");
    const companyId = String(entry.companyId ?? "");
    if (!id || !companyId) throw new Error("Financial ledger identity is required.");
    transaction.set(
      firestore.doc(businessPath(companyId, "financial_ledger_entries", id)),
      entry,
    );
  }
}

export function buildLedgerQueryKeys(input: {
  type: string;
  accountKeys: string[];
  customerId: string;
  paymentMethod: string;
}): string[] {
  const uniqueAccountKeys = [...new Set(input.accountKeys.filter(Boolean))];
  if (uniqueAccountKeys.length > 2) {
    throw new Error("Financial ledger entries may reference at most two accounts.");
  }
  const types = ["", input.type];
  const accounts = ["", ...uniqueAccountKeys];
  const customers = input.customerId ? ["", input.customerId] : [""];
  const payments = input.paymentMethod ? ["", input.paymentMethod] : [""];
  const baseKeys = new Set<string>();
  for (const type of types) {
    for (const accountKey of accounts) {
      for (const customerId of customers) {
        for (const paymentMethod of payments) {
          baseKeys.add(canonicalLedgerQueryKey({
            type,
            accountKey,
            customerId,
            paymentMethod,
          }));
        }
      }
    }
  }
  return normalizeLedgerQueryKeysForSchemaV3([...baseKeys]);
}

/**
 * Converts the canonical query string into the fixed-width value stored in
 * queryKeys. Full SHA-256 is used so financial filters do not rely on a
 * collision-prone truncated digest.
 */
export function ledgerQueryKeyHash(value: string): string {
  return `v3:${createHash("sha256").update(value, "utf8").digest("base64url")}`;
}

export function isLedgerQueryKeyHash(value: string): boolean {
  return LEDGER_QUERY_KEY_HASH_PATTERN.test(value) &&
    Buffer.byteLength(value, "utf8") === LEDGER_QUERY_KEY_HASH_BYTES;
}

/**
 * Shared writer/migration guard for schema-v3 base-filter queryKeys. Search is
 * deliberately excluded so it cannot multiply these combinations.
 */
export function normalizeLedgerQueryKeysForSchemaV3(value: unknown): string[] {
  if (!Array.isArray(value)) {
    throw new Error("Financial ledger queryKeys must be an array.");
  }
  if (value.length === 0) {
    throw new Error("Financial ledger queryKeys must not be empty.");
  }
  if (value.length > MAX_LEDGER_QUERY_KEYS) {
    throw new Error(
      `Financial ledger queryKeys exceeds the ${MAX_LEDGER_QUERY_KEYS} key limit.`,
    );
  }
  const normalized = new Set<string>();
  for (const item of value) {
    if (typeof item !== "string" || item.length === 0) {
      throw new Error("Financial ledger queryKeys must contain only non-empty strings.");
    }
    normalized.add(isLedgerQueryKeyHash(item) ? item : ledgerQueryKeyHash(item));
  }
  const result = [...normalized].sort();
  if (result.length > MAX_LEDGER_QUERY_KEYS) {
    throw new Error(
      `Financial ledger queryKeys exceeds the ${MAX_LEDGER_QUERY_KEYS} key limit.`,
    );
  }
  const indexedValueBytes = result.reduce(
    (total, item) => total + Buffer.byteLength(item, "utf8") + 1,
    0,
  );
  if (result.some((item) => !isLedgerQueryKeyHash(item))) {
    throw new Error("Financial ledger queryKeys contains an invalid schema-v3 hash.");
  }
  if (indexedValueBytes > MAX_LEDGER_QUERY_KEY_INDEXED_VALUE_BYTES) {
    throw new Error(
      "Financial ledger queryKeys exceeds the schema-v3 indexed-value byte budget.",
    );
  }
  return result;
}

export function canonicalLedgerQueryKey(input: {
  type?: string;
  accountKey?: string;
  customerId?: string;
  paymentMethod?: string;
}): string {
  const parts: string[] = [];
  addQueryPart(parts, "type", input.type);
  addQueryPart(parts, "account", input.accountKey);
  addQueryPart(parts, "customer", input.customerId);
  addQueryPart(parts, "payment", input.paymentMethod);
  return parts.length === 0 ? "all" : parts.join("|");
}

export function normalizeLedgerSearch(value: string): string {
  return value
    .toLocaleLowerCase("en")
    .replace(/[|=]+/g, " ")
    .replace(/[^a-z0-9\u0600-\u06ff]+/gi, " ")
    .trim()
    .replace(/\s+/g, " ");
}

export function ledgerSearchTokenHash(value: string): string {
  return `v3s:${createHash("sha256").update(value, "utf8").digest("base64url")}`;
}

export function isLedgerSearchTokenHash(value: string): boolean {
  return LEDGER_SEARCH_TOKEN_HASH_PATTERN.test(value) &&
    Buffer.byteLength(value, "utf8") === LEDGER_SEARCH_TOKEN_HASH_BYTES;
}

export function buildLedgerSearchTokens(value: string | string[]): string[] {
  const tokens = ledgerSearchKeywords(value).map(ledgerSearchTokenHash);
  if (tokens.length === 0) {
    // All ledger entries need a searchable projection shape, even when their
    // optional human-readable fields happen to be empty.
    return [ledgerSearchTokenHash("_")];
  }
  if (tokens.length > MAX_LEDGER_SEARCH_TOKENS) {
    throw new Error(
      `Financial ledger searchTokens exceeds the ${MAX_LEDGER_SEARCH_TOKENS} token limit.`,
    );
  }
  if (tokens.some((token) => !isLedgerSearchTokenHash(token))) {
    throw new Error("Financial ledger searchTokens contains an invalid schema-v3 hash.");
  }
  const indexedValueBytes = tokens.reduce(
    (total, token) => total + Buffer.byteLength(token, "utf8") + 1,
    0,
  );
  if (indexedValueBytes > MAX_LEDGER_SEARCH_TOKEN_INDEXED_VALUE_BYTES) {
    throw new Error(
      "Financial ledger searchTokens exceeds the schema-v3 indexed-value byte budget.",
    );
  }
  return tokens;
}

function ledgerSearchKeywords(value: string | string[]): string[] {
  const phrases = (Array.isArray(value) ? value : [value])
    .map(normalizeLedgerSearch)
    .filter(Boolean);
  const seeds = [...new Set([
    ...phrases,
    ...phrases.flatMap((phrase) => phrase.split(" ")),
  ])].slice(0, 24);
  const keywords = new Set<string>();
  for (const seed of seeds) {
    keywords.add(seed.slice(0, 20));
  }
  for (let length = 2; length <= 20; length += 1) {
    for (const seed of seeds) {
      const bounded = seed.slice(0, 20);
      if (length <= bounded.length) keywords.add(bounded.slice(0, length));
      if (keywords.size >= 96) return [...keywords];
    }
  }
  return [...keywords];
}

function account(type: string, key: string, id: string, name: string): LedgerAccount {
  return {type, key, id, name};
}

function addQueryPart(parts: string[], name: string, value?: string): void {
  if (value) parts.push(`${name}=${encodeURIComponent(value)}`);
}
