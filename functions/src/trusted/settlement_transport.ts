import {createHmac, randomBytes, timingSafeEqual} from "node:crypto";
import {Auth, getAuth} from "firebase-admin/auth";
import {DocumentSnapshot, FieldPath, Firestore, getFirestore, Transaction} from "firebase-admin/firestore";
import {HttpsError, onCall} from "firebase-functions/v2/https";
import {requireCallableUid, requireTrustedUser, TRUSTED_CALLABLE_OPTIONS} from "./common";
import {settlementBreakdownTransaction, SettlementCashBreakdown, SETTLEMENT_BREAKDOWN_LIMITS} from "./settlement_breakdown";
import {settlementBreakdownDetailPages, SettlementBreakdownDetailPage} from "./settlement_breakdown_presentation";
import {assertSettlementRecoveryEmulator} from "./settlement_journal_persistence";
import {settlementInventoryEvidenceDigest as digest} from "./settlement_pending_evidence";
import {freeze, id, time} from "./settlement_preflight_shared";
import {CASH_SOURCE_COLLECTIONS} from "./settlement_source_evidence";
import {settlementReadStage, settlementReadStageSync} from "./settlement_read_profile";
import {SettlementReadTarget, assertApprovedSettlementReadTarget, assertSettlementReadTransaction,
  createStagingSettlementReadTarget, SETTLEMENT_STAGING_PROJECT, SETTLEMENT_STAGING_FLAG} from "./settlement_read_target";
import {createSettlementPilotAccess} from "./settlement_staging_access";
import {verifySettlementReadRuntime} from "./settlement_runtime_canary";

export const SETTLEMENT_TRANSPORT_LIMITS = Object.freeze({ttlMillis: 300000, sessions: 4, retainedBytes: 67108864,
  sessionBytes: 25165824, responseBytes: 1048576, requestsPerMinute: 64, startsPerMinute: 2,
  maximumRequests: 512, sessionReadWork: 1000000, inventoryDocuments: 16000, concurrentWork: 2,
  globalReadWorkPerMinute: 500000, globalRequestsPerMinute: 128, quotaSubjects: 256, deliveryPages: 6});
const invalid = () => new HttpsError("failed-precondition", "Settlement session expired, changed or unavailable. Restart details.", {reason: "session_expired"});
const denied = () => new HttpsError("permission-denied", "Settlement evidence access denied.");
const exhausted = () => new HttpsError("resource-exhausted", "Settlement transport resource limit reached.");
type Scope = {companyId: string; salesRepId: string; settlementId: string};
export type SettlementReadPrincipal = {uid: string; authTime: number; appId?: string};
type Principal = SettlementReadPrincipal;
export interface SettlementTransportOptions {
  readTarget?: SettlementReadTarget;
  /** Server-owned security configuration, freshly checked before/after work. */
  access?: (principal: Principal) => Promise<string>;
  runtimeReady?: () => Promise<void>;
}
type Witness = SettlementCashBreakdown["readWitness"][number];
type Token = Scope & Principal & {v: 1; sid: string; evidence: string; snapshot: string; revision: string;
  issued: number; expires: number; page: number; purpose: "page" | "pdf"; delivery: 1 | 2; controlRevision?: string};
type Session = {token: Token; pages: readonly string[]; pageDigests: readonly string[]; witness: readonly Witness[];
  expected: ReadonlyMap<string, Witness>; inventories: readonly {path: string; count: number}[];
  ends: number[]; lastStart: number;
  bytes: number; requests: number; reads: number; next: number; busy: boolean; labels: {representative: string; settlement: string}};

/** Process-local, bounded and disposable. Cold loss/rerouting rejects tokens;
 * financial snapshots are NEVER rebuilt under an existing session. Test-only.
 * A distributed cache/rate boundary requires separate staging acceptance. */
export function createSettlementTransport(db: Firestore, auth: Pick<Auth, "getUser">, clock: () => number = Date.now, options: SettlementTransportOptions = {}) {
  const assertTarget = () => options.readTarget ? assertApprovedSettlementReadTarget(db, options.readTarget) : assertSettlementRecoveryEmulator(db);
  assertTarget();
  if (options.readTarget && (!options.access || !options.runtimeReady)) throw denied();
  const key = randomBytes(32), sessions = new Map<string, Session>();
  const quotas = new Map<string, {until: number; requests: number; starts: number}>();
  const starting = new Set<string>();
  const readonly = <T>(read: (tx: Transaction) => Promise<T>): Promise<T> => db.runTransaction(async tx => {
    const actual = Reflect.get(tx, "_firestore");
    if (!actual) throw new HttpsError("failed-precondition", "Supported isolated SDK transaction required.");
    if (options.readTarget) assertSettlementReadTransaction(tx, db, options.readTarget);else assertSettlementRecoveryEmulator(actual);
    return read(tx);
  }, {readOnly: true});
  let globalWindow = clock() + 60000, globalReadWork = 0, globalRequests = 0;
  let totalReadWork = 0;
  let bytes = 0, work = 0;
  function charge(n: number) {
    if (clock() >= globalWindow) {globalWindow = clock() + 60000;globalReadWork = 0;globalRequests = 0;}
    if (globalReadWork + n > SETTLEMENT_TRANSPORT_LIMITS.globalReadWorkPerMinute) throw exhausted();globalReadWork += n;totalReadWork += n;
  }
  function remove(sid: string) {const s = sessions.get(sid);if (s) {bytes -= s.bytes;sessions.delete(sid);}}
  function prune() {
    for (const [sid, s] of sessions) if (!s.busy && s.token.expires <= clock()) remove(sid);
    for (const [uid, q] of quotas) if (q.until <= clock()) quotas.delete(uid);
  }
  function quota(uid: string, start: boolean) {
    prune();charge(0);if (++globalRequests > SETTLEMENT_TRANSPORT_LIMITS.globalRequestsPerMinute) throw exhausted();let q = quotas.get(uid);
    if (!q) {if (quotas.size >= SETTLEMENT_TRANSPORT_LIMITS.quotaSubjects) throw exhausted();q = {until: clock() + 60000, requests: 0, starts: 0};quotas.set(uid, q);}
    if (++q.requests > SETTLEMENT_TRANSPORT_LIMITS.requestsPerMinute || start && ++q.starts > SETTLEMENT_TRANSPORT_LIMITS.startsPerMinute) throw exhausted();
  }
  function sign(value: Token) {
    const body = Buffer.from(JSON.stringify(value)).toString("base64url");
    const token = `${body}.${createHmac("sha256", key).update(body).digest("base64url")}`;
    if (token.length > 4096) throw exhausted();return token;
  }
  function parse(value: unknown, principal: Principal): Token {
    if (typeof value !== "string" || value.length > 4096 || !/^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]{43}$/.test(value)) throw invalid();
    const [body, signature] = value.split("."), actual = Buffer.from(signature, "base64url"), expected = createHmac("sha256", key).update(body).digest();
    if (actual.toString("base64url") !== signature || actual.length !== expected.length || !timingSafeEqual(actual, expected)) throw invalid();
    let t: Token;try {t = JSON.parse(Buffer.from(body, "base64url").toString("utf8"));} catch {throw invalid();}
    if (t.v !== 1 || t.uid !== principal.uid || t.authTime !== principal.authTime || t.appId !== principal.appId || t.expires <= clock() || t.issued > clock() || t.expires - t.issued !== SETTLEMENT_TRANSPORT_LIMITS.ttlMillis) throw invalid();
    return t;
  }
  async function authState(principal: Principal) {
    let user;try {user = await settlementReadStage("authProvider", () => auth.getUser(principal.uid));} catch {throw denied();}
    const revoked = user.tokensValidAfterTime === undefined ? 0 : Math.floor(Date.parse(user.tokensValidAfterTime) / 1000);
    if (user.disabled || user.uid !== principal.uid || !Number.isFinite(revoked) || principal.authTime < revoked) throw denied();
  }
  async function authority(principal: Principal, scope: Scope, witness?: readonly Witness[]) {
    await authState(principal);
    charge(5);return settlementReadStage("authority", () => readonly(async tx => {
      const user = await requireTrustedUser(tx, db, principal.uid, scope.companyId);
      const paths = [`users/${principal.uid}`, `companies/${scope.companyId}`, `users/${scope.salesRepId}`, `companies/${scope.companyId}/settlements/${scope.settlementId}`];
      const snaps = await tx.getAll(...paths.map(p => db.doc(p))), [p, c, r, target] = snaps.map(s => s.data());
      if (user.role !== "admin" || !p || p.uid !== undefined && p.uid !== principal.uid ||
          !c || c.id !== scope.companyId || c.active !== true || c.companyId !== undefined && c.companyId !== scope.companyId ||
          !r || r.companyId !== scope.companyId || r.role !== "sales_rep" || r.uid !== undefined && r.uid !== scope.salesRepId ||
          !target || target.id !== scope.settlementId || target.companyId !== scope.companyId || target.salesRepId !== scope.salesRepId || target.status !== "posted") throw denied();
      if (witness) {const byPath = new Map(witness.map(w => [w.path, w]));for (const s of snaps) if (!sameVersion(s, byPath.get(s.ref.path))) throw invalid();}
      if (typeof r.name === "string" && r.name.length > 2048 || typeof target.settlementNumber === "string" && target.settlementNumber.length > 2048) throw exhausted();
      return {representative: typeof r.name === "string" ? r.name : scope.salesRepId,
        settlement: typeof target.settlementNumber === "string" ? target.settlementNumber : scope.settlementId};
    }));
  }
  async function unchanged(s: Session) {
    const expected = s.expected;let reads = 0;
    const debit = (n: number) => {
      if (s.reads + n > SETTLEMENT_TRANSPORT_LIMITS.sessionReadWork) throw exhausted();
      charge(n);s.reads += n;
    };
    await readonly(async tx => {
      debit(1);
      const anchor = await tx.get(db.doc(`companies/${s.token.companyId}`));reads++;
      const stamp = JSON.stringify(time(anchor.readTime)), seen = new Set<string>();
      const check = (doc: DocumentSnapshot) => {
        if (JSON.stringify(time(doc.readTime)) !== stamp || seen.has(doc.ref.path) || !sameVersion(doc, expected.get(doc.ref.path))) throw invalid();
        seen.add(doc.ref.path);
      };
      check(anchor);
      // Expected cardinality + one sentinel proves complete membership, including
      // empty collections and insertions beyond the last original document ID.
      // All six bounded projections share this fresh transaction's read time.
      // Reserve ALL work before issuing RPCs, and drain failures before freeing
      // the concurrency slot. No unobserved background query escapes admission.
      debit(s.inventories.reduce((n, inventory) => n + inventory.count + 1, 0));
      const results = await Promise.allSettled(s.inventories.map(({path, count}) =>
        tx.get(db.collection(path).orderBy(FieldPath.documentId()).select().limit(count + 1))));
      for (const [index, result] of results.entries()) {
        if (result.status === "rejected") throw result.reason;
        const page = result.value;reads += page.size;
        if (clock() >= s.token.expires || JSON.stringify(time(page.readTime)) !== stamp ||
          page.size !== page.docs.length || page.size !== s.inventories[index].count) throw invalid();
        for (const doc of page.docs) check(doc);
      }
      const rest = s.witness.filter(w => !seen.has(w.path));
      if (rest.length > 64) throw invalid();
      if (rest.length) {debit(rest.length);const docs = await tx.getAll(...rest.map(w => db.doc(w.path)));reads += docs.length;for (const doc of docs) check(doc);}
      if (seen.size !== expected.size) throw invalid();
    });
    return reads;
  }
  const descriptor = (s: Session, index: number) => {
    const last = index + 1 === s.pages.length;
    return {schemaVersion: 1, kind: "page", provenance: "authenticated_firebase", expiresAtMillis: s.token.expires,
      representativeLabel: s.labels.representative, settlementLabel: s.labels.settlement, page: null,
      nextToken: last ? null : sign({...s.token, purpose: "page", page: index + 1}),
      exportToken: last ? sign({...s.token, purpose: "pdf", page: index}) : null};
  };
  // Immutable server-owned JSON strings release the full report/object graph
  // after start. Decode only the bounded pages actually being delivered.
  const response = (s: Session, index: number) => settlementReadStageSync("deliveryDecoding", () => freeze({...descriptor(s, index),
    page: JSON.parse(s.pages[index]) as SettlementBreakdownDetailPage}));
  const deliveryHeader = (s: Session, index: number) => ({schemaVersion: 2 as const, kind: "pages" as const, provenance: "authenticated_firebase" as const,
    firstPageIndex: index, nextPageIndex: s.ends[index] < s.pages.length ? s.ends[index] : null, pageCount: s.ends[index] - index});
  const deliveryDigest = (s: Session, index: number) => digest({...deliveryHeader(s, index), pageDigests: s.pageDigests.slice(index, s.ends[index])});
  const delivery = (s: Session, index: number) => {
    if (s.token.delivery === 1) return response(s, index);
    const end = s.ends[index], pages = s.pages.slice(index, end).map((_, offset) => response(s, index + offset));
    return freeze({...deliveryHeader(s, index), pages, deliveryDigest: deliveryDigest(s, index)});
  };
  return {
    // Internal diagnostics for isolated performance tests, never a wire field.
    statistics: () => ({sessions: sessions.size, retainedBytes: bytes, chargedReadWork: totalReadWork,
      currentMinuteReadWork: globalReadWork, sessionReadWork: [...sessions.values()].reduce((n, s) => n + s.reads, 0)}),
    async request(principal: Principal, input: unknown) {
      assertTarget();
      id(principal.uid, "Viewer");
      if (!Number.isSafeInteger(principal.authTime) || principal.authTime <= 0 || principal.authTime > Math.floor(clock() / 1000) + 60) throw denied();
      if (!input || typeof input !== "object" || Array.isArray(input)) throw new HttpsError("invalid-argument", "Versioned settlement request required.");
      const v = input as Record<string, unknown>, start = v.action === "start";
      const fields = start ? ["schemaVersion", "action", "companyId", "salesRepId", "settlementId"] : ["schemaVersion", "action", "token"];
      if (![1, 2].includes(Number(v.schemaVersion)) || typeof v.schemaVersion !== "number" || !["start", "page", "authorizePdf"].includes(String(v.action)) || Object.keys(v).length !== fields.length || fields.some(k => !(k in v)))
        throw new HttpsError("invalid-argument", "Unsupported settlement request.");
      quota(principal.uid, start);
      if (work >= SETTLEMENT_TRANSPORT_LIMITS.concurrentWork) throw exhausted();
      work++;
      let active: Session | undefined;
      let ownsStart = false;
      try {
        if (options.runtimeReady) await options.runtimeReady();
        const controlRevision = options.access ? await options.access(principal) : undefined;
        const finalAccess = async () => {if (await options.access?.(principal) !== controlRevision) throw invalid();};
        if (start) {
          if (starting.has(principal.uid) || [...sessions.values()].some(s => s.token.uid === principal.uid && s.busy)) throw new HttpsError("aborted", "Settlement request already in progress.");
          starting.add(principal.uid);
          ownsStart = true;
          const scope = {companyId: id(v.companyId, "Company"), salesRepId: id(v.salesRepId, "Representative"), settlementId: id(v.settlementId, "Settlement")};
          if (options.readTarget) assertApprovedSettlementReadTarget(db, options.readTarget, scope.companyId);
          await authority(principal, scope);
          if (sessions.size >= SETTLEMENT_TRANSPORT_LIMITS.sessions && ![...sessions.values()].some(s => s.token.uid === principal.uid)) throw exhausted();
          charge(16064);
          const report = await settlementReadStage("initialVerification", () => settlementBreakdownTransaction(db, principal.uid, scope,
            {enableEmulatorBreakdown: true, readTarget: options.readTarget, maximumAttempts: 1, pageSize: SETTLEMENT_BREAKDOWN_LIMITS.maximumPageSize}));
          if (!report.snapshotCoverage.complete || !("movements" in report)) {
            await authority(principal, scope);
            await finalAccess();
            return freeze({schemaVersion: 1, kind: "incomplete", provenance: "authenticated_firebase", ...scope, reason: "incomplete_coverage"});
          }
          const pages = settlementReadStageSync("pageConstruction", () => settlementBreakdownDetailPages(report));
          if (report.currency.length !== 3) throw new HttpsError("data-loss", "Invalid cash currency.");
          const serializedPages = settlementReadStageSync("cacheSerialization", () => Object.freeze(pages.map(p => JSON.stringify(p))));
          const pageDigests = Object.freeze(pages.map(p => p.pageDigest));
          const sizes = serializedPages.map(p => Buffer.byteLength(p));
          const retained = sizes.reduce((a, b) => a + b, 0) + Buffer.byteLength(JSON.stringify(report.readWitness)) + Buffer.byteLength(JSON.stringify(pageDigests));
          if (sizes.some(n => n > SETTLEMENT_TRANSPORT_LIMITS.responseBytes - 12288) || retained > SETTLEMENT_TRANSPORT_LIMITS.sessionBytes || bytes + retained > SETTLEMENT_TRANSPORT_LIMITS.retainedBytes) throw exhausted();
          const issued = clock(), token: Token = {...scope, ...principal, v: 1, sid: randomBytes(24).toString("base64url"), issued,
            expires: issued + SETTLEMENT_TRANSPORT_LIMITS.ttlMillis, evidence: report.evidenceDigest, snapshot: report.snapshotCoverage.digest,
            revision: digest(report.readWitness), page: 0, purpose: "page", delivery: v.schemaVersion as 1 | 2,
            ...(controlRevision === undefined ? {} : {controlRevision})};
          const expected = new Map(report.readWitness.map(w => [w.path, w]));
          const inventories = CASH_SOURCE_COLLECTIONS.map(collection => {
            const path = `companies/${scope.companyId}/${collection}`;
            return {path, count: report.readWitness.filter(w => w.exists && w.path.startsWith(`${path}/`) && w.path.split("/").length === 4).length};
          });
          active = {token, pages: serializedPages, pageDigests, witness: report.readWitness, bytes: retained, requests: 1, reads: report.observation.scannedDocuments,
            expected, inventories, ends: [], lastStart: 0, next: 0, busy: true, labels: await authority(principal, scope, report.readWitness)};
          let deliveries = 0;
          for (let index = 0; index < pages.length;) {
            let end = index, size = 512, envelopeBytes = 0;
            do {
              // The descriptor contains exactly one four-byte JSON null for
              // page; substitute its already measured serialized page length.
              const n = Buffer.byteLength(JSON.stringify(descriptor(active, end))) - 4 + sizes[end];
              if (n > SETTLEMENT_TRANSPORT_LIMITS.responseBytes) throw exhausted();
              if (size + n + 1 > SETTLEMENT_TRANSPORT_LIMITS.responseBytes) break;
              size += n + 1;envelopeBytes += n;end++;
            } while (token.delivery === 2 && end < pages.length && end - index < SETTLEMENT_TRANSPORT_LIMITS.deliveryPages);
            if (end === index) throw exhausted();
            active.ends[index] = end;
            // Exact whole-body bound without decoding every financial page a
            // second time during admission. JSON null is replaced by either
            // one serialized page, or an array with its brackets and commas.
            const bodyBytes = token.delivery === 1 ? envelopeBytes :
              Buffer.byteLength(JSON.stringify({...deliveryHeader(active, index), pages: null, deliveryDigest: deliveryDigest(active, index)})) - 4 +
              2 + envelopeBytes + (end - index - 1);
            if (bodyBytes > SETTLEMENT_TRANSPORT_LIMITS.responseBytes) throw exhausted();
            index = end;deliveries++;
          }
          if ((deliveries + 3) * (report.readWitness.length + 64) > SETTLEMENT_TRANSPORT_LIMITS.sessionReadWork) throw exhausted();
          active.next = active.ends[0];
          await settlementReadStage("versionValidation", () => unchanged(active!));
          await authority(principal, scope, active.witness);await authState(principal);
          await finalAccess();
          if (clock() >= token.expires || sessions.size >= SETTLEMENT_TRANSPORT_LIMITS.sessions && ![...sessions.values()].some(s => s.token.uid === principal.uid) || bytes + retained > SETTLEMENT_TRANSPORT_LIMITS.retainedBytes) throw exhausted();
          // A replacement session supersedes the same user's old target session.
          for (const [sid, old] of sessions) if (!old.busy && old.token.uid === principal.uid) remove(sid);
          sessions.set(token.sid, active);bytes += retained;
          return delivery(active, 0);
        }
        const token = parse(v.token, principal), s = sessions.get(token.sid);
        if (token.controlRevision !== controlRevision) throw invalid();
        if (!s || token.delivery !== v.schemaVersion || digest({...token, page: 0, purpose: "page"}) !== digest(s.token)) throw invalid();
        if (s.busy) throw new HttpsError("aborted", "Settlement request already in progress.");
        active = s;s.busy = true;
        if (++s.requests > SETTLEMENT_TRANSPORT_LIMITS.maximumRequests || s.reads + s.witness.length + 64 > SETTLEMENT_TRANSPORT_LIMITS.sessionReadWork) throw exhausted();
        const pdf = v.action === "authorizePdf";
        if (pdf ? token.purpose !== "pdf" || s.next !== s.pages.length || token.page !== s.pages.length - 1 :
          token.purpose !== "page" || token.page !== s.lastStart && token.page !== s.next || s.ends[token.page] === undefined) throw invalid();
        await authority(principal, token, s.witness);
        await settlementReadStage("versionValidation", () => unchanged(s));
        await authority(principal, token, s.witness);await authState(principal);
        await finalAccess();
        if (clock() >= token.expires) throw invalid();
        if (pdf) return freeze({schemaVersion: 1, kind: "pdf_permission", provenance: "authenticated_firebase",
          evidenceDigest: token.evidence, snapshotDigest: token.snapshot, validUntilMillis: Math.min(token.expires, clock() + 15000)});
        const value = delivery(s, token.page);s.lastStart = token.page;s.next = Math.max(s.next, s.ends[token.page]);return value;
      } catch (error) {
        if (options.access && error instanceof HttpsError && ["permission-denied", "unauthenticated", "failed-precondition"].includes(error.code)) {
          for (const [sid, old] of sessions) if (old.token.uid === principal.uid) remove(sid);
        }
        if (active && error instanceof HttpsError && ["permission-denied", "unauthenticated", "failed-precondition", "data-loss"].includes(error.code)) remove(active.token.sid);
        throw error;
      } finally {if (active) active.busy = false;if (ownsStart) starting.delete(principal.uid);work--;}
    },
  };
}
function sameVersion(s: DocumentSnapshot, expected: Witness | undefined) {
  return expected !== undefined && s.exists === expected.exists && (!s.exists ||
    JSON.stringify(time(s.createTime)) === JSON.stringify(expected.createTime) && JSON.stringify(time(s.updateTime)) === JSON.stringify(expected.updateTime));
}
let service: ReturnType<typeof createSettlementTransport> | undefined;
export const getSettlementBreakdown = onCall({...TRUSTED_CALLABLE_OPTIONS, maxInstances: 1, concurrency: 2, timeoutSeconds: 60, memory: "512MiB", cpu: 1,
  enforceAppCheck: process.env.FATOORA_SETTLEMENT_READ_TRANSPORT === SETTLEMENT_STAGING_FLAG}, async request => {
  if (!request.rawRequest.rawBody || request.rawRequest.rawBody.length > 16384) throw new HttpsError("resource-exhausted", "Settlement request size limit exceeded.");
  const staging = process.env.FATOORA_SETTLEMENT_READ_TRANSPORT === SETTLEMENT_STAGING_FLAG;
  if (!staging && (process.env.FATOORA_SETTLEMENT_READ_TRANSPORT !== "phase2b12-emulator-only" || process.env.FUNCTIONS_EMULATOR !== "true" ||
      !/^127\.0\.0\.1:\d+$/.test(process.env.FIREBASE_AUTH_EMULATOR_HOST ?? ""))) throw new HttpsError("failed-precondition", "Settlement transport is disabled outside approved testing.");
  const uid = requireCallableUid(request, "getSettlementBreakdown");
  const project = staging ? SETTLEMENT_STAGING_PROJECT : "demo-fatoora-phase2b7";
  if (request.auth?.token.aud !== project || request.auth.token.iss !== `https://securetoken.google.com/${project}` || staging && !request.app) throw denied();
  const authTime = request.auth?.token.auth_time;
  if (typeof authTime !== "number") throw denied();
  if (!service) {
    const db = getFirestore();
    const readTarget = staging ? createStagingSettlementReadTarget(db) : undefined;
    service = createSettlementTransport(db, getAuth(), Date.now, {readTarget,
      runtimeReady: readTarget ? () => verifySettlementReadRuntime(db, getAuth(), readTarget) : undefined,
      access: readTarget ? createSettlementPilotAccess(db, readTarget) : undefined});
  }
  return service.request({uid, authTime, ...(staging ? {appId: request.app!.appId} : {})}, request.data);
});
