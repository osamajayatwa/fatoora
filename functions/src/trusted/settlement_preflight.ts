import {DocumentData, DocumentSnapshot, Firestore, Transaction} from "firebase-admin/firestore";
import {HttpsError} from "firebase-functions/v2/https";
import {createHash} from "node:crypto";
import {requireTrustedUser} from "./common";
import {cashBalanceDocumentId} from "./cash_ledger";
import {decimalNumber, parseUnits, sumUnits} from "./exact_decimal";
import {companyCashAccount, repCashAccount} from "./financial_ledger";
import {
  buildSettlementJournalIntent, validateSettlementJournalIntent,
  SettlementCashMapping, SettlementJournalIntent, SettlementJournalIntentInput,
} from "./financial_ledger_mappings";

export interface SettlementPreflightInput {
  companyId: string;
  settlementId: string;
  expectedBookId?: string;
  expectedPreflightDigest?: string;
}
interface Time {seconds: number; nanoseconds: number}
interface Position {
  path: string;
  amountUnits: string;
  lastMovementId: string;
  updatedAt: Time;
  headRecordedAt: Time;
  headCommittedAt: Time;
}
export interface SettlementPreflight {
  schemaVersion: 1;
  mode: "committed_settlement_read_only";
  preparedByUid: string;
  intent: SettlementJournalIntent;
  preflightDigest: string;
  context: {
    bookRevisionId: string;
    policyRevisionId: string;
    mappingRevisionId: string;
    legacyCurrencyBindingRevisionId: string | null;
    period: {id: string; revisionId: string; startsAt: Time; endsAt: Time};
  };
  positions: readonly Position[];
  sourceKey: {path: string; state: "absent" | "matching_binding"};
  timestamps: {
    accountingDate: Time;
    sourceRecordedAt: Time;
    sourceCommittedAt: Time;
    transactionReadTime: Time;
    journalCommittedAt: null;
  };
  observations: readonly {path: string; readTime: Time; updateTime: Time | null}[];
}

/** Internal read-only entry point. Never exported as a callable or used by the writer. */
export async function preflightSettlementTransaction(
  firestore: Firestore, uid: string | undefined, input: SettlementPreflightInput,
): Promise<SettlementPreflight> {
  return firestore.runTransaction((transaction) => prepareSettlementPreflight(transaction, firestore, uid, input));
}

/** Must run before caller-owned writes. No transaction state escapes a retry. */
export async function prepareSettlementPreflight(
  transaction: Transaction, firestore: Firestore, uid: string | undefined, input: SettlementPreflightInput,
): Promise<SettlementPreflight> {
  const companyId = id(input?.companyId, "companyId"), settlementId = id(input?.settlementId, "settlementId");
  if (uid) id(uid, "uid");
  const user = await requireTrustedUser(transaction, firestore, uid, companyId);
  if (user.role !== "admin") throw new HttpsError("permission-denied", "Only administrators can preflight settlements.");
  const snapshots = new Map<string, DocumentSnapshot>();
  const read = async (paths: string[]): Promise<DocumentSnapshot[]> => {
    const missing = [...new Set(paths)].filter((path) => !snapshots.has(path));
    need(snapshots.size + missing.length <= 24, "Preflight read budget exceeded.");
    if (missing.length) {
      const results = await transaction.getAll(...missing.map((path) => firestore.doc(path)));
      for (const snapshot of results) snapshots.set(snapshot.ref.path, snapshot);
    }
    return paths.map((path) => snapshots.get(path)!);
  };
  const c = `companies/${companyId}`;
  const [companySnapshot] = await read([c]);
  const company = required(companySnapshot);
  eq(company.id, companyId, "Company identity");
  if (company.companyId !== undefined) eq(company.companyId, companyId, "Company scope metadata");
  eq(company.active, true, "Active company");
  const bookId = id(company.activeBookId, "activeBookId"), b = `${c}/books/${bookId}`;
  if (input.expectedBookId !== undefined) eq(input.expectedBookId, bookId, "Expected book");
  const [bookSnapshot] = await read([b]);
  const book = configured(bookSnapshot, companyId);
  if (book.bookId !== undefined) eq(book.bookId, bookId, "Book scope metadata");
  eq(book.active, true, "Active book");
  eq(book.mode, "configuration", "Supported preflight-only book mode");
  eq(book.settlementPreflightEnabled, true, "Settlement preflight gate");
  eq(book.journalPostingEnabled, false, "Journal persistence must remain disabled");
  const policyId = id(book.policyRevisionId, "policyRevisionId");
  const mappingId = id(book.settlementMappingRevisionId, "settlementMappingRevisionId");
  const periodId = id(book.settlementPeriodId, "settlementPeriodId");
  const [policySnapshot, mappingSnapshot, periodSnapshot, lockSnapshot, sourceSnapshot] = await read([
    `${b}/policy_revisions/${policyId}`, `${b}/settlement_mappings/${mappingId}`,
    `${b}/periods/${periodId}`, `${c}/maintenance_locks/cash_reconciliation`, `${c}/settlements/${settlementId}`,
  ]);
  const policy = configured(policySnapshot, companyId, bookId);
  const mapping = configured(mappingSnapshot, companyId, bookId);
  const period = configured(periodSnapshot, companyId, bookId);
  eq(policy.revisionId, policyId, "Policy revision");
  eq(mapping.revisionId, mappingId, "Mapping revision");
  eq(policy.currency, book.currency, "Book currency");
  eq(policy.moneyScale, book.moneyScale, "Book monetary scale");
  eq(policy.moneyScale, 3, "Supported source precision");
  need(typeof policy.currency === "string" && /^[A-Z]{3}$/.test(policy.currency), "Explicit currency required.");
  eq(policy.accountingDateBasis, "settlement_business_date", "Supported accounting date basis");
  eq(period.status, "open", "Open accounting period");
  if (lockSnapshot.exists) eq(lockSnapshot.data()?.active, false, "Cash reconciliation lock");
  const source = required(sourceSnapshot);
  eq(source.id, settlementId, "Settlement path identity");
  eq(source.companyId, companyId, "Settlement company");
  const rep = id(source.salesRepId, "salesRepId");
  const repMovementId = `${settlementId}_rep_out`, companyMovementId = `${settlementId}_company_in`;
  const repBalanceId = cashBalanceDocumentId("rep_cash", rep);
  const companyBalanceId = cashBalanceDocumentId("company_cash", "");
  const [repSnapshot, outSnapshot, inSnapshot, repBalanceSnapshot, companyBalanceSnapshot, legacySnapshot] = await read([
    `users/${rep}`, `${c}/cash_movements/${repMovementId}`, `${c}/cash_movements/${companyMovementId}`,
    `${c}/cash_balances/${repBalanceId}`, `${c}/cash_balances/${companyBalanceId}`,
    `${c}/financial_ledger_entries/settlement_${settlementId}_transfer`,
  ]);
  const repUser = required(repSnapshot);
  if (repUser.uid !== undefined) eq(repUser.uid, rep, "Representative profile identity");
  eq(repUser.companyId, companyId, "Representative company");
  eq(repUser.role, "sales_rep", "Representative role");
  eq(repUser.active, true, "Active representative");
  eq(repUser.approvalStatus, "approved", "Approved representative");
  const out = required(outSnapshot), incoming = required(inSnapshot);
  eq(out.id, outSnapshot.id, "OUT document identity");
  eq(incoming.id, inSnapshot.id, "IN document identity");
  let bindingRevision: string | null = null;
  if (policy.legacyCurrencyBindingId !== undefined) {
    const bindingId = id(policy.legacyCurrencyBindingId, "legacyCurrencyBindingId");
    const [bindingSnapshot] = await read([`${b}/currency_bindings/${bindingId}`]);
    const binding = configured(bindingSnapshot, companyId, bookId);
    eq(binding.revisionId, bindingId, "Currency binding revision");
    for (const [field, expected] of Object.entries({sourceCollection: "settlements", postingSource: "recordCashSettlement",
      settlementMetadataVersion: 1, currency: policy.currency, moneyScale: policy.moneyScale})) eq(binding[field], expected, `Binding ${field}`);
    bindingRevision = bindingId;
  }
  if ([source, out, incoming].some((document) => document.currency === undefined)) {
    need(bindingRevision !== null, "Legacy source currency is blocked until its binding is approved.");
  }
  const mappingRoles = [
    {role: "companyCash", ledgerAccountKey: companyCashAccount().key, treasuryAccountId: companyBalanceId,
      holderType: "company" as const, holderUid: companyId},
    {role: "representativeCash", ledgerAccountKey: repCashAccount(rep, "").key, treasuryAccountId: repBalanceId,
      holderType: "representative" as const, holderUid: rep},
  ];
  const accountSnapshots = await read(mappingRoles.map(({role}) => `${b}/chart_accounts/${id(mapping[`${role}AccountId`], `${role}AccountId`)}`));
  const mappings = mappingRoles.map((role, index): SettlementCashMapping => {
    const account = configured(accountSnapshots[index], companyId, bookId);
    eq(account.revisionId, mapping[`${role.role}AccountRevisionId`], "Pinned cash account revision");
    for (const [field, expected] of Object.entries({accountType: "asset", control: "cash", active: true,
      postingAllowed: true, requiresTreasuryDimension: true, currency: policy.currency, moneyScale: 3})) eq(account[field], expected, `Cash account ${field}`);
    return {companyId, bookId, currency: policy.currency, moneyScale: 3, mappingRevisionId: mappingId,
      accountId: accountSnapshots[index].id, accountRevisionId: account.revisionId,
      accountType: "asset", control: "cash", active: true, postingAllowed: true, requiresTreasuryDimension: true,
      ledgerAccountKey: role.ledgerAccountKey, treasuryAccountId: role.treasuryAccountId,
      holderType: role.holderType, holderUid: role.holderUid};
  });
  const evidence: SettlementJournalIntentInput = {
    companyId, bookId, policy: {companyId, bookId, revisionId: policyId, currency: policy.currency, moneyScale: 3,
      ...(bindingRevision === null ? {} : {legacyCurrencyBindingId: bindingRevision})},
    mappings, settlement: source, movements: [out, incoming],
  };
  const intent = validateSettlementJournalIntent(buildSettlementJournalIntent(evidence), evidence);
  // Stored server transforms and SDK commit metadata are different clocks.
  // Preserve both; verify the four original documents share an actual commit.
  const sourceCommittedAt = time(sourceSnapshot.createTime);
  for (const snapshot of [sourceSnapshot, outSnapshot, inSnapshot, legacySnapshot]) {
    eq(compare(time(snapshot.createTime), sourceCommittedAt), 0, "Atomic source commit metadata");
  }
  need(compare(intent.source.provenance.postedAt, sourceCommittedAt) <= 0, "Source recorded time exceeds its commit time.");
  need(compare(sourceCommittedAt, time(companySnapshot.readTime)) <= 0, "Source commit exceeds transaction read time.");
  const startsAt = time(period.startsAt), endsAt = time(period.endsAt), accountingDate = intent.source.settlementDate;
  need(compare(startsAt, endsAt) < 0 && compare(accountingDate, startsAt) >= 0 && compare(accountingDate, endsAt) < 0,
    "Settlement accounting date is outside the configured open period.");
  validateLegacy(required(legacySnapshot), intent);
  const positions: Position[] = [];
  for (const [index, balanceSnapshot] of [repBalanceSnapshot, companyBalanceSnapshot].entries()) {
    const balance = required(balanceSnapshot), movement = intent.movements[index];
    eq(balance.id, balanceSnapshot.id, "Cash position identity");
    eq(balance.companyId, companyId, "Cash position company");
    eq(balance.cashAccount, movement.cashAccount, "Cash position account");
    eq(balance.salesRepId, movement.salesRepId, "Cash position representative");
    for (const field of ["treasuryAccountId", "holderType", "holderUid"] as const) {
      if (balance[field] !== undefined) eq(balance[field], movement[field], `Cash position ${field}`);
    }
    if (balance.currency !== undefined) eq(balance.currency, intent.currency, "Cash position currency");
    if (balance.moneyScale !== undefined) eq(balance.moneyScale, intent.moneyScale, "Cash position scale");
    const headId = id(balance.lastMovementId, "lastMovementId");
    const [headSnapshot] = await read([`${c}/cash_movements/${headId}`]);
    const head = required(headSnapshot);
    eq(head.id, headId, "Cash head identity");
    eq(head.companyId, companyId, "Cash head company");
    eq(head.cashAccount, movement.cashAccount, "Cash head account");
    eq(head.salesRepId, movement.salesRepId, "Cash head representative");
    for (const field of ["treasuryAccountId", "holderType", "holderUid"] as const) {
      if (head[field] !== undefined) eq(head[field], movement[field], `Cash head ${field}`);
    }
    if (head.cashAccountSalesRepId !== undefined) eq(head.cashAccountSalesRepId, movement.salesRepId, "Cash head holder alias");
    if (head.currency !== undefined) eq(head.currency, intent.currency, "Cash head currency");
    if (head.moneyScale !== undefined) eq(head.moneyScale, intent.moneyScale, "Cash head scale");
    need(head.direction === "in" || head.direction === "out", "Cash head direction unavailable.");
    const amount = money(head.amount), before = money(head.balanceBefore), after = money(head.balanceAfter), position = money(balance.amount);
    need(amount > 0n && before >= 0n && after >= 0n && position >= 0n, "Invalid physical cash position.");
    eq(sumUnits([before, head.direction === "out" ? -amount : amount]), after, "Cash head balance equation");
    eq(position, after, "Stale cash balance projection");
    const updatedAt = time(balance.updatedAt), headRecordedAt = time(head.createdAt), headCommittedAt = time(headSnapshot.createTime);
    eq(compare(time(balanceSnapshot.updateTime), headCommittedAt), 0, "Atomic cash position/head commit metadata");
    eq(compare(updatedAt, headRecordedAt), 0, "Cash balance/head recorded timestamp");
    need(compare(headRecordedAt, headCommittedAt) <= 0, "Cash head recorded time exceeds commit time.");
    need(compare(headCommittedAt, sourceCommittedAt) >= 0, "Cash head predates settlement.");
    positions.push({path: balanceSnapshot.ref.path, amountUnits: position.toString(), lastMovementId: headId, updatedAt, headRecordedAt, headCommittedAt});
  }
  const context: SettlementPreflight["context"] = {
    bookRevisionId: book.revisionId, policyRevisionId: policyId, mappingRevisionId: mappingId,
    legacyCurrencyBindingRevisionId: bindingRevision,
    period: {id: periodId, revisionId: period.revisionId, startsAt, endsAt},
  };
  // Fixed ordered tuples bind configuration without volatile observation times.
  const preflightDigest = createHash("sha256").update(JSON.stringify([
    1, intent.id, intent.payloadDigest, sourceCommittedAt.seconds, sourceCommittedAt.nanoseconds,
    context.bookRevisionId, policyId, mappingId, bindingRevision,
    periodId, period.revisionId, startsAt.seconds, startsAt.nanoseconds, endsAt.seconds, endsAt.nanoseconds,
  ])).digest("hex");
  if (input.expectedPreflightDigest !== undefined) {
    need(typeof input.expectedPreflightDigest === "string" && /^[a-f0-9]{64}$/.test(input.expectedPreflightDigest), "Invalid expected preflight digest.");
    eq(input.expectedPreflightDigest, preflightDigest, "Conflicting preflight retry", "already-exists");
  }
  const keyPath = `${b}/source_keys/${intent.id}`, [keySnapshot] = await read([keyPath]);
  if (keySnapshot.exists) {
    const key = required(keySnapshot);
    for (const [field, expected] of Object.entries({schemaVersion: 1, companyId, bookId, sourceCollection: "settlements",
      sourceId: settlementId, action: intent.action, intentId: intent.id, payloadDigest: intent.payloadDigest, preflightDigest})) {
      eq(key[field], expected, `Conflicting source binding ${field}`, "already-exists");
    }
  }
  return freeze({schemaVersion: 1, mode: "committed_settlement_read_only", preparedByUid: user.uid, intent, preflightDigest, context, positions,
    sourceKey: {path: keyPath, state: keySnapshot.exists ? "matching_binding" : "absent"},
    timestamps: {accountingDate, sourceRecordedAt: intent.source.provenance.postedAt, sourceCommittedAt,
      transactionReadTime: time(companySnapshot.readTime), journalCommittedAt: null},
    observations: [...snapshots.values()].map((s) => ({path: s.ref.path, readTime: time(s.readTime), updateTime: s.updateTime ? time(s.updateTime) : null})),
  });
}

type FailureCode = "failed-precondition" | "already-exists";
function need(condition: boolean, message: string): asserts condition {
  if (!condition) throw new HttpsError("failed-precondition", message);
}
function eq(actual: unknown, expected: unknown, label: string, code: FailureCode = "failed-precondition"): void {
  if (actual !== expected) throw new HttpsError(code, `${label} is inconsistent.`);
}
function id(value: unknown, label: string): string {
  need(typeof value === "string" && value.length > 0 && value.length <= 256 && value.trim() === value &&
    !/[\/\u0000-\u001f\u007f]/u.test(value) && value !== "." && value !== "..", `${label} is missing or invalid.`);
  return value;
}
function required(snapshot: DocumentSnapshot): DocumentData {
  need(snapshot.exists, `Required preflight evidence is missing: ${snapshot.ref.path}`);
  return snapshot.data()!;
}
function configured(snapshot: DocumentSnapshot, companyId: string, bookId?: string): DocumentData {
  const data = required(snapshot);
  eq(data.id, snapshot.id, "Configuration document identity");
  eq(data.companyId, companyId, "Configuration company");
  if (bookId !== undefined) eq(data.bookId, bookId, "Configuration book");
  id(data.revisionId, "Configuration revision");
  eq(data.approvalStatus, "approved", "Approved accounting configuration");
  return data;
}
function time(value: unknown): Time {
  const t = value as Time | null;
  need(t !== null && typeof t === "object" && Number.isSafeInteger(t.seconds) &&
    t.seconds >= -62135596800 && t.seconds <= 253402300799 && Number.isInteger(t.nanoseconds) &&
    t.nanoseconds >= 0 && t.nanoseconds < 1000000000, "Resolved server/source timestamp required.");
  return {seconds: t.seconds, nanoseconds: t.nanoseconds};
}
function compare(a: Time, b: Time): number {
  const left = BigInt(a.seconds) * 1000000000n + BigInt(a.nanoseconds), right = BigInt(b.seconds) * 1000000000n + BigInt(b.nanoseconds);
  return left < right ? -1 : left > right ? 1 : 0;
}
function money(value: unknown): bigint {
  need(typeof value === "string" || (typeof value === "number" && Number.isFinite(value)), "Exact cash amount unavailable.");
  const units = parseUnits(String(value), 3);
  if (typeof value === "number") eq(decimalNumber(units), value, "Exact legacy numeric amount");
  return units;
}
function validateLegacy(row: DocumentData, intent: SettlementJournalIntent): void {
  const source = intent.source;
  for (const [field, expected] of Object.entries({id: `settlement_${source.id}_transfer`, companyId: intent.companyId,
    type: "settlement", component: intent.action, operationId: source.id,
    sourceCollection: "settlements", sourceId: source.id, sourcePath: source.path,
    referenceType: "settlement", referenceId: source.id, referenceNumber: source.number,
    debitAccountType: "cash", debitAccountKey: companyCashAccount().key, debitAccountId: "",
    creditAccountType: "cash", creditAccountKey: repCashAccount(source.salesRepId, "").key, creditAccountId: source.salesRepId})) {
    eq(row[field], expected, `Legacy settlement projection ${field}`);
  }
  eq(money(row.amount).toString(), intent.amountUnits, "Legacy settlement projection amount");
  if (row.currency !== undefined) eq(row.currency, intent.currency, "Legacy settlement projection currency");
  if (row.moneyScale !== undefined) eq(row.moneyScale, intent.moneyScale, "Legacy settlement projection scale");
  eq(compare(time(row.occurredAt), source.settlementDate), 0, "Legacy business date");
  // The legacy row aliases postedAt to business time, NOT actual commit time.
  eq(compare(time(row.postedAt), source.settlementDate), 0, "Legacy postedAt alias");
}
function freeze<T>(value: T): T {
  if (value !== null && typeof value === "object") {
    for (const child of Object.values(value)) freeze(child);
    Object.freeze(value);
  }
  return value;
}
