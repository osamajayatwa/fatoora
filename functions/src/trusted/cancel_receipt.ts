import {DocumentData, FieldValue, Firestore, Query, Timestamp, getFirestore} from "firebase-admin/firestore";
import {HttpsError, onCall} from "firebase-functions/v2/https";
import {TRUSTED_CALLABLE_OPTIONS, businessPath, deterministicId, optionalString,
  record, requireCallableUid, requireTrustedUser, requiredString, roundMoney} from "./common";
import {CashAccount, readCashBalance, writeCashBalance} from "./cash_ledger";
import {buildFinancialLedgerEntry, LedgerAccount} from "./financial_ledger";

const MAX_ALLOCATIONS = 100;
const MAX_LEDGER_ENTRIES = 101;

export const cancelReceipt = onCall(TRUSTED_CALLABLE_OPTIONS, async (request) => {
  const uid = requireCallableUid(request, "cancelReceipt");
  const input = record(request.data);
  return cancelReceiptTransaction(getFirestore(), uid,
    requiredString(input.companyId, "companyId"),
    requiredString(input.receiptId, "receiptId"), input.reason);
});

function blocked(dependency: string): never {
  throw new HttpsError("failed-precondition", "Receipt cannot be safely cancelled: " + dependency + ".",
    {reason: "receipt-cancellation-unsafe", dependency});
}
function money(data: DocumentData, field: string): number {
  const value = data[field];
  if (typeof value !== "number" || !Number.isFinite(value)) blocked("inconsistent posting records");
  return roundMoney(value);
}
function ids(value: unknown): string[] {
  if (!Array.isArray(value) || value.some((id) => typeof id !== "string" || !id || id.includes("/"))) {
    blocked("inconsistent posting records");
  }
  return value as string[];
}
function account(data: DocumentData, side: "debit" | "credit"): LedgerAccount {
  const result = {type: optionalString(data[`${side}AccountType`]), key: optionalString(data[`${side}AccountKey`]),
    id: optionalString(data[`${side}AccountId`]), name: optionalString(data[`${side}AccountName`])};
  if (!result.type || !result.key || !result.name) blocked("incomplete financial ledger");
  return result;
}

/** Deterministic inverse entries retain the receipt type so type-filtered totals net correctly. */
export function buildReceiptCancellationEntries(
  originals: DocumentData[], companyId: string, receiptId: string, date: Timestamp, reason: string,
): DocumentData[] {
  return originals.map((original) => ({
    ...buildFinancialLedgerEntry({
      id: deterministicId("receipt_reversal", `${receiptId}:${original.id}`), companyId,
      occurredAt: date, type: "receipt", component: "customer_collection_reversal",
      description: `Receipt cancellation ${optionalString(original.referenceNumber)}`,
      amount: money(original, "amount"), debit: account(original, "credit"), credit: account(original, "debit"),
      referenceType: "receipt", referenceId: receiptId, referenceNumber: optionalString(original.referenceNumber),
      sourceCollection: "receipts", sourceId: receiptId,
      customerId: optionalString(original.customerId), customerName: optionalString(original.customerName),
      salesRepId: optionalString(original.salesRepId), salesRepName: optionalString(original.salesRepName),
      ownershipSource: optionalString(original.ownershipSource), paymentMethod: optionalString(original.paymentMethod),
      notes: reason, operationId: `cancel_receipt:${receiptId}`,
      metrics: {sales: -money(original, "metricSales"), cashSales: -money(original, "metricCashSales"),
        creditSales: -money(original, "metricCreditSales"), receipts: -money(original, "metricReceipts"),
        expenses: -money(original, "metricExpenses"), returns: -money(original, "metricReturns"),
        settlements: -money(original, "metricSettlements"), receivables: -money(original, "metricReceivables"),
        companyCashNet: -money(original, "metricCompanyCashNet"), repCashIn: -money(original, "metricRepCashIn"),
        repCashOut: -money(original, "metricRepCashOut")},
    }), isReversal: true, reversesEntryId: original.id,
  }));
}

export async function cancelReceiptTransaction(
  firestore: Firestore, uid: string | undefined, companyId: string, receiptId: string, rawReason: unknown,
): Promise<{receiptId: string; alreadyCancelled: boolean}> {
  return firestore.runTransaction(async (transaction) => {
    const user = await requireTrustedUser(transaction, firestore, uid, companyId);
    if (user.role !== "admin") throw new HttpsError("permission-denied", "Only administrators can cancel receipts.");
    const reason = requiredString(rawReason, "reason");
    if (reason.length > 500 || !receiptId || receiptId.includes("/")) {
      throw new HttpsError("invalid-argument", "Cancellation reason or receipt ID is invalid.");
    }
    const ref = firestore.doc(businessPath(companyId, "receipts", receiptId));
    const snapshot = await transaction.get(ref);
    if (!snapshot.exists) throw new HttpsError("not-found", "Receipt was not found.");
    const receipt = snapshot.data() ?? {};
    if (receipt.companyId !== companyId) blocked("inconsistent receipt identity");
    if (receipt.status === "cancelled") {
      if (receipt.cancellationVersion !== 1) blocked("unverified historical cancellation");
      return {receiptId, alreadyCancelled: true};
    }
    // Existing trusted receipts predate an explicit status field and are posted on creation.
    if (receipt.status && receipt.status !== "posted") blocked("receipt is not posted");
    const amount = money(receipt, "amount");
    if (amount <= 0) blocked("inconsistent receipt amount");
    const customerId = requiredString(receipt.customerId, "customerId");
    if (customerId.includes("/")) blocked("inconsistent customer identity");
    const customerRef = firestore.doc(businessPath(companyId, "customers", customerId));
    const customerSnapshot = await transaction.get(customerRef);
    const customer = customerSnapshot.data() ?? {};
    if (!customerSnapshot.exists || customer.companyId !== companyId) blocked("customer is missing");
    const balanceBefore = money(customer, "currentBalance");
    const totalPaid = money(customer, "totalPaid");
    if (totalPaid < amount) blocked("inconsistent customer payment total");

    const transactionIds = ids(receipt.customerTransactionIds);
    if (transactionIds.length !== 1) blocked("incomplete customer ledger");
    const creditSnapshot = await transaction.get(firestore.doc(businessPath(companyId, "customer_transactions", transactionIds[0])));
    const credit = creditSnapshot.data() ?? {};
    if (!creditSnapshot.exists || credit.companyId !== companyId || credit.customerId !== customerId ||
        credit.sourceId !== receiptId || credit.sourceCollection !== "receipts" ||
        money(credit, "creditAmount") !== amount || money(credit, "debitAmount") !== 0 ||
        money(credit, "signedAmount") !== -amount ||
        roundMoney(money(credit, "balanceBefore") - amount) !== money(credit, "balanceAfter")) blocked("incomplete customer ledger");
    // Credit is the signed customer balance, not a separate mutable credit bucket.
    // Any subsequent customer transaction makes a credit-producing receipt unsafe.
    if (money(credit, "balanceAfter") < 0) {
      if (!(credit.createdAt instanceof Timestamp)) blocked("credit posting date is missing");
      const dependent = await transaction.get(firestore.collection(`companies/${companyId}/customer_transactions`)
        .where("customerId", "==", customerId).where("createdAt", ">=", credit.createdAt).limit(2));
      if (dependent.docs.some((doc) => doc.id !== creditSnapshot.id)) blocked("customer credit has subsequent transactions");
      if (balanceBefore !== money(credit, "balanceAfter")) blocked("customer credit has changed");
    }

    const allocations = record(receipt.invoiceAllocations);
    if (!receipt.invoiceAllocations || typeof receipt.invoiceAllocations !== "object" ||
        Array.isArray(receipt.invoiceAllocations) || Object.keys(allocations).length > MAX_ALLOCATIONS) {
      blocked("allocation history is missing or exceeds the safe cancellation limit");
    }
    let allocated = 0;
    const invoiceUpdates: Array<{id: string; data: DocumentData}> = [];
    for (const [invoiceId, value] of Object.entries(allocations)) {
      const applied = money({amount: value}, "amount");
      if (!invoiceId || invoiceId.includes("/") || applied <= 0) blocked("inconsistent invoice allocations");
      allocated = roundMoney(allocated + applied);
      const invoiceSnapshot = await transaction.get(firestore.doc(businessPath(companyId, "invoices", invoiceId)));
      const invoice = invoiceSnapshot.data() ?? {};
      if (!invoiceSnapshot.exists || invoice.companyId !== companyId || invoice.customerId !== customerId ||
          invoice.financialPosted !== true || !["confirmed", "accepted"].includes(String(invoice.invoiceStatus))) {
        blocked("allocated invoice is missing or no longer posted");
      }
      if ((invoice.returnInvoiceIds as unknown[] | undefined)?.length ||
          Number(invoice.returnedTotal ?? 0) !== 0 || Number(invoice.returnedReceivableAmount ?? 0) !== 0) {
        blocked("allocated invoice has sales returns");
      }
      const receiptIds = ids(invoice.receiptIds);
      const paid = money(invoice, "paidAmount");
      const remaining = money(invoice, "remainingAmount");
      if (!receiptIds.includes(receiptId) || paid < applied || remaining < 0 ||
          roundMoney(paid + remaining) !== money(invoice, "grandTotal")) blocked("invoice payment history has changed");
      const nextPaid = roundMoney(paid - applied);
      const nextRemaining = roundMoney(remaining + applied);
      const activeIds = receiptIds.filter((id) => id !== receiptId);
      invoiceUpdates.push({id: invoiceId, data: {
        paidAmount: nextPaid, remainingAmount: nextRemaining,
        paymentStatus: nextRemaining === 0 ? "paid" : nextPaid > 0 ? "partiallyPaid" : "unpaid",
        hasReceivedPayment: nextPaid > 0, receiptIds: activeIds, lastReceiptId: activeIds.at(-1) ?? "",
        cancelledReceiptIds: FieldValue.arrayUnion(receiptId), updatedAt: FieldValue.serverTimestamp(),
      }});
    }
    if (allocated > amount) blocked("allocations exceed receipt amount");
    const ledgerSnapshots = await transaction.get(firestore.collection(`companies/${companyId}/financial_ledger_entries`)
      .where("sourceId", "==", receiptId).limit(MAX_LEDGER_ENTRIES + 1));
    const originals = ledgerSnapshots.docs.map((doc) => ({...doc.data(), id: doc.id}));
    if (!originals.length || originals.length > MAX_LEDGER_ENTRIES || originals.some((entry: DocumentData) =>
      entry.companyId !== companyId || entry.sourceCollection !== "receipts" || entry.type !== "receipt" ||
      entry.isReversal === true || entry.customerId !== customerId || entry.creditAccountKey !== `customer:${customerId}` ||
      entry.paymentMethod !== receipt.paymentMethod || money(entry, "amount") <= 0 ||
      money(entry, "metricReceipts") !== money(entry, "amount") || money(entry, "metricReceivables") !== -money(entry, "amount"))) {
      blocked("incomplete financial ledger");
    }
    if (roundMoney(originals.reduce((sum, entry) => sum + money(entry, "amount"), 0)) !== amount) {
      blocked("financial ledger does not reconcile");
    }
    const date = Timestamp.now();
    const reversals = buildReceiptCancellationEntries(originals, companyId, receiptId, date, reason);
    const debitRef = firestore.doc(businessPath(companyId, "customer_transactions", deterministicId("receipt_cancel", receiptId)));
    const cashRef = firestore.doc(businessPath(companyId, "cash_movements", deterministicId("receipt_cancel_cash", receiptId)));
    for (const reversalRef of [debitRef, cashRef, ...reversals.map((entry) =>
      firestore.doc(businessPath(companyId, "financial_ledger_entries", entry.id)))]) {
      if ((await transaction.get(reversalRef)).exists) blocked("partial cancellation records already exist");
    }

    const cashIds = ids(receipt.cashMovementIds);
    let cashState;
    let cashAfter = 0;
    let cashOriginal: DocumentData | undefined;
    if (receipt.paymentMethod === "cash") {
      if (cashIds.length !== 1) blocked("incomplete cash movement");
      const movement = await transaction.get(firestore.doc(businessPath(companyId, "cash_movements", cashIds[0])));
      cashOriginal = movement.data() ?? {};
      const cashAccount = cashOriginal.cashAccount as CashAccount;
      const owner = cashAccount === "rep_cash" ? optionalString(cashOriginal.salesRepId) : "";
      if (!movement.exists || cashOriginal.companyId !== companyId || cashOriginal.sourceId !== receiptId ||
          cashOriginal.sourceCollection !== "receipts" || cashOriginal.direction !== "in" ||
          money(cashOriginal, "amount") !== amount || !["company_cash", "rep_cash"].includes(cashAccount) ||
          (cashAccount === "rep_cash" && (!owner || owner !== receipt.createdByUid)) ||
          !(cashOriginal.createdAt instanceof Timestamp)) blocked("incomplete cash movement");
      if (originals.some((entry: DocumentData) => entry.debitAccountKey !==
          (cashAccount === "rep_cash" ? `rep_cash:${owner}` : "company_cash"))) blocked("cash ledger account does not reconcile");
      let outflows: Query = firestore.collection(`companies/${companyId}/cash_movements`)
        .where("cashAccount", "==", cashAccount).where("direction", "==", "out")
        .where("createdAt", ">=", cashOriginal.createdAt);
      if (owner) outflows = outflows.where("salesRepId", "==", owner);
      if (!(await transaction.get(outflows.limit(1))).empty) blocked("cash has subsequent spending or settlements");
      try {
        cashState = await readCashBalance(transaction, firestore, companyId, cashAccount, owner);
      } catch (error) {
        if (error instanceof HttpsError && ["failed-precondition", "data-loss"].includes(error.code)) {
          blocked("cash account requires reconciliation");
        }
        throw error;
      }
      cashAfter = roundMoney(cashState.amount - amount);
      if (cashAfter < 0) blocked("original cash account has insufficient funds");
    } else {
      if (!["bank", "check", "cliq"].includes(String(receipt.paymentMethod)) || cashIds.length) blocked("unsupported collection account");
      const expectedAccount = receipt.paymentMethod === "bank" ? "bank_unallocated" :
        receipt.paymentMethod === "check" ? "check_clearing" : "cliq_clearing";
      if (originals.some((entry: DocumentData) => entry.debitAccountKey !== expectedAccount)) {
        blocked("collection ledger account does not reconcile");
      }
      // These accounts have no settlement subsystem. Refuse if any recorded
      // outflow depends on the collection account rather than guessing a refund.
      for (const key of new Set(originals.map((entry: DocumentData) => optionalString(entry.debitAccountKey)))) {
        const dependencies = await transaction.get(firestore.collection(`companies/${companyId}/financial_ledger_entries`)
          .where("creditAccountKey", "==", key).limit(1));
        if (!dependencies.empty) blocked("collection account has dependent outflows");
      }
    }

    // All reads finish above. Receipt/customer/invoice/cash reads participate in
    // transaction retries against concurrent posting, settlements and cancellation.
    const actor = {createdByUid: user.uid, createdByName: user.name, createdByRole: user.role};
    const source = {companyId, sourceCollection: "receipts", sourceId: receiptId,
      sourceNumber: optionalString(receipt.receiptNumber), referenceId: receiptId,
      receiptId, receiptNumber: optionalString(receipt.receiptNumber),
      customerId, customerName: optionalString(credit.customerName),
      salesRepId: optionalString(receipt.salesRepId), salesRepName: optionalString(receipt.salesRepName),
      notes: reason, reason, ...actor, createdAt: FieldValue.serverTimestamp()};
    transaction.create(debitRef, {...source, id: debitRef.id, transactionType: "receipt_cancellation",
      type: "receipt_cancellation", reversesTransactionId: creditSnapshot.id,
      transactionDate: date, amount, signedAmount: amount, debitAmount: amount, creditAmount: 0,
      balanceBefore, balanceAfter: roundMoney(balanceBefore + amount)});
    if (cashState && cashOriginal) {
      writeCashBalance(transaction, cashState, cashAfter, cashRef.id, companyId);
      transaction.create(cashRef, {...source, id: cashRef.id, movementType: "receipt_cancellation",
        type: "receipt_cancellation", direction: "out", amount, cashAccount: cashState.account,
        salesRepId: cashState.account === "rep_cash" ? cashState.salesRepId : optionalString(cashOriginal.salesRepId),
        salesRepName: optionalString(cashOriginal.salesRepName), paymentType: "cash",
        referenceNumber: optionalString(receipt.receiptNumber), reversesMovementId: cashIds[0],
        balanceBefore: cashState.amount, balanceAfter: cashAfter, date, movementDate: date});
    }
    for (const entry of reversals) transaction.create(
      firestore.doc(businessPath(companyId, "financial_ledger_entries", entry.id)), {...entry, ...actor});
    for (const update of invoiceUpdates) transaction.update(
      firestore.doc(businessPath(companyId, "invoices", update.id)), update.data);
    transaction.update(customerRef, {currentBalance: roundMoney(balanceBefore + amount),
      totalPaid: roundMoney(totalPaid - amount), updatedAt: FieldValue.serverTimestamp()});
    transaction.update(ref, {status: "cancelled", cancellationVersion: 1, cancelledAt: date, cancelledByUid: user.uid,
      cancelledByName: user.name, cancelledByRole: user.role, cancellationReason: reason,
      cancellationCustomerTransactionIds: [debitRef.id], cancellationCashMovementIds: cashState ? [cashRef.id] : [],
      cancellationFinancialLedgerEntryIds: reversals.map((entry) => entry.id),
      cancellationFinancialLedgerEntries: reversals.map((entry) => ({...entry, ...actor})),
      updatedAt: FieldValue.serverTimestamp()});
    return {receiptId, alreadyCancelled: false};
  });
}
