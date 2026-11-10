import {createHash} from "node:crypto";
import {HttpsError} from "firebase-functions/v2/https";
import {parseUnits} from "./exact_decimal";

export const ACCOUNTING_MAPPING_ROLES = {
  companyCash: ["asset", "cash"], representativeCash: ["asset", "cash"],
  receivables: ["asset", "receivable"], sales: ["income", "none"],
  salesReturns: ["income", "none"], operatingExpense: ["expense", "none"],
  representativePayable: ["liability", "payable"], customerCredits: ["liability", "customer_credit"],
  outputTax: ["liability", "tax"], bankClearing: ["asset", "clearing"],
} as const;
export type MappingRole = keyof typeof ACCOUNTING_MAPPING_ROLES;
export const ACCOUNTING_CONTROL_TYPES: Readonly<Record<string, readonly string[]>> = {
  cash: ["asset"], receivable: ["asset"], payable: ["liability"], customer_credit: ["liability"],
  tax: ["asset", "liability"], clearing: ["asset", "liability"],
};
export interface ConfigurationAccount {
  id: string; code: string; name: string; parentId: string | null;
  accountType: "asset" | "liability" | "equity" | "income" | "expense";
  normalSide: "debit" | "credit"; control: "none" | "cash" | "receivable" | "payable" | "customer_credit" | "tax" | "clearing";
  postingAllowed: boolean; active: boolean;
}
export interface ConfigurationPeriod {id: string; name: string; startsOn: string; endsBefore: string}
export interface ConfigurationTaxCode {code: string; ratePercent: string; startsOn: string; endsBefore: string; outputAccountId: string}
export interface AccountingConfiguration {
  schemaVersion: 1; name: string; currency: string; moneyScale: number; quantityScale: number; priceScale: number;
  timezone: "Asia/Amman"; fiscalYearStartMonth: number; fiscalYearStartDay: number;
  inventoryMode: "quantity_only"; costCoverage: "not_recorded";
  accounts: ConfigurationAccount[]; periods: ConfigurationPeriod[];
  mappings: Partial<Record<MappingRole, string>>; taxCodes: ConfigurationTaxCode[];
  taxPolicy: {status: "unconfirmed" | "documented"; priceBasis: "inclusive" | "exclusive" | null; evidenceRef: string | null};
  openingBoundary: {cutoverDate: string | null; financialCoverage: "unknown" | "documented";
    quantityCoverage: "unknown" | "documented"; evidenceRefs: string[]; retainedEarningsTreatment: string | null};
}
export interface ConfigurationReadiness {
  configurationComplete: boolean; postingEnabled: false; approvalStatus: "unreviewed";
  missing: string[]; activationBlockers: string[];
}

export function configurationError(field: string, reason: string): never {
  throw new HttpsError("invalid-argument", `Invalid accounting configuration: ${field} (${reason}).`, {field, reason});
}
export function configurationId(value: unknown, field: string): string {
  if (typeof value !== "string" || !/^[A-Za-z0-9][A-Za-z0-9_-]{0,95}$/.test(value)) configurationError(field, "invalid_identifier");
  return value;
}
export function configurationRecord(value: unknown, field: string, keys: readonly string[]): Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value)) configurationError(field, "object_required");
  const record = value as Record<string, unknown>;
  if (Object.keys(record).some(k => !keys.includes(k))) configurationError(field, "unknown_field");
  return record;
}
function text(value: unknown, field: string, max = 200): string {
  if (typeof value !== "string" || !value.trim() || value.trim() !== value || value.length > max || /[\u0000-\u001f\u007f]/u.test(value)) configurationError(field, "text_required");
  return value;
}
function nullableText(value: unknown, field: string, max = 500): string | null {return value === null ? null : text(value, field, max);}
function integer(value: unknown, field: string, min: number, max: number): number {
  if (typeof value !== "number" || !Number.isSafeInteger(value) || value < min || value > max) configurationError(field, "integer_out_of_range");
  return value;
}
function choice<T extends string>(value: unknown, field: string, choices: readonly T[]): T {
  if (typeof value !== "string" || !choices.includes(value as T)) configurationError(field, "unsupported_value");
  return value as T;
}
function boolean(value: unknown, field: string): boolean {if (typeof value !== "boolean") configurationError(field, "boolean_required");return value;}
function list(value: unknown, field: string, max: number): unknown[] {
  if (!Array.isArray(value) || value.length > max) configurationError(field, "array_limit");return value;
}
export function configurationDate(value: unknown, field: string): string {
  if (typeof value !== "string" || !/^\d{4}-\d{2}-\d{2}$/.test(value) || value < "1900-01-01" || value > "2199-12-31") configurationError(field, "invalid_date");
  const parsed = new Date(`${value}T00:00:00Z`);
  if (!Number.isFinite(parsed.getTime()) || parsed.toISOString().slice(0, 10) !== value) configurationError(field, "invalid_date");
  return value;
}
function unique(values: string[], field: string): void {if (new Set(values).size !== values.length) configurationError(field, "duplicate");}
function compareText(a: string, b: string): number {return a < b ? -1 : a > b ? 1 : 0;}
function interval(start: string, end: string, field: string): void {if (start >= end) configurationError(field, "empty_or_reversed_range");}

/** A draft contract, with no inferred currency, tax, opening balances or approval. */
export function validateAccountingConfiguration(input: unknown): AccountingConfiguration {
  let bytes: number;
  try {bytes = Buffer.byteLength(JSON.stringify(input), "utf8");} catch {configurationError("configuration", "invalid_json");}
  if (bytes! > 192 * 1024) configurationError("configuration", "payload_limit");
  const d = configurationRecord(input, "configuration", ["schemaVersion", "name", "currency", "moneyScale", "quantityScale", "priceScale", "timezone",
    "fiscalYearStartMonth", "fiscalYearStartDay", "inventoryMode", "costCoverage", "accounts", "periods", "mappings", "taxCodes", "taxPolicy", "openingBoundary"]);
  if (d.schemaVersion !== 1) configurationError("schemaVersion", "unsupported_value");
  const currency = text(d.currency, "currency", 3);
  if (!/^[A-Z]{3}$/.test(currency)) configurationError("currency", "explicit_currency_required");
  const fiscalYearStartMonth = integer(d.fiscalYearStartMonth, "fiscalYearStartMonth", 1, 12);
  const fiscalYearStartDay = integer(d.fiscalYearStartDay, "fiscalYearStartDay", 1, 31);
  configurationDate(`2001-${String(fiscalYearStartMonth).padStart(2, "0")}-${String(fiscalYearStartDay).padStart(2, "0")}`, "fiscalYearStartDay");
  const accounts = list(d.accounts, "accounts", 80).map((v, i): ConfigurationAccount => {
    const f = `accounts.${i}`, a = configurationRecord(v, f, ["id", "code", "name", "parentId", "accountType", "normalSide", "control", "postingAllowed", "active"]);
    const code = text(a.code, `${f}.code`, 32).toUpperCase();
    if (!/^[A-Z0-9][A-Z0-9.-]*$/.test(code)) configurationError(`${f}.code`, "invalid_code");
    const result: ConfigurationAccount = {id: configurationId(a.id, `${f}.id`), code, name: text(a.name, `${f}.name`),
      parentId: a.parentId === null ? null : configurationId(a.parentId, `${f}.parentId`),
      accountType: choice(a.accountType, `${f}.accountType`, ["asset", "liability", "equity", "income", "expense"]),
      normalSide: choice(a.normalSide, `${f}.normalSide`, ["debit", "credit"]),
      control: choice(a.control, `${f}.control`, ["none", "cash", "receivable", "payable", "customer_credit", "tax", "clearing"]),
      postingAllowed: boolean(a.postingAllowed, `${f}.postingAllowed`), active: boolean(a.active, `${f}.active`)};
    if (!result.postingAllowed && result.control !== "none") configurationError(f, "group_control_account");
    if (result.control !== "none" && !ACCOUNTING_CONTROL_TYPES[result.control].includes(result.accountType)) configurationError(f, "invalid_control_type");
    return result;
  });
  unique(accounts.map(a => a.id), "accounts.id");unique(accounts.map(a => a.code), "accounts.code");
  const byId = new Map(accounts.map(a => [a.id, a]));
  for (const a of accounts) {
    const seen = new Set([a.id]);let parent = a.parentId;
    while (parent !== null) {
      if (seen.has(parent)) configurationError("accounts.parentId", "cycle");seen.add(parent);
      const p = byId.get(parent);
      if (!p || p.postingAllowed || p.accountType !== a.accountType || a.active && !p.active) configurationError("accounts.parentId", "invalid_parent");
      parent = p.parentId;
    }
  }
  const periods = list(d.periods, "periods", 36).map((v, i): ConfigurationPeriod => {
    const f = `periods.${i}`, p = configurationRecord(v, f, ["id", "name", "startsOn", "endsBefore"]);
    const result = {id: configurationId(p.id, `${f}.id`), name: text(p.name, `${f}.name`), startsOn: configurationDate(p.startsOn, `${f}.startsOn`), endsBefore: configurationDate(p.endsBefore, `${f}.endsBefore`)};
    interval(result.startsOn, result.endsBefore, f);
    const anniversary = `${String(fiscalYearStartMonth).padStart(2, "0")}-${String(fiscalYearStartDay).padStart(2, "0")}`;
    const nextFiscalYear = Number(result.startsOn.slice(0, 4)) + (result.startsOn.slice(5) >= anniversary ? 1 : 0);
    if (result.endsBefore > `${nextFiscalYear}-${anniversary}`) configurationError(f, "crosses_fiscal_year");
    return result;
  }).sort((a, b) => compareText(a.startsOn, b.startsOn) || compareText(a.id, b.id));
  unique(periods.map(p => p.id), "periods.id");
  for (let i = 1; i < periods.length; i++) if (periods[i].startsOn < periods[i - 1].endsBefore) configurationError("periods", "overlap");
  const mappings: AccountingConfiguration["mappings"] = {};
  const suppliedMappings = configurationRecord(d.mappings, "mappings", Object.keys(ACCOUNTING_MAPPING_ROLES));
  for (const role of Object.keys(suppliedMappings) as MappingRole[]) {
    const target = configurationId(suppliedMappings[role], `mappings.${role}`), a = byId.get(target), [type, control] = ACCOUNTING_MAPPING_ROLES[role];
    if (!a || !a.active || !a.postingAllowed || a.accountType !== type || a.control !== control) configurationError(`mappings.${role}`, "invalid_posting_account");
    mappings[role] = target;
  }
  if (mappings.companyCash && mappings.companyCash === mappings.representativeCash) configurationError("mappings", "cash_accounts_must_be_distinct");
  const taxCodes = list(d.taxCodes, "taxCodes", 80).map((v, i): ConfigurationTaxCode => {
    const f = `taxCodes.${i}`, t = configurationRecord(v, f, ["code", "ratePercent", "startsOn", "endsBefore", "outputAccountId"]);
    const rate = text(t.ratePercent, `${f}.ratePercent`, 12);
    if (!/^(0|[1-9][0-9]*)(\.[0-9]{1,6})?$/.test(rate)) configurationError(`${f}.ratePercent`, "exact_decimal_required");
    const units = parseUnits(rate, 6);
    if (units < 0n || units > 100000000n) configurationError(`${f}.ratePercent`, "rate_out_of_range");
    const code = text(t.code, `${f}.code`, 32).toUpperCase();
    if (!/^[A-Z0-9][A-Z0-9_-]*$/.test(code)) configurationError(`${f}.code`, "invalid_code");
    const outputAccountId = configurationId(t.outputAccountId, `${f}.outputAccountId`), a = byId.get(outputAccountId);
    if (!a || !a.active || !a.postingAllowed || a.accountType !== "liability" || a.control !== "tax") configurationError(`${f}.outputAccountId`, "invalid_tax_account");
    const result = {code, ratePercent: rate, startsOn: configurationDate(t.startsOn, `${f}.startsOn`), endsBefore: configurationDate(t.endsBefore, `${f}.endsBefore`), outputAccountId};
    interval(result.startsOn, result.endsBefore, f);return result;
  }).sort((a, b) => compareText(a.code, b.code) || compareText(a.startsOn, b.startsOn));
  for (let i = 1; i < taxCodes.length; i++) if (taxCodes[i].code === taxCodes[i - 1].code && taxCodes[i].startsOn < taxCodes[i - 1].endsBefore) configurationError("taxCodes", "overlap");
  const t = configurationRecord(d.taxPolicy, "taxPolicy", ["status", "priceBasis", "evidenceRef"]);
  const taxPolicy: AccountingConfiguration["taxPolicy"] = {status: choice(t.status, "taxPolicy.status", ["unconfirmed", "documented"]),
    priceBasis: t.priceBasis === null ? null : choice(t.priceBasis, "taxPolicy.priceBasis", ["inclusive", "exclusive"] as const), evidenceRef: nullableText(t.evidenceRef, "taxPolicy.evidenceRef")};
  if (taxPolicy.status === "documented" && (!taxPolicy.evidenceRef || !taxPolicy.priceBasis)) configurationError("taxPolicy", "evidence_required");
  const o = configurationRecord(d.openingBoundary, "openingBoundary", ["cutoverDate", "financialCoverage", "quantityCoverage", "evidenceRefs", "retainedEarningsTreatment"]);
  const openingBoundary: AccountingConfiguration["openingBoundary"] = {cutoverDate: o.cutoverDate === null ? null : configurationDate(o.cutoverDate, "openingBoundary.cutoverDate"),
    financialCoverage: choice(o.financialCoverage, "openingBoundary.financialCoverage", ["unknown", "documented"]),
    quantityCoverage: choice(o.quantityCoverage, "openingBoundary.quantityCoverage", ["unknown", "documented"]),
    evidenceRefs: list(o.evidenceRefs, "openingBoundary.evidenceRefs", 20).map(v => text(v, "openingBoundary.evidenceRefs", 500)),
    retainedEarningsTreatment: nullableText(o.retainedEarningsTreatment, "openingBoundary.retainedEarningsTreatment")};
  unique(openingBoundary.evidenceRefs, "openingBoundary.evidenceRefs");
  if ([openingBoundary.financialCoverage, openingBoundary.quantityCoverage].includes("documented") && (!openingBoundary.cutoverDate || !openingBoundary.evidenceRefs.length)) configurationError("openingBoundary", "evidence_required");
  return {schemaVersion: 1, name: text(d.name, "name"), currency, moneyScale: integer(d.moneyScale, "moneyScale", 0, 6),
    quantityScale: integer(d.quantityScale, "quantityScale", 0, 6), priceScale: integer(d.priceScale, "priceScale", 0, 6),
    timezone: choice(d.timezone, "timezone", ["Asia/Amman"]), fiscalYearStartMonth, fiscalYearStartDay,
    inventoryMode: choice(d.inventoryMode, "inventoryMode", ["quantity_only"]), costCoverage: choice(d.costCoverage, "costCoverage", ["not_recorded"]),
    accounts: accounts.sort((a, b) => compareText(a.id, b.id)), periods, mappings, taxCodes, taxPolicy, openingBoundary};
}

export function accountingConfigurationReadiness(c: AccountingConfiguration): ConfigurationReadiness {
  const missing: string[] = [];
  for (const role of Object.keys(ACCOUNTING_MAPPING_ROLES) as MappingRole[]) if (role !== "bankClearing" && !c.mappings[role]) missing.push(`mapping_${role}`);
  if (!c.accounts.some(a => a.active && a.postingAllowed && a.accountType === "equity")) missing.push("equity_account");
  if (!c.periods.length) missing.push("accounting_periods");
  if (c.taxPolicy.status !== "documented") missing.push("tax_policy_evidence");
  if (!c.openingBoundary.cutoverDate) missing.push("opening_cutover_date");
  else if (!c.periods.some(p => p.startsOn <= c.openingBoundary.cutoverDate! && c.openingBoundary.cutoverDate! < p.endsBefore)) missing.push("opening_period_coverage");
  if (c.openingBoundary.financialCoverage !== "documented") missing.push("financial_opening_evidence");
  if (c.openingBoundary.quantityCoverage !== "documented") missing.push("quantity_opening_evidence");
  if (!c.openingBoundary.retainedEarningsTreatment) missing.push("retained_earnings_treatment");
  return {configurationComplete: missing.length === 0, postingEnabled: false, approvalStatus: "unreviewed", missing,
    activationBlockers: ["accountant_owner_confirmation", "opening_reconciliation", "posting_engine_acceptance"]};
}

/** Sorted keys make equivalent requests independent of JSON object insertion order. */
export function configurationDigest(value: unknown): string {
  const canonical = (v: unknown): unknown => Array.isArray(v) ? v.map(canonical) : v && typeof v === "object" ?
    Object.fromEntries(Object.entries(v).sort(([a], [b]) => compareText(a, b)).map(([k, x]) => [k, canonical(x)])) : v;
  return createHash("sha256").update(JSON.stringify(canonical(value))).digest("hex");
}
