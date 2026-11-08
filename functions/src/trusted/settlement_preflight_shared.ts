import {DocumentData, DocumentSnapshot, Firestore, Transaction} from "firebase-admin/firestore";
import {HttpsError} from "firebase-functions/v2/https";
import {decimalNumber, parseUnits, sumUnits} from "./exact_decimal";
import {cashBalanceDocumentId} from "./cash_ledger";
import {companyCashAccount, repCashAccount} from "./financial_ledger";
import {SettlementCashMapping, SettlementMonetaryPolicy} from "./settlement_journal_intent";

export interface Time {seconds: number; nanoseconds: number}
export interface Position {
  path: string; amountUnits: string; lastMovementId: string;
  updatedAt: Time; headRecordedAt: Time; headCommittedAt: Time;
}
export interface Context {
  bookRevisionId: string; policyRevisionId: string; mappingRevisionId: string;
  legacyCurrencyBindingRevisionId: string | null;
  period: {id: string; revisionId: string; startsAt: Time; endsAt: Time};
}
export type Read = (paths: string[]) => Promise<DocumentSnapshot[]>;
export function settlementReader(transaction: Transaction, firestore: Firestore): {read: Read; snapshots: Map<string, DocumentSnapshot>} {
  const snapshots = new Map<string, DocumentSnapshot>();
  const read: Read = async paths => {
    const missing = [...new Set(paths)].filter(p => !snapshots.has(p));
    need(snapshots.size + missing.length <= 24, "Preflight read budget exceeded.");
    if (missing.length) for (const s of await transaction.getAll(...missing.map(p => firestore.doc(p)))) snapshots.set(s.ref.path, s);
    return paths.map(p => snapshots.get(p)!);
  };
  return {read, snapshots};
}
export interface BookEvidence {
  companyId: string; bookId: string; c: string; b: string;
  companySnapshot: DocumentSnapshot; mapping: DocumentData;
  policy: SettlementMonetaryPolicy; context: Context;
}
export async function readSettlementBook(read: Read, companyId: string, expectedBookId?: string): Promise<BookEvidence> {
  const c = `companies/${companyId}`, [companySnapshot] = await read([c]), company = required(companySnapshot);
  eq(company.id, companyId, "Company identity");
  if (company.companyId !== undefined) eq(company.companyId, companyId, "Company scope metadata");
  eq(company.active, true, "Active company");
  const bookId = id(company.activeBookId, "activeBookId"), b = `${c}/books/${bookId}`;
  if (expectedBookId !== undefined) eq(expectedBookId, bookId, "Expected book");
  const [bookSnapshot] = await read([b]), book = configured(bookSnapshot, companyId);
  if (book.bookId !== undefined) eq(book.bookId, bookId, "Book scope metadata");
  eq(book.active, true, "Active book"); eq(book.mode, "configuration", "Supported preflight-only book mode");
  eq(book.settlementPreflightEnabled, true, "Settlement preflight gate");
  eq(book.journalPostingEnabled, false, "Journal persistence must remain disabled");
  const policyId = id(book.policyRevisionId, "policyRevisionId"), mappingId = id(book.settlementMappingRevisionId, "mappingRevisionId");
  const periodId = id(book.settlementPeriodId, "settlementPeriodId");
  const [p, m, periodSnapshot, lock] = await read([`${b}/policy_revisions/${policyId}`, `${b}/settlement_mappings/${mappingId}`,
    `${b}/periods/${periodId}`, `${c}/maintenance_locks/cash_reconciliation`]);
  const policy = configured(p, companyId, bookId), mapping = configured(m, companyId, bookId), period = configured(periodSnapshot, companyId, bookId);
  eq(policy.revisionId, policyId, "Policy revision"); eq(mapping.revisionId, mappingId, "Mapping revision");
  eq(policy.currency, book.currency, "Book currency"); eq(policy.moneyScale, book.moneyScale, "Book monetary scale");
  eq(policy.moneyScale, 3, "Supported source precision");
  need(typeof policy.currency === "string" && /^[A-Z]{3}$/.test(policy.currency), "Explicit currency required.");
  eq(policy.accountingDateBasis, "settlement_business_date", "Supported accounting date basis");
  eq(period.status, "open", "Open accounting period");
  if (lock.exists) eq(lock.data()?.active, false, "Cash reconciliation lock");
  let bindingRevision: string | null = null;
  if (policy.legacyCurrencyBindingId !== undefined) {
    const bindingId = id(policy.legacyCurrencyBindingId, "legacyCurrencyBindingId");
    const [snapshot] = await read([`${b}/currency_bindings/${bindingId}`]), binding = configured(snapshot, companyId, bookId);
    eq(binding.revisionId, bindingId, "Currency binding revision");
    for (const [field, expected] of Object.entries({sourceCollection: "settlements", postingSource: "recordCashSettlement",
      settlementMetadataVersion: 1, currency: policy.currency, moneyScale: 3})) eq(binding[field], expected, `Binding ${field}`);
    bindingRevision = bindingId;
  }
  return {companyId, bookId, c, b, companySnapshot, mapping,
    policy: {companyId, bookId, revisionId: policyId, currency: policy.currency, moneyScale: 3,
      ...(bindingRevision === null ? {} : {legacyCurrencyBindingId: bindingRevision})},
    context: {bookRevisionId: book.revisionId, policyRevisionId: policyId, mappingRevisionId: mappingId,
      legacyCurrencyBindingRevisionId: bindingRevision,
      period: {id: periodId, revisionId: period.revisionId, startsAt: time(period.startsAt), endsAt: time(period.endsAt)}}};
}
export async function readSettlementMappings(read: Read, book: BookEvidence, rep: string): Promise<{mappings: SettlementCashMapping[]; representative: DocumentData}> {
  const {companyId, bookId, b, mapping, policy} = book;
  const [repSnapshot] = await read([`users/${rep}`]), representative = required(repSnapshot);
  if (representative.uid !== undefined) eq(representative.uid, rep, "Representative profile identity");
  eq(representative.companyId, companyId, "Representative company"); eq(representative.role, "sales_rep", "Representative role");
  eq(representative.active, true, "Active representative"); eq(representative.approvalStatus, "approved", "Approved representative");
  const roles = [{role: "companyCash", ledgerAccountKey: companyCashAccount().key, treasuryAccountId: "company_cash", holderType: "company" as const, holderUid: companyId},
    {role: "representativeCash", ledgerAccountKey: repCashAccount(rep, "").key, treasuryAccountId: cashBalanceDocumentId("rep_cash", rep), holderType: "representative" as const, holderUid: rep}];
  const accounts = await read(roles.map(r => `${b}/chart_accounts/${id(mapping[`${r.role}AccountId`], `${r.role}AccountId`)}`));
  const mappings = roles.map((role, i): SettlementCashMapping => {
    const a = configured(accounts[i], companyId, bookId);
    eq(a.revisionId, mapping[`${role.role}AccountRevisionId`], "Pinned cash account revision");
    for (const [field, expected] of Object.entries({accountType: "asset", control: "cash", active: true, postingAllowed: true,
      requiresTreasuryDimension: true, currency: policy.currency, moneyScale: 3})) eq(a[field], expected, `Cash account ${field}`);
    return {companyId, bookId, currency: policy.currency, moneyScale: 3, mappingRevisionId: book.context.mappingRevisionId,
      accountId: accounts[i].id, accountRevisionId: a.revisionId, accountType: "asset", control: "cash", active: true,
      postingAllowed: true, requiresTreasuryDimension: true, ledgerAccountKey: role.ledgerAccountKey,
      treasuryAccountId: role.treasuryAccountId, holderType: role.holderType, holderUid: role.holderUid};
  });
  return {mappings, representative};
}
export async function readSettlementPositions(read: Read, book: BookEvidence, rep: string): Promise<{positions: Position[]; legacyCurrency: boolean}> {
  const {c, companyId, policy} = book, positions: Position[] = [];
  const balances = await read([`${c}/cash_balances/${cashBalanceDocumentId("rep_cash", rep)}`, `${c}/cash_balances/company_cash`]);
  let legacyCurrency = false;
  for (const [i, s] of balances.entries()) {
    const balance = required(s), expected = {cashAccount: i === 0 ? "rep_cash" : "company_cash", salesRepId: i === 0 ? rep : "",
      treasuryAccountId: s.id, holderType: i === 0 ? "representative" : "company", holderUid: i === 0 ? rep : companyId};
    eq(balance.id, s.id, "Cash position identity"); eq(balance.companyId, companyId, "Cash position company");
    for (const field of ["cashAccount", "salesRepId"] as const) eq(balance[field], expected[field], `Cash position ${field}`);
    for (const field of ["treasuryAccountId", "holderType", "holderUid"] as const) if (balance[field] !== undefined) eq(balance[field], expected[field], `Cash position ${field}`);
    if (balance.currency !== undefined) eq(balance.currency, policy.currency, "Cash position currency");
    if (balance.moneyScale !== undefined) eq(balance.moneyScale, 3, "Cash position scale");
    const headId = id(balance.lastMovementId, "lastMovementId"), [headSnapshot] = await read([`${c}/cash_movements/${headId}`]), head = required(headSnapshot);
    eq(head.id, headId, "Cash head identity"); eq(head.companyId, companyId, "Cash head company");
    for (const field of ["cashAccount", "salesRepId"] as const) eq(head[field], expected[field], `Cash head ${field}`);
    for (const field of ["treasuryAccountId", "holderType", "holderUid"] as const) if (head[field] !== undefined) eq(head[field], expected[field], `Cash head ${field}`);
    if (head.cashAccountSalesRepId !== undefined) eq(head.cashAccountSalesRepId, expected.salesRepId, "Cash head holder alias");
    if (head.currency !== undefined) eq(head.currency, policy.currency, "Cash head currency");
    if (head.moneyScale !== undefined) eq(head.moneyScale, 3, "Cash head scale");
    legacyCurrency ||= balance.currency === undefined || head.currency === undefined;
    need(head.direction === "in" || head.direction === "out", "Cash head direction unavailable.");
    const amount = money(head.amount), before = money(head.balanceBefore), after = money(head.balanceAfter), position = money(balance.amount);
    need(amount > 0n && before >= 0n && after >= 0n && position >= 0n, "Invalid physical cash position.");
    eq(sumUnits([before, head.direction === "out" ? -amount : amount]), after, "Cash head balance equation");
    eq(position, after, "Stale cash balance projection");
    const updatedAt = time(balance.updatedAt), headRecordedAt = time(head.createdAt), headCommittedAt = time(headSnapshot.createTime);
    eq(compare(time(s.updateTime), headCommittedAt), 0, "Atomic cash position/head commit metadata");
    eq(compare(updatedAt, headRecordedAt), 0, "Cash balance/head recorded timestamp");
    need(compare(headRecordedAt, headCommittedAt) <= 0, "Cash head recorded time exceeds commit time.");
    positions.push({path: s.ref.path, amountUnits: position.toString(), lastMovementId: headId, updatedAt, headRecordedAt, headCommittedAt});
  }
  return {positions, legacyCurrency};
}
export function periodContains(context: Context, date: Time): void {
  const {startsAt, endsAt} = context.period;
  need(compare(startsAt, endsAt) < 0 && compare(date, startsAt) >= 0 && compare(date, endsAt) < 0,
    "Settlement accounting date is outside the configured open period.");
}
export function need(condition: boolean, message: string): asserts condition { if (!condition) throw new HttpsError("failed-precondition", message); }
export function eq(actual: unknown, expected: unknown, label: string, code: "failed-precondition" | "already-exists" = "failed-precondition"): void {
  if (actual !== expected) throw new HttpsError(code, `${label} is inconsistent.`);
}
export function id(value: unknown, label: string): string {
  need(typeof value === "string" && value.length > 0 && value.length <= 256 && value.trim() === value &&
    !/[\\/\u0000-\u001f\u007f]/u.test(value) && value !== "." && value !== "..", `${label} is missing or invalid.`);return value;
}
export function required(snapshot: DocumentSnapshot): DocumentData { need(snapshot.exists, `Required preflight evidence is missing: ${snapshot.ref.path}`);return snapshot.data()!; }
function configured(snapshot: DocumentSnapshot, companyId: string, bookId?: string): DocumentData {
  const d = required(snapshot);eq(d.id, snapshot.id, "Configuration document identity");eq(d.companyId, companyId, "Configuration company");
  if (bookId !== undefined) eq(d.bookId, bookId, "Configuration book");id(d.revisionId, "Configuration revision");eq(d.approvalStatus, "approved", "Approved accounting configuration");return d;
}
export function time(value: unknown): Time {
  const t = value as Time | null;need(t !== null && typeof t === "object" && Number.isSafeInteger(t.seconds) && t.seconds >= -62135596800 && t.seconds <= 253402300799 &&
    Number.isInteger(t.nanoseconds) && t.nanoseconds >= 0 && t.nanoseconds < 1000000000, "Resolved server/source timestamp required.");
  return {seconds: t.seconds, nanoseconds: t.nanoseconds};
}
export function compare(a: Time, b: Time): number {const l = BigInt(a.seconds) * 1000000000n + BigInt(a.nanoseconds), r = BigInt(b.seconds) * 1000000000n + BigInt(b.nanoseconds);return l < r ? -1 : l > r ? 1 : 0;}
export function money(value: unknown): bigint {
  need(typeof value === "string" || typeof value === "number" && Number.isFinite(value), "Exact cash amount unavailable.");
  const units = parseUnits(String(value), 3);if (typeof value === "number") eq(decimalNumber(units), value, "Exact legacy numeric amount");return units;
}
export function freeze<T>(value: T): T {if (value !== null && typeof value === "object") {for (const child of Object.values(value)) freeze(child);Object.freeze(value);}return value;}
