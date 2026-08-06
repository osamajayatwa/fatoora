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
  businessPath,
  numberFrom,
  optionalString,
  permissionValue,
  record,
  requireCallableUid,
  requireDocumentAccess,
  requireTrustedUser,
  requiredString,
  roundMoney,
  roundQuantity,
} from "./common";
import {applyCashChange, CashAccount} from "./cash_ledger";
import {
  TrustedInvoiceLine,
  calculateInvoiceTotals,
  calculatePayment,
} from "./totals";

interface InvoiceRequest {
  companyId?: unknown;
  invoiceId?: unknown;
}

interface PendingWrite {
  ref: DocumentReference;
  data: DocumentData;
  merge?: boolean;
}

interface CatalogLine {
  line: TrustedInvoiceLine;
  index: number;
  item?: DocumentData;
  itemRef?: DocumentReference;
}

export const confirmInvoice = onCall(TRUSTED_CALLABLE_OPTIONS, async (request) => {
  const uid = requireCallableUid(request, "confirmInvoice");
  const input = record(request.data) as InvoiceRequest;
  const companyId = requiredString(input.companyId, "companyId");
  const invoiceId = requiredString(input.invoiceId, "invoiceId");
  const result = await confirmInvoiceTransaction(
    getFirestore(),
    uid,
    companyId,
    invoiceId,
  );
  return result;
});

export async function confirmInvoiceTransaction(
  firestore: Firestore,
  uid: string | undefined,
  companyId: string,
  invoiceId: string,
): Promise<{invoiceId: string; alreadyPosted: boolean}> {
  return firestore.runTransaction(async (transaction) => {
    const user = await requireTrustedUser(transaction, firestore, uid, companyId);
    const invoiceRef = firestore.doc(businessPath(companyId, "invoices", invoiceId));
    const invoiceSnapshot = await transaction.get(invoiceRef);
    if (!invoiceSnapshot.exists) {
      throw new HttpsError("not-found", "Invoice was not found.");
    }
    const invoice = invoiceSnapshot.data() ?? {};
    requireDocumentAccess(user, invoice);
    if (
      invoice.invoiceStatus === "confirmed" &&
      invoice.financialPosted === true &&
      invoice.inventoryPosted === true
    ) {
      return {invoiceId, alreadyPosted: true};
    }
    if (
      invoice.invoiceStatus !== "draft" ||
      invoice.financialPosted === true ||
      invoice.inventoryPosted === true ||
      invoice.isLocked === true
    ) {
      throw new HttpsError("failed-precondition", "Invoice is not an editable draft.");
    }

    const customerId = requiredString(invoice.customerId, "customerId");
    const customerRef = firestore.doc(businessPath(companyId, "customers", customerId));
    const customerSnapshot = await transaction.get(customerRef);
    if (!customerSnapshot.exists) {
      throw new HttpsError("not-found", "Customer was not found.");
    }
    const customer = customerSnapshot.data() ?? {};
    if (customer.companyId !== companyId || customer.active !== true) {
      throw new HttpsError("failed-precondition", "Customer is inactive or invalid.");
    }
    if (user.role === "sales_rep" && customer.createdByUid !== user.uid) {
      throw new HttpsError("permission-denied", "Customer is not owned by this representative.");
    }

    const settingsSnapshot = await transaction.get(
      firestore.doc(businessPath(companyId, "settings", "app")),
    );
    const settings = settingsSnapshot.data();
    const canDiscount = user.role === "admin" || permissionValue(
      settings,
      "allowSalesRepDiscount",
    );
    const canEditPrice = user.role === "admin" || permissionValue(
      settings,
      "allowSalesRepPriceEdit",
    );
    const totals = calculateInvoiceTotals(invoice.items);
    const catalogLines: CatalogLine[] = [];
    for (let index = 0; index < totals.items.length; index += 1) {
      const line = totals.items[index];
      if (!canDiscount && line.discount !== 0) {
        throw new HttpsError("permission-denied", "Discount permission is required.");
      }
      if (!line.itemId || line.itemId.startsWith("manual-")) {
        if (!canEditPrice || !line.itemName) {
          throw new HttpsError("permission-denied", "Manual invoice line is not permitted.");
        }
        catalogLines.push({line, index});
        continue;
      }
      const itemRef = firestore.doc(`items/${line.itemId}`);
      const itemSnapshot = await transaction.get(itemRef);
      if (!itemSnapshot.exists) {
        throw new HttpsError("failed-precondition", `Invoice item ${line.itemId} is missing.`);
      }
      const item = itemSnapshot.data() ?? {};
      if (
        item.id !== line.itemId ||
        item.deleted === true ||
        item.active !== true ||
        !optionalString(item.name)
      ) {
        throw new HttpsError("failed-precondition", `Invoice item ${line.itemId} is not eligible.`);
      }
      if (!canEditPrice && Math.abs(numberFrom(item, "price") - line.unitPrice) > 0.0005) {
        throw new HttpsError("permission-denied", "Catalog price editing is disabled.");
      }
      catalogLines.push({
        index,
        line: {
          ...line,
          itemName: optionalString(item.name),
          itemCode: optionalString(item.code),
          unit: optionalString(item.unit),
        },
        item,
        itemRef,
      });
    }

    const normalizedItems = catalogLines.map((entry) => entry.line);
    const normalizedTotals = calculateInvoiceTotals(normalizedItems);
    const hasReceivedPayment = invoice.hasReceivedPayment === true;
    const payment = calculatePayment(
      normalizedTotals.grandTotal,
      hasReceivedPayment,
      invoice.paidAmount,
    );
    const invoiceNumber = requiredString(invoice.invoiceNumber, "invoiceNumber");
    const invoiceDate = invoice.invoiceDate instanceof Timestamp
      ? invoice.invoiceDate
      : Timestamp.now();
    const salesRepId = requiredString(invoice.salesRepId, "salesRepId");
    if (user.role === "sales_rep" && salesRepId !== user.uid) {
      throw new HttpsError("permission-denied", "Invoice belongs to another representative.");
    }
    const salesRepName = optionalString(invoice.salesRepName) || user.name;
    const sourceType = invoice.stockSourceType === "salesRep"
      ? "salesRep"
      : "companyWarehouse";
    const sourceRepId = sourceType === "salesRep"
      ? requiredString(invoice.stockSourceSalesRepId, "stockSourceSalesRepId")
      : "";
    if (sourceType === "salesRep" && sourceRepId !== salesRepId) {
      throw new HttpsError("failed-precondition", "Invoice inventory source is invalid.");
    }

    const inventory = await buildInvoiceInventory(
      transaction,
      firestore,
      companyId,
      invoiceId,
      invoiceNumber,
      invoiceDate,
      sourceType,
      sourceRepId,
      salesRepName,
      user,
      catalogLines,
      optionalString(invoice.notes),
    );
    const debitRef = firestore.doc(
      businessPath(companyId, "customer_transactions", `${invoiceId}_debit`),
    );
    const paymentRef = firestore.doc(
      businessPath(companyId, "customer_transactions", `${invoiceId}_payment`),
    );
    const cashRef = firestore.doc(
      businessPath(companyId, "cash_movements", `${invoiceId}_cash`),
    );
    const duplicateRefs = [debitRef];
    if (payment.paidAmount > 0) duplicateRefs.push(paymentRef, cashRef);
    for (const ref of duplicateRefs) {
      if ((await transaction.get(ref)).exists) {
        throw new HttpsError("failed-precondition", "Invoice has partial posting records.");
      }
    }

    const customerBalanceBefore = roundMoney(numberFrom(customer, "currentBalance"));
    const debitBalance = roundMoney(customerBalanceBefore + normalizedTotals.grandTotal);
    const finalBalance = roundMoney(debitBalance - payment.paidAmount);
    const cashAccount: CashAccount = invoice.createdByRole === "sales_rep"
      ? "rep_cash"
      : "company_cash";
    const cashBalance = payment.paidAmount > 0
      ? await applyCashChange(
        transaction,
        firestore,
        companyId,
        cashAccount,
        cashAccount === "rep_cash" ? salesRepId : "",
        "in",
        payment.paidAmount,
        cashRef.id,
      )
      : undefined;

    const transactionIds = [debitRef.id];
    if (payment.paidAmount > 0) transactionIds.push(paymentRef.id);
    transaction.update(customerRef, {
      currentBalance: finalBalance,
      totalSales: roundMoney(numberFrom(customer, "totalSales") + normalizedTotals.grandTotal),
      totalPaid: roundMoney(numberFrom(customer, "totalPaid") + payment.paidAmount),
      updatedAt: FieldValue.serverTimestamp(),
    });
    transaction.set(debitRef, customerTransactionData({
      id: debitRef.id,
      companyId,
      customer,
      invoiceId,
      invoiceNumber,
      invoiceDate,
      type: "invoice",
      debitAmount: normalizedTotals.grandTotal,
      creditAmount: 0,
      balanceBefore: customerBalanceBefore,
      balanceAfter: debitBalance,
      invoice,
      salesRepId,
      salesRepName,
    }));
    if (payment.paidAmount > 0) {
      transaction.set(paymentRef, customerTransactionData({
        id: paymentRef.id,
        companyId,
        customer,
        invoiceId,
        invoiceNumber,
        invoiceDate,
        type: "payment",
        debitAmount: 0,
        creditAmount: payment.paidAmount,
        balanceBefore: debitBalance,
        balanceAfter: finalBalance,
        invoice,
        salesRepId,
        salesRepName,
      }));
      transaction.set(cashRef, {
        id: cashRef.id,
        companyId,
        movementType: "invoice_payment",
        type: payment.paymentType === "partial" ? "invoice_partial" : "invoice_cash",
        direction: "in",
        amount: payment.paidAmount,
        cashAccount,
        balanceBefore: cashBalance?.before ?? 0,
        balanceAfter: cashBalance?.after ?? payment.paidAmount,
        paymentType: payment.paymentType,
        customerId,
        customerName: optionalString(customer.name),
        referenceId: invoiceId,
        referenceNumber: invoiceNumber,
        sourceCollection: "invoices",
        sourceId: invoiceId,
        sourceNumber: invoiceNumber,
        date: invoiceDate,
        movementDate: invoiceDate,
        notes: optionalString(invoice.notes),
        salesRepId,
        salesRepName,
        createdByUid: optionalString(invoice.createdByUid) || user.uid,
        createdByName: optionalString(invoice.createdByName) || user.name,
        createdByRole: optionalString(invoice.createdByRole) || user.role,
        createdAt: FieldValue.serverTimestamp(),
      });
    }
    for (const write of inventory.writes) {
      if (write.merge) {
        transaction.set(write.ref, write.data, {merge: true});
      } else {
        transaction.set(write.ref, write.data);
      }
    }
    transaction.update(invoiceRef, {
      items: normalizedTotals.items,
      subtotal: normalizedTotals.subtotal,
      totalDiscount: normalizedTotals.totalDiscount,
      totalTax: normalizedTotals.totalTax,
      grandTotal: normalizedTotals.grandTotal,
      paidAmount: payment.paidAmount,
      remainingAmount: payment.remainingAmount,
      paymentType: payment.paymentType,
      paymentMethod: payment.paymentType,
      paymentStatus: payment.paymentStatus,
      hasReceivedPayment: payment.paidAmount > 0,
      invoiceStatus: "confirmed",
      isLocked: true,
      financialPosted: true,
      financialPostedAt: FieldValue.serverTimestamp(),
      financialPostedByUid: user.uid,
      financialPostedByName: user.name,
      customerTransactionIds: transactionIds,
      cashMovementIds: payment.paidAmount > 0 ? [cashRef.id] : [],
      inventoryPosted: true,
      inventoryPostedAt: FieldValue.serverTimestamp(),
      inventoryPostedByUid: user.uid,
      inventoryPostedByName: user.name,
      inventoryMovementIds: inventory.movementIds,
      updatedAt: FieldValue.serverTimestamp(),
    });
    return {invoiceId, alreadyPosted: false};
  });
}

async function buildInvoiceInventory(
  transaction: Transaction,
  firestore: Firestore,
  companyId: string,
  invoiceId: string,
  invoiceNumber: string,
  invoiceDate: Timestamp,
  sourceType: string,
  sourceRepId: string,
  salesRepName: string,
  user: TrustedUser,
  catalogLines: CatalogLine[],
  notes: string,
): Promise<{writes: PendingWrite[]; movementIds: string[]}> {
  const writes: PendingWrite[] = [];
  const movementIds: string[] = [];
  const running = new Map<string, number>();
  const finalItemWrites = new Map<string, PendingWrite>();
  const finalBalanceWrites = new Map<string, PendingWrite>();
  const balanceCreatedAt = new Map<string, unknown>();

  for (const entry of catalogLines) {
    if (!entry.item || !entry.itemRef || entry.item.trackStock !== true) continue;
    const itemId = entry.line.itemId;
    const quantity = roundQuantity(entry.line.quantity);
    const sourceLineId = `${invoiceId}_line_${String(entry.index).padStart(3, "0")}`;
    if (sourceType === "salesRep") {
      const balanceId = `${sourceRepId}_${itemId}`;
      const balanceRef = firestore.doc(
        businessPath(companyId, "rep_inventory_balances", balanceId),
      );
      let before = running.get(balanceId);
      let balanceData: DocumentData | undefined;
      if (before === undefined) {
        const balanceSnapshot = await transaction.get(balanceRef);
        balanceData = balanceSnapshot.data();
        balanceCreatedAt.set(balanceId, balanceData?.createdAt);
        before = roundQuantity(numberFrom(balanceData ?? {}, "quantity"));
      }
      const after = roundQuantity(before - quantity);
      if (after < 0) {
        throw new HttpsError("failed-precondition", `Insufficient representative stock for ${itemId}.`);
      }
      running.set(balanceId, after);
      const movementId = `${sourceLineId}_${sourceRepId}_${itemId}_invoice_sale`;
      const movementRef = firestore.doc(
        businessPath(companyId, "rep_inventory_movements", movementId),
      );
      if ((await transaction.get(movementRef)).exists) {
        throw new HttpsError("failed-precondition", "Inventory movement already exists.");
      }
      movementIds.push(movementId);
      writes.push({ref: movementRef, data: {
        id: movementId,
        companyId,
        salesRepId: sourceRepId,
        salesRepNameSnapshot: salesRepName,
        itemId,
        modelSnapshot: optionalString(entry.item.code),
        itemNameSnapshot: optionalString(entry.item.name),
        unitSnapshot: optionalString(entry.item.unit),
        direction: "out",
        quantity,
        quantityBefore: before,
        quantityAfter: after,
        reason: "invoiceSale",
        referenceType: "invoice",
        referenceId: invoiceId,
        referenceNumber: invoiceNumber,
        sourceLineId,
        sourceLineIndex: entry.index,
        transferType: "",
        createdByUid: user.uid,
        createdByName: user.name,
        createdAt: FieldValue.serverTimestamp(),
      }});
      finalBalanceWrites.set(balanceId, {ref: balanceRef, merge: true, data: {
        id: balanceId,
        companyId,
        salesRepId: sourceRepId,
        itemId,
        quantity: after,
        modelSnapshot: optionalString(entry.item.code),
        itemNameSnapshot: optionalString(entry.item.name),
        unitSnapshot: optionalString(entry.item.unit),
        createdAt: balanceCreatedAt.get(balanceId) ?? FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
        lastMovementId: movementId,
        lastReferenceType: "invoice",
        lastReferenceId: invoiceId,
      }});
      continue;
    }

    let before = running.get(itemId);
    if (before === undefined) before = roundQuantity(numberFrom(entry.item, "currentStock"));
    const after = roundQuantity(before - quantity);
    if (after < 0) {
      throw new HttpsError("failed-precondition", `Insufficient warehouse stock for ${itemId}.`);
    }
    running.set(itemId, after);
    const movementId = `${sourceLineId}_${itemId}_invoice_sale`;
    const movementRef = firestore.doc(
      businessPath(companyId, "stock_movements", movementId),
    );
    if ((await transaction.get(movementRef)).exists) {
      throw new HttpsError("failed-precondition", "Inventory movement already exists.");
    }
    movementIds.push(movementId);
    writes.push({ref: movementRef, data: {
      id: movementId,
      companyId,
      warehouseId: optionalString(entry.item.warehouseId) || "default_warehouse",
      itemId,
      itemName: optionalString(entry.item.name),
      itemCode: optionalString(entry.item.code),
      movementType: "invoice_sale",
      direction: "out",
      quantity,
      quantityBefore: before,
      quantityAfter: after,
      referenceType: "invoice",
      referenceId: invoiceId,
      referenceNumber: invoiceNumber,
      sourceLineId,
      sourceLineIndex: entry.index,
      movementDate: invoiceDate,
      notes,
      createdByUid: user.uid,
      createdByName: user.name,
      createdByRole: user.role,
      createdAt: FieldValue.serverTimestamp(),
    }});
    finalItemWrites.set(itemId, {ref: entry.itemRef, merge: true, data: {
      currentStock: after,
      inventoryUpdatedAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    }});
  }
  writes.push(...finalItemWrites.values(), ...finalBalanceWrites.values());
  return {writes, movementIds};
}

function customerTransactionData(input: {
  id: string;
  companyId: string;
  customer: DocumentData;
  invoiceId: string;
  invoiceNumber: string;
  invoiceDate: Timestamp;
  type: "invoice" | "payment";
  debitAmount: number;
  creditAmount: number;
  balanceBefore: number;
  balanceAfter: number;
  invoice: DocumentData;
  salesRepId: string;
  salesRepName: string;
}): DocumentData {
  const amount = input.debitAmount || input.creditAmount;
  return {
    id: input.id,
    companyId: input.companyId,
    customerId: input.customer.id,
    customerName: optionalString(input.customer.name),
    transactionType: input.type,
    type: input.type,
    referenceId: input.invoiceId,
    invoiceId: input.invoiceId,
    invoiceNumber: input.invoiceNumber,
    sourceCollection: "invoices",
    sourceId: input.invoiceId,
    sourceNumber: input.invoiceNumber,
    transactionDate: input.invoiceDate,
    debitAmount: input.debitAmount,
    creditAmount: input.creditAmount,
    amount,
    signedAmount: input.debitAmount > 0 ? amount : -amount,
    balanceBefore: input.balanceBefore,
    balanceAfter: input.balanceAfter,
    notes: optionalString(input.invoice.notes),
    createdByUid: optionalString(input.invoice.createdByUid),
    createdByName: optionalString(input.invoice.createdByName),
    createdByRole: optionalString(input.invoice.createdByRole),
    salesRepId: input.salesRepId,
    salesRepName: input.salesRepName,
    createdAt: FieldValue.serverTimestamp(),
  };
}
