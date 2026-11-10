import {createHash} from "node:crypto";
import {HttpsError} from "firebase-functions/v2/https";
import {decimalNumber, parseUnits, sumUnits} from "./exact_decimal";
import {companyCashAccount, repCashAccount} from "./financial_ledger";

export interface SettlementMonetaryPolicy {
  companyId: string;
  bookId: string;
  revisionId: string;
  currency: string;
  moneyScale: 3;
  legacyCurrencyBindingId?: string;
}

/** Supplied configuration evidence, never a default chart-of-accounts mapping. */
export interface SettlementCashMapping {
  companyId: string;
  bookId: string;
  mappingRevisionId: string;
  currency: string;
  moneyScale: 3;
  accountId: string;
  accountRevisionId: string;
  accountType: "asset";
  control: "cash";
  active: true;
  postingAllowed: true;
  requiresTreasuryDimension: true;
  ledgerAccountKey: string;
  treasuryAccountId: string;
  holderType: "company" | "representative";
  holderUid: string;
}

export interface SettlementJournalIntentInput {
  companyId: string;
  bookId: string;
  policy: SettlementMonetaryPolicy;
  mappings: readonly SettlementCashMapping[];
  settlement: Readonly<Record<string, unknown>>;
  movements: readonly Readonly<Record<string, unknown>>[];
}

interface SourceTimestamp {seconds: number; nanoseconds: number}
interface SourceActor {uid: string; name: string; role: "admin"}
interface Provenance {
  settlementMetadataVersion: 1;
  postingSource: "recordCashSettlement";
  paymentMethod: "cash";
  createdBy: SourceActor;
  sourceCreatedBy: SourceActor;
  postedBy: SourceActor;
  createdAt: SourceTimestamp;
  postedAt: SourceTimestamp;
  sellerId: "";
  sellerName: "";
  sellerIdentityStatus: "not_applicable";
  collectorUid: "";
  collectorName: "";
  collectorIdentityStatus: "not_applicable";
}
interface IntentMovement {
  id: string;
  path: string;
  companyId: string;
  settlementId: string;
  operationId: string;
  sourceCollection: "settlements";
  sourceId: string;
  sourceNumber: string;
  referenceId: string;
  referenceNumber: string;
  type: "settlement_to_admin";
  movementType: "settlement_to_admin";
  direction: "in" | "out";
  counterpartMovementId: string;
  cashAccount: "company_cash" | "rep_cash";
  treasuryAccountId: string;
  holderType: "company" | "representative";
  holderUid: string;
  salesRepId: string;
  amountUnits: string;
  balanceBeforeUnits: string;
  balanceAfterUnits: string;
  currency: string;
  moneyScale: 3;
  date: SourceTimestamp;
  movementDate: SourceTimestamp;
  provenance: Provenance;
}
interface IntentLine {
  id: string;
  companyId: string;
  bookId: string;
  currency: string;
  moneyScale: 3;
  account: SettlementCashMapping;
  debitUnits: string;
  creditUnits: string;
  cashMovementId: string;
  counterpartMovementId: string;
}
export interface SettlementJournalIntent {
  schemaVersion: 1;
  id: string;
  companyId: string;
  bookId: string;
  action: "rep_to_company_cash";
  currency: string;
  moneyScale: 3;
  amountUnits: string;
  policy: SettlementMonetaryPolicy;
  source: {
    collection: "settlements";
    id: string;
    path: string;
    number: string;
    status: "posted";
    operationId: string;
    idempotencyKey: string;
    salesRepId: string;
    repMovementId: string;
    companyMovementId: string;
    sourceCashAccount: "rep_cash";
    sourceCashAccountId: string;
    destinationCashAccount: "company_cash";
    destinationCashAccountId: "company_cash";
    settlementDate: SourceTimestamp;
    updatedAt: SourceTimestamp;
    provenance: Provenance;
  };
  movements: readonly IntentMovement[];
  lines: readonly IntentLine[];
  payloadDigest: string;
}

export type SettlementJournalEconomics = Pick<SettlementJournalIntent,
  "schemaVersion" | "id" | "companyId" | "bookId" | "action" | "currency" | "moneyScale" | "amountUnits" | "policy" | "lines">;

export function settlementJournalIdentity(companyId: string, bookId: string, settlementId: string): string {
  return `settlement_intent_${hash([1, identifier(companyId, "companyId"), identifier(bookId, "bookId"),
    "settlements", identifier(settlementId, "settlementId"), "rep_to_company_cash"])}`;
}

/** Shared pure economics for committed and pending evidence. No clocks or writes. */
export function buildSettlementJournalEconomics(input: {
  companyId: string; bookId: string; settlementId: string; salesRepId: string;
  amountUnits: string; policy: SettlementMonetaryPolicy; mappings: readonly SettlementCashMapping[];
}): SettlementJournalEconomics {
  object(input, "input");
  const companyId = identifier(input.companyId, "companyId"), bookId = identifier(input.bookId, "bookId");
  const settlementId = identifier(input.settlementId, "settlementId"), rep = identifier(input.salesRepId, "salesRepId");
  check(typeof input.amountUnits === "string" && /^[1-9][0-9]{0,29}$/.test(input.amountUnits), "Positive canonical settlement units required.");
  const amount = sumUnits([BigInt(input.amountUnits)]), policy = monetaryPolicy(input.policy, companyId, bookId);
  check(Array.isArray(input.mappings) && input.mappings.length === 2, "Exactly two explicit cash mappings required.");
  const mappings = input.mappings.map((m) => cashMapping(m, companyId, bookId, policy));
  const accountFor = (credit: boolean): SettlementCashMapping => {
    const matches = mappings.filter(a => a.ledgerAccountKey === (credit ? repCashAccount(rep, "").key : companyCashAccount().key));
    check(matches.length === 1, "Missing or ambiguous cash mapping.");
    const a = matches[0];
    equal(a.treasuryAccountId, credit ? `rep_${rep}` : "company_cash", "Mapping treasury dimension");
    equal(a.holderType, credit ? "representative" : "company", "Mapping holder type");
    equal(a.holderUid, credit ? rep : companyId, "Mapping holder dimension");
    return a;
  };
  const sourceAccount = accountFor(true), destinationAccount = accountFor(false);
  if (sourceAccount.accountId === destinationAccount.accountId) equal(sourceAccount.accountRevisionId, destinationAccount.accountRevisionId, "Shared cash-control revision");
  const id = settlementJournalIdentity(companyId, bookId, settlementId);
  const lines = [false, true].map((credit): IntentLine => ({
    id: `${id}_${credit ? "credit" : "debit"}`, companyId, bookId,
    currency: policy.currency, moneyScale: 3, account: credit ? sourceAccount : destinationAccount,
    debitUnits: credit ? "0" : amount.toString(), creditUnits: credit ? amount.toString() : "0",
    cashMovementId: `${settlementId}_${credit ? "rep_out" : "company_in"}`,
    counterpartMovementId: `${settlementId}_${credit ? "company_in" : "rep_out"}`,
  }));
  equal(sumUnits(lines.map(l => BigInt(l.debitUnits))), sumUnits(lines.map(l => BigInt(l.creditUnits))), "Journal balance");
  return freeze({schemaVersion: 1, id, companyId, bookId, action: "rep_to_company_cash", currency: policy.currency,
    moneyScale: 3, amountUnits: amount.toString(), policy, lines});
}

/** Offline only. Caller must supply trusted snapshots/configuration and, for
 * replay comparison, the prior intent. This function performs no dedup writes. */
export function buildSettlementJournalIntent(
  input: SettlementJournalIntentInput,
  priorIntent?: unknown,
): SettlementJournalIntent {
  const data = object(input, "input");
  const companyId = identifier(data.companyId, "companyId");
  const bookId = identifier(data.bookId, "bookId");
  const policy = monetaryPolicy(data.policy, companyId, bookId);
  const settlement = object(data.settlement, "settlement");
  equal(settlement.companyId, companyId, "Settlement company");
  equal(settlement.status, "posted", "Settlement status");
  const settlementId = identifier(settlement.id, "settlement.id");
  const key = text(settlement.idempotencyKey, "idempotencyKey", 128);
  check(/^[A-Za-z0-9_-]{8,128}$/.test(key), "Invalid settlement idempotency key.");
  equal(settlementId, `settlement_${key}`, "Settlement identity");
  equal(settlement.operationId, settlementId, "Settlement operation");
  const number = text(settlement.settlementNumber, "settlementNumber");
  for (const [field, expected] of Object.entries({
    bookId, settlementId, sourceCollection: "settlements", sourceId: settlementId,
    sourceNumber: number, referenceId: settlementId, referenceNumber: number,
    sourcePath: `companies/${companyId}/settlements/${settlementId}`,
  })) {
    if (settlement[field] !== undefined) equal(settlement[field], expected, `Settlement ${field}`);
  }
  const rep = identifier(settlement.salesRepId, "salesRepId");
  const amount = money(settlement.amount, "settlement.amount");
  check(amount > 0n, "Settlement amount must be positive.");
  checkCurrency(settlement, policy);
  const provenance = sourceProvenance(settlement);
  check(provenance.createdBy.uid !== rep, "Posting admin cannot be the representative holder.");
  const date = timestamp(settlement.settlementDate, "settlementDate");
  const updatedAt = timestamp(settlement.updatedAt, "updatedAt");
  same(updatedAt, provenance.createdAt, "Settlement commit timestamps");
  equal(settlement.repMovementId, `${settlementId}_rep_out`, "Source movement ID");
  equal(settlement.companyMovementId, `${settlementId}_company_in`, "Destination movement ID");
  equal(settlement.sourceCashAccount, "rep_cash", "Source cash account");
  equal(settlement.sourceCashAccountId, `rep_${rep}`, "Source treasury account");
  equal(settlement.destinationCashAccount, "company_cash", "Destination cash account");
  equal(settlement.destinationCashAccountId, "company_cash", "Destination treasury account");

  check(Array.isArray(data.movements) && data.movements.length === 2, "Exactly two source movements required.");
  const rawMovements = (data.movements as unknown[]).map((m) => object(m, "movement"));
  const movements = [true, false].map((isOut): IntentMovement => {
    const movementId = `${settlementId}_${isOut ? "rep_out" : "company_in"}`;
    const matches = rawMovements.filter((m) => m.id === movementId);
    check(matches.length === 1, "Missing or duplicate settlement movement.");
    const m = matches[0];
    equal(m.companyId, companyId, "Movement company");
    equal(m.type, "settlement_to_admin", "Movement type");
    equal(m.movementType, "settlement_to_admin", "Movement type");
    equal(m.settlementId, settlementId, "Movement settlement");
    equal(m.operationId, settlementId, "Movement operation");
    equal(m.sourceCollection, "settlements", "Movement source collection");
    equal(m.sourceId, settlementId, "Movement source");
    equal(m.referenceId, settlementId, "Movement reference");
    equal(m.sourceNumber, number, "Movement source number");
    equal(m.referenceNumber, number, "Movement reference number");
    if (m.bookId !== undefined) equal(m.bookId, bookId, "Movement book");
    if (m.sourcePath !== undefined) {
      equal(m.sourcePath, `companies/${companyId}/settlements/${settlementId}`, "Movement source path");
    }
    equal(m.direction, isOut ? "out" : "in", "Movement direction");
    equal(m.cashAccount, isOut ? "rep_cash" : "company_cash", "Movement cash account");
    const treasuryAccountId = isOut ? `rep_${rep}` : "company_cash";
    const holderType = isOut ? "representative" : "company";
    const holderUid = isOut ? rep : companyId;
    equal(m.treasuryAccountId, treasuryAccountId, "Movement treasury identity");
    equal(m.holderType, holderType, "Movement holder type");
    equal(m.holderUid, holderUid, "Movement holder identity");
    equal(m.salesRepId, isOut ? rep : "", "Movement cash-account representative");
    if (m.cashAccountSalesRepId !== undefined) {
      equal(m.cashAccountSalesRepId, isOut ? rep : "", "Conflicting cash-account representative");
    }
    const counterpartMovementId = `${settlementId}_${isOut ? "company_in" : "rep_out"}`;
    equal(m.counterpartMovementId, counterpartMovementId, "Reciprocal movement reference");
    equal(money(m.amount, "movement.amount"), amount, "Movement amount");
    checkCurrency(m, policy);
    const before = money(m.balanceBefore, "balanceBefore");
    const after = money(m.balanceAfter, "balanceAfter");
    check(before >= 0n && after >= 0n, "Negative physical cash balance.");
    equal(sumUnits([before, isOut ? -amount : amount]), after, "Movement balance equation");
    const movementDate = timestamp(m.movementDate, "movementDate");
    const storedDate = timestamp(m.date, "date");
    same(storedDate, date, "Movement business date");
    same(movementDate, date, "Movement business date");
    const movementProvenance = sourceProvenance(m);
    same(movementProvenance, provenance, "Movement provenance");
    return {
      id: movementId, path: `companies/${companyId}/cash_movements/${movementId}`,
      companyId, settlementId, operationId: settlementId, sourceCollection: "settlements",
      sourceId: settlementId, sourceNumber: number, referenceId: settlementId,
      referenceNumber: number, type: "settlement_to_admin", movementType: "settlement_to_admin",
      direction: isOut ? "out" : "in", counterpartMovementId,
      cashAccount: isOut ? "rep_cash" : "company_cash", treasuryAccountId,
      holderType, holderUid, salesRepId: isOut ? rep : "", amountUnits: amount.toString(),
      balanceBeforeUnits: before.toString(), balanceAfterUnits: after.toString(),
      currency: policy.currency, moneyScale: 3, date: storedDate, movementDate,
      provenance: movementProvenance,
    };
  });

  const economics = buildSettlementJournalEconomics({companyId, bookId, settlementId, salesRepId: rep,
    amountUnits: amount.toString(), policy, mappings: data.mappings as SettlementCashMapping[]});
  const {id, lines} = economics;
  const sourceAccount = lines[1].account;
  const payload: Omit<SettlementJournalIntent, "payloadDigest"> = {
    schemaVersion: 1, id, companyId, bookId, action: "rep_to_company_cash",
    currency: policy.currency, moneyScale: 3, amountUnits: amount.toString(), policy,
    source: {
      collection: "settlements", id: settlementId,
      path: `companies/${companyId}/settlements/${settlementId}`, number, status: "posted",
      operationId: settlementId, idempotencyKey: key, salesRepId: rep,
      repMovementId: movements[0].id, companyMovementId: movements[1].id,
      sourceCashAccount: "rep_cash", sourceCashAccountId: sourceAccount.treasuryAccountId,
      destinationCashAccount: "company_cash", destinationCashAccountId: "company_cash",
      settlementDate: date, updatedAt, provenance,
    }, movements, lines,
  };
  const intent = {...payload, payloadDigest: hash(payload)};
  if (priorIntent !== undefined && canonical(priorIntent) !== canonical(intent)) {
    throw new HttpsError("already-exists", "Settlement journal intent conflicts with the prior intent.");
  }
  return freeze(intent);
}

/** Validate against original evidence, not merely a balanced caller-supplied journal. */
export function validateSettlementJournalIntent(
  candidate: unknown,
  input: SettlementJournalIntentInput,
): SettlementJournalIntent {
  const expected = buildSettlementJournalIntent(input);
  same(candidate, expected, "Journal intent does not match its source evidence");
  return expected;
}

function check(condition: boolean, message: string): asserts condition {
  if (!condition) throw new HttpsError("invalid-argument", message);
}
function equal(actual: unknown, expected: unknown, label: string): void {
  check(actual === expected, `${label} is inconsistent.`);
}
function object(value: unknown, label: string): Record<string, unknown> {
  check(value !== null && typeof value === "object" && !Array.isArray(value), `${label} must be an object.`);
  return value as Record<string, unknown>;
}
function text(value: unknown, label: string, limit = 256): string {
  check(typeof value === "string" && value.length > 0 && value.length <= limit &&
    value.trim() === value && !/[\u0000-\u001f\u007f]/u.test(value), `${label} is missing or invalid.`);
  return value;
}
function identifier(value: unknown, label: string): string {
  const id = text(value, label);
  check(!id.includes("/") && id !== "." && id !== "..", `${label} must be a single identifier.`);
  return id;
}
function timestamp(value: unknown, label: string): SourceTimestamp {
  const t = object(value, label);
  check(Number.isSafeInteger(t.seconds) && (t.seconds as number) >= -62135596800 &&
    (t.seconds as number) <= 253402300799 && Number.isInteger(t.nanoseconds) &&
    (t.nanoseconds as number) >= 0 && (t.nanoseconds as number) < 1000000000, `${label} must be a resolved timestamp.`);
  return {seconds: t.seconds as number, nanoseconds: t.nanoseconds as number};
}
function money(value: unknown, label: string): bigint {
  check(typeof value === "string" || (typeof value === "number" && Number.isFinite(value)), `${label} must be exact money.`);
  const units = parseUnits(String(value), 3);
  if (typeof value === "number") equal(decimalNumber(units), value, `${label} numeric round trip`);
  return units;
}
function monetaryPolicy(value: unknown, companyId: string, bookId: string): SettlementMonetaryPolicy {
  const p = object(value, "policy");
  equal(p.companyId, companyId, "Policy company");
  equal(p.bookId, bookId, "Policy book");
  equal(p.moneyScale, 3, "Supported cash-source scale");
  const currency = text(p.currency, "policy.currency", 3);
  check(/^[A-Z]{3}$/.test(currency), "Explicit functional currency required.");
  return {
    companyId, bookId, currency, moneyScale: 3,
    revisionId: identifier(p.revisionId, "policy.revisionId"),
    ...(p.legacyCurrencyBindingId === undefined ? {} : {
      legacyCurrencyBindingId: identifier(p.legacyCurrencyBindingId, "legacyCurrencyBindingId"),
    }),
  };
}
function checkCurrency(data: Record<string, unknown>, policy: SettlementMonetaryPolicy): void {
  if (data.currency === undefined) {
    check(policy.legacyCurrencyBindingId !== undefined, "Unverified legacy source currency; explicit binding required.");
  } else equal(data.currency, policy.currency, "Source currency");
  if (data.moneyScale !== undefined) equal(data.moneyScale, policy.moneyScale, "Source monetary scale");
}
function sourceProvenance(data: Record<string, unknown>): Provenance {
  equal(data.settlementMetadataVersion, 1, "Supported source metadata version");
  equal(data.postingSource, "recordCashSettlement", "Trusted source writer");
  equal(data.paymentMethod, "cash", "Source payment method");
  const actor = (prefix: string): SourceActor => {
    equal(data[`${prefix}Role`], "admin", `${prefix} role`);
    return {uid: identifier(data[`${prefix}Uid`], `${prefix}Uid`),
      name: text(data[`${prefix}Name`], `${prefix}Name`, 512), role: "admin"};
  };
  const createdBy = actor("createdBy"), sourceCreatedBy = actor("sourceCreatedBy"), postedBy = actor("postedBy");
  same(createdBy, sourceCreatedBy, "Source initiator");
  same(createdBy, postedBy, "Synchronous settlement poster");
  const createdAt = timestamp(data.createdAt, "createdAt"), postedAt = timestamp(data.postedAt, "postedAt");
  same(createdAt, postedAt, "Source commit timestamps");
  for (const field of ["sellerId", "sellerName", "collectorUid", "collectorName"]) equal(data[field], "", field);
  for (const field of ["sellerIdentityStatus", "collectorIdentityStatus"]) equal(data[field], "not_applicable", field);
  return {
    settlementMetadataVersion: 1, postingSource: "recordCashSettlement", paymentMethod: "cash",
    createdBy, sourceCreatedBy, postedBy, createdAt, postedAt,
    sellerId: "", sellerName: "", sellerIdentityStatus: "not_applicable",
    collectorUid: "", collectorName: "", collectorIdentityStatus: "not_applicable",
  };
}
function cashMapping(
  value: unknown, companyId: string, bookId: string, policy: SettlementMonetaryPolicy,
): SettlementCashMapping {
  const m = object(value, "mapping");
  equal(m.companyId, companyId, "Mapping company");
  equal(m.bookId, bookId, "Mapping book");
  equal(m.currency, policy.currency, "Mapping currency");
  equal(m.moneyScale, policy.moneyScale, "Mapping monetary scale");
  equal(m.accountType, "asset", "Cash account classification");
  equal(m.control, "cash", "Cash account control");
  for (const flag of ["active", "postingAllowed", "requiresTreasuryDimension"]) equal(m[flag], true, flag);
  check(m.holderType === "company" || m.holderType === "representative", "Unsupported holder type.");
  return {
    companyId, bookId, currency: policy.currency, moneyScale: 3,
    mappingRevisionId: identifier(m.mappingRevisionId, "mappingRevisionId"),
    accountId: identifier(m.accountId, "accountId"), accountRevisionId: identifier(m.accountRevisionId, "accountRevisionId"),
    accountType: "asset", control: "cash", active: true, postingAllowed: true, requiresTreasuryDimension: true,
    ledgerAccountKey: text(m.ledgerAccountKey, "ledgerAccountKey"),
    treasuryAccountId: identifier(m.treasuryAccountId, "treasuryAccountId"), holderType: m.holderType,
    holderUid: identifier(m.holderUid, "holderUid"),
  };
}
// Canonicalize only bounded JSON data; never hash arbitrary raw snapshots.
function canonical(value: unknown): string {
  let nodes = 0;
  const normalize = (v: unknown, depth: number): unknown => {
    check(++nodes <= 2048 && depth <= 12, "Journal intent exceeds structural limits.");
    if (v === null || typeof v === "boolean") return v;
    if (typeof v === "string") { check(v.length <= 2048, "Journal intent string is too long."); return v; }
    if (typeof v === "number") { check(Number.isSafeInteger(v), "Unsafe journal intent number."); return v; }
    if (Array.isArray(v)) { check(v.length <= 16, "Journal intent array is too long."); return v.map((item) => normalize(item, depth + 1)); }
    const obj = object(v, "journal intent value");
    check(Object.getPrototypeOf(obj) === Object.prototype || Object.getPrototypeOf(obj) === null, "Journal intent must contain plain JSON data.");
    const keys = Object.keys(obj).sort();
    check(keys.length <= 64 && keys.every((key) => key.length <= 128), "Journal intent object is too large.");
    return Object.fromEntries(keys.map((key) => [key, normalize(obj[key], depth + 1)]));
  };
  const result = JSON.stringify(normalize(value, 0));
  check(Buffer.byteLength(result, "utf8") <= 65536, "Journal intent exceeds 64 KiB.");
  return result;
}
function same(actual: unknown, expected: unknown, label: string): void {
  equal(canonical(actual), canonical(expected), label);
}
function hash(value: unknown): string { return createHash("sha256").update(canonical(value)).digest("hex"); }
function freeze<T>(value: T): T {
  if (value !== null && typeof value === "object") {
    for (const child of Object.values(value)) freeze(child);
    Object.freeze(value);
  }
  return value;
}
