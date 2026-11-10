import {DocumentData, DocumentSnapshot, Firestore, Timestamp, Transaction} from "firebase-admin/firestore";
import {accountingCanonical, accountingDigest, accountingNeed, accountingSame} from "./accounting_journal";
import {immutableAccountingRecord} from "./accounting_transaction";
import {parseUnits} from "./exact_decimal";

export interface AccountingEffect {path: string; immutable: boolean; document: DocumentData}
export interface EffectChunk {path: string; digest: string; count: number}

/** Exclude generated timestamps; normalize only explicitly scaled compatibility values. */
export function accountingDomainWitness(data: DocumentData): DocumentData {
  function convert(v: unknown, key: string, parent: DocumentData): unknown {
    if (["createdAt", "updatedAt", "postedAt", "stockUpdatedAt", "quantityUpdatedAt"].includes(key)) return undefined;
    if (v instanceof Timestamp) return {seconds: v.seconds, nanoseconds: v.nanoseconds};
    if (v === null) return null;
    if (["amount", "balanceBefore", "balanceAfter"].includes(key) || key.startsWith("metric") && typeof v === "number") {
      accountingNeed(typeof v === "number" && Number.isFinite(v), "Legacy money evidence is invalid.");
      return parseUnits(String(v), parent.moneyScale ?? 3).toString();
    }
    if (["quantity", "quantityBefore", "quantityAfter", "currentStock"].includes(key) && typeof v === "number") {
      const scale = parent.quantityScale ?? parent.stockQuantityScale;
      if (scale !== undefined) return parseUnits(String(v), scale).toString();
    }
    if (Array.isArray(v)) return v.map(x => convert(x, "", {}));
    if (v && typeof v === "object") return Object.fromEntries(Object.entries(v).map(([k, x]) => [k, convert(x, k, v)]).filter(([, x]) => x !== undefined));
    return v;
  }
  return JSON.parse(accountingCanonical(convert(data, "", {}))) as DocumentData;
}

export function prepareEffectManifest(companyId: string, bookId: string, eventId: string, effects: AccountingEffect[]) {
  const pieces = effects.map(e => accountingCanonical(e));
  if (effects.length <= 100 && pieces.reduce((n, p) => n + Buffer.byteLength(p), 0) <= 96 * 1024) return {effects, effectChunks: [] as EffectChunk[], records: [] as {path: string; data: DocumentData}[]};
  const groups: AccountingEffect[][] = [];let current: AccountingEffect[] = [], bytes = 0;
  for (let i = 0; i < effects.length; i++) {
    const size = Buffer.byteLength(pieces[i]);accountingNeed(size <= 96 * 1024, "One domain effect exceeds the evidence chunk budget.");
    if (current.length && (current.length >= 32 || bytes + size > 96 * 1024)) {groups.push(current);current = [];bytes = 0;}
    current.push(effects[i]);bytes += size;
  }
  if (current.length) groups.push(current);
  accountingNeed(groups.length <= 16, "Domain effects exceed the atomic evidence chunk budget.");
  const records = groups.map((group, index) => ({path: `companies/${companyId}/books/${bookId}/event_effect_chunks/${eventId}_${index.toString().padStart(3, "0")}`,
    data: {schemaVersion: 1, environment: "synthetic_emulator_only", companyId, bookId, eventId, index, effects: group}}));
  return {effects: [] as AccountingEffect[], effectChunks: records.map(r => ({path: r.path, digest: accountingDigest(r.data), count: r.data.effects.length})), records};
}

const caches = new WeakMap<Transaction, Map<string, Promise<AccountingEffect[]>>>();
export function readAccountingEffects(tx: Transaction, db: Firestore, snapshot: DocumentSnapshot, event: DocumentData): Promise<AccountingEffect[]> {
  let cache = caches.get(tx);if (!cache) {cache = new Map();caches.set(tx, cache);}
  const key = snapshot.ref.path;const found = cache.get(key);if (found) return found;
  const result = (async () => {
    const inline = event.effects, chunks: EffectChunk[] = event.effectChunks ?? [];
    accountingNeed(Array.isArray(inline) && Array.isArray(chunks) && chunks.length <= 16 && inline.length <= 480, "Invalid event effect manifest.", "data-loss");
    if (!chunks.length) return inline as AccountingEffect[];
    accountingNeed(inline.length === 0, "Mixed inline/chunked financial evidence is invalid.", "data-loss");
    const base = `companies/${event.companyId}/books/${event.bookId}/event_effect_chunks/${event.eventId}_`;
    chunks.forEach((c, i) => accountingNeed(c.path === `${base}${i.toString().padStart(3, "0")}` && Number.isSafeInteger(c.count) && c.count > 0 && c.count <= 32, "Invalid effect chunk reference.", "data-loss"));
    const snapshots = await tx.getAll(...chunks.map(c => db.doc(c.path)));const effects: AccountingEffect[] = [];
    snapshots.forEach((s, i) => {
      const payload = immutableAccountingRecord(s);
      accountingNeed(s.createTime!.isEqual(snapshot.createTime!) && payload.companyId === event.companyId && payload.bookId === event.bookId && payload.eventId === event.eventId && payload.index === i && payload.effects?.length === chunks[i].count, "Effect chunk scope/commit is invalid.", "data-loss");
      accountingSame(accountingDigest(payload), chunks[i].digest, "Atomic effect chunk digest");effects.push(...payload.effects);
    });
    accountingNeed(effects.length <= 480, "Effect manifest exceeds its declared budget.", "data-loss");return effects;
  })();
  cache.set(key, result);return result;
}
