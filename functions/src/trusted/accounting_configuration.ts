import {FieldValue, Firestore} from "firebase-admin/firestore";
import {HttpsError, onCall} from "firebase-functions/v2/https";
import {TRUSTED_CALLABLE_OPTIONS, requireCallableUid, requireTrustedUser} from "./common";
import {AccountingConfiguration, ConfigurationReadiness, accountingConfigurationReadiness, configurationDigest,
  configurationError, configurationId, configurationRecord, validateAccountingConfiguration} from "./accounting_configuration_contract";

export interface AccountingConfigurationResult {
  schemaVersion: 1; companyId: string; bookId: string; revision: number;
  configuration: AccountingConfiguration | null; readiness: ConfigurationReadiness | null;
}

/** Deployment alone cannot enable configuration. No command activates a book or writes money. */
export const manageAccountingConfiguration = onCall(TRUSTED_CALLABLE_OPTIONS, async request => {
  const uid = requireCallableUid(request, "manageAccountingConfiguration");
  if (process.env.FATOORA_ACCOUNTING_CONFIGURATION_ENABLED !== "true") throw new HttpsError("failed-precondition", "Accounting configuration is unavailable.");
  const {getFirestore} = await import("firebase-admin/firestore");
  return accountingConfigurationTransaction(getFirestore(), uid, request.data);
});

export async function accountingConfigurationTransaction(db: Firestore, uid: string | undefined, input: unknown): Promise<AccountingConfigurationResult> {
  const raw = configurationRecord(input, "request", ["action", "companyId", "bookId", "expectedRevision", "requestId", "configuration"]);
  const companyId = configurationId(raw.companyId, "companyId"), bookId = configurationId(raw.bookId, "bookId");
  if (raw.action !== "read" && raw.action !== "save") configurationError("action", "unsupported_value");
  const save = raw.action === "save";
  if (!save && ["expectedRevision", "requestId", "configuration"].some(k => k in raw)) configurationError("request", "unexpected_read_fields");
  const configuration = save ? validateAccountingConfiguration(raw.configuration) : null;
  const expected = raw.expectedRevision;
  if (save && (typeof expected !== "number" || !Number.isSafeInteger(expected) || expected < 0 || expected >= 1000000)) configurationError("expectedRevision", "integer_out_of_range");
  const requestId = save ? configurationId(raw.requestId, "requestId") : "";
  const digest = save ? configurationDigest({companyId, bookId, expectedRevision: expected, configuration}) : "";
  const c = `companies/${companyId}`, b = `${c}/books/${bookId}`;
  return db.runTransaction(async tx => {
    const user = await requireTrustedUser(tx, db, uid, companyId);
    if (user.role !== "admin") throw new HttpsError("permission-denied", "Only company administrators can configure accounting.");
    const [companySnapshot, bookSnapshot] = await tx.getAll(db.doc(c), db.doc(b));
    const company = companySnapshot.data(), book = bookSnapshot.data();
    if (!companySnapshot.exists || company?.id !== companyId || company.active !== true || company.companyId !== undefined && company.companyId !== companyId) throw new HttpsError("failed-precondition", "An active, correctly scoped company is required.");
    if (bookSnapshot.exists && (book?.companyId !== companyId || book.bookId !== bookId || book.id !== bookId || book.accountingFoundationVersion !== 1)) throw new HttpsError("failed-precondition", "This book is outside the accounting configuration contract.");
    const revision = bookSnapshot.exists ? book!.configurationRevision : 0;
    if (!Number.isSafeInteger(revision) || revision < 0 || bookSnapshot.exists && revision < 1) throw new HttpsError("data-loss", "Invalid configuration revision.");
    let previous: AccountingConfiguration | null = null;
    if (bookSnapshot.exists) {
      const snapshot = await tx.get(db.doc(`${b}/configuration_revisions/revision_${revision}`));
      if (!snapshot.exists || snapshot.data()?.companyId !== companyId || snapshot.data()?.bookId !== bookId) throw new HttpsError("data-loss", "Configuration revision is missing or outside this book.");
      previous = validateAccountingConfiguration(snapshot.data()!.configuration);
      if (configurationDigest(previous) !== snapshot.data()?.configurationDigest || book!.configurationDigest !== snapshot.data()?.configurationDigest) throw new HttpsError("data-loss", "Configuration digest does not match its revision.");
    }
    if (!save) return {schemaVersion: 1, companyId, bookId, revision, configuration: previous, readiness: previous ? accountingConfigurationReadiness(previous) : null};
    const requestRef = db.doc(`${b}/configuration_requests/${configurationDigest([user.uid, requestId])}`);
    const [requestSnapshot, lockSnapshot] = await tx.getAll(requestRef, db.doc(`${c}/maintenance_locks/accounting_configuration`));
    if (requestSnapshot.exists) {
      if (requestSnapshot.data()?.requestDigest !== digest || requestSnapshot.data()?.actorUid !== user.uid) throw new HttpsError("already-exists", "Configuration request identity is already in use.");
      return requestSnapshot.data()!.result as AccountingConfigurationResult;
    }
    if (lockSnapshot.exists && lockSnapshot.data()?.active !== false) throw new HttpsError("failed-precondition", "Accounting configuration is under maintenance.");
    if (company.activeBookId === bookId || bookSnapshot.exists && (book!.active !== false || book!.mode !== "configuration" || book!.journalPostingEnabled !== false || book!.settlementPreflightEnabled !== false || book!.settlementJournalEmulatorEnabled !== false || book!.configurationLocked !== false)) throw new HttpsError("failed-precondition", "Configuration changes require an inactive, unused draft book.");
    if (revision !== expected) throw new HttpsError("aborted", "Configuration changed. Reload before saving.");
    // Stable IDs are retained even in draft history; deactivate unwanted accounts.
    if (previous?.accounts.some(a => !configuration!.accounts.some(n => n.id === a.id)) || previous?.periods.some(p => !configuration!.periods.some(n => n.id === p.id))) throw new HttpsError("failed-precondition", "Existing account and period identities must be retained.");
    const nextRevision = revision + 1, revisionId = `revision_${nextRevision}`;
    const accountRefs = configuration!.accounts.map(a => db.doc(`${b}/chart_accounts/${a.id}`));
    const codeRefs = configuration!.accounts.map(a => db.doc(`${b}/account_codes/${configurationDigest(a.code)}`));
    const periodRefs = configuration!.periods.map(p => db.doc(`${b}/periods/${p.id}`));
    const targets = [...accountRefs, ...codeRefs, ...periodRefs];
    const snapshots = targets.length ? await tx.getAll(...targets) : [];
    for (const s of snapshots) if (s.exists && (s.data()?.companyId !== companyId || s.data()?.bookId !== bookId || s.data()?.used === true)) throw new HttpsError("failed-precondition", "A configuration target is used or outside this book.");
    for (let i = 0; i < codeRefs.length; i++) {
      const s = snapshots[accountRefs.length + i];
      if (s.exists && (s.data()?.code !== configuration!.accounts[i].code || s.data()?.accountId !== configuration!.accounts[i].id)) throw new HttpsError("already-exists", "An account code is already reserved.");
    }
    const storedDigest = configurationDigest(configuration), readiness = accountingConfigurationReadiness(configuration!);
    const result: AccountingConfigurationResult = {schemaVersion: 1, companyId, bookId, revision: nextRevision, configuration: configuration!, readiness};
    const scope = {companyId, bookId, revisionId, approvalStatus: "unreviewed"};
    const stamp = {updatedAt: FieldValue.serverTimestamp(), updatedByUid: user.uid};
    // Every read is complete. One book gate serializes code/calendar/mapping changes.
    tx.set(db.doc(b), {...scope, ...stamp, id: bookId, accountingFoundationVersion: 1, configurationRevision: nextRevision,
      configurationDigest: storedDigest, name: configuration!.name, currency: configuration!.currency, moneyScale: configuration!.moneyScale,
      quantityScale: configuration!.quantityScale, priceScale: configuration!.priceScale, timezone: configuration!.timezone,
      active: false, mode: "configuration", configurationLocked: false, journalPostingEnabled: false,
      settlementPreflightEnabled: false, settlementJournalEmulatorEnabled: false, policyRevisionId: revisionId,
      fiscalCalendarRevisionId: revisionId, inventoryMode: "quantity_only", costCoverage: "not_recorded"});
    tx.create(db.doc(`${b}/configuration_revisions/${revisionId}`), {...scope, configuration: configuration!, configurationDigest: storedDigest,
      createdAt: FieldValue.serverTimestamp(), createdByUid: user.uid});
    tx.create(db.doc(`${b}/policy_revisions/${revisionId}`), {...scope, id: revisionId, currency: configuration!.currency,
      moneyScale: configuration!.moneyScale, quantityScale: configuration!.quantityScale, priceScale: configuration!.priceScale,
      timezone: configuration!.timezone, fiscalYearStartMonth: configuration!.fiscalYearStartMonth, fiscalYearStartDay: configuration!.fiscalYearStartDay,
      taxPolicy: configuration!.taxPolicy, taxCodes: configuration!.taxCodes, openingBoundary: configuration!.openingBoundary,
      inventoryMode: "quantity_only", costCoverage: "not_recorded"});
    tx.create(db.doc(`${b}/account_mappings/${revisionId}`), {...scope, id: revisionId, mappings: configuration!.mappings});
    configuration!.accounts.forEach((a, i) => {
      tx.set(accountRefs[i], {...scope, ...stamp, ...a, currency: configuration!.currency, moneyScale: configuration!.moneyScale,
        requiresTreasuryDimension: a.control === "cash" || a.control === "clearing", requiresCustomerDimension: a.control === "receivable" || a.control === "customer_credit", used: false});
      if (!snapshots[accountRefs.length + i].exists) tx.create(codeRefs[i], {companyId, bookId, code: a.code, accountId: a.id});
    });
    configuration!.periods.forEach((p, i) => tx.set(periodRefs[i], {...scope, ...stamp, ...p, status: "open", used: false, timezone: configuration!.timezone}));
    tx.create(db.doc(`${b}/audit_events/configuration_${revisionId}`), {...scope, action: "save_accounting_configuration", actorUid: user.uid,
      previousRevision: revision, configurationDigest: storedDigest, previousDigest: previous ? configurationDigest(previous) : null,
      recordedAt: FieldValue.serverTimestamp(), requestId});
    tx.create(requestRef, {companyId, bookId, actorUid: user.uid, requestId, requestDigest: digest, result, createdAt: FieldValue.serverTimestamp()});
    return result;
  });
}
