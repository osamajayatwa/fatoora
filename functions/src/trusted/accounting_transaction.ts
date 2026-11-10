import {DocumentData, DocumentReference, DocumentSnapshot, FieldPath, FieldValue, Firestore, Transaction} from "firebase-admin/firestore";
import {accountingCanonical, accountingDigest, accountingNeed, accountingSame} from "./accounting_journal";

export interface AccountingEmulatorOptions {enableEmulatorPosting?: boolean}
export function assertAccountingEmulator(db: Firestore, options: AccountingEmulatorOptions): void {
  accountingNeed(options.enableEmulatorPosting === true, "Accounting engine is disabled by default.");
  const host = process.env.FIRESTORE_EMULATOR_HOST ?? "", settings = Reflect.get(db, "_settings");
  let project: unknown;try {project = Reflect.get(db, "projectId");} catch {project = null;}
  accountingNeed(/^127\.0\.0\.1:\d+$/.test(host) && project === "demo-fatoora-phase2d" && db.databaseId === "(default)" && settings?.servicePath === "127.0.0.1" && settings?.ssl === false && settings?.port === Number(host.split(":")[1]), "Accounting posting requires the dedicated synthetic loopback database.");
}
export interface AccountingTransactionBudget {reads: number; writes: number; bytes: number}
export const ACCOUNTING_WRITE_BUDGET = 480;
export const ACCOUNTING_CONTROL_COLLECTIONS = ["open_items", "open_item_positions", "party_positions", "allocations"];
const selectors = new WeakMap<Transaction, {companyId: string; bookId: string; select(customerId: string, limit: number): Promise<DocumentSnapshot[]>}>();
export function assertAccountingControlContext(tx: Transaction, companyId: string, bookId: string): void {
  const state = selectors.get(tx);accountingNeed(state && state.companyId === companyId && state.bookId === bookId, "Control preparers require the scoped synthetic accounting transaction.");
}
export function inheritAccountingTransactionScope(alias: Transaction, source: Transaction): void {
  const state = selectors.get(source);accountingNeed(state, "Only a guarded transaction can supply a composition alias.");selectors.set(alias, state);
}
export function selectOpenChargePositions(tx: Transaction, companyId: string, bookId: string, customerId: string, limit = 100): Promise<DocumentSnapshot[]> {
  const selector = selectors.get(tx);
  accountingNeed(selector && selector.companyId === companyId && selector.bookId === bookId && /^[A-Za-z0-9][A-Za-z0-9_-]{0,95}$/.test(customerId) && Number.isSafeInteger(limit) && limit >= 1 && limit <= 100, "A bounded, current-book open-item selector is required.");
  return selector.select(customerId, limit);
}

/** One attempt, one cache. Restrict financial writers to their declared domain paths. */
export function accountingTransaction(transaction: Transaction, db: Firestore, companyId: string, bookId: string, domainPaths: readonly string[], controlPaths: readonly string[] = [], itemPaths: readonly string[] = []) {
  const cache = new Map<string, DocumentSnapshot>(), b = `companies/${companyId}/books/${bookId}/`;
  const actualDb = Reflect.get(transaction, "_firestore") as Firestore;
  assertAccountingEmulator(actualDb, {enableEmulatorPosting: true});
  const companyRoot = `companies/${companyId}/`;
  accountingNeed(domainPaths.every(p => p.startsWith(companyRoot) && !p.startsWith(`${companyRoot}books/`)), "Domain paths must belong to this company's existing business collections.");
  accountingNeed(controlPaths.every(p => p.startsWith(b) && ACCOUNTING_CONTROL_COLLECTIONS.includes(p.slice(b.length).split("/")[0]) && p.slice(b.length).split("/").length === 2), "Only declared current-book subledger targets are allowed.");
  accountingNeed(itemPaths.every(p => /^items\/[A-Za-z0-9][A-Za-z0-9_-]{0,95}$/.test(p)), "Only explicitly declared catalog items are supported.");
  const budget: AccountingTransactionBudget = {reads: 0, writes: 0, bytes: 0};let writing = false;
  const read = async (refs: DocumentReference[]): Promise<DocumentSnapshot[]> => {
    accountingNeed(!writing, "All accounting reads must precede writes.");
    accountingNeed(refs.every(r => typeof r?.path === "string" && r.firestore === actualDb &&
      (r.path === `companies/${companyId}` || r.path.startsWith(companyRoot) && (!r.path.startsWith(`${companyRoot}books/`) || r.path === b.slice(0, -1) || r.path.startsWith(b)) || /^users\/[^/]+$/.test(r.path) || itemPaths.includes(r.path))), "Only current-company/book document reads are supported.");
    const missing = [...new Map(refs.filter(r => !cache.has(r.path)).map(r => [r.path, r])).values()];
    accountingNeed(budget.reads + missing.length <= 600, "Accounting read budget exceeded.");
    if (missing.length) {
      let values: DocumentSnapshot[];
      try {values = await transaction.getAll(...missing);} catch (error) {
        const e = error as {code?: number; details?: string};
        if (e.code === 3 && e.details === "Transaction is invalid or closed.") throw Object.assign(new Error("Synthetic emulator transaction expired.", {cause: error}), {code: 10});
        throw error;
      }
      for (const value of values) cache.set(value.ref.path, value);
      budget.reads += missing.length;
    }
    return refs.map(r => cache.get(r.path)!);
  };
  const tx = new Proxy(transaction, {get(target, prop) {
    if (prop === "get") return async (ref: DocumentReference) => (await read([ref]))[0];
    if (prop === "getAll") return (...refs: DocumentReference[]) => read(refs);
    if (["set", "create", "update", "delete"].includes(String(prop))) return (ref: DocumentReference, ...args: unknown[]) => {
      accountingNeed(prop !== "delete" && ref.firestore === actualDb && (ref.path.startsWith(b) || ref.path === b.slice(0, -1) || domainPaths.includes(ref.path) || itemPaths.includes(ref.path)), "Undeclared accounting write target.");
      writing = true;accountingNeed(++budget.writes <= ACCOUNTING_WRITE_BUDGET, "Accounting write budget exceeded.");
      const bytes = Buffer.byteLength(JSON.stringify(args[0]), "utf8");
      accountingNeed(bytes <= 512 * 1024 && (budget.bytes += bytes) <= 4 * 1024 * 1024, "Accounting write byte budget exceeded.");
      return Reflect.apply(Reflect.get(target, prop), target, [ref, ...args]);
    };
    const value = Reflect.get(target, prop, target);return typeof value === "function" ? value.bind(target) : value;
  }});
  selectors.set(tx, {companyId, bookId, select: async (customerId, limit) => {
    accountingNeed(!writing && budget.reads + limit + 1 <= 600, "Open-item query exceeds the read budget or follows writes.");
    const query = actualDb.collection(`${b}open_item_positions`).where("customerId", "==", customerId).where("kind", "==", "charge").where("state", "==", "open")
      .orderBy("dueDate").orderBy("originalDate").orderBy(FieldPath.documentId()).limit(limit + 1);
    const result = await transaction.get(query);budget.reads += Math.max(1, result.size);
    for (const s of result.docs) cache.set(s.ref.path, s);
    return result.docs;
  }});
  return {tx, budget};
}

export function accountingRecord(payload: DocumentData): DocumentData {
  accountingCanonical(payload);
  return {...payload, recordDigest: accountingDigest(payload), recordedAt: FieldValue.serverTimestamp()};
}
export function immutableAccountingRecord(snapshot: DocumentSnapshot): DocumentData {
  accountingNeed(snapshot.exists && snapshot.createTime && snapshot.updateTime && snapshot.createTime.isEqual(snapshot.updateTime), "Immutable accounting evidence is missing or was overwritten.", "data-loss");
  const {recordDigest, recordedAt, ...payload} = snapshot.data()!;
  accountingNeed(recordedAt && typeof recordedAt.seconds === "number" && (recordedAt.seconds < snapshot.createTime.seconds ||
    recordedAt.seconds === snapshot.createTime.seconds && recordedAt.nanoseconds <= snapshot.createTime.nanoseconds), "Accounting recorded time is invalid.", "data-loss");
  accountingSame(accountingDigest(payload), recordDigest, "Accounting evidence digest");return payload;
}
