"use strict";
const assert = require("node:assert/strict");
const {test} = require("node:test");
const {readFileSync} = require("node:fs");
const {join} = require("node:path");
const {createHash} = require("node:crypto");
const {getApps} = require("firebase-admin/app");
const {Timestamp} = require("firebase-admin/firestore");
const {MAX_DECIMAL_UNITS, formatUnits} = require("../lib/trusted/exact_decimal");
const {
  buildSettlementJournalIntent: build,
  validateSettlementJournalIntent: validate,
  buildSettlementFinancialLedgerEntry,
} = require("../lib/trusted/financial_ledger_mappings");

// Committed Phase 2B-3 writer payload, no database or inferred currency policy.
const fixture = JSON.parse(readFileSync(join(__dirname, "../../test/fixtures/cash_settlement_metadata.json"), "utf8"));
function evidence() {
  const movements = structuredClone(fixture);
  for (const m of movements) {
    for (const key of ["date", "movementDate", "createdAt", "postedAt"]) {
      m[key] = Timestamp.fromDate(new Date(m[key]));
    }
  }
  const [out, incoming] = movements;
  const common = Object.fromEntries([
    "companyId", "amount", "settlementMetadataVersion", "postingSource", "operationId", "paymentMethod",
    "createdByUid", "createdByName", "createdByRole", "sourceCreatedByUid", "sourceCreatedByName", "sourceCreatedByRole",
    "postedByUid", "postedByName", "postedByRole", "createdAt", "postedAt",
    "sellerId", "sellerName", "sellerIdentityStatus", "collectorUid", "collectorName", "collectorIdentityStatus",
  ].map((key) => [key, out[key]]));
  const settlement = {...common, id: out.settlementId, status: "posted", salesRepId: out.salesRepId,
    salesRepName: out.salesRepName, settlementNumber: out.sourceNumber,
    idempotencyKey: out.settlementId.slice("settlement_".length), settlementDate: out.date, updatedAt: out.createdAt,
    repMovementId: out.id, companyMovementId: incoming.id,
    sourceCashAccount: "rep_cash", sourceCashAccountId: out.treasuryAccountId,
    destinationCashAccount: "company_cash", destinationCashAccountId: incoming.treasuryAccountId};
  const policy = {companyId: out.companyId, bookId: "offline-test-book", revisionId: "synthetic-policy-v1",
    currency: "JOD", moneyScale: 3, legacyCurrencyBindingId: "synthetic-reviewed-cash-currency"};
  const mappings = [incoming, out].map((m) => ({companyId: out.companyId, bookId: policy.bookId,
    currency: policy.currency, moneyScale: 3,
    mappingRevisionId: `synthetic-mapping-${m.cashAccount}-v1`,
    accountId: `synthetic-chart-${m.cashAccount}`, accountRevisionId: "synthetic-account-v1",
    accountType: "asset", control: "cash", active: true, postingAllowed: true, requiresTreasuryDimension: true,
    ledgerAccountKey: m.cashAccount === "company_cash" ? "company_cash" : `rep_cash:${out.salesRepId}`,
    treasuryAccountId: m.treasuryAccountId, holderType: m.holderType, holderUid: m.holderUid}));
  return {companyId: out.companyId, bookId: policy.bookId, policy, mappings, settlement, movements};
}
function sourceDocs(f) { return [f.settlement, ...f.movements]; }
function invalid(run) { assert.throws(run, (error) => error.code === "invalid-argument"); }
function setAmount(f, amount, before, after, companyBefore, companyAfter) {
  for (const d of sourceDocs(f)) d.amount = amount;
  Object.assign(f.movements[0], {balanceBefore: before, balanceAfter: after});
  Object.assign(f.movements[1], {balanceBefore: companyBefore, balanceAfter: companyAfter});
}
function canonical(value) {
  if (Array.isArray(value)) return value.map(canonical);
  if (value && typeof value === "object") return Object.fromEntries(Object.keys(value).sort().map((k) => [k, canonical(value[k])]));
  return value;
}

test("settlement intent debits company cash and credits representative cash with exact balanced units", () => {
  const f = evidence(), intent = build(f);
  assert.equal(intent.schemaVersion, 1);
  assert.equal(intent.amountUnits, "30123");
  assert.equal(intent.currency, "JOD");
  assert.equal(intent.moneyScale, 3);
  assert.equal(intent.lines.length, 2);
  const [debit, credit] = intent.lines;
  assert.equal(debit.account.ledgerAccountKey, "company_cash");
  assert.equal(credit.account.ledgerAccountKey, `rep_cash:${f.settlement.salesRepId}`);
  assert.deepEqual([debit.debitUnits, debit.creditUnits, credit.debitUnits, credit.creditUnits], ["30123", "0", "0", "30123"]);
  assert.equal(BigInt(debit.debitUnits) + BigInt(credit.debitUnits), BigInt(debit.creditUnits) + BigInt(credit.creditUnits));
  assert.equal(debit.cashMovementId, f.settlement.companyMovementId);
  assert.equal(credit.cashMovementId, f.settlement.repMovementId);
  assert.equal(debit.counterpartMovementId, credit.cashMovementId);
  assert.equal(credit.counterpartMovementId, debit.cashMovementId);
  assert.equal(debit.account.holderUid, f.companyId);
  assert.equal(credit.account.holderUid, f.settlement.salesRepId);
  assert.notEqual(credit.account.holderUid, intent.source.provenance.createdBy.uid);
  assert.ok(intent.lines.every((l) => l.companyId === f.companyId && l.bookId === f.bookId && l.currency === intent.currency));
  assert.deepEqual(validate(JSON.parse(JSON.stringify(intent)), f), intent);
  const {payloadDigest, ...payload} = intent;
  assert.equal(payloadDigest, createHash("sha256").update(JSON.stringify(canonical(payload))).digest("hex"));
});

test("settlement intent preserves source, movements, exact balances, actors and nanosecond provenance", () => {
  const f = evidence();
  const commit = new Timestamp(1793773968, 123456789);
  for (const d of sourceDocs(f)) d.createdAt = d.postedAt = commit;
  f.settlement.updatedAt = commit;
  const intent = build(f);
  assert.equal(intent.source.id, f.settlement.id);
  assert.equal(intent.source.path, `companies/${f.companyId}/settlements/${f.settlement.id}`);
  assert.equal(intent.source.operationId, f.settlement.operationId);
  assert.equal(intent.source.repMovementId, f.settlement.repMovementId);
  assert.equal(intent.source.companyMovementId, f.settlement.companyMovementId);
  assert.deepEqual(intent.source.provenance.postedAt, {seconds: commit.seconds, nanoseconds: 123456789});
  assert.deepEqual(intent.source.provenance.createdBy, intent.source.provenance.sourceCreatedBy);
  assert.deepEqual(intent.source.provenance.createdBy, intent.source.provenance.postedBy);
  assert.equal(intent.source.provenance.collectorUid, "");
  assert.equal(intent.source.provenance.sellerIdentityStatus, "not_applicable");
  assert.deepEqual(intent.movements.map((m) => [m.balanceBeforeUnits, m.balanceAfterUnits]), [["100111", "69988"], ["20222", "50345"]]);
  assert.deepEqual(intent.movements.map((m) => m.direction), ["out", "in"]);
  assert.ok(intent.movements.every((m) => m.sourceId === intent.source.id && m.referenceId === intent.source.id));
});

test("settlement intent replays deterministically after input ordering and decimal spelling changes", () => {
  const f = evidence(), first = build(f);
  f.mappings.reverse(); f.movements.reverse();
  for (const d of sourceDocs(f)) d.amount = "00030.123";
  assert.deepEqual(build(f, JSON.parse(JSON.stringify(first))), first);
  assert.equal(first.id, `settlement_intent_${createHash("sha256").update(JSON.stringify([
    1, f.companyId, f.bookId, "settlements", f.settlement.id, "rep_to_company_cash",
  ])).digest("hex")}`);
  assert.notEqual(first.lines[0].id, first.lines[1].id);
});

test("settlement intent supports an explicitly shared cash control only with distinct validated dimensions", () => {
  const f = evidence();
  for (const m of f.mappings) m.accountId = "synthetic-shared-cash-control";
  const result = build(f);
  assert.equal(result.lines[0].account.accountId, result.lines[1].account.accountId);
  assert.notEqual(result.lines[0].account.treasuryAccountId, result.lines[1].account.treasuryAccountId);
  assert.notEqual(result.lines[0].account.holderType, result.lines[1].account.holderType);
});

test("settlement intent requires currency evidence instead of guessing from legacy JOD formatting", () => {
  const f = evidence();
  delete f.policy.legacyCurrencyBindingId;
  invalid(() => build(f));
  for (const d of sourceDocs(f)) { d.currency = "JOD"; d.moneyScale = 3; }
  assert.equal(build(f).currency, "JOD");
  delete f.movements[0].currency;
  invalid(() => build(f));
});

test("settlement intent accepts only explicitly matching single currency, with no implicit FX", () => {
  const f = evidence();
  f.policy.currency = "USD";
  for (const m of f.mappings) m.currency = "USD";
  for (const d of sourceDocs(f)) d.currency = "USD";
  assert.equal(build(f).currency, "USD"); // Synthetic declared scale-3 policy, not company configuration.
});

test("settlement intent preserves the maximum exact string units and the smallest cash unit", () => {
  for (const units of [1n, MAX_DECIMAL_UNITS]) {
    const f = evidence(), amount = formatUnits(units, 3);
    setAmount(f, amount, amount, "0.000", "0.000", amount);
    assert.equal(build(f).amountUnits, units.toString());
  }
});

for (const [name, value] of [
  ["zero", 0], ["negative", -1], ["negative string", "-0.001"], ["missing", undefined], ["null", null],
  ["NaN", NaN], ["infinity", Infinity], ["boolean", true], ["array", []], ["object", {}],
  ["exponent", "1e3"], ["excess precision", "30.1230"], ["non-rounded number", 30.1234],
  ["whitespace", " 30.123"], ["positive sign", "+30.123"], ["empty", ""], ["newline", "30.123\n"],
  ["too many units", "1000000000000000000000000000.000"], ["unsafe number", 9007199254740.992],
  ["oversize input", "0".repeat(65)],
]) {
  test(`settlement intent rejects ${name} amounts`, () => {
    const f = evidence();
    setAmount(f, value, value, "0.000", "0.000", value);
    invalid(() => build(f));
  });
}

const invalidEvidence = [
  ["missing company", (f) => delete f.companyId], ["default company fallback", (f) => f.companyId = ""],
  ["path injection", (f) => f.companyId = "other/company"], ["missing book", (f) => delete f.bookId],
  ["missing policy", (f) => delete f.policy], ["missing policy revision", (f) => delete f.policy.revisionId],
  ["foreign policy", (f) => f.policy.companyId = "foreign"], ["foreign policy book", (f) => f.policy.bookId = "foreign"],
  ["missing currency", (f) => delete f.policy.currency], ["malformed currency", (f) => f.policy.currency = "jod"],
  ["unsupported scale", (f) => f.policy.moneyScale = 2], ["empty legacy binding", (f) => f.policy.legacyCurrencyBindingId = ""],
  ["missing settlement", (f) => delete f.settlement], ["foreign settlement", (f) => f.settlement.companyId = "foreign"],
  ["unposted settlement", (f) => f.settlement.status = "draft"], ["wrong settlement identity", (f) => f.settlement.id += "-changed"],
  ["wrong idempotency key", (f) => f.settlement.idempotencyKey = "other-retry-key"],
  ["wrong operation", (f) => f.settlement.operationId = "other-operation"],
  ["explicit foreign source book", (f) => f.settlement.bookId = "foreign"],
  ["explicit wrong source collection", (f) => f.settlement.sourceCollection = "receipts"],
  ["explicit wrong source identity", (f) => f.settlement.sourceId = "other"],
  ["explicit foreign source path", (f) => f.settlement.sourcePath = "companies/foreign/settlements/other"],
  ["missing source movement ID", (f) => delete f.settlement.repMovementId],
  ["wrong destination movement ID", (f) => f.settlement.companyMovementId = f.settlement.repMovementId],
  ["wrong source account", (f) => f.settlement.sourceCashAccount = "company_cash"],
  ["wrong source account ID", (f) => f.settlement.sourceCashAccountId = "company_cash"],
  ["wrong destination account", (f) => f.settlement.destinationCashAccount = "bank"],
  ["wrong destination account ID", (f) => f.settlement.destinationCashAccountId = "unverified"],
  ["missing mappings", (f) => delete f.mappings], ["one mapping", (f) => f.mappings.pop()],
  ["extra mapping", (f) => f.mappings.push(f.mappings[0])], ["duplicate mappings", (f) => f.mappings[1] = f.mappings[0]],
  ["foreign mapping company", (f) => f.mappings[0].companyId = "foreign"],
  ["foreign mapping book", (f) => f.mappings[0].bookId = "foreign"],
  ["missing chart account", (f) => delete f.mappings[0].accountId],
  ["missing chart revision", (f) => delete f.mappings[0].accountRevisionId],
  ["missing mapping revision", (f) => delete f.mappings[0].mappingRevisionId],
  ["unverified source key", (f) => f.mappings[1].ledgerAccountKey = "cash"],
  ["swapped holder", (f) => f.mappings[1].holderUid = f.settlement.createdByUid],
  ["missing dimensions", (f) => f.mappings[0].requiresTreasuryDimension = false],
  ["wrong treasury dimension", (f) => f.mappings[1].treasuryAccountId = "rep_other"],
  ["wrong holder type", (f) => f.mappings[1].holderType = "company"],
  ["sales revenue mapping", (f) => f.mappings[0].accountType = "income"],
  ["expense mapping", (f) => f.mappings[1].accountType = "expense"],
  ["non-cash control", (f) => f.mappings[0].control = "bank"],
  ["inactive account", (f) => f.mappings[0].active = false],
  ["non-posting group", (f) => f.mappings[1].postingAllowed = false],
  ["mapping currency mismatch", (f) => f.mappings[0].currency = "USD"],
  ["mapping scale mismatch", (f) => f.mappings[1].moneyScale = 2],
  ["inconsistent shared chart revision", (f) => { f.mappings[1].accountId = f.mappings[0].accountId; f.mappings[1].accountRevisionId = "changed"; }],
  ["missing movements", (f) => delete f.movements], ["single movement", (f) => f.movements.pop()],
  ["extra movement", (f) => f.movements.push(f.movements[0])],
  ["duplicate movement", (f) => f.movements[1] = f.movements[0]],
  ["negative representative balance", (f) => f.movements[0].balanceAfter = -1],
  ["negative company balance", (f) => f.movements[1].balanceBefore = -1],
  ["incorrect source balance equation", (f) => f.movements[0].balanceAfter = 69.989],
  ["incorrect destination balance equation", (f) => f.movements[1].balanceAfter = 50.346],
  ["missing balance", (f) => delete f.movements[0].balanceBefore],
  ["unresolved server timestamp", (f) => f.settlement.postedAt = {serverTimestamp: true}],
  ["string timestamp", (f) => f.settlement.settlementDate = "2026-08-05T12:00:00Z"],
  ["invalid timestamp seconds", (f) => f.settlement.settlementDate = {seconds: 0.5, nanoseconds: 0}],
  ["invalid timestamp nanoseconds", (f) => f.settlement.settlementDate = {seconds: 0, nanoseconds: 1e9}],
  ["incorrect updatedAt", (f) => f.settlement.updatedAt = new Timestamp(0, 0)],
];
// Every source document must carry matching, verified identity/currency/provenance.
for (const [field, bad] of [
  ["currency", "USD"], ["moneyScale", 2], ["settlementMetadataVersion", 2], ["postingSource", "client"],
  ["createdByRole", "sales_rep"], ["postedByUid", "forged"], ["sourceCreatedByName", "forged"],
  ["sellerId", "invented"], ["collectorUid", "invented"], ["collectorIdentityStatus", "unknown"],
  ["createdAt", new Timestamp(0, 0)],
]) {
  for (let index = 0; index < 3; index++) {
    invalidEvidence.push([`${field} mismatch on document ${index}`, (f) => sourceDocs(f)[index][field] = bad]);
  }
}
for (const [field, bad] of [
  ["companyId", "foreign"], ["amount", 30.124], ["sourceCollection", "receipts"],
  ["bookId", "foreign"], ["sourcePath", "companies/foreign/settlements/other"],
  ["sourceId", "other"], ["sourceNumber", "OTHER"], ["referenceId", "other"], ["referenceNumber", "OTHER"],
  ["settlementId", "other"], ["operationId", "other"], ["type", "receipt_cash"], ["movementType", "receipt"],
  ["direction", "unknown"], ["cashAccount", "bank"], ["holderUid", "forged"],
  ["treasuryAccountId", "other"], ["cashAccountSalesRepId", "other"], ["salesRepId", "other"],
  ["counterpartMovementId", "missing"], ["date", new Timestamp(0, 0)], ["movementDate", new Timestamp(0, 0)],
]) {
  for (let index = 0; index < 2; index++) {
    invalidEvidence.push([`${field} mismatch on movement ${index}`, (f) => f.movements[index][field] = bad]);
  }
}
for (const [name, mutate] of invalidEvidence) {
  test(`settlement intent rejects ${name}`, () => { const f = evidence(); mutate(f); invalid(() => build(f)); });
}

for (const [name, mutate] of [
  ["amount", (f) => setAmount(f, "30.124", "100.111", "69.987", "20.222", "50.346")],
  ["policy revision", (f) => f.policy.revisionId = "synthetic-policy-v2"],
  ["mapping revision", (f) => f.mappings[0].mappingRevisionId += "-changed"],
  ["chart account", (f) => f.mappings[0].accountId += "-changed"],
  ["business date", (f) => { const t = new Timestamp(0, 1); f.settlement.settlementDate = t; for (const m of f.movements) m.date = m.movementDate = t; }],
  ["stored commit provenance", (f) => { const t = new Timestamp(0, 1); f.settlement.updatedAt = t; for (const d of sourceDocs(f)) d.createdAt = d.postedAt = t; }],
  ["posting actor", (f) => { for (const d of sourceDocs(f)) for (const p of ["createdBy", "sourceCreatedBy", "postedBy"]) d[`${p}Uid`] = "another-admin"; }],
]) {
  test(`settlement intent conflicts on a coherent changed ${name} retry`, () => {
    const f = evidence(), previous = build(f);
    mutate(f);
    const changed = build(f);
    assert.equal(changed.id, previous.id);
    assert.notEqual(changed.payloadDigest, previous.payloadDigest);
    assert.throws(() => build(f, previous), {code: "already-exists"});
  });
}

for (const [name, mutate] of [
  ["unequal debit/credit", (i) => i.lines[0].debitUnits = "30124"],
  ["balanced but wrong amounts", (i) => { i.lines[0].debitUnits = i.lines[1].creditUnits = "30124"; }],
  ["reversed lines", (i) => i.lines.reverse()], ["duplicate line", (i) => i.lines[1] = i.lines[0]],
  ["extra line", (i) => i.lines.push(i.lines[0])], ["wrong line company", (i) => i.lines[0].companyId = "foreign"],
  ["wrong line currency", (i) => i.lines[1].currency = "USD"],
  ["both sides positive", (i) => i.lines[0].creditUnits = "30123"],
  ["zero lines", (i) => { for (const l of i.lines) l.debitUnits = l.creditUnits = "0"; }],
  ["wrong intent ID", (i) => i.id += "-changed"], ["wrong line ID", (i) => i.lines[0].id += "-changed"],
  ["wrong digest", (i) => i.payloadDigest = "0".repeat(64)], ["unrecognized effect", (i) => i.cashMovementsToCreate = []],
]) {
  test(`settlement intent validator rejects ${name} even with a recomputed digest`, () => {
    const f = evidence(), forged = JSON.parse(JSON.stringify(build(f)));
    mutate(forged);
    if (name !== "wrong digest") {
      const {payloadDigest, ...payload} = forged;
      forged.payloadDigest = createHash("sha256").update(JSON.stringify(canonical(payload))).digest("hex");
    }
    invalid(() => validate(forged, f));
  });
}

test("settlement intent source identities separate companies, books and representatives", () => {
  const f = evidence(), original = build(f);
  for (const change of ["company", "book", "representative"]) {
    const other = evidence();
    if (change === "company") {
      other.companyId = other.policy.companyId = "another-company";
      for (const d of sourceDocs(other)) d.companyId = other.companyId;
      other.movements[1].holderUid = other.companyId;
      for (const m of other.mappings) { m.companyId = other.companyId; if (m.holderType === "company") m.holderUid = other.companyId; }
    } else if (change === "book") {
      other.bookId = other.policy.bookId = "another-book";
      for (const m of other.mappings) m.bookId = other.bookId;
    } else {
      other.settlement.salesRepId = other.movements[0].salesRepId = other.movements[0].holderUid = "another-representative";
      other.settlement.sourceCashAccountId = other.movements[0].treasuryAccountId = "rep_another-representative";
      const m = other.mappings[1];
      m.holderUid = "another-representative"; m.treasuryAccountId = "rep_another-representative";
      m.ledgerAccountKey = "rep_cash:another-representative";
    }
    const changed = build(other);
    if (change === "representative") assert.equal(changed.id, original.id); // Same source, changed economic evidence must conflict.
    else assert.notEqual(changed.id, original.id);
    assert.throws(() => build(other, original), {code: "already-exists"});
  }
});

test("settlement intent is detached, deeply immutable, and creates no duplicate or external accounting effects", () => {
  const f = evidence(), before = JSON.stringify(f), appsBefore = getApps().length;
  const first = build(f);
  for (let n = 0; n < 20; n++) assert.deepEqual(build(f, first), first);
  assert.equal(JSON.stringify(f), before);
  assert.equal(getApps().length, appsBefore);
  assert.equal(Object.isFrozen(f.settlement), false);
  assert.ok(Object.isFrozen(first) && Object.isFrozen(first.lines) && Object.isFrozen(first.lines[0].account));
  assert.throws(() => first.lines.push(first.lines[0]), TypeError);
  assert.throws(() => first.lines[0].account.holderUid = "tampered", TypeError);
  f.mappings[0].accountId = "mutated-after-build";
  assert.notEqual(first.lines[0].account.accountId, "mutated-after-build");
  assert.equal(first.lines.length, 2);
  assert.equal(first.movements.length, 2);
  assert.equal("cashMovementsToCreate" in first, false);
});

test("settlement intent agrees with the unchanged legacy settlement mapping without invoking the writer", () => {
  const f = evidence(), s = f.settlement;
  const input = {companyId: f.companyId, settlementId: s.id, settlementNumber: s.settlementNumber,
    settlementDate: s.settlementDate, amount: s.amount, salesRepId: s.salesRepId, salesRepName: s.salesRepName, notes: ""};
  const legacyBefore = buildSettlementFinancialLedgerEntry(input);
  const intent = build(f);
  assert.deepEqual(buildSettlementFinancialLedgerEntry(input), legacyBefore);
  assert.equal(intent.lines[0].account.ledgerAccountKey, legacyBefore.debitAccountKey);
  assert.equal(intent.lines[1].account.ledgerAccountKey, legacyBefore.creditAccountKey);
  assert.equal(legacyBefore.amount, 30.123);
  assert.equal(legacyBefore.metricSales, 0);
  assert.equal(legacyBefore.metricExpenses, 0);
  for (const file of ["record_cash_settlement.ts", "../index.ts"]) {
    const source = readFileSync(join(__dirname, "../src/trusted", file), "utf8");
    assert.doesNotMatch(source, /buildSettlementJournalIntent|validateSettlementJournalIntent/);
  }
});

test("settlement intent validator bounds malformed, cyclic and oversized candidate payloads", () => {
  const f = evidence();
  const cycle = {}; cycle.self = cycle;
  for (const candidate of [undefined, null, true, [], {units: 1n}, cycle, {text: "x".repeat(2049)}, new Date()]) {
    invalid(() => validate(candidate, f));
  }
});
