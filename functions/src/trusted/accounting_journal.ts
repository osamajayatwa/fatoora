import {HttpsError} from "firebase-functions/v2/https";
import {ACCOUNTING_CONTROL_TYPES, configurationDate, configurationDigest, configurationId, configurationRecord, ConfigurationAccount} from "./accounting_configuration_contract";
import {MAX_DECIMAL_UNITS, sumUnits} from "./exact_decimal";

export interface JournalAccount extends ConfigurationAccount {
  companyId: string; bookId: string; revisionId: string; currency: string; moneyScale: number;
}
export interface AccountingJournalLine {
  id: string; account: JournalAccount; debitUnits: string; creditUnits: string;
  dimensions: Partial<Record<"treasuryAccountId" | "holderType" | "holderUid" | "customerId" | "payableId" | "sellerId" | "collectorUid", string>>;
}
export interface AccountingJournal {
  schemaVersion: 1; companyId: string; bookId: string; currency: string; moneyScale: number;
  accountingDate: string; periodId: string; journalDefinitionId: string; journalDefinitionRevisionId: string; configurationDigest: string;
  source: {system: "fatoora"; type: string; id: string; revision: string; action: string};
  lines: AccountingJournalLine[]; debitUnits: string; creditUnits: string;
}

export function accountingNeed(condition: unknown, message: string, code: "invalid-argument" | "failed-precondition" | "data-loss" = "failed-precondition"): asserts condition {
  if (!condition) throw new HttpsError(code, message);
}
export function accountingUnits(value: unknown): bigint {
  accountingNeed(typeof value === "string" && /^(0|[1-9][0-9]{0,29})$/.test(value), "Canonical nonnegative integer-unit strings are required.", "invalid-argument");
  const units = BigInt(value);accountingNeed(units <= MAX_DECIMAL_UNITS, "Accounting units exceed the supported range.", "invalid-argument");return units;
}

/** Financial evidence has only explicit exact units and bounded integer metadata. */
export function accountingCanonical(value: unknown): string {
  let nodes = 0;
  function normalize(v: unknown, depth: number): unknown {
    accountingNeed(++nodes <= 20000 && depth <= 20, "Accounting evidence exceeds its structural budget.", "invalid-argument");
    if (v === null || typeof v === "boolean") return v;
    if (typeof v === "string") {accountingNeed(v.length <= 65536, "Accounting evidence string is too large.", "invalid-argument");return v;}
    if (typeof v === "number") {accountingNeed(Number.isSafeInteger(v) && !Object.is(v, -0), "Only exact bounded integer metadata is allowed.", "invalid-argument");return v;}
    if (Array.isArray(v)) return v.map(x => normalize(x, depth + 1));
    accountingNeed(v && typeof v === "object" && Object.getPrototypeOf(v) === Object.prototype, "Plain resolved accounting evidence is required.", "invalid-argument");
    return Object.fromEntries(Object.keys(v).sort().map(k => [k, normalize((v as Record<string, unknown>)[k], depth + 1)]));
  }
  const encoded = JSON.stringify(normalize(value, 0));
  accountingNeed(Buffer.byteLength(encoded, "utf8") <= 512 * 1024, "Accounting document exceeds the application byte budget.", "invalid-argument");
  return encoded;
}
export function accountingDigest(value: unknown): string {return configurationDigest(JSON.parse(accountingCanonical(value)));}
export function accountingSame(actual: unknown, expected: unknown, label: string): void {
  accountingNeed(accountingCanonical(actual) === accountingCanonical(expected), `${label} is inconsistent.`, "data-loss");
}
export function accountingHash(value: unknown): string {
  accountingNeed(typeof value === "string" && /^[a-f0-9]{64}$/.test(value), "A valid accounting digest is required.", "invalid-argument");return value;
}

/** Internal intent validator. Public commands never accept account lines. */
export function validateAccountingJournal(input: AccountingJournal): AccountingJournal {
  const j = configurationRecord(input, "journal", ["schemaVersion", "companyId", "bookId", "currency", "moneyScale", "accountingDate", "periodId", "journalDefinitionId", "journalDefinitionRevisionId", "configurationDigest", "source", "lines", "debitUnits", "creditUnits"]);
  accountingNeed(j.schemaVersion === 1, "Unsupported journal schema.", "invalid-argument");
  const companyId = configurationId(j.companyId, "companyId"), bookId = configurationId(j.bookId, "bookId");
  accountingNeed(typeof j.currency === "string" && /^[A-Z]{3}$/.test(j.currency) && Number.isSafeInteger(j.moneyScale) && (j.moneyScale as number) >= 0 && (j.moneyScale as number) <= 6, "Explicit currency and scale are required.", "invalid-argument");
  configurationDate(j.accountingDate, "accountingDate");configurationId(j.periodId, "periodId");configurationId(j.journalDefinitionId, "journalDefinitionId");accountingHash(j.configurationDigest);
  configurationId(j.journalDefinitionRevisionId, "journalDefinitionRevisionId");
  const source = configurationRecord(j.source, "source", ["system", "type", "id", "revision", "action"]);
  accountingNeed(source.system === "fatoora", "Unsupported source system.", "invalid-argument");
  for (const key of ["type", "id", "revision", "action"]) configurationId(source[key], `source.${key}`);
  accountingNeed(Array.isArray(j.lines) && j.lines.length >= 2 && j.lines.length <= 256, "A journal requires 2 to 256 complete lines.", "invalid-argument");
  const seen = new Set<string>();
  for (const line of j.lines as AccountingJournalLine[]) {
    configurationRecord(line, "line", ["id", "account", "debitUnits", "creditUnits", "dimensions"]);
    configurationId(line.id, "line.id");accountingNeed(!seen.has(line.id), "Duplicate journal line identity.", "invalid-argument");seen.add(line.id);
    const debit = accountingUnits(line.debitUnits), credit = accountingUnits(line.creditUnits);
    accountingNeed((debit > 0n) !== (credit > 0n), "Each line requires exactly one positive side.", "invalid-argument");
    const a = line.account;
    configurationRecord(a, "account", ["id", "code", "name", "parentId", "accountType", "normalSide", "control", "postingAllowed", "active", "companyId", "bookId", "revisionId", "currency", "moneyScale"]);
    configurationId(a.id, "account.id");configurationId(a.revisionId, "account.revisionId");
    if (a.parentId !== null) configurationId(a.parentId, "account.parentId");
    accountingNeed(a.companyId === companyId && a.bookId === bookId && a.currency === j.currency && a.moneyScale === j.moneyScale && a.active === true && a.postingAllowed === true, "Journal account scope, currency or activity is invalid.", "invalid-argument");
    accountingNeed(typeof a.code === "string" && /^[A-Z0-9][A-Z0-9.-]{0,31}$/.test(a.code) && typeof a.name === "string" && a.name.trim().length > 0 && a.name.length <= 200 && ["asset", "liability", "equity", "income", "expense"].includes(a.accountType) && ["debit", "credit"].includes(a.normalSide), "A complete account snapshot is required.", "invalid-argument");
    const dims = configurationRecord(line.dimensions, "dimensions", ["treasuryAccountId", "holderType", "holderUid", "customerId", "payableId", "sellerId", "collectorUid"]);
    for (const [key, value] of Object.entries(dims)) configurationId(value, `dimensions.${key}`);
    accountingNeed(["none", "cash", "clearing", "receivable", "payable", "customer_credit", "tax"].includes(a.control), "Unknown account control.", "invalid-argument");
    accountingNeed(a.control === "none" || ACCOUNTING_CONTROL_TYPES[a.control].includes(a.accountType), "Account control/type is inconsistent.", "invalid-argument");
    if (a.control === "cash" || a.control === "clearing") accountingNeed(dims.treasuryAccountId && dims.holderUid && ["company", "representative"].includes(dims.holderType as string), "Treasury control requires an explicit account and holder.", "invalid-argument");
    if (a.control === "receivable" || a.control === "customer_credit") accountingNeed(dims.customerId, "Customer control requires a customer dimension.", "invalid-argument");
    if (a.control === "payable") accountingNeed(dims.payableId, "Payable control requires a payable reference.", "invalid-argument");
  }
  const debits = sumUnits((j.lines as AccountingJournalLine[]).map(l => accountingUnits(l.debitUnits)));
  const credits = sumUnits((j.lines as AccountingJournalLine[]).map(l => accountingUnits(l.creditUnits)));
  accountingNeed(debits > 0n && debits === credits && accountingUnits(j.debitUnits) === debits && accountingUnits(j.creditUnits) === credits, "Journal debit and credit totals must balance exactly.", "invalid-argument");
  return JSON.parse(accountingCanonical(input)) as AccountingJournal;
}

export function accountingEventId(companyId: string, bookId: string, source: AccountingJournal["source"]): string {
  return `event_${accountingDigest([1, companyId, bookId, source.system, source.type, source.id, source.action])}`;
}

export interface AccountingTime {seconds: number; nanoseconds: number}
export function accountingTime(value: unknown): AccountingTime {
  const t = configurationRecord(value, "businessTime", ["seconds", "nanoseconds"]);
  accountingNeed(Number.isSafeInteger(t.seconds) && (t.seconds as number) >= -2208988800 && (t.seconds as number) < 7258118400 && Number.isInteger(t.nanoseconds) && (t.nanoseconds as number) >= 0 && (t.nanoseconds as number) < 1000000000 && (t.nanoseconds as number) % 1000 === 0, "Exact microsecond business time is required.", "invalid-argument");
  return {seconds: t.seconds as number, nanoseconds: t.nanoseconds as number};
}
export function accountingLocalDate(value: AccountingTime): string {
  const t = accountingTime(value), date = new Date(t.seconds * 1000 + Math.floor(t.nanoseconds / 1000000));
  const parts = new Intl.DateTimeFormat("en", {timeZone: "Asia/Amman", year: "numeric", month: "2-digit", day: "2-digit"}).formatToParts(date);
  return configurationDate(["year", "month", "day"].map(k => parts.find(p => p.type === k)!.value).join("-"), "accountingDate");
}
