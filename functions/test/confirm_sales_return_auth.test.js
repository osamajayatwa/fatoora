const assert = require("node:assert/strict");
const {readFileSync} = require("node:fs");
const {join} = require("node:path");
const {after, before, test} = require("node:test");

const {deleteApp, initializeApp} = require("firebase-admin/app");
const {Timestamp, getFirestore} = require("firebase-admin/firestore");

const {
  confirmInvoice,
} = require("../lib/trusted/confirm_invoice");
const {
  confirmSalesReturn,
} = require("../lib/trusted/confirm_sales_return");
const {
  createReceipt,
} = require("../lib/trusted/create_receipt");
const {
  approveExpense,
  createExpense,
} = require("../lib/trusted/expenses");
const {
  createCustomer,
  updateCustomer,
} = require("../lib/trusted/customer_profiles");
const {
  createItem,
} = require("../lib/trusted/inventory");
const {
  postCustomerOpeningBalance,
} = require("../lib/trusted/post_opening_balance");
const {
  recordCashSettlement,
} = require("../lib/trusted/record_cash_settlement");

const projectId = "fatoora-return-auth-test";
const app = initializeApp({projectId});
const db = getFirestore(app);
const now = Timestamp.fromDate(new Date("2026-08-06T00:00:00.000Z"));

before(() => {
  if (!process.env.FIRESTORE_EMULATOR_HOST) {
    throw new Error("Sales-return auth tests require the Firestore emulator.");
  }
});

after(async () => {
  await deleteApp(app);
});

test("all trusted callables use the same v2 authentication pathway and options", async () => {
  const callables = [
    approveExpense,
    confirmInvoice,
    confirmSalesReturn,
    createCustomer,
    createExpense,
    createItem,
    createReceipt,
    postCustomerOpeningBalance,
    recordCashSettlement,
    updateCustomer,
  ];
  for (const callable of callables) {
    assert.deepEqual(callable.__endpoint, confirmInvoice.__endpoint);
    await assert.rejects(
      callable.run({
        auth: undefined,
        data: {companyId: "auth-path-company", invoiceId: "invoice", returnId: "return"},
      }),
      (error) => error.code === "unauthenticated",
    );
  }

  const trustedSources = [
    "confirm_invoice.ts",
    "confirm_sales_return.ts",
    "create_receipt.ts",
    "customer_profiles.ts",
    "expenses.ts",
    "inventory.ts",
    "post_opening_balance.ts",
    "record_cash_settlement.ts",
  ].map((fileName) => readFileSync(
    join(__dirname, "..", "src", "trusted", fileName),
    "utf8",
  ));
  for (const source of trustedSources) {
    assert.match(source, /requireCallableUid\(request,/);
    assert.doesNotMatch(source, /context\.auth|\(data,\s*context\)/);
  }
  const commonSource = readFileSync(
    join(__dirname, "..", "src", "trusted", "common.ts"),
    "utf8",
  );
  assert.match(commonSource, /invoker:\s*"public"/);
});

test("unauthenticated receipt and expense calls create no effects", async () => {
  const companyId = "callable-auth-no-effects";
  const invocations = [
    () => createReceipt.run({
      auth: undefined,
      data: {
        companyId,
        idempotencyKey: "receipt_auth_failure",
        customerId: "customer",
        amount: 5,
        paymentMethod: "cash",
        receiptDate: now,
      },
    }),
    () => createExpense.run({
      auth: undefined,
      data: {
        companyId,
        idempotencyKey: "expense_auth_failure",
        amount: 5,
        expenseDate: now,
        category: "office",
        fundingSource: "company_cash",
      },
    }),
  ];
  for (const invocation of invocations) {
    await assert.rejects(invocation, (error) => error.code === "unauthenticated");
  }
  for (const collection of [
    "receipts",
    "expenses",
    "customer_transactions",
    "cash_movements",
  ]) {
    const snapshot = await db.collection(
      `companies/${companyId}/${collection}`,
    ).get();
    assert.equal(snapshot.size, 0, collection);
  }
});

test("authenticated admin confirms a valid sales return", async () => {
  const fixture = await seedReturnFixture({
    suffix: "admin",
    role: "admin",
  });
  const result = await invokeReturn(fixture, fixture.uid, "admin-return");

  assert.equal(result.returnId, "admin-return");
  assert.equal((await fixture.returnRef("admin-return").get()).data().status, "confirmed");
  assert.equal((await fixture.itemRef.get()).data().currentStock, 10);
  assert.equal((await fixture.customerRef.get()).data().currentBalance, 0);
});

test("authenticated sales representative confirms an allowed sales return", async () => {
  const fixture = await seedReturnFixture({
    suffix: "representative",
    role: "sales_rep",
    allowSalesRepCreateReturns: true,
  });
  const result = await invokeReturn(fixture, fixture.uid, "representative-return");

  assert.equal(result.returnId, "representative-return");
  assert.equal((await fixture.returnRef("representative-return").get()).data().status, "confirmed");
  assert.equal((await fixture.itemRef.get()).data().currentStock, 10);
});

test("unauthenticated return fails before any business effects", async () => {
  const fixture = await seedReturnFixture({
    suffix: "unauthenticated",
    role: "admin",
  });
  const before = await readEffects(fixture);

  await assert.rejects(
    invokeReturn(fixture, undefined, "unauthenticated-return"),
    (error) => error.code === "unauthenticated",
  );

  const afterEffects = await readEffects(fixture);
  assert.deepEqual(afterEffects, before);
  assert.equal((await fixture.returnRef("unauthenticated-return").get()).exists, false);
});

test("disabled, pending, and unauthorized users are rejected", async () => {
  const disabledFixture = await seedReturnFixture({
    suffix: "disabled-permission",
    role: "sales_rep",
    allowSalesRepCreateReturns: false,
  });
  await assert.rejects(
    invokeReturn(disabledFixture, disabledFixture.uid, "disabled-permission-return"),
    (error) => error.code === "permission-denied",
  );

  const pendingFixture = await seedReturnFixture({
    suffix: "pending",
    role: "sales_rep",
    userOverrides: {approvalStatus: "pending"},
  });
  await assert.rejects(
    invokeReturn(pendingFixture, pendingFixture.uid, "pending-return"),
    (error) => error.code === "permission-denied",
  );

  const inactiveFixture = await seedReturnFixture({
    suffix: "inactive",
    role: "sales_rep",
    userOverrides: {active: false},
  });
  await assert.rejects(
    invokeReturn(inactiveFixture, inactiveFixture.uid, "inactive-return"),
    (error) => error.code === "permission-denied",
  );

  const unauthorizedFixture = await seedReturnFixture({
    suffix: "wrong-owner",
    role: "sales_rep",
  });
  const otherUid = "wrong-owner-other-rep";
  await seedUser(otherUid, "sales_rep", unauthorizedFixture.companyId);
  await assert.rejects(
    invokeReturn(unauthorizedFixture, otherUid, "wrong-owner-return"),
    (error) => error.code === "permission-denied",
  );

  for (const [fixture, returnId] of [
    [disabledFixture, "disabled-permission-return"],
    [pendingFixture, "pending-return"],
    [inactiveFixture, "inactive-return"],
    [unauthorizedFixture, "wrong-owner-return"],
  ]) {
    assert.equal((await fixture.returnRef(returnId).get()).exists, false);
    assert.equal((await fixture.itemRef.get()).data().currentStock, 9);
  }
});

async function seedReturnFixture({
  suffix,
  role,
  allowSalesRepCreateReturns = true,
  userOverrides = {},
}) {
  const companyId = `return-auth-${suffix}`;
  const uid = `${suffix}-user`;
  const invoiceId = `${suffix}-invoice`;
  const customerId = `${suffix}-customer`;
  const itemId = `${suffix}-item`;
  const movementId = `${invoiceId}_line_000_${itemId}_invoice_sale`;
  await seedUser(uid, role, companyId, userOverrides);
  await db.doc(`companies/${companyId}/settings/app`).set({
    permissionSettings: {allowSalesRepCreateReturns},
  });
  const customerRef = db.doc(`companies/${companyId}/customers/${customerId}`);
  await customerRef.set({
    id: customerId,
    companyId,
    name: "Auth test customer",
    active: true,
    createdByUid: uid,
    currentBalance: 10,
    totalSales: 10,
    totalPaid: 0,
  });
  const itemRef = db.doc(`items/${itemId}`);
  await itemRef.set({
    id: itemId,
    name: "Auth test item",
    code: suffix,
    unit: "piece",
    active: true,
    deleted: false,
    trackStock: true,
    currentStock: 9,
  });
  await db.doc(`companies/${companyId}/stock_movements/${movementId}`).set({
    id: movementId,
    companyId,
    itemId,
    sourceLineId: `${invoiceId}_line_000`,
  });
  const invoiceRef = db.doc(`companies/${companyId}/invoices/${invoiceId}`);
  await invoiceRef.set({
    id: invoiceId,
    companyId,
    invoiceNumber: `INV-${suffix}`,
    invoiceStatus: "confirmed",
    financialPosted: true,
    inventoryPosted: true,
    customerId,
    customerSnapshot: {id: customerId, name: "Auth test customer"},
    salesRepId: uid,
    salesRepName: uid,
    createdByUid: uid,
    createdByRole: role,
    stockSourceType: "companyWarehouse",
    inventoryMovementIds: [movementId],
    invoiceDate: now,
    remainingAmount: 10,
    paidAmount: 0,
    returnedReceivableAmount: 0,
    returnedQuantitiesByItem: {},
    returnedTotal: 0,
    returnedSubtotal: 0,
    returnedDiscount: 0,
    returnedTax: 0,
    customerCreditAmount: 0,
    cashRefundAmount: 0,
    returnInvoiceIds: [],
    receiptIds: [],
    items: [{
      itemId,
      itemName: "Auth test item",
      itemCode: suffix,
      unit: "piece",
      quantity: 1,
      unitPrice: 10,
      discount: 0,
      subtotal: 10,
      taxPercent: 0,
      taxAmount: 0,
      total: 10,
    }],
  });
  return {
    companyId,
    uid,
    invoiceId,
    customerRef,
    itemRef,
    invoiceRef,
    returnRef: (returnId) => db.doc(
      `companies/${companyId}/sales_returns/${returnId}`,
    ),
  };
}

async function seedUser(uid, role, companyId, overrides = {}) {
  await db.doc(`users/${uid}`).set({
    uid,
    name: uid,
    role,
    companyId,
    active: true,
    approvalStatus: "approved",
    ...overrides,
  });
}

async function invokeReturn(fixture, uid, returnId) {
  return confirmSalesReturn.run({
    auth: uid ? {uid} : undefined,
    data: {
      companyId: fixture.companyId,
      returnId,
      originalInvoiceId: fixture.invoiceId,
      refundType: "credit_customer_balance",
      returnDate: now,
      reason: "Authentication test return",
      items: [{
        originalInvoiceItemId: `${fixture.invoiceId}:0`,
        returnedQuantity: 1,
      }],
    },
  });
}

async function readEffects(fixture) {
  const [invoice, customer, item, returns, ledger, cash, stock] = await Promise.all([
    fixture.invoiceRef.get(),
    fixture.customerRef.get(),
    fixture.itemRef.get(),
    db.collection(`companies/${fixture.companyId}/sales_returns`).get(),
    db.collection(`companies/${fixture.companyId}/customer_transactions`).get(),
    db.collection(`companies/${fixture.companyId}/cash_movements`).get(),
    db.collection(`companies/${fixture.companyId}/stock_movements`).get(),
  ]);
  return {
    invoice: invoice.data(),
    customer: customer.data(),
    item: item.data(),
    returnCount: returns.size,
    ledgerCount: ledger.size,
    cashCount: cash.size,
    stockCount: stock.size,
  };
}
