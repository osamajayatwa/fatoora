import {DocumentData, DocumentReference, FieldValue, Firestore, Transaction, getFirestore} from "firebase-admin/firestore";
import {HttpsError, onCall} from "firebase-functions/v2/https";
import {
  TRUSTED_CALLABLE_OPTIONS,
  businessPath,
  deterministicId,
  finiteNumber,
  optionalString,
  record,
  requireCallableUid,
  requireTrustedUser,
  requiredIdempotencyKey,
  requiredString,
  roundMoney,
  timestampFrom,
} from "./common";
import {readCashBalance, writeCashBalance} from "./cash_ledger";
import {writeFinancialLedgerEntries} from "./financial_ledger";
import {buildSettlementFinancialLedgerEntry} from "./financial_ledger_mappings";
import {buildExactSettlementLedgerProjection} from "./financial_ledger_mappings";
import {prepareExactCashChange, compatibleExactNumber} from "./cash_ledger";
import type {AccountingPostingContext} from "./accounting_posting";
import type {AccountingControlEffect} from "./accounting_controls";
import {accountingNeed, accountingUnits} from "./accounting_journal";
import {assertAccountingEmulator} from "./accounting_transaction";

interface SettlementRequest {
  companyId?: unknown;
  idempotencyKey?: unknown;
  salesRepId?: unknown;
  salesRepName?: unknown;
  amount?: unknown;
  settlementDate?: unknown;
  notes?: unknown;
}

export const recordCashSettlement = onCall(
  TRUSTED_CALLABLE_OPTIONS,
  async (request) => {
    const uid = requireCallableUid(request, "recordCashSettlement");
    // The existing endpoint selects one implementation. Even this explicit
    // switch cannot enable the foundation writer outside its synthetic emulator.
    if (process.env.FATOORA_ACCOUNTING_ENGINE_EMULATOR === "true") {
      const {postFoundationCashSettlement} = await import("./accounting_settlement");
      return postFoundationCashSettlement(getFirestore(), uid, request.data, {enableEmulatorPosting: true});
    }
    const input = record(request.data) as SettlementRequest;
    const companyId = requiredString(input.companyId, "companyId");
    const key = requiredIdempotencyKey(input.idempotencyKey);
    return recordCashSettlementTransaction(
      getFirestore(),
      uid,
      companyId,
      key,
      input,
    );
  },
);

export async function recordCashSettlementTransaction(
  firestore: Firestore,
  uid: string | undefined,
  companyId: string,
  idempotencyKey: string,
  input: SettlementRequest,
): Promise<{settlementId: string; alreadyPosted: boolean}> {
  return firestore.runTransaction(async transaction => {
    const plan = await prepareCashSettlementWrite(transaction, firestore, uid, companyId, idempotencyKey, input);
    return plan.write();
  });
}

export interface CashSettlementWritePlan {
  settlementId: string;
  alreadyPosted: boolean;
  controlEffects?: AccountingControlEffect[];
  write(options?: {immutableCreate?: boolean; accountingBinding?: DocumentData}): {settlementId: string; alreadyPosted: boolean};
}

/** Shared existing writer: finish every read before returning the write closure.
 * The callable uses the original defaults; the isolated accounting adapter may
 * strengthen immutable creates and attach references in this same transaction. */
export async function prepareCashSettlementWrite(
  transaction: Transaction, firestore: Firestore, uid: string | undefined,
  companyId: string, idempotencyKey: string, input: SettlementRequest,
  exact?: {context: AccountingPostingContext; amountUnits: string},
): Promise<CashSettlementWritePlan> {
    const user = await requireTrustedUser(transaction, firestore, uid, companyId);
    if (user.role !== "admin") {
      throw new HttpsError("permission-denied", "Only administrators can settle cash.");
    }
    const salesRepId = requiredString(input.salesRepId, "salesRepId");
    const repSnapshot = await transaction.get(firestore.doc(`users/${salesRepId}`));
    const rep = repSnapshot.data() ?? {};
    if (
      !repSnapshot.exists ||
      rep.role !== "sales_rep" ||
      rep.active !== true ||
      rep.approvalStatus !== "approved" ||
      rep.companyId !== companyId
    ) {
      throw new HttpsError("failed-precondition", "Representative is not active and approved.");
    }
    const salesRepName = optionalString(rep.name) ||
      optionalString(input.salesRepName) || salesRepId;
    if (exact) {
      assertAccountingEmulator(firestore, {enableEmulatorPosting: true});
      accountingNeed(exact.context.companyId === companyId && exact.context.actor.uid === user.uid, "Exact settlement context is outside this command.");
      return prepareExactSettlementWrite(transaction, firestore, exact.context, idempotencyKey, salesRepId, salesRepName, input, exact.amountUnits);
    }
    const amount = roundMoney(finiteNumber(input.amount, "amount"));
    if (amount <= 0) throw new HttpsError("invalid-argument", "Amount must be positive.");
    const date = timestampFrom(input.settlementDate, "settlementDate");
    const settlementId = deterministicId("settlement", idempotencyKey);
    const settlementRef = firestore.doc(
      businessPath(companyId, "settlements", settlementId),
    );
    const existing = await transaction.get(settlementRef);
    if (existing.exists) {
      const data = existing.data() ?? {};
      if (
        data.salesRepId !== salesRepId ||
        roundMoney(typeof data.amount === "number" ? data.amount : 0) !== amount
      ) {
        throw new HttpsError("already-exists", "Idempotency key is already in use.");
      }
      return {settlementId, alreadyPosted: true, write: () => ({settlementId, alreadyPosted: true})};
    }

    const repMovementRef = firestore.doc(
      businessPath(companyId, "cash_movements", `${settlementId}_rep_out`),
    );
    const companyMovementRef = firestore.doc(
      businessPath(companyId, "cash_movements", `${settlementId}_company_in`),
    );
    if (
      (await transaction.get(repMovementRef)).exists ||
      (await transaction.get(companyMovementRef)).exists
    ) {
      throw new HttpsError("data-loss", "Settlement movement pair is incomplete.");
    }
    const repBalance = await readCashBalance(
      transaction,
      firestore,
      companyId,
      "rep_cash",
      salesRepId,
    );
    const companyBalance = await readCashBalance(
      transaction,
      firestore,
      companyId,
      "company_cash",
      "",
    );
    const repAfter = roundMoney(repBalance.amount - amount);
    if (repAfter < 0) {
      throw new HttpsError("failed-precondition", "Settlement exceeds available representative cash.");
    }
    const companyAfter = roundMoney(companyBalance.amount + amount);
    const referenceNumber = `SET-${date.toDate().toISOString().slice(0, 10).replace(/-/g, "")}-${idempotencyKey.slice(0, 6).toUpperCase()}`;
    return {settlementId, alreadyPosted: false, write: (options = {}) => {
    const binding = options.accountingBinding ? {accounting: options.accountingBinding} : {};
    const writeSource = (ref: DocumentReference, data: DocumentData): void => {
      if (options.immutableCreate) transaction.create(ref, data);
      else transaction.set(ref, data);
    };
    // The admin initiates and posts this transfer; neither role establishes
    // custody or an upstream seller/collector. Keep provenance on all three
    // documents in the existing atomic commit, including its server timestamp.
    const postingMetadata = {
      ...binding,
      settlementMetadataVersion: 1,
      postingSource: "recordCashSettlement",
      operationId: settlementId,
      sourceCreatedByUid: user.uid,
      sourceCreatedByName: user.name,
      sourceCreatedByRole: user.role,
      postedByUid: user.uid,
      postedByName: user.name,
      postedByRole: user.role,
      postedAt: FieldValue.serverTimestamp(),
      paymentMethod: "cash",
      sellerId: "",
      sellerName: "",
      sellerIdentityStatus: "not_applicable",
      collectorUid: "",
      collectorName: "",
      collectorIdentityStatus: "not_applicable",
    };
    const common = {
      ...postingMetadata,
      companyId,
      type: "settlement_to_admin",
      movementType: "settlement_to_admin",
      amount,
      referenceId: settlementId,
      referenceNumber,
      sourceCollection: "settlements",
      sourceId: settlementId,
      sourceNumber: referenceNumber,
      settlementId,
      customerId: "",
      customerName: "",
      date,
      movementDate: date,
      notes: optionalString(input.notes),
      createdByUid: user.uid,
      createdByName: user.name,
      createdByRole: user.role,
      createdAt: FieldValue.serverTimestamp(),
    };
    writeSource(repMovementRef, {
      ...common,
      id: repMovementRef.id,
      salesRepId,
      salesRepName,
      cashAccount: "rep_cash",
      treasuryAccountId: repBalance.ref.id,
      holderType: "representative",
      holderUid: repBalance.salesRepId,
      counterpartMovementId: companyMovementRef.id,
      direction: "out",
      balanceBefore: repBalance.amount,
      balanceAfter: repAfter,
    });
    writeSource(companyMovementRef, {
      ...common,
      id: companyMovementRef.id,
      salesRepId: "",
      salesRepName,
      cashAccount: "company_cash",
      treasuryAccountId: companyBalance.ref.id,
      holderType: "company",
      holderUid: companyId,
      counterpartMovementId: repMovementRef.id,
      direction: "in",
      balanceBefore: companyBalance.amount,
      balanceAfter: companyAfter,
    });
    writeCashBalance(
      transaction,
      repBalance,
      repAfter,
      repMovementRef.id,
      companyId,
    );
    writeCashBalance(
      transaction,
      companyBalance,
      companyAfter,
      companyMovementRef.id,
      companyId,
    );
    writeSource(settlementRef, {
      ...postingMetadata,
      id: settlementId,
      companyId,
      settlementNumber: referenceNumber,
      status: "posted",
      amount,
      salesRepId,
      salesRepName,
      repMovementId: repMovementRef.id,
      companyMovementId: companyMovementRef.id,
      sourceCashAccount: repBalance.account,
      sourceCashAccountId: repBalance.ref.id,
      destinationCashAccount: companyBalance.account,
      destinationCashAccountId: companyBalance.ref.id,
      settlementDate: date,
      notes: optionalString(input.notes),
      idempotencyKey,
      createdByUid: user.uid,
      createdByName: user.name,
      createdByRole: user.role,
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
    writeFinancialLedgerEntries(transaction, firestore, [
      {...buildSettlementFinancialLedgerEntry({
        companyId,
        settlementId,
        settlementNumber: referenceNumber,
        settlementDate: date,
        amount,
        salesRepId,
        salesRepName,
        notes: optionalString(input.notes),
      }), ...binding},
    ]);
    return {settlementId, alreadyPosted: false};
    }};
}

async function prepareExactSettlementWrite(tx: Transaction, db: Firestore, context: AccountingPostingContext, operationId: string,
  salesRepId: string, salesRepName: string, input: SettlementRequest, amountUnits: string): Promise<CashSettlementWritePlan> {
  const amount = accountingUnits(amountUnits);accountingNeed(amount > 0n, "Settlement must be positive.");
  const settlementId = deterministicId("settlement", operationId), source = db.doc(businessPath(context.companyId, "settlements", settlementId));
  if ((await tx.get(source)).exists) return {settlementId, alreadyPosted: true, write: () => ({settlementId, alreadyPosted: true})};
  const out = await prepareExactCashChange(tx, db, context, {cashAccount: "rep_cash", salesRepId, direction: "out", amountUnits, movementId: `${settlementId}_rep_out`});
  const incoming = await prepareExactCashChange(tx, db, context, {cashAccount: "company_cash", direction: "in", amountUnits, movementId: `${settlementId}_company_in`});
  const date = timestampFrom(input.settlementDate, "settlementDate"), notes = optionalString(input.notes);
  const referenceNumber = `SET-${date.toDate().toISOString().slice(0, 10).replace(/-/g, "")}-${operationId.slice(0, 6).toUpperCase()}`;
  const metadata = {settlementMetadataVersion: 1, postingSource: "recordCashSettlement", operationId: settlementId,
    sourceCreatedByUid: context.actor.uid, sourceCreatedByName: context.actor.name, sourceCreatedByRole: context.actor.role,
    postedByUid: context.actor.uid, postedByName: context.actor.name, postedByRole: context.actor.role, postedAt: FieldValue.serverTimestamp(),
    paymentMethod: "cash", sellerId: "", sellerName: "", sellerIdentityStatus: "not_applicable", collectorUid: "", collectorName: "", collectorIdentityStatus: "not_applicable"};
  return {settlementId, alreadyPosted: false, controlEffects: [out.effect, incoming.effect], write(options = {}) {
    accountingNeed(options.immutableCreate === true && options.accountingBinding?.eventId === context.eventId, "Exact settlement requires the shared atomic engine.");
    const binding = options.accountingBinding!, common = {...metadata, companyId: context.companyId, type: "settlement_to_admin", movementType: "settlement_to_admin",
      referenceId: settlementId, referenceNumber, sourceCollection: "settlements", sourceId: settlementId, sourceNumber: referenceNumber,
      settlementId, customerId: "", customerName: "", date, movementDate: date, notes, salesRepName,
      createdByUid: context.actor.uid, createdByName: context.actor.name, createdByRole: context.actor.role};
    for (const [plan, counterpart] of [[out, `${settlementId}_company_in`], [incoming, `${settlementId}_rep_out`]] as const) {
      for (const write of plan.writes(binding, {...common, counterpartMovementId: counterpart})) {
        if (write.method === "create") tx.create(db.doc(write.path), write.data);else tx.set(db.doc(write.path), write.data, {merge: true});
      }
    }
    const number = compatibleExactNumber(amount, context.configuration.moneyScale);
    tx.create(source, {...metadata, id: settlementId, companyId: context.companyId, settlementNumber: referenceNumber, status: "posted",
      amount: number, amountUnits, currency: context.configuration.currency, moneyScale: context.configuration.moneyScale,
      legacyAmountCoverage: number === null ? "not_representable" : "exact", salesRepId, salesRepName,
      repMovementId: `${settlementId}_rep_out`, companyMovementId: `${settlementId}_company_in`, sourceCashAccount: "rep_cash",
      sourceCashAccountId: out.position.id, destinationCashAccount: "company_cash", destinationCashAccountId: incoming.position.id,
      settlementDate: date, notes, idempotencyKey: operationId, accounting: binding, createdByUid: context.actor.uid,
      createdByName: context.actor.name, createdByRole: context.actor.role, createdAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp()});
    writeFinancialLedgerEntries(tx, db, [{...buildExactSettlementLedgerProjection({companyId: context.companyId, settlementId,
      settlementNumber: referenceNumber, settlementDate: date, amountUnits, currency: context.configuration.currency,
      moneyScale: context.configuration.moneyScale, salesRepId, salesRepName, notes}), accounting: binding}]);
    return {settlementId, alreadyPosted: false};
  }};
}
