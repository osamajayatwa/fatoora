"use strict";
const assert = require("node:assert/strict");
const {test, after} = require("node:test");
const {writeFileSync} = require("node:fs");
const {join} = require("node:path");
if (!/^127\.0\.0\.1:\d+$/.test(process.env.FIRESTORE_EMULATOR_HOST || "")) throw new Error("Coverage tests require isolated loopback emulators.");
const {initializeApp, deleteApp} = require("firebase-admin/app");
const {getFirestore, Timestamp, FieldValue} = require("firebase-admin/firestore");
const {settlementBreakdownTransaction: breakdown, SETTLEMENT_BREAKDOWN_LIMITS: limits} = require("../lib/trusted/settlement_breakdown");
const {canonicalSettlementEvidence: strictCodec, canonicalSettlementInventoryEvidence: inventoryCodec} = require("../lib/trusted/settlement_pending_evidence");
const {breakdownFixture, time} = require("./helpers/settlement_breakdown_fixture");
const {volumeFixture, receiptHistoryFixture} = require("./helpers/settlement_volume_fixture");
const {settlementBreakdownDetailPage: detailPage, verifySettlementBreakdownDetailPages: assemblePages} = require("../lib/trusted/settlement_breakdown_presentation");
const app = initializeApp({projectId: "demo-fatoora-phase2b7"}, "settlement-coverage-tests"), db = getFirestore(app);
const benchmarks = [];
after(async () => {writeFileSync(join(__dirname, "../../output/phase2b10-performance.json"), JSON.stringify({synthetic: true, emulator: process.env.FIRESTORE_EMULATOR_HOST, benchmarks}, null, 2));await deleteApp(app);});
const verified = r => assert.equal(r.status, "verified_cash_reconstruction", JSON.stringify(r.issues));
const blocked = (r, code) => {assert.equal(r.status, "blocked");assert.equal(r.totals, null);if (code) assert.ok(r.issues.some(i => i.code === code), JSON.stringify(r.issues));};
const code = expected => e => {assert.equal(e.code, expected, e.stack);return true;};
const run = (f, options = {}, database = db) => breakdown(database, f.admin, {companyId: f.companyId, salesRepId: f.rep, settlementId: f.currentId}, {enableEmulatorBreakdown: true, ...options});
const pagesFor = r => Array.from({length: Math.max(1, Math.ceil(r.cutoffMovementIds.length / 64))}, (_, pageIndex) =>
  detailPage(r, {evidenceDigest: r.evidenceDigest, snapshotDigest: r.snapshotCoverage.digest, pageIndex}));
function wrapped(transform) {return new Proxy(db, {get(target, prop) {
  if (prop === "runTransaction") return (callback, options) => db.runTransaction(raw => callback(new Proxy(raw, {get(t, p) {
    if (p === "get") return async q => transform(await t.get(q), q);
    const value = Reflect.get(t, p, t);return typeof value === "function" ? value.bind(t) : value;
  }})), options);
  const value = Reflect.get(target, prop, target);return typeof value === "function" ? value.bind(target) : value;
}});}
function queryView(snapshot, changes) {return new Proxy(snapshot, {get(target, prop) {
  if (Object.hasOwn(changes, prop)) return changes[prop];const value = Reflect.get(target, prop, target);return typeof value === "function" ? value.bind(target) : value;
}});}

for (const count of [100, 1000, 3000]) test(`complete exact coverage of ${count} synthetic invoice cash movements`, async t => {
  const seedAt = performance.now(), f = await volumeFixture(db, count, {mixed: true}), seedMilliseconds = performance.now() - seedAt, started = performance.now();
  const r = await run(f), milliseconds = performance.now() - started;verified(r);
  assert.equal(r.totals.cashAvailableBeforeUnits, f.beforeUnits);assert.equal(r.totals.remainingUnits, f.remainingUnits);
  assert.equal(r.snapshotCoverage.complete, true);assert.equal(r.snapshotCoverage.counts.length, 6);
  assert.equal(r.snapshotCoverage.counts.reduce((sum, c) => sum + c.count, 0), r.observation.scannedDocuments);
  assert.equal(r.snapshotCoverage.collections.length, 6);
  for (const p of r.snapshotCoverage.pages) assert.deepEqual(p.readTime, r.observation.readTime);
  for (const collection of r.snapshotCoverage.collections) {
    const pages = r.snapshotCoverage.pages.filter(p => p.collection === collection);assert.equal(pages.at(-1).terminal, true);
    assert.equal(pages.reduce((sum, p) => sum + p.count, 0), r.snapshotCoverage.counts.find(c => c.collection === collection).count);
  }
  assert.equal(new Set(r.committedOrder).size, r.committedOrder.length);assert.ok(r.observation.queryCount <= limits.queries);
  assert.ok(r.movements.some(m => m.category === "cash_refund"));assert.ok(r.movements.some(m => m.category === "cash_expense"));assert.ok(r.movements.some(m => m.category === "receipt_collection"));
  assert.equal(r.movements.filter(m => m.id.startsWith("volume-")).length, count);
  assert.equal(r.movements.find(m => m.id === "volume-000000_cash").sourceNumber, "INV-0");
  const presentationAt = performance.now(), pages = pagesFor(r), assembled = assemblePages(pages), presentationMilliseconds = performance.now() - presentationAt;
  assert.equal(assembled.rows.length, r.cutoffMovementIds.length);assert.deepEqual(assembled.totals, r.totals);
  const measurement = {invoiceCashMovements: count, seedMilliseconds: Math.round(seedMilliseconds), elapsedMilliseconds: Math.round(milliseconds),
    documentGets: r.observation.documentGets, currentAuthorizationGets: r.observation.authorizationDocumentGets, queries: r.observation.queryCount,
    aggregateQueries: r.snapshotCoverage.counts.length, pageQueries: r.snapshotCoverage.pages.length, scannedDocuments: r.observation.scannedDocuments, payloadBytes: r.observation.payloadBytes,
    presentationPages: pages.length, presentationMilliseconds: Math.round(presentationMilliseconds)};
  benchmarks.push(measurement);t.diagnostic(JSON.stringify(measurement));
  if (count === 100) {
    const other = await run(f, {pageSize: 16});verified(other);assert.deepEqual(other.totals, r.totals);assert.equal(other.evidenceDigest, r.evidenceDigest);
    assert.notEqual(other.snapshotCoverage.digest, r.snapshotCoverage.digest);
  }
});

test("one invoice with 1000 receipt references uses the shared validator without the old 32-reference ceiling", async () => {
  const f = await receiptHistoryFixture(db, 1000), r = await run(f);verified(r);assert.equal(r.totals.remainingUnits, f.remainingUnits);
  assert.equal(r.movements.filter(m => m.category === "receipt_collection").length, 1000);
  assert.ok(r.movements.filter(m => m.category === "receipt_collection").every(m => m.receivableAllocations[0].invoiceId === "dense-invoice"));
  assert.equal(r.movements.find(m => m.category === "receipt_collection").referencedDocuments[0].number, "INV-dense-invoice");
});

test("document-ID pagination preserves case, punctuation and Unicode source IDs across boundaries", async () => {
  const f = await breakdownFixture(db), batch = db.batch(), names = ["A", "a", "_", "-", "0", "é", "أ", "中"];
  for (let i = 0; i < 32; i++) {const id = `${names[i % names.length]}-${i}`;batch.create(f.ref("invoices", id), {id, companyId: f.companyId, invoiceStatus: "draft", financialPosted: false});}
  await batch.commit();const current = await f.settle("unicode-cursors", 1);f.currentId = current.settlementId;
  const r = await run(f, {pageSize: 16});verified(r);assert.equal(r.nonCashSources.invoices.length, 32);
  assert.equal(new Set(r.nonCashSources.invoices.map(d => d.id)).size, 32);assert.equal(r.snapshotCoverage.counts.find(c => c.collection === "invoices").count, 32);
  const pages = r.snapshotCoverage.pages.filter(p => p.collection === "invoices");assert.deepEqual(pages.map(p => p.count), [16, 16, 0]);assert.equal(pages[2].terminal, true);
  verified(await run(f, {pageSize: 16, readBudget: r.observation.scannedDocuments}));
  blocked(await run(f, {pageSize: 16, readBudget: r.observation.scannedDocuments - 1}), "inventory_bound_exceeded");
});

test("snapshot counts detect a skipped source document even when it has no cash leg", async () => {
  const f = await breakdownFixture(db), current = await f.settle("skip-probe", 1);f.currentId = current.settlementId;
  await f.expense("pending-source", 2, "rep_collected_cash", false);
  const database = wrapped((snapshot, q) => q._queryOptions?.parentPath?.toString() && snapshot.docs?.some(d => d.ref.path.includes("/expenses/")) ? queryView(snapshot, {docs: [], size: 0}) : snapshot);
  await assert.rejects(run(f, {}, database), /independent snapshot count/);
});

test("read-time mismatch and repeated cursor documents reject instead of clearing coverage", async () => {
  const f = await volumeFixture(db, 40);
  for (const corrupt of ["time", "repeat"]) {
    let previous;
    const database = wrapped(snapshot => {
      if (!snapshot.docs || !snapshot.docs[0]?.ref.path.includes("/cash_movements/")) return snapshot;
      if (corrupt === "time") return queryView(snapshot, {readTime: Timestamp.fromMillis(1)});
      if (previous) return queryView(snapshot, {docs: [previous, ...snapshot.docs.slice(1)]});
      previous = snapshot.docs.at(-1);return snapshot;
    });
    await assert.rejects(run(f, {pageSize: 16}, database), code("data-loss"));
  }
});

test("concurrent insertion behind a passed cursor stays out of the original snapshot and enters the next complete report", async () => {
  const f = await volumeFixture(db, 40);let inserted = false;
  const database = wrapped(async snapshot => {
    if (!inserted && snapshot.docs?.some(d => d.ref.path.includes("/invoices/"))) {
      inserted = true;await f.ref("invoices", "000-new-behind-cursor").create({id: "000-new-behind-cursor", companyId: f.companyId, invoiceStatus: "draft", financialPosted: false});
    }
    return snapshot;
  });
  const first = await run(f, {pageSize: 16}, database);verified(first);
  assert.ok(!first.nonCashSources.invoices.some(d => d.id === "000-new-behind-cursor"));
  const next = await run(f, {pageSize: 16});verified(next);assert.ok(next.nonCashSources.invoices.some(d => d.id === "000-new-behind-cursor"));assert.deepEqual(next.totals, first.totals);
});

test("authority revoked during pagination prevents delivery of an otherwise coherent old snapshot", async () => {
  const f = await volumeFixture(db, 40);let revoked = false;
  const database = wrapped(async snapshot => {
    if (!revoked && snapshot.docs?.length) {revoked = true;await db.doc(`users/${f.admin}`).update({active: false});}return snapshot;
  });
  await assert.rejects(run(f, {pageSize: 16}, database), code("permission-denied"));
});

test("source mutation ahead of the cursor cannot mix new source contents into old cash evidence", async () => {
  const f = await volumeFixture(db, 40);let changed = false;
  const database = wrapped(async snapshot => {
    if (!changed && snapshot.docs?.some(d => d.ref.path.includes("/cash_movements/"))) {changed = true;await f.ref("invoices", "volume-000020").update({currency: "USD"});}return snapshot;
  });
  verified(await run(f, {pageSize: 16}, database));blocked(await run(f, {pageSize: 16}), "inconsistent_source");
});

test("settlement committed between pages changes the next current balance without rebasing the original cutoff", async () => {
  const f = await volumeFixture(db, 40);let posted = false;
  const database = wrapped(async snapshot => {
    if (!posted && snapshot.docs?.some(d => d.ref.path.includes("/cash_movements/"))) {posted = true;await f.settle("mid-pagination", 2);}return snapshot;
  });
  const original = await run(f, {pageSize: 16}, database);verified(original);assert.equal(original.totals.currentBalanceUnits, f.remainingUnits);
  const next = await run(f, {pageSize: 16});verified(next);assert.equal(next.totals.remainingUnits, f.remainingUnits);assert.equal(next.totals.currentBalanceUnits, (BigInt(f.remainingUnits) - 2000n).toString());
  const pages = pagesFor(next), assembled = assemblePages(pages);assert.ok(!assembled.rows.some(r => r.source.id === "settlement_settlement-key-mid-pagination"));
});

test("independent count disagreement, cross-company rows and page permission failures do not produce a report", async () => {
  const f = await volumeFixture(db, 40);
  await assert.rejects(run(f, {}, wrapped(snapshot => snapshot.docs ? snapshot : queryView(snapshot, {data: () => ({count: snapshot.data().count + 1})}))), code("data-loss"));
  await assert.rejects(run(f, {}, wrapped(snapshot => {
    if (snapshot.docs?.length) throw Object.assign(new Error("Synthetic query denied"), {code: 7});return snapshot;
  })), code(7));
  const foreign = await breakdownFixture(db), foreignDoc = await foreign.ref("cash_movements", `rep_${foreign.rep}_opening`).get();
  await assert.rejects(run(f, {}, wrapped(snapshot => snapshot.docs?.length ? queryView(snapshot, {docs: [foreignDoc, ...snapshot.docs.slice(1)]}) : snapshot)), code("data-loss"));
});

test("detail pages reject gaps, reordering, duplicates, edits and mixed snapshots even with identical economic digests", async () => {
  const f = await volumeFixture(db, 80), r = await run(f), next = await run(f);verified(r);verified(next);assert.equal(r.evidenceDigest, next.evidenceDigest);
  const pages = pagesFor(r), other = pagesFor(next);assert.equal(pages.length, 2);
  for (const invalid of [[pages[0]], [...pages].reverse(), [pages[0], pages[0]], [pages[0], other[1]]]) assert.throws(() => assemblePages(invalid), code("data-loss"));
  const edited = JSON.parse(JSON.stringify(pages));edited[1].rows[0].sourceNumber = "forged-number";assert.throws(() => assemblePages(edited), code("data-loss"));
  assert.throws(() => detailPage(r, {evidenceDigest: next.evidenceDigest, snapshotDigest: next.snapshotCoverage.digest, pageIndex: 0}), code("failed-precondition"));
  assert.throws(() => detailPage(r, {evidenceDigest: r.evidenceDigest, snapshotDigest: r.snapshotCoverage.digest, pageIndex: 2}), code("invalid-argument"));
});

test("complete but historically blocked details preserve null totals; incomplete scans cannot become screen/PDF detail pages", async () => {
  const f = await volumeFixture(db, 80);await f.ref("cash_movements", `rep_${f.rep}_opening`).delete();const r = await run(f);blocked(r, "unknown_opening");
  const assembled = assemblePages(pagesFor(r));assert.equal(assembled.status, "blocked");assert.equal(assembled.totals, null);assert.equal(assembled.opening.amountUnits, null);
  const incomplete = await run(f, {readBudget: 32});blocked(incomplete);assert.throws(() => detailPage(incomplete, {evidenceDigest: incomplete.evidenceDigest, snapshotDigest: incomplete.snapshotCoverage.digest, pageIndex: 0}), code("failed-precondition"));
});

test("page-size and read budgets cannot increase hard ceilings or accept malformed limits", async () => {
  const f = await volumeFixture(db, 1);
  for (const options of [{pageSize: 15}, {pageSize: 257}, {pageSize: 16.5}, {readBudget: 16001}, {readBudget: 0}]) await assert.rejects(run(f, options), code("invalid-argument"));
});

test("read-budget exhaustion distinguishes incomplete coverage from a missing opening and suppresses all totals", async () => {
  const f = await volumeFixture(db, 80), r = await run(f, {readBudget: 32, pageSize: 16});blocked(r, "inventory_bound_exceeded");
  assert.equal(r.opening.state, "not_evaluated_incomplete_coverage");assert.equal(r.snapshotCoverage.complete, false);assert.ok(r.observation.scannedDocuments <= 33);
  assert.equal(r.snapshotCoverage.incompleteReason, "document_budget");
  assert.equal(r.carry.amountUnits, null);
});

test("page-query exhaustion blocks a history that fits the document ceiling", async () => {
  const f = await volumeFixture(db, 2200), r = await run(f, {pageSize: 16});blocked(r, "inventory_bound_exceeded");
  assert.equal(r.snapshotCoverage.complete, false);assert.equal(r.observation.queryCount, limits.queries);assert.ok(r.observation.scannedDocuments < limits.inventoryDocuments);
  assert.equal(r.snapshotCoverage.incompleteReason, "query_budget");
});

test("snapshot expiration never falls back to independently fresh pages", async () => {
  const f = await volumeFixture(db, 40);let nonemptyPages = 0;
  const database = wrapped(snapshot => {if (snapshot.docs?.length && ++nonemptyPages === 2) throw Object.assign(new Error("Synthetic expired snapshot"), {code: 9});return snapshot;});
  await assert.rejects(run(f, {pageSize: 16}, database), code(9));assert.equal(nonemptyPages, 2);
});

test("a genuinely excessive reference history stays an explicit blocker rather than truncating its links", async () => {
  const f = await breakdownFixture(db);await f.invoice("reference-budget");const receipt = await f.receipt("reference-budget", 1);
  await f.ref("invoices", "reference-budget").update({receiptIds: [receipt.receiptId, ...Array.from({length: 2048}, (_, i) => `historical-${i}`)]});
  const current = await f.settle("reference-budget", 1);f.currentId = current.settlementId;blocked(await run(f), "reference_coverage");
});

test("large-history missing openings, missing intermediate records, duplicates and currency conflicts fail closed", async () => {
  for (const mode of ["opening", "gap", "duplicate", "currency"]) {
    const f = await volumeFixture(db, 80);
    if (mode === "opening") await f.ref("cash_movements", `rep_${f.rep}_opening`).delete();
    if (mode === "gap") {await f.ref("cash_movements", "volume-000040_cash").delete();await f.ref("invoices", "volume-000040").delete();}
    if (mode === "duplicate") {const m = (await f.ref("cash_movements", "volume-000040_cash").get()).data();await f.ref("cash_movements", "alternate-duplicate").create({...m, id: "alternate-duplicate", createdAt: FieldValue.serverTimestamp()});}
    if (mode === "currency") await f.ref("invoices", "volume-000040").update({currency: "USD"});
    const r = await run(f, {pageSize: 16});blocked(r, mode === "opening" ? "unknown_opening" : mode === "gap" ? "incomplete_movement_coverage" : mode === "duplicate" ? "duplicate_movement" : "inconsistent_source");
    assert.equal(r.snapshotCoverage.complete, true);if (mode === "opening") assert.equal(r.opening.amountUnits, null);
  }
});

test("strict stored accounting codec is unchanged while inventory codec supports bounded larger lists", () => {
  const ordinary = {units: "1234", references: ["one", "two"]};assert.equal(strictCodec(ordinary), inventoryCodec(ordinary));
  const large = Array.from({length: 1000}, (_, i) => `movement-${i}`);assert.throws(() => strictCodec(large));assert.equal(JSON.parse(inventoryCodec(large)).length, 1000);
  assert.throws(() => inventoryCodec(Array(100)));assert.throws(() => inventoryCodec({money: 0.1}));assert.throws(() => inventoryCodec(Array.from({length: 16001}, () => "x")));
});
