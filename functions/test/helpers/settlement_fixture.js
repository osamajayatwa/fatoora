"use strict";
const {randomUUID} = require("node:crypto");
const {recordCashSettlementTransaction: legacyPost} = require("../../lib/trusted/record_cash_settlement");
const {pendingSettlementEvidenceTransaction: prepare} = require("../../lib/trusted/settlement_pending_evidence");
const {persistSettlementJournalTransaction: persist} = require("../../lib/trusted/settlement_journal_persistence");
const {Timestamp} = require("firebase-admin/firestore");
const enabled = Object.freeze({enableEmulatorPersistence: true});
async function createSettlementFixture(db, date) {
  const time = t => ({seconds: t.seconds, nanoseconds: t.nanoseconds});
  const company = `atomic-${randomUUID()}`, admin = `${company}-admin`, rep = `${company}-rep`;
  const c = `companies/${company}`, bookId = "synthetic-book", b = `${c}/books/${bookId}`;
  const paths = {company: c, book: b, policy: `${b}/policy_revisions/policy-v1`, mapping: `${b}/settlement_mappings/mapping-v1`,
    period: `${b}/periods/period-v1`, binding: `${b}/currency_bindings/binding-v1`, companyAccount: `${b}/chart_accounts/company-control`,
    repAccount: `${b}/chart_accounts/rep-control`, lock: `${c}/maintenance_locks/cash_reconciliation`,
    definition: `${b}/journal_definitions/settlement-journal`, seal: `${b}/posting_contracts/settlement-v1`,
    repBalance: `${c}/cash_balances/rep_${rep}`, companyBalance: `${c}/cash_balances/company_cash`};
  const scoped = id => ({id, companyId: company, bookId, revisionId: id, approvalStatus: "approved"});
  const batch = db.batch();
  batch.set(db.doc(c), {id: company, active: true, activeBookId: bookId});
  for (const [uid, role] of [[admin, "admin"], [rep, "sales_rep"]]) {
    batch.set(db.doc(`users/${uid}`), {uid, name: uid, role, companyId: company, active: true, approvalStatus: "approved"});
  }
  batch.set(db.doc(b), {...scoped(bookId), revisionId: "book-v1", active: true, mode: "configuration",
    settlementPreflightEnabled: true, journalPostingEnabled: false, currency: "JOD", moneyScale: 3,
    policyRevisionId: "policy-v1", settlementMappingRevisionId: "mapping-v1", settlementPeriodId: "period-v1",
    settlementJournalEmulatorEnabled: true, settlementJournalDefinitionId: "settlement-journal",
    settlementJournalDefinitionRevisionId: "journal-v1", postingLaneCount: 4, postingLaneSchemaVersion: 1});
  batch.set(db.doc(paths.policy), {...scoped("policy-v1"), currency: "JOD", moneyScale: 3,
    accountingDateBasis: "settlement_business_date", legacyCurrencyBindingId: "binding-v1"});
  batch.set(db.doc(paths.binding), {...scoped("binding-v1"), currency: "JOD", moneyScale: 3,
    sourceCollection: "settlements", postingSource: "recordCashSettlement", settlementMetadataVersion: 1});
  batch.set(db.doc(paths.mapping), {...scoped("mapping-v1"), companyCashAccountId: "company-control",
    companyCashAccountRevisionId: "company-account-v1", representativeCashAccountId: "rep-control", representativeCashAccountRevisionId: "rep-account-v1"});
  for (const [path, id, revisionId] of [[paths.companyAccount, "company-control", "company-account-v1"],
    [paths.repAccount, "rep-control", "rep-account-v1"]]) batch.set(db.doc(path), {...scoped(id), revisionId, currency: "JOD", moneyScale: 3,
    accountType: "asset", control: "cash", active: true, postingAllowed: true, requiresTreasuryDimension: true});
  batch.set(db.doc(paths.period), {...scoped("period-v1"), status: "open",
    startsAt: Timestamp.fromDate(new Date("2026-01-01T00:00:00Z")), endsAt: Timestamp.fromDate(new Date("2027-01-01T00:00:00Z"))});
  batch.set(db.doc(paths.definition), {...scoped("settlement-journal"), revisionId: "journal-v1", active: true,
    action: "rep_to_company_cash", currency: "JOD", moneyScale: 3, numberingPolicy: "source_identity"});
  for (const [id, account, uid, amount] of [[`rep_${rep}`, "rep_cash", rep, 100.111], ["company_cash", "company_cash", "", 20.222]]) {
    batch.set(db.doc(`${c}/cash_balances/${id}`), {id, companyId: company, cashAccount: account, salesRepId: uid, amount});
  }
  await batch.commit();
  await legacyPost(db, admin, company, "existing-cash-head-key", {salesRepId: rep, amount: 30.123, settlementDate: date});
  Object.assign(paths, {repHead: `${c}/cash_movements/settlement_existing-cash-head-key_rep_out`,
    companyHead: `${c}/cash_movements/settlement_existing-cash-head-key_company_in`});
  const input = {companyId: company, idempotencyKey: "atomic-settlement-key", salesRepId: rep,
    amount: "1.234", settlementDate: time(date), notes: "Synthetic atomic settlement"};
  return {company, admin, rep, c, b, bookId, paths, input,
    review: async (overrides = {}, uid = admin) => (await prepare(db, uid, {...input, ...overrides})).evidence,
    persist: (overrides = {}, expected, uid = admin, database = db, options = enabled) => persist(database, uid, {...input, ...overrides}, expected, options),
    advance: () => legacyPost(db, admin, company, `advance-${randomUUID()}`, {salesRepId: rep, amount: 1, settlementDate: date})};
}

module.exports = {createSettlementFixture};
