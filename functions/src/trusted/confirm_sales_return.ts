import {
  DocumentData,
  DocumentReference,
  FieldValue,
  Firestore,
  Timestamp,
  Transaction,
  getFirestore,
} from "firebase-admin/firestore";
import {HttpsError, onCall} from "firebase-functions/v2/https";
import {
  TRUSTED_CALLABLE_OPTIONS,
  TrustedUser,
  allocateDocumentNumber,
  buildSearchKeywords,
  businessPath,
  deterministicId,
  documentPrefix,
  numberFrom,
  optionalString,
  permissionValue,
  record,
  requireCallableUid,
  requireDocumentAccess,
  requireTrustedUser,
  requiredIdempotencyKey,
  requiredString,
  roundMoney,
  roundQuantity,
  timestampFrom,
} from "./common";
import {applyCashChange, CashAccount} from "./cash_ledger";
import {writeFinancialLedgerEntries} from "./financial_ledger";
import {buildSalesReturnFinancialLedgerEntries} from "./financial_ledger_mappings";

interface ReturnRequest {
  companyId?: unknown;
  returnId?: unknown;
  idempotencyKey?: unknown;
  originalInvoiceId?: unknown;
  items?: unknown;
  refundType?: unknown;
  returnDate?: unknown;
  reason?: unknown;
}

interface ReturnLine {
  originalInvoiceItemId: string;
  originalIndex: number;
  itemId: string;
  itemName: string;
  itemCode: string;
  unit: string;
  returnedQuantity: number;
  unitPrice: number;
  discountPerUnit: number;
  discountAmount: number;
  taxPercent: number;
  subtotal: number;
  taxAmount: number;
  total: number;
}

interface PendingWrite {
  ref: DocumentReference;
  data: DocumentData;
  merge?: boolean;
}

export const confirmSalesReturn = onCall(
  TRUSTED_CALLABLE_OPTIONS,
  async (request) => {
    const uid = requireCallableUid(request, "confirmSalesReturn");
    const input = record(request.data) as ReturnRequest;
    const companyId = requiredString(input.companyId, "companyId");
    const returnId = optionalString(input.returnId);
    const key = returnId ? "" : requiredIdempotencyKey(input.idempotencyKey);
    return confirmSalesReturnTransaction(
      getFirestore(),
      uid,
      companyId,
      returnId || deterministicId("return", key),
      input,
    );
  },
);

export async function confirmSalesReturnTransaction(
  firestore: Firestore,
  uid: string | undefined,
  companyId: string,
  returnId: string,
  input: ReturnRequest,
): Promise<{returnId: string; returnNumber: string; alreadyPosted: boolean}> {
  return firestore.runTransaction(async (transaction) => {
    const user = await requireTrustedUser(transaction, firestore, uid, companyId);
    const returnRef = firestore.doc(businessPath(companyId, "sales_returns", returnId));
    const returnSnapshot = await transaction.get(returnRef);
    const existing = returnSnapshot.data();
    if (returnSnapshot.exists) {
      requireDocumentAccess(user, existing ?? {});
      if (
        existing?.status === "confirmed" &&
        existing.financialPosted === true &&
        existing.inventoryPosted === true
      ) {
        return {
          returnId,
          returnNumber: optionalString(existing.returnNumber),
          alreadyPosted: true,
        };
      }
      if (existing?.status !== "draft") {
        throw new HttpsError("failed-precondition", "Sales return is not a draft.");
      }
    }
    const source = existing ?? record(input);
    const originalInvoiceId = requiredString(
      source.originalInvoiceId ?? input.originalInvoiceId,
      "originalInvoiceId",
    );
    const invoiceRef = firestore.doc(
      businessPath(companyId, "invoices", originalInvoiceId),
    );
    const invoiceSnapshot = await transaction.get(invoiceRef);
    if (!invoiceSnapshot.exists) throw new HttpsError("not-found", "Original invoice was not found.");
    const invoice = invoiceSnapshot.data() ?? {};
    requireDocumentAccess(user, invoice);
    if (
      invoice.invoiceStatus !== "confirmed" ||
      invoice.financialPosted !== true ||
      invoice.inventoryPosted !== true
    ) {
      throw new HttpsError("failed-precondition", "Original invoice is not posted.");
    }
    const settingsSnapshot = await transaction.get(
      firestore.doc(businessPath(companyId, "settings", "app")),
    );
    const settings = settingsSnapshot.data();
    if (
      user.role === "sales_rep" &&
      !permissionValue(settings, "allowSalesRepCreateReturns")
    ) {
      throw new HttpsError("permission-denied", "Sales returns are disabled.");
    }

    const requestedLines = source.items ?? input.items;
    const lines = normalizeReturnLines(originalInvoiceId, invoice.items, requestedLines);
    const currentAllocation = await readReturnedQuantities(
      transaction,
      firestore,
      companyId,
      originalInvoiceId,
      invoice,
    );
    const nextAllocation = {...currentAllocation};
    for (const line of lines) {
      const original = record((invoice.items as unknown[])[line.originalIndex]);
      const sold = roundQuantity(numberFrom(original, "quantity"));
      const prior = roundQuantity(nextAllocation[line.originalInvoiceItemId] ?? 0);
      if (line.returnedQuantity > roundQuantity(Math.max(sold - prior, 0))) {
        throw new HttpsError("failed-precondition", `Return exceeds sold quantity for line ${line.originalIndex + 1}.`);
      }
      nextAllocation[line.originalInvoiceItemId] = roundQuantity(prior + line.returnedQuantity);
    }
    const totals = returnTotals(lines);
    const customerId = requiredString(invoice.customerId, "customerId");
    const customerRef = firestore.doc(businessPath(companyId, "customers", customerId));
    const customerSnapshot = await transaction.get(customerRef);
    if (!customerSnapshot.exists) throw new HttpsError("not-found", "Customer was not found.");
    const customer = customerSnapshot.data() ?? {};
    if (customer.companyId !== companyId) {
      throw new HttpsError("data-loss", "Invoice customer belongs to another company.");
    }

    let returnNumber = optionalString(existing?.returnNumber);
    let counterWrite: PendingWrite | undefined;
    const returnDate = source.returnDate instanceof Timestamp
      ? source.returnDate
      : timestampFrom(source.returnDate ?? input.returnDate, "returnDate");
    if (!returnNumber) {
      const numberAllocation = await allocateDocumentNumber(
        transaction,
        firestore,
        companyId,
        "sales_returns",
        returnDate,
        documentPrefix(settings, "salesReturnPrefix", "RET"),
      );
      returnNumber = numberAllocation.number;
      counterWrite = {
        ref: numberAllocation.counterRef,
        data: numberAllocation.counterData,
        merge: true,
      };
    }

    const reason = optionalString(source.reason ?? input.reason);
    if (!reason || reason.length > 500) {
      throw new HttpsError("invalid-argument", "A valid return reason is required.");
    }
    const inventory = await buildReturnInventory(
      transaction,
      firestore,
      companyId,
      returnId,
      returnNumber,
      returnDate,
      invoice,
      lines,
      user,
      reason,
    );
    const requestedRefundType = optionalString(source.refundType ?? input.refundType);
    const refundType = requestedRefundType === "cash_refund" || requestedRefundType === "cashRefund"
      ? "cash_refund"
      : requestedRefundType === "credit_customer_balance" || requestedRefundType === "customerCredit"
        ? "credit_customer_balance"
        : "";
    if (!refundType) {
      throw new HttpsError("invalid-argument", "Refund type is invalid.");
    }
    const outstanding = roundMoney(Math.max(
      numberFrom(invoice, "remainingAmount") - numberFrom(invoice, "returnedReceivableAmount"),
      0,
    ));
    const receivableReduction = roundMoney(Math.min(totals.grandTotal, outstanding));
    const paidPortion = roundMoney(totals.grandTotal - receivableReduction);
    const cashRefundAmount = refundType === "cash_refund" ? paidPortion : 0;
    const customerCreditAmount = refundType === "credit_customer_balance" ? paidPortion : 0;
    const creditRef = firestore.doc(
      businessPath(companyId, "customer_transactions", `${returnId}_credit`),
    );
    const refundRef = firestore.doc(
      businessPath(companyId, "customer_transactions", `${returnId}_refund`),
    );
    const cashRef = firestore.doc(
      businessPath(companyId, "cash_movements", `${returnId}_cash_refund`),
    );
    const duplicateRefs = [creditRef];
    if (cashRefundAmount > 0) duplicateRefs.push(refundRef, cashRef);
    for (const ref of duplicateRefs) {
      if ((await transaction.get(ref)).exists) {
        throw new HttpsError("data-loss", "Sales return has partial posting records.");
      }
    }
    const refundSource = cashRefundAmount > 0
      ? await resolveRefundSource(
        transaction,
        firestore,
        companyId,
        invoice,
        cashRefundAmount,
      )
      : undefined;
    const cashBalance = cashRefundAmount > 0 && refundSource
      ? await applyCashChange(
        transaction,
        firestore,
        companyId,
        refundSource.account,
        refundSource.account === "rep_cash" ? refundSource.salesRepId : "",
        "out",
        cashRefundAmount,
        cashRef.id,
      )
      : undefined;

    const balanceBefore = roundMoney(numberFrom(customer, "currentBalance"));
    const balanceAfterCredit = roundMoney(balanceBefore - totals.grandTotal);
    const balanceAfter = roundMoney(
      balanceBefore - receivableReduction - customerCreditAmount,
    );
    const salesRepId = optionalString(invoice.salesRepId);
    const salesRepName = optionalString(invoice.salesRepName);
    transaction.update(customerRef, {
      currentBalance: balanceAfter,
      totalSales: roundMoney(Math.max(numberFrom(customer, "totalSales") - totals.grandTotal, 0)),
      totalPaid: roundMoney(Math.max(numberFrom(customer, "totalPaid") - cashRefundAmount, 0)),
      lastSalesReturnId: returnId,
      updatedAt: FieldValue.serverTimestamp(),
    });
    transaction.set(creditRef, returnLedgerData({
      id: creditRef.id,
      companyId,
      customer,
      invoice,
      returnId,
      returnNumber,
      returnDate,
      type: "return",
      debit: 0,
      credit: totals.grandTotal,
      balanceBefore,
      balanceAfter: balanceAfterCredit,
      user,
      salesRepId,
      salesRepName,
      notes: reason,
    }));
    if (cashRefundAmount > 0 && refundSource) {
      transaction.set(refundRef, returnLedgerData({
        id: refundRef.id,
        companyId,
        customer,
        invoice,
        returnId,
        returnNumber,
        returnDate,
        type: "refund",
        debit: cashRefundAmount,
        credit: 0,
        balanceBefore: balanceAfterCredit,
        balanceAfter,
        user,
        salesRepId,
        salesRepName,
        notes: reason,
      }));
      transaction.set(cashRef, {
        id: cashRef.id,
        companyId,
        movementType: "sales_return",
        type: "sales_return_cash_refund",
        direction: "out",
        amount: cashRefundAmount,
        cashAccount: refundSource.account,
        balanceBefore: cashBalance?.before ?? 0,
        balanceAfter: cashBalance?.after ?? 0,
        paymentType: refundType,
        customerId,
        customerName: optionalString(customer.name),
        referenceId: returnId,
        referenceNumber: returnNumber,
        sourceCollection: "sales_returns",
        sourceId: returnId,
        sourceNumber: returnNumber,
        originalCollectionSourceIds: refundSource.sourceMovementIds,
        date: returnDate,
        movementDate: returnDate,
        notes: optionalString(source.reason ?? input.reason),
        salesRepId: refundSource.salesRepId,
        salesRepName,
        createdByUid: user.uid,
        createdByName: user.name,
        createdByRole: user.role,
        createdAt: FieldValue.serverTimestamp(),
      });
    }
    for (const write of inventory.writes) {
      if (write.merge) transaction.set(write.ref, write.data, {merge: true});
      else transaction.set(write.ref, write.data);
    }
    if (counterWrite) {
      transaction.set(counterWrite.ref, counterWrite.data, {merge: true});
    }
    const allReturned = (invoice.items as unknown[]).every((raw, index) => {
      const original = record(raw);
      return roundQuantity(nextAllocation[`${originalInvoiceId}:${index}`] ?? 0) >=
        roundQuantity(numberFrom(original, "quantity"));
    });
    const returnIds = Array.isArray(invoice.returnInvoiceIds) ? invoice.returnInvoiceIds : [];
    transaction.update(invoiceRef, {
      returnedQuantitiesByItem: nextAllocation,
      lastSalesReturnId: returnId,
      returnStatus: allReturned ? "returned" : "partiallyReturned",
      returnedTotal: roundMoney(numberFrom(invoice, "returnedTotal") + totals.grandTotal),
      returnedSubtotal: roundMoney(numberFrom(invoice, "returnedSubtotal") + totals.subtotal),
      returnedDiscount: roundMoney(numberFrom(invoice, "returnedDiscount") + totals.totalDiscount),
      returnedTax: roundMoney(numberFrom(invoice, "returnedTax") + totals.totalTax),
      returnedReceivableAmount: roundMoney(
        numberFrom(invoice, "returnedReceivableAmount") + receivableReduction,
      ),
      customerCreditAmount: roundMoney(
        numberFrom(invoice, "customerCreditAmount") + customerCreditAmount,
      ),
      cashRefundAmount: roundMoney(numberFrom(invoice, "cashRefundAmount") + cashRefundAmount),
      returnInvoiceIds: [...returnIds, returnId],
      latestReturnAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
    const customerTransactionIds = cashRefundAmount > 0
      ? [creditRef.id, refundRef.id]
      : [creditRef.id];
    transaction.set(returnRef, {
      ...(existing ?? {}),
      id: returnId,
      companyId,
      returnNumber,
      returnInvoiceId: returnId,
      originalInvoiceId,
      originalInvoiceNumber: optionalString(invoice.invoiceNumber),
      originalPaymentType: optionalString(invoice.paymentType),
      searchKeywords: buildSearchKeywords([
        returnNumber,
        invoice.invoiceNumber,
        record(invoice.customerSnapshot).name,
        salesRepName,
      ]),
      originalInvoiceDate: invoice.invoiceDate,
      customerId,
      customerSnapshot: invoice.customerSnapshot,
      items: lines,
      subtotal: totals.subtotal,
      totalDiscount: totals.totalDiscount,
      totalTax: totals.totalTax,
      grandTotal: totals.grandTotal,
      receivableReduction,
      customerCreditAmount,
      cashRefundAmount,
      refundType,
      returnDate,
      reason,
      status: "confirmed",
      salesRepId,
      salesRepName,
      createdByUid: optionalString(existing?.createdByUid) || user.uid,
      createdByName: optionalString(existing?.createdByName) || user.name,
      createdByRole: optionalString(existing?.createdByRole) || user.role,
      financialPosted: true,
      inventoryPosted: true,
      financialPostedAt: FieldValue.serverTimestamp(),
      inventoryPostedAt: FieldValue.serverTimestamp(),
      stockMovementIds: inventory.movementIds,
      customerTransactionIds,
      cashMovementIds: cashRefundAmount > 0 ? [cashRef.id] : [],
      createdAt: existing?.createdAt ?? FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
    const ledgerEntries = buildSalesReturnFinancialLedgerEntries({
      companyId,
      returnId,
      returnNumber,
      returnDate,
      grandTotal: totals.grandTotal,
      cashRefundAmount,
      refundType,
      refundCashAccount: refundSource?.account ?? "",
      refundCashSalesRepId: refundSource?.salesRepId ?? "",
      customerId,
      customerName: optionalString(customer.name),
      salesRepId,
      salesRepName,
      quantity: roundQuantity(lines.reduce((sum, line) => sum + line.returnedQuantity, 0)),
      reason,
    });
    writeFinancialLedgerEntries(transaction, firestore, ledgerEntries);
    return {returnId, returnNumber, alreadyPosted: false};
  });
}

function normalizeReturnLines(
  invoiceId: string,
  rawInvoiceItems: unknown,
  rawReturnItems: unknown,
): ReturnLine[] {
  if (!Array.isArray(rawInvoiceItems) || !Array.isArray(rawReturnItems) || rawReturnItems.length === 0) {
    throw new HttpsError("invalid-argument", "Sales return items are required.");
  }
  const seen = new Set<string>();
  return rawReturnItems.map((raw, returnIndex) => {
    const requested = record(raw);
    const lineId = requiredString(requested.originalInvoiceItemId, `items[${returnIndex}].originalInvoiceItemId`);
    const prefix = `${invoiceId}:`;
    if (!lineId.startsWith(prefix) || seen.has(lineId)) {
      throw new HttpsError("invalid-argument", "Sales return line identity is invalid.");
    }
    seen.add(lineId);
    const originalIndex = Number(lineId.slice(prefix.length));
    if (!Number.isInteger(originalIndex) || originalIndex < 0 || originalIndex >= rawInvoiceItems.length) {
      throw new HttpsError("invalid-argument", "Sales return line does not exist.");
    }
    const original = record(rawInvoiceItems[originalIndex]);
    const soldQuantity = roundQuantity(numberFrom(original, "quantity"));
    const returnedQuantity = roundQuantity(numberFrom(requested, "returnedQuantity"));
    if (soldQuantity <= 0 || returnedQuantity <= 0) {
      throw new HttpsError("invalid-argument", "Sales return quantity is invalid.");
    }
    const discountPerUnit = roundMoney(numberFrom(original, "discount") / soldQuantity);
    const unitPrice = roundMoney(
      Math.max(numberFrom(original, "subtotal") - numberFrom(original, "discount"), 0) /
      soldQuantity,
    );
    const taxPercent = roundMoney(Math.min(Math.max(numberFrom(original, "taxPercent"), 0), 100));
    const subtotal = roundMoney(returnedQuantity * unitPrice);
    const taxAmount = roundMoney(subtotal * taxPercent / 100);
    return {
      originalInvoiceItemId: lineId,
      originalIndex,
      itemId: optionalString(original.itemId),
      itemName: optionalString(original.itemName),
      itemCode: optionalString(original.itemCode),
      unit: optionalString(original.unit),
      returnedQuantity,
      unitPrice,
      discountPerUnit,
      discountAmount: roundMoney(returnedQuantity * discountPerUnit),
      taxPercent,
      subtotal,
      taxAmount,
      total: roundMoney(subtotal + taxAmount),
    };
  });
}

function returnTotals(lines: ReturnLine[]) {
  return {
    subtotal: roundMoney(lines.reduce((sum, line) => sum + line.subtotal, 0)),
    totalDiscount: roundMoney(lines.reduce((sum, line) => sum + line.discountAmount, 0)),
    totalTax: roundMoney(lines.reduce((sum, line) => sum + line.taxAmount, 0)),
    grandTotal: roundMoney(lines.reduce((sum, line) => sum + line.total, 0)),
  };
}

async function readReturnedQuantities(
  transaction: Transaction,
  firestore: Firestore,
  companyId: string,
  invoiceId: string,
  invoice: DocumentData,
): Promise<Record<string, number>> {
  const stored = record(invoice.returnedQuantitiesByItem);
  const result: Record<string, number> = {};
  for (const [key, value] of Object.entries(stored)) {
    if (typeof value === "number" && Number.isFinite(value)) result[key] = roundQuantity(value);
  }
  if (Object.keys(result).length > 0) return result;
  const legacy = await transaction.get(
    firestore.collection(`companies/${companyId}/sales_returns`)
      .where("originalInvoiceId", "==", invoiceId)
      .where("status", "==", "confirmed"),
  );
  for (const document of legacy.docs) {
    const items = document.data().items;
    if (!Array.isArray(items)) continue;
    for (const raw of items) {
      const item = record(raw);
      const lineId = optionalString(item.originalInvoiceItemId);
      if (!lineId) continue;
      result[lineId] = roundQuantity(
        (result[lineId] ?? 0) + numberFrom(item, "returnedQuantity"),
      );
    }
  }
  return result;
}

async function buildReturnInventory(
  transaction: Transaction,
  firestore: Firestore,
  companyId: string,
  returnId: string,
  returnNumber: string,
  returnDate: Timestamp,
  invoice: DocumentData,
  lines: ReturnLine[],
  user: TrustedUser,
  notes: string,
): Promise<{writes: PendingWrite[]; movementIds: string[]}> {
  const sourceType = invoice.stockSourceType === "salesRep" ? "salesRep" : "companyWarehouse";
  const sourceRepId = sourceType === "salesRep"
    ? requiredString(invoice.stockSourceSalesRepId, "stockSourceSalesRepId")
    : "";
  const originalMovementIds = Array.isArray(invoice.inventoryMovementIds)
    ? invoice.inventoryMovementIds.filter((value): value is string => typeof value === "string")
    : [];
  const originalMovements: DocumentData[] = [];
  const movementCollection = sourceType === "salesRep"
    ? "rep_inventory_movements"
    : "stock_movements";
  for (const id of originalMovementIds) {
    const snapshot = await transaction.get(
      firestore.doc(businessPath(companyId, movementCollection, id)),
    );
    if (snapshot.exists) originalMovements.push(snapshot.data() ?? {});
  }
  const writes: PendingWrite[] = [];
  const movementIds: string[] = [];
  const running = new Map<string, number>();
  const finalWrites = new Map<string, PendingWrite>();
  const balanceCreatedAt = new Map<string, unknown>();
  for (const line of lines) {
    if (!line.itemId || line.itemId.startsWith("manual-")) continue;
    const originalSourceLineId = `${invoice.id}_line_${String(line.originalIndex).padStart(3, "0")}`;
    const wasTracked = originalMovements.some((movement) =>
      movement.itemId === line.itemId &&
      (!movement.sourceLineId || movement.sourceLineId === originalSourceLineId),
    );
    if (!wasTracked) continue;
    const itemRef = firestore.doc(`items/${line.itemId}`);
    const itemSnapshot = await transaction.get(itemRef);
    if (!itemSnapshot.exists) {
      throw new HttpsError("failed-precondition", `Return item ${line.itemId} is missing.`);
    }
    const item = itemSnapshot.data() ?? {};
    if (item.deleted === true || item.active !== true || item.id !== line.itemId) {
      throw new HttpsError("failed-precondition", `Return item ${line.itemId} is not eligible.`);
    }
    const sourceLineId = line.originalInvoiceItemId;
    if (sourceType === "salesRep") {
      const balanceId = `${sourceRepId}_${line.itemId}`;
      const balanceRef = firestore.doc(
        businessPath(companyId, "rep_inventory_balances", balanceId),
      );
      let before = running.get(balanceId);
      let createdAt: unknown;
      if (before === undefined) {
        const balance = await transaction.get(balanceRef);
        before = roundQuantity(numberFrom(balance.data() ?? {}, "quantity"));
        createdAt = balance.data()?.createdAt;
        balanceCreatedAt.set(balanceId, createdAt);
      }
      const after = roundQuantity(before + line.returnedQuantity);
      running.set(balanceId, after);
      const movementId = `${returnId}_line_${line.originalIndex}_${sourceRepId}_${line.itemId}_sales_return`;
      const movementRef = firestore.doc(
        businessPath(companyId, "rep_inventory_movements", movementId),
      );
      if ((await transaction.get(movementRef)).exists) {
        throw new HttpsError("data-loss", "Return inventory movement already exists.");
      }
      movementIds.push(movementId);
      writes.push({ref: movementRef, data: {
        id: movementId,
        companyId,
        salesRepId: sourceRepId,
        salesRepNameSnapshot: optionalString(invoice.salesRepName),
        itemId: line.itemId,
        modelSnapshot: optionalString(item.code),
        itemNameSnapshot: optionalString(item.name),
        unitSnapshot: optionalString(item.unit),
        direction: "in",
        quantity: line.returnedQuantity,
        quantityBefore: before,
        quantityAfter: after,
        reason: "salesReturn",
        referenceType: "salesReturn",
        referenceId: returnId,
        referenceNumber: returnNumber,
        sourceLineId,
        sourceLineIndex: line.originalIndex,
        transferType: "",
        createdByUid: user.uid,
        createdByName: user.name,
        createdAt: FieldValue.serverTimestamp(),
      }});
      finalWrites.set(balanceId, {ref: balanceRef, merge: true, data: {
        id: balanceId,
        companyId,
        salesRepId: sourceRepId,
        itemId: line.itemId,
        quantity: after,
        modelSnapshot: optionalString(item.code),
        itemNameSnapshot: optionalString(item.name),
        unitSnapshot: optionalString(item.unit),
        createdAt: balanceCreatedAt.get(balanceId) ?? FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
        lastMovementId: movementId,
        lastReferenceType: "salesReturn",
        lastReferenceId: returnId,
      }});
      continue;
    }
    let before = running.get(line.itemId);
    if (before === undefined) before = roundQuantity(numberFrom(item, "currentStock"));
    const after = roundQuantity(before + line.returnedQuantity);
    running.set(line.itemId, after);
    const movementId = `${returnId}_line_${line.originalIndex}_${line.itemId}_sales_return`;
    const movementRef = firestore.doc(businessPath(companyId, "stock_movements", movementId));
    if ((await transaction.get(movementRef)).exists) {
      throw new HttpsError("data-loss", "Return inventory movement already exists.");
    }
    movementIds.push(movementId);
    writes.push({ref: movementRef, data: {
      id: movementId,
      companyId,
      warehouseId: optionalString(item.warehouseId) || "default_warehouse",
      itemId: line.itemId,
      itemName: optionalString(item.name),
      itemCode: optionalString(item.code),
      movementType: "sales_return",
      direction: "in",
      quantity: line.returnedQuantity,
      quantityBefore: before,
      quantityAfter: after,
      referenceType: "sales_return",
      referenceId: returnId,
      referenceNumber: returnNumber,
      sourceLineId,
      sourceLineIndex: line.originalIndex,
      movementDate: returnDate,
      notes,
      createdByUid: user.uid,
      createdByName: user.name,
      createdByRole: user.role,
      createdAt: FieldValue.serverTimestamp(),
    }});
    finalWrites.set(line.itemId, {ref: itemRef, merge: true, data: {
      currentStock: after,
      inventoryUpdatedAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    }});
  }
  writes.push(...finalWrites.values());
  return {writes, movementIds};
}

async function resolveRefundSource(
  transaction: Transaction,
  firestore: Firestore,
  companyId: string,
  invoice: DocumentData,
  requestedRefund: number,
): Promise<{account: CashAccount; salesRepId: string; sourceMovementIds: string[]}> {
  const sources = new Map<string, {
    account: CashAccount;
    salesRepId: string;
    ids: string[];
    collectedAmount: number;
  }>();
  const invoiceId = requiredString(invoice.id, "invoice.id");
  const direct = await transaction.get(
    firestore.doc(businessPath(companyId, "cash_movements", `${invoiceId}_cash`)),
  );
  if (direct.exists) {
    const directData = direct.data() ?? {};
    addRefundSource(
      sources,
      direct.id,
      directData,
      roundMoney(numberFrom(directData, "amount")),
    );
  }
  const receiptIds = Array.isArray(invoice.receiptIds)
    ? invoice.receiptIds.filter((value): value is string => typeof value === "string")
    : [];
  for (const receiptId of receiptIds) {
    const receipt = await transaction.get(
      firestore.doc(businessPath(companyId, "receipts", receiptId)),
    );
    const receiptData = receipt.data() ?? {};
    const allocations = record(receiptData.invoiceAllocations);
    const allocatedAmount = roundMoney(numberFrom(allocations, invoiceId));
    if (allocatedAmount <= 0 || receiptData.paymentMethod !== "cash") continue;
    const movementIds = Array.isArray(receiptData.cashMovementIds)
      ? receiptData.cashMovementIds.filter((value): value is string => typeof value === "string")
      : [];
    for (const movementId of movementIds) {
      const movement = await transaction.get(
        firestore.doc(businessPath(companyId, "cash_movements", movementId)),
      );
      if (movement.exists) {
        addRefundSource(
          sources,
          movement.id,
          movement.data() ?? {},
          allocatedAmount,
        );
      }
    }
  }
  if (sources.size !== 1) {
    throw new HttpsError(
      "failed-precondition",
      sources.size === 0
        ? "No verified cash collection source exists for this refund."
        : "Cash refund spans multiple collection accounts; use customer credit.",
    );
  }
  const source = [...sources.values()][0];
  const previousReturns = await transaction.get(
    firestore.collection(`companies/${companyId}/sales_returns`)
      .where("originalInvoiceId", "==", invoiceId)
      .where("status", "==", "confirmed"),
  );
  const alreadyRefunded = roundMoney(previousReturns.docs.reduce(
    (sum, document) => sum + numberFrom(document.data(), "cashRefundAmount"),
    0,
  ));
  const refundableCash = roundMoney(Math.max(source.collectedAmount - alreadyRefunded, 0));
  if (requestedRefund > refundableCash) {
    throw new HttpsError(
      "failed-precondition",
      "Cash refund exceeds verified cash collected for this invoice.",
    );
  }
  return {account: source.account, salesRepId: source.salesRepId, sourceMovementIds: source.ids};
}

function addRefundSource(
  sources: Map<string, {
    account: CashAccount;
    salesRepId: string;
    ids: string[];
    collectedAmount: number;
  }>,
  movementId: string,
  movement: DocumentData,
  collectedAmount: number,
): void {
  const account = movement.cashAccount === "rep_cash" ? "rep_cash" : "company_cash";
  const salesRepId = account === "rep_cash" ? optionalString(movement.salesRepId) : "";
  if (account === "rep_cash" && !salesRepId) {
    throw new HttpsError("data-loss", "Cash collection source has no representative.");
  }
  const key = `${account}:${salesRepId}`;
  const existing = sources.get(key) ?? {
    account,
    salesRepId,
    ids: [],
    collectedAmount: 0,
  };
  existing.ids.push(movementId);
  existing.collectedAmount = roundMoney(existing.collectedAmount + collectedAmount);
  sources.set(key, existing);
}

function returnLedgerData(input: {
  id: string;
  companyId: string;
  customer: DocumentData;
  invoice: DocumentData;
  returnId: string;
  returnNumber: string;
  returnDate: Timestamp;
  type: "return" | "refund";
  debit: number;
  credit: number;
  balanceBefore: number;
  balanceAfter: number;
  user: TrustedUser;
  salesRepId: string;
  salesRepName: string;
  notes: string;
}): DocumentData {
  const amount = input.debit || input.credit;
  return {
    id: input.id,
    companyId: input.companyId,
    customerId: input.customer.id,
    customerName: optionalString(input.customer.name),
    transactionType: input.type,
    type: input.type,
    referenceId: input.returnId,
    returnInvoiceId: input.returnId,
    returnNumber: input.returnNumber,
    originalInvoiceId: input.invoice.id,
    originalInvoiceNumber: optionalString(input.invoice.invoiceNumber),
    sourceCollection: "sales_returns",
    sourceId: input.returnId,
    sourceNumber: input.returnNumber,
    transactionDate: input.returnDate,
    debitAmount: input.debit,
    creditAmount: input.credit,
    amount,
    signedAmount: input.debit > 0 ? amount : -amount,
    balanceBefore: input.balanceBefore,
    balanceAfter: input.balanceAfter,
    notes: input.notes,
    createdByUid: input.user.uid,
    createdByName: input.user.name,
    createdByRole: input.user.role,
    salesRepId: input.salesRepId,
    salesRepName: input.salesRepName,
    createdAt: FieldValue.serverTimestamp(),
  };
}
