const assert = require("node:assert/strict");
const {readFileSync} = require("node:fs");
const {join} = require("node:path");
const {after, before, test} = require("node:test");

const {deleteApp, initializeApp} = require("firebase-admin/app");
const {Timestamp, getFirestore} = require("firebase-admin/firestore");

const {
  confirmInvoiceTransaction,
} = require("../lib/trusted/confirm_invoice");
const {
  confirmInventoryTransferTransaction,
} = require("../lib/trusted/confirm_inventory_transfer");
const {
  confirmSalesReturnTransaction,
} = require("../lib/trusted/confirm_sales_return");
const {
  createReceiptTransaction,
} = require("../lib/trusted/create_receipt");
const {
  approveExpenseTransaction,
  createExpenseTransaction,
} = require("../lib/trusted/expenses");
const {
  adjustStockTransaction,
  createItemTransaction,
} = require("../lib/trusted/inventory");
const {
  createCustomerTransaction,
  normalizePhone,
  updateCustomerTransaction,
} = require("../lib/trusted/customer_profiles");
const {
  postOpeningBalanceTransaction,
} = require("../lib/trusted/post_opening_balance");
const {
  updateOpeningBalanceTransaction,
} = require("../lib/trusted/update_opening_balance");
const {
  recordCashSettlementTransaction,
} = require("../lib/trusted/record_cash_settlement");
const {
  COMPANY_CASH_OPENING_BALANCE_DATE,
  COMPANY_CASH_OPENING_BALANCE_EMAIL,
  COMPANY_CASH_OPENING_BALANCE_MOVEMENT_ID,
  COMPANY_CASH_OPENING_BALANCE_UID,
  postCompanyCashOpeningBalanceTransaction,
} = require("../lib/trusted/post_company_cash_opening_balance");
const {
  calculateInvoiceTotals,
  calculatePayment,
} = require("../lib/trusted/totals");
const {
  readCashBalance,
} = require("../lib/trusted/cash_ledger");
const {
  submitInvoiceToJoFotara,
} = require("../lib/submit_invoice_to_jofotara");
const {
  CASH_RECONCILIATION_SCHEMA_VERSION,
  buildCashReconciliationPlan,
  executeCashReconciliation,
} = require("../scripts/cash_reconciliation_common");

const app = initializeApp({projectId: "fatoora-trusted-test"}, "trusted-tests");
const db = getFirestore(app);
const now = Timestamp.fromDate(new Date("2026-08-05T12:00:00.000Z"));

before(async () => {
  if (!process.env.FIRESTORE_EMULATOR_HOST) {
    throw new Error("Trusted transaction tests require the Firestore emulator.");
  }
});

after(async () => {
  await deleteApp(app);
});

test("invoice totals ignore forged client aggregates and reject invalid payment", () => {
  const totals = calculateInvoiceTotals([{
    itemId: "item-a",
    itemName: "Forged",
    quantity: 2,
    unitPrice: 10,
    discount: 1,
    taxPercent: 16,
    subtotal: 0.001,
    taxAmount: 0,
    total: 999999,
  }]);
  assert.deepEqual(
    {
      subtotal: totals.subtotal,
      discount: totals.totalDiscount,
      tax: totals.totalTax,
      total: totals.grandTotal,
    },
    {subtotal: 20, discount: 1, tax: 3.04, total: 22.04},
  );
  assert.throws(() => calculatePayment(22.04, true, 23));
  assert.throws(() => calculateInvoiceTotals([{
    quantity: 1,
    unitPrice: 10,
    discount: 11,
    taxPercent: 0,
  }]));
});

test("JoFotara is not exported and its retained callable fails without writes", async () => {
  const indexSource = readFileSync(
    join(__dirname, "..", "src", "index.ts"),
    "utf8",
  );
  assert.doesNotMatch(indexSource, /submitInvoiceToJoFotara/);
  const disabledScenarios = [
    {name: "admin", auth: {uid: "admin"}, data: {companyId: "company-a", invoiceId: "invoice-a"}},
    {name: "sales representative", auth: {uid: "rep"}, data: {companyId: "company-a", invoiceId: "invoice-a"}},
    {name: "pending user", auth: {uid: "pending"}, data: {companyId: "company-a", invoiceId: "invoice-a"}},
    {name: "inactive user", auth: {uid: "inactive"}, data: {companyId: "company-a", invoiceId: "invoice-a"}},
    {name: "wrong company", auth: {uid: "admin"}, data: {companyId: "company-b", invoiceId: "invoice-a"}},
    {name: "wrong owner", auth: {uid: "rep-b"}, data: {companyId: "company-a", invoiceId: "invoice-a"}},
    {name: "missing invoice", auth: {uid: "admin"}, data: {companyId: "company-a", invoiceId: "missing"}},
    {name: "duplicate submission", auth: {uid: "admin"}, data: {companyId: "company-a", invoiceId: "already-submitted"}},
    {name: "external submission failure", auth: {uid: "admin"}, data: {companyId: "company-a", invoiceId: "external-failure"}},
  ];
  for (const scenario of disabledScenarios) {
    await assert.rejects(
      submitInvoiceToJoFotara.run({
        auth: scenario.auth,
        data: scenario.data,
      }),
      (error) => error.code === "failed-precondition",
      scenario.name,
    );
  }
});

test("customer profiles normalize and reserve phones server-side under concurrency", async () => {
  const companyId = "trusted-customers";
  const adminUid = "customer-admin";
  const repUid = "customer-rep";
  const otherRepUid = "customer-other-rep";
  await seedUser(adminUid, "admin", companyId);
  await seedUser(repUid, "sales_rep", companyId);
  await seedUser(otherRepUid, "sales_rep", companyId);
  await db.doc(`companies/${companyId}/settings/app`).set({
    permissionSettings: {allowSalesRepCreateCustomers: false},
  });
  const profile = {
    name: "Customer A",
    phone: "+962 79 123 4567",
    addressText: "Amman",
    city: "Amman",
    area: "Shmeisani",
    notes: "Trusted profile",
    active: true,
  };

  await assert.rejects(() => createCustomerTransaction(
    db,
    repUid,
    companyId,
    "customer-rep-denied",
    profile,
  ), (error) => error.code === "permission-denied");

  const replay = await Promise.all([
    retryTransientTransaction(() => createCustomerTransaction(
      db,
      adminUid,
      companyId,
      "customer-admin-key",
      profile,
    )),
    retryTransientTransaction(() => createCustomerTransaction(
      db,
      adminUid,
      companyId,
      "customer-admin-key",
      profile,
    )),
  ]);
  assert.deepEqual(replay.map((result) => result.alreadyPosted).sort(), [false, true]);
  const customerId = "customer_customer-admin-key";
  const created = (await db.doc(
    `companies/${companyId}/customers/${customerId}`,
  ).get()).data();
  assert.equal(normalizePhone(profile.phone), "0791234567");
  assert.equal(created.phoneNormalized, "0791234567");
  assert.equal(created.currentBalance, 0);
  assert.equal(created.totalSales, 0);
  assert.equal(created.totalPaid, 0);
  assert.equal((await db.doc(
    `companies/${companyId}/customer_phone_reservations/0791234567`,
  ).get()).data().customerId, customerId);

  await assert.rejects(() => createCustomerTransaction(
    db,
    adminUid,
    companyId,
    "customer-duplicate-phone",
    {...profile, name: "Duplicate", phone: "00962-79-123-4567"},
  ), (error) => error.code === "already-exists");
  const phoneRace = await Promise.allSettled([
    retryTransientTransaction(() => createCustomerTransaction(
      db,
      adminUid,
      companyId,
      "customer-phone-race-a",
      {...profile, name: "Phone race A", phone: "076 555 5555"},
    )),
    retryTransientTransaction(() => createCustomerTransaction(
      db,
      adminUid,
      companyId,
      "customer-phone-race-b",
      {...profile, name: "Phone race B", phone: "+962 76 555 5555"},
    )),
  ]);
  assert.equal(
    phoneRace.filter((result) => result.status === "fulfilled").length,
    1,
  );
  await assert.rejects(() => updateCustomerTransaction(
    db,
    otherRepUid,
    companyId,
    customerId,
    {...profile, name: "Forbidden"},
  ), (error) => error.code === "permission-denied");

  await db.doc(`companies/${companyId}/settings/app`).set({
    permissionSettings: {allowSalesRepCreateCustomers: true},
  });
  const repProfile = {...profile, name: "Rep customer", phone: "0780000000"};
  const repCustomer = await createCustomerTransaction(
    db,
    repUid,
    companyId,
    "customer-rep-key",
    repProfile,
  );
  await db.doc(`companies/${companyId}/settings/app`).set({
    permissionSettings: {allowSalesRepCreateCustomers: false},
  });
  const repReplay = await createCustomerTransaction(
    db,
    repUid,
    companyId,
    "customer-rep-key",
    repProfile,
  );
  assert.equal(repReplay.alreadyPosted, true);
  await updateCustomerTransaction(
    db,
    repUid,
    companyId,
    repCustomer.customerId,
    {
      ...profile,
      name: "Rep customer updated",
      phone: "+962 77 000 0000",
      currentBalance: 999999,
    },
  );
  const updated = (await db.doc(
    `companies/${companyId}/customers/${repCustomer.customerId}`,
  ).get()).data();
  assert.equal(updated.name, "Rep customer updated");
  assert.equal(updated.phoneNormalized, "0770000000");
  assert.equal(updated.currentBalance, 0);
  assert.equal((await db.doc(
    `companies/${companyId}/customer_phone_reservations/0780000000`,
  ).get()).exists, false);
  await db.doc(
    `companies/${companyId}/customer_phone_reservations/0770000000`,
  ).delete();
  await updateCustomerTransaction(
    db,
    repUid,
    companyId,
    repCustomer.customerId,
    {...profile, name: "Rep customer updated", phone: "+962 77 000 0000"},
  );
  assert.equal((await db.doc(
    `companies/${companyId}/customer_phone_reservations/0770000000`,
  ).get()).data().customerId, repCustomer.customerId);
});

test("missing materialized cash balance fails closed when movement history exists", async () => {
  const companyId = "trusted-cash-reconciliation";
  await db.doc(`companies/${companyId}/cash_movements/legacy-cash-in`).set({
    id: "legacy-cash-in",
    companyId,
    cashAccount: "company_cash",
    salesRepId: "",
    direction: "in",
    amount: 25,
  });
  await assert.rejects(
    () => db.runTransaction((transaction) => readCashBalance(
      transaction,
      db,
      companyId,
      "company_cash",
      "",
    )),
    (error) => error.code === "failed-precondition",
  );
  const fresh = await db.runTransaction((transaction) => readCashBalance(
    transaction,
    db,
    "trusted-fresh-cash",
    "company_cash",
    "",
  ));
  assert.equal(fresh.amount, 0);
});

test("cash reconciliation apply refuses unresolved movements without writing", async () => {
  const companyId = "trusted-cash-unresolved";
  await db.doc(`companies/${companyId}/cash_movements/missing-rep`).set({
    id: "missing-rep",
    companyId,
    movementType: "receipt",
    direction: "in",
    amount: 10,
    cashAccount: "rep_cash",
    salesRepId: "",
    sourceCollection: "receipts",
    sourceId: "missing-rep",
    date: now,
  });
  await assert.rejects(
    () => executeCashReconciliation({
      db,
      projectId: "fatoora-trusted-test",
      companyId,
      apply: true,
    }),
    /unresolved cash issue/,
  );
  assert.equal((await db.doc(
    `companies/${companyId}/cash_balances/company_cash`,
  ).get()).exists, false);
  assert.equal((await db.doc(
    `companies/${companyId}/maintenance_locks/cash_reconciliation`,
  ).get()).exists, false);
});

test("trusted cash operations continue after idempotent full-history reconciliation", async () => {
  const companyId = "trusted-cash-after-reconciliation";
  const adminUid = "reconciliation-admin";
  const repAUid = "reconciliation-rep-a";
  const repBUid = "reconciliation-rep-b";
  await seedUser(adminUid, "admin", companyId);
  await seedUser(repAUid, "sales_rep", companyId);
  await seedUser(repBUid, "sales_rep", companyId);
  await seedCustomer(companyId, "reconciliation-customer", adminUid, 0);
  await Promise.all([
    seedCashMovement(companyId, "legacy-company-in", {
      amount: 100,
      cashAccount: "company_cash",
      salesRepId: "",
    }),
    seedCashMovement(companyId, "legacy-rep-a-in", {
      amount: 40,
      cashAccount: "rep_cash",
      salesRepId: repAUid,
    }),
    seedCashMovement(companyId, "legacy-rep-b-in", {
      amount: 30,
      cashAccount: "rep_cash",
      salesRepId: repBUid,
    }),
  ]);

  const first = await executeCashReconciliation({
    db,
    projectId: "fatoora-trusted-test",
    companyId,
    apply: true,
    pageSize: 2,
  });
  assert.equal(first.plan.issueCount, 0);
  assert.equal(first.balanceWrites, 3);
  const companyBalanceRef = db.doc(
    `companies/${companyId}/cash_balances/company_cash`,
  );
  const repABalanceRef = db.doc(
    `companies/${companyId}/cash_balances/rep_${repAUid}`,
  );
  const repBBalanceRef = db.doc(
    `companies/${companyId}/cash_balances/rep_${repBUid}`,
  );
  const reconciledCompany = (await companyBalanceRef.get()).data();
  assert.equal(reconciledCompany.amount, 100);
  assert.equal(reconciledCompany.schemaVersion, CASH_RECONCILIATION_SCHEMA_VERSION);
  assert.equal(reconciledCompany.reconciliation.movementCount, 1);
  assert.equal((await repABalanceRef.get()).data().amount, 40);
  assert.equal((await repBBalanceRef.get()).data().amount, 30);

  const repeated = await executeCashReconciliation({
    db,
    projectId: "fatoora-trusted-test",
    companyId,
    apply: true,
    pageSize: 2,
  });
  assert.equal(repeated.plan.issueCount, 0);
  assert.equal(repeated.balanceWrites, 0);

  const lockRef = db.doc(
    `companies/${companyId}/maintenance_locks/cash_reconciliation`,
  );
  await lockRef.set({active: true, runId: "test-active-lock"}, {merge: true});
  await assert.rejects(
    () => db.runTransaction((transaction) => readCashBalance(
      transaction,
      db,
      companyId,
      "company_cash",
      "",
    )),
    (error) => error.code === "failed-precondition",
  );
  await lockRef.set({active: false}, {merge: true});

  await db.doc("items/item-a").set({
    id: "item-a",
    name: "Reconciliation item",
    code: "REC-A",
    unit: "piece",
    price: 10,
    active: true,
    deleted: false,
    trackStock: true,
    currentStock: 100,
  });
  const cashInvoiceId = "reconciliation-cash-invoice";
  await db.doc(`companies/${companyId}/invoices/${cashInvoiceId}`).set({
    ...invoiceDraft({
      id: cashInvoiceId,
      companyId,
      customerId: "reconciliation-customer",
      uid: adminUid,
      quantity: 1,
    }),
    customerSnapshot: {id: "reconciliation-customer", name: "Customer"},
    hasReceivedPayment: true,
    paidAmount: 10,
  });
  await confirmInvoiceTransaction(db, adminUid, companyId, cashInvoiceId);
  assert.equal((await companyBalanceRef.get()).data().amount, 110);

  const partialInvoiceId = "reconciliation-partial-invoice";
  await db.doc(`companies/${companyId}/invoices/${partialInvoiceId}`).set({
    ...invoiceDraft({
      id: partialInvoiceId,
      companyId,
      customerId: "reconciliation-customer",
      uid: adminUid,
      quantity: 1,
    }),
    customerSnapshot: {id: "reconciliation-customer", name: "Customer"},
    hasReceivedPayment: true,
    paidAmount: 4,
  });
  await confirmInvoiceTransaction(db, adminUid, companyId, partialInvoiceId);
  assert.equal((await companyBalanceRef.get()).data().amount, 114);

  await createReceiptTransaction(
    db,
    adminUid,
    companyId,
    "reconciliation_receipt_001",
    {
      customerId: "reconciliation-customer",
      amount: 6,
      paymentMethod: "cash",
      receiptDate: now,
      notes: "Receipt after reconciliation",
    },
  );
  assert.equal((await companyBalanceRef.get()).data().amount, 120);

  await createExpenseTransaction(
    db,
    adminUid,
    companyId,
    "reconciliation_expense_001",
    {
      amount: 5,
      expenseDate: now,
      category: "office",
      description: "Expense after reconciliation",
      fundingSource: "company_cash",
    },
  );
  assert.equal((await companyBalanceRef.get()).data().amount, 115);

  await confirmSalesReturnTransaction(
    db,
    adminUid,
    companyId,
    "reconciliation_return_001",
    {
      originalInvoiceId: cashInvoiceId,
      refundType: "cash_refund",
      returnDate: now,
      reason: "Return after reconciliation",
      items: [{
        originalInvoiceItemId: `${cashInvoiceId}:0`,
        returnedQuantity: 1,
      }],
    },
  );
  assert.equal((await companyBalanceRef.get()).data().amount, 105);

  await recordCashSettlementTransaction(
    db,
    adminUid,
    companyId,
    "reconciliation_settlement_001",
    {
      salesRepId: repAUid,
      amount: 10,
      settlementDate: now,
      notes: "Settlement after reconciliation",
    },
  );
  assert.equal((await companyBalanceRef.get()).data().amount, 115);
  assert.equal((await repABalanceRef.get()).data().amount, 30);
  assert.equal((await repBBalanceRef.get()).data().amount, 30);

  const postTransactionAudit = await executeCashReconciliation({
    db,
    projectId: "fatoora-trusted-test",
    companyId,
    apply: false,
    pageSize: 2,
  });
  assert.equal(postTransactionAudit.plan.issueCount, 0);
  const auditedBalances = Object.fromEntries(
    postTransactionAudit.plan.accounts.map((account) => [
      account.documentId,
      account.calculatedBalance,
    ]),
  );
  assert.equal(auditedBalances.company_cash, 115);
  assert.equal(auditedBalances[`rep_${repAUid}`], 30);
  assert.equal(auditedBalances[`rep_${repBUid}`], 30);
});

test("item opening stock is server-owned, paired, and idempotent", async () => {
  const companyId = "default_company";
  const adminUid = "item-admin";
  const repUid = "item-rep";
  const key = "inventory-create-key";
  await seedUser(adminUid, "admin", companyId);
  await seedUser(repUid, "sales_rep", companyId);
  const input = {
    name: "Tracked item",
    code: "TRACK-1",
    description: "Trusted opening stock",
    unit: "piece",
    price: 12.345,
    taxRate: 16,
    active: true,
    currentStock: 7.125,
    openingStock: 7.125,
    minStock: 1,
    trackStock: true,
    costPrice: 8,
    warehouseId: "default_warehouse",
  };
  await assert.rejects(() => createItemTransaction(
    db,
    repUid,
    companyId,
    "inventory-rep-key",
    input,
  ));
  const results = await Promise.all([
    retryTransientTransaction(
      () => createItemTransaction(db, adminUid, companyId, key, input),
    ),
    retryTransientTransaction(
      () => createItemTransaction(db, adminUid, companyId, key, input),
    ),
  ]);
  assert.deepEqual(
    results.map((result) => result.alreadyPosted).sort(),
    [false, true],
  );
  const itemId = `item_${key}`;
  const item = (await db.doc(`items/${itemId}`).get()).data();
  const movement = (await db.doc(
    `companies/${companyId}/stock_movements/${itemId}_opening_balance`,
  ).get()).data();
  assert.equal(item.currentStock, 7.125);
  assert.equal(item.lastStockMovementId, movement.id);
  assert.equal(movement.quantityBefore, 0);
  assert.equal(movement.quantityAfter, 7.125);
  assert.equal(movement.quantity, 7.125);
  await assert.rejects(() => createItemTransaction(
    db,
    adminUid,
    companyId,
    key,
    {...input, currentStock: 99, openingStock: 99},
  ));
  await assert.rejects(() => createItemTransaction(
    db,
    adminUid,
    companyId,
    "inventory-invalid-opening",
    {...input, openingStock: 1},
  ));
});

test("manual stock adjustments are admin-only, atomic, and idempotent", async () => {
  const companyId = "default_company";
  const adminUid = "adjustment-admin";
  const repUid = "adjustment-rep";
  const itemId = "manual-adjustment-item";
  const key = "manual-adjustment-key";
  const input = {
    itemId,
    adjustmentType: "manual_adjustment_in",
    quantity: 2.25,
    notes: "Received after stock count",
  };
  await seedUser(adminUid, "admin", companyId);
  await seedUser(repUid, "sales_rep", companyId);
  await db.doc(`items/${itemId}`).set({
    id: itemId,
    companyId,
    name: "Adjusted item",
    code: "ADJ-1",
    unit: "piece",
    active: true,
    deleted: false,
    trackStock: true,
    currentStock: 5,
    warehouseId: "default_warehouse",
  });

  await assert.rejects(() => adjustStockTransaction(
    db,
    repUid,
    companyId,
    "manual-adjustment-rep-key",
    input,
  ));
  const results = await Promise.all([
    retryTransientTransaction(
      () => adjustStockTransaction(db, adminUid, companyId, key, input),
    ),
    retryTransientTransaction(
      () => adjustStockTransaction(db, adminUid, companyId, key, input),
    ),
  ]);
  assert.deepEqual(
    results.map((result) => result.alreadyPosted).sort(),
    [false, true],
  );

  const movementId = `stock_adjustment_${key}`;
  const item = (await db.doc(`items/${itemId}`).get()).data();
  const movement = (await db.doc(
    `companies/${companyId}/stock_movements/${movementId}`,
  ).get()).data();
  assert.equal(item.currentStock, 7.25);
  assert.equal(item.lastStockMovementId, movementId);
  assert.equal(movement.quantityBefore, 5);
  assert.equal(movement.quantityAfter, 7.25);
  assert.equal(movement.notes, input.notes);

  await assert.rejects(
    () => adjustStockTransaction(
      db,
      adminUid,
      companyId,
      "manual-adjustment-insufficient-key",
      {...input, adjustmentType: "manual_adjustment_out", quantity: 99},
    ),
    (error) => error.code === "failed-precondition" &&
      error.details?.reason === "insufficient-stock",
  );
  assert.equal((await db.doc(`items/${itemId}`).get()).data().currentStock, 7.25);
});

test("inventory transfers post atomically through the trusted server", async () => {
  const companyId = "trusted-inventory-transfer";
  const adminUid = "transfer-admin";
  const repUid = "transfer-rep";
  const itemId = "transfer-item";
  const transferId = "warehouse-to-rep";
  await seedUser(adminUid, "admin", companyId);
  await seedUser(repUid, "sales_rep", companyId, {name: "Transfer Rep"});
  await db.doc(`items/${itemId}`).set({
    id: itemId,
    name: "Transfer Item",
    code: "TRF-1",
    unit: "piece",
    active: true,
    deleted: false,
    trackStock: true,
    currentStock: 10,
    warehouseId: "default_warehouse",
  });
  await db.doc(
    `companies/${companyId}/rep_inventory_balances/${repUid}_${itemId}`,
  ).set({
    id: `${repUid}_${itemId}`,
    companyId,
    salesRepId: repUid,
    itemId,
    quantity: 1,
    createdAt: now,
  });
  await seedInventoryTransfer(companyId, transferId, adminUid, repUid, itemId, {
    quantity: 3.5,
  });

  await assert.rejects(
    () => confirmInventoryTransferTransaction(
      db,
      repUid,
      companyId,
      transferId,
    ),
    (error) => error.code === "permission-denied",
  );
  const result = await confirmInventoryTransferTransaction(
    db,
    adminUid,
    companyId,
    transferId,
  );
  assert.deepEqual(result, {transferId, alreadyPosted: false});

  const transfer = (await db.doc(
    `companies/${companyId}/inventory_transfers/${transferId}`,
  ).get()).data();
  const item = (await db.doc(`items/${itemId}`).get()).data();
  const balance = (await db.doc(
    `companies/${companyId}/rep_inventory_balances/${repUid}_${itemId}`,
  ).get()).data();
  const companyMovement = (await db.doc(
    `companies/${companyId}/stock_movements/${transferId}_${itemId}_warehouse`,
  ).get()).data();
  const repMovement = (await db.doc(
    `companies/${companyId}/rep_inventory_movements/${transferId}_${repUid}_${itemId}`,
  ).get()).data();
  assert.equal(transfer.status, "confirmed");
  assert.equal(transfer.lines[0].warehouseQuantityBefore, 10);
  assert.equal(transfer.lines[0].warehouseQuantityAfter, 6.5);
  assert.equal(transfer.lines[0].repQuantityBefore, 1);
  assert.equal(transfer.lines[0].repQuantityAfter, 4.5);
  assert.equal(item.currentStock, 6.5);
  assert.equal(balance.quantity, 4.5);
  assert.equal(companyMovement.direction, "out");
  assert.equal(companyMovement.quantityBefore, 10);
  assert.equal(companyMovement.quantityAfter, 6.5);
  assert.equal(repMovement.direction, "in");
  assert.equal(repMovement.reason, "warehouseDelivery");

  const replay = await confirmInventoryTransferTransaction(
    db,
    adminUid,
    companyId,
    transferId,
  );
  assert.deepEqual(replay, {transferId, alreadyPosted: true});
  assert.equal((await db.doc(`items/${itemId}`).get()).data().currentStock, 6.5);
});

test("an insufficient inventory transfer creates no partial effects", async () => {
  const companyId = "trusted-inventory-transfer-insufficient";
  const adminUid = "transfer-insufficient-admin";
  const repUid = "transfer-insufficient-rep";
  const itemId = "transfer-insufficient-item";
  const transferId = "insufficient-transfer";
  await seedUser(adminUid, "admin", companyId);
  await seedUser(repUid, "sales_rep", companyId);
  await db.doc(`items/${itemId}`).set({
    id: itemId,
    name: "Limited Item",
    code: "LIMIT-1",
    unit: "piece",
    active: true,
    deleted: false,
    trackStock: true,
    currentStock: 2,
  });
  await seedInventoryTransfer(companyId, transferId, adminUid, repUid, itemId, {
    quantity: 3,
  });

  await assert.rejects(
    () => confirmInventoryTransferTransaction(
      db,
      adminUid,
      companyId,
      transferId,
    ),
    (error) =>
      error.code === "failed-precondition" &&
      error.details?.reason === "insufficient-warehouse-stock",
  );
  assert.equal((await db.doc(`items/${itemId}`).get()).data().currentStock, 2);
  assert.equal((await db.doc(
    `companies/${companyId}/inventory_transfers/${transferId}`,
  ).get()).data().status, "draft");
  assert.equal((await db.doc(
    `companies/${companyId}/stock_movements/${transferId}_${itemId}_warehouse`,
  ).get()).exists, false);
  assert.equal((await db.doc(
    `companies/${companyId}/rep_inventory_balances/${repUid}_${itemId}`,
  ).get()).exists, false);
});

test("opening balance is permission checked, one-time, and idempotent", async () => {
  const companyId = "trusted-opening";
  await seedUser("opening-admin", "admin", companyId);
  await seedUser("opening-pending", "sales_rep", companyId, {approvalStatus: "pending"});
  await db.doc(`companies/${companyId}/customers/customer-a`).set({
    id: "customer-a",
    companyId,
    name: "Customer A",
    active: true,
    createdByUid: "opening-admin",
    currentBalance: 5,
    totalSales: 100,
    totalPaid: 20,
  });
  const input = {
    openingBalanceType: "customer_owes",
    amount: 10,
    transactionDate: now,
    notes: "Opening",
  };
  await assert.rejects(() => postOpeningBalanceTransaction(
    db,
    "opening-pending",
    companyId,
    "customer-a",
    input,
  ));
  const first = await postOpeningBalanceTransaction(
    db,
    "opening-admin",
    companyId,
    "customer-a",
    input,
  );
  const replay = await postOpeningBalanceTransaction(
    db,
    "opening-admin",
    companyId,
    "customer-a",
    input,
  );
  assert.equal(first.balanceAfter, 15);
  assert.equal(replay.alreadyPosted, true);
  const customer = (await db.doc(`companies/${companyId}/customers/customer-a`).get()).data();
  assert.equal(customer.currentBalance, 15);
  assert.equal(customer.openingBalance, 10);
  assert.equal(customer.totalSales, 100);
  assert.equal(customer.totalPaid, 20);
  await assert.rejects(() => postOpeningBalanceTransaction(
    db,
    "opening-admin",
    companyId,
    "customer-a",
    {...input, amount: 999},
  ));
});

test("opening balance edits post only signed differences and retain one original", async () => {
  const companyId = "trusted-opening-adjustment";
  const adminUid = "opening-adjustment-admin";
  const otherRepUid = "opening-adjustment-other-rep";
  const customerId = "opening-adjustment-customer";
  await seedUser(adminUid, "admin", companyId);
  await seedUser(otherRepUid, "sales_rep", companyId);
  await db.doc(`companies/${companyId}/customers/${customerId}`).set({
    id: customerId,
    companyId,
    name: "Adjustment Customer",
    active: true,
    createdByUid: adminUid,
    currentBalance: 5,
    totalSales: 100,
    totalPaid: 20,
  });
  await postOpeningBalanceTransaction(
    db,
    adminUid,
    companyId,
    customerId,
    {
      openingBalanceType: "customer_owes",
      amount: 10,
      transactionDate: now,
      notes: "Original opening balance",
    },
  );

  const firstKey = "opening_adjustment_001";
  await assert.rejects(
    () => updateOpeningBalanceTransaction(
      db,
      otherRepUid,
      companyId,
      customerId,
      "opening_adjustment_denied",
      {
        openingBalanceType: "customer_credit",
        amount: 4,
        reason: "Unauthorized correction",
      },
    ),
    (error) => error.code === "permission-denied",
  );
  const first = await updateOpeningBalanceTransaction(
    db,
    adminUid,
    companyId,
    customerId,
    firstKey,
    {
      openingBalanceType: "customer_credit",
      amount: 4,
      reason: "Correct sign from source records",
    },
  );
  assert.equal(first.difference, -14);
  assert.equal(first.balanceAfter, 1);
  assert.equal(first.alreadyPosted, false);

  const originalId = `${customerId}_opening_balance`;
  const original = (await db.doc(
    `companies/${companyId}/customer_transactions/${originalId}`,
  ).get()).data();
  const firstAdjustment = (await db.doc(
    `companies/${companyId}/customer_transactions/${first.adjustmentTransactionId}`,
  ).get()).data();
  const customerAfterFirst = (await db.doc(
    `companies/${companyId}/customers/${customerId}`,
  ).get()).data();
  assert.equal(original.transactionType, "opening_balance");
  assert.equal(original.amount, 4);
  assert.equal(original.signedAmount, -4);
  assert.equal(original.openingBalanceType, "customer_credit");
  assert.equal(original.debitAmount, 10);
  assert.equal(original.creditAmount, 0);
  assert.equal(firstAdjustment.transactionType, "opening_balance_adjustment");
  assert.equal(firstAdjustment.oldAmount, 10);
  assert.equal(firstAdjustment.newAmount, -4);
  assert.equal(firstAdjustment.difference, -14);
  assert.equal(firstAdjustment.debitAmount, 0);
  assert.equal(firstAdjustment.creditAmount, 14);
  assert.equal(firstAdjustment.reason, "Correct sign from source records");
  assert.equal(firstAdjustment.adjustedByUid, adminUid);
  assert.ok(firstAdjustment.adjustedAt);
  assert.equal(firstAdjustment.originalOpeningBalanceReference, originalId);
  assert.equal(customerAfterFirst.currentBalance, 1);
  assert.equal(customerAfterFirst.openingBalance, -4);
  assert.equal(customerAfterFirst.totalSales, 100);
  assert.equal(customerAfterFirst.totalPaid, 20);

  const replay = await updateOpeningBalanceTransaction(
    db,
    adminUid,
    companyId,
    customerId,
    firstKey,
    {
      openingBalanceType: "customer_credit",
      amount: 4,
      reason: "Correct sign from source records",
    },
  );
  assert.equal(replay.alreadyPosted, true);
  assert.equal((await db.doc(
    `companies/${companyId}/customers/${customerId}`,
  ).get()).data().currentBalance, 1);

  const second = await updateOpeningBalanceTransaction(
    db,
    adminUid,
    companyId,
    customerId,
    "opening_adjustment_002",
    {
      openingBalanceType: "customer_owes",
      amount: 7,
      reason: "Final verified receivable",
    },
  );
  assert.equal(second.difference, 11);
  assert.equal(second.balanceAfter, 12);
  const secondAdjustment = (await db.doc(
    `companies/${companyId}/customer_transactions/${second.adjustmentTransactionId}`,
  ).get()).data();
  assert.equal(secondAdjustment.oldAmount, -4);
  assert.equal(secondAdjustment.newAmount, 7);
  assert.equal(secondAdjustment.debitAmount, 11);
  assert.equal(secondAdjustment.creditAmount, 0);

  const openingRows = await db.collection(
    `companies/${companyId}/customer_transactions`,
  ).where("transactionType", "==", "opening_balance").get();
  const adjustmentRows = await db.collection(
    `companies/${companyId}/customer_transactions`,
  ).where("transactionType", "==", "opening_balance_adjustment").get();
  assert.equal(openingRows.size, 1);
  assert.equal(adjustmentRows.size, 2);
  const ledgerSigned = [...openingRows.docs, ...adjustmentRows.docs]
    .reduce((sum, document) => {
      const data = document.data();
      return sum + data.debitAmount - data.creditAmount;
    }, 0);
  assert.equal(ledgerSigned, 7);

  await assert.rejects(
    () => updateOpeningBalanceTransaction(
      db,
      adminUid,
      companyId,
      customerId,
      "opening_adjustment_no_reason",
      {openingBalanceType: "customer_credit", amount: 2, reason: ""},
    ),
    (error) => error.code === "invalid-argument",
  );
  await assert.rejects(
    () => updateOpeningBalanceTransaction(
      db,
      adminUid,
      companyId,
      customerId,
      "opening_adjustment_no_change",
      {openingBalanceType: "customer_owes", amount: 7, reason: "No change"},
    ),
    (error) =>
      error.code === "invalid-argument" && error.details?.reason === "no-change",
  );
});

test("concurrent invoice confirmations post totals and stock exactly once", async () => {
  const companyId = "trusted-invoice";
  const adminUid = "invoice-admin";
  await seedUser(adminUid, "admin", companyId);
  await seedCustomer(companyId, "customer-a", adminUid, 0);
  await db.doc("items/item-a").set({
    id: "item-a",
    name: "Catalog item",
    code: "A",
    unit: "piece",
    price: 10,
    active: true,
    deleted: false,
    trackStock: true,
    currentStock: 10,
  });
  await db.doc(`companies/${companyId}/invoices/invoice-a`).set(invoiceDraft({
    id: "invoice-a",
    companyId,
    customerId: "customer-a",
    uid: adminUid,
    quantity: 6,
  }));
  const attempts = await Promise.all([
    retryTransientTransaction(
      () => confirmInvoiceTransaction(db, adminUid, companyId, "invoice-a"),
    ),
    retryTransientTransaction(
      () => confirmInvoiceTransaction(db, adminUid, companyId, "invoice-a"),
    ),
  ]);
  assert.equal(attempts.filter((result) => result.alreadyPosted).length, 1);
  const invoice = (await db.doc(`companies/${companyId}/invoices/invoice-a`).get()).data();
  const item = (await db.doc("items/item-a").get()).data();
  const customer = (await db.doc(`companies/${companyId}/customers/customer-a`).get()).data();
  assert.equal(invoice.grandTotal, 60);
  assert.equal(invoice.financialPosted, true);
  assert.equal(item.currentStock, 4);
  assert.equal(customer.currentBalance, 60);
  const movements = await db.collection(`companies/${companyId}/stock_movements`).get();
  assert.equal(movements.size, 1);

  await db.doc(`companies/${companyId}/invoices/missing-item`).set({
    ...invoiceDraft({
      id: "missing-item",
      companyId,
      customerId: "customer-a",
      uid: adminUid,
      quantity: 1,
    }),
    items: [{
      itemId: "deleted-item",
      itemName: "Missing",
      quantity: 1,
      unitPrice: 1,
      discount: 0,
      taxPercent: 0,
    }],
  });
  await assert.rejects(() => confirmInvoiceTransaction(
    db,
    adminUid,
    companyId,
    "missing-item",
  ));
  await seedUser("invoice-other-rep", "sales_rep", companyId);
  await assert.rejects(() => confirmInvoiceTransaction(
    db,
    "invoice-other-rep",
    companyId,
    "invoice-a",
  ));
});

test("receipt allocates across more than 250 outstanding invoices", async () => {
  const companyId = "trusted-receipt";
  const adminUid = "receipt-admin";
  await seedUser(adminUid, "admin", companyId);
  await seedCustomer(companyId, "customer-a", adminUid, 260);
  const batchSize = 250;
  for (let start = 0; start < 260; start += batchSize) {
    const batch = db.batch();
    for (let index = start; index < Math.min(start + batchSize, 260); index += 1) {
      const id = `invoice-${String(index).padStart(3, "0")}`;
      batch.set(db.doc(`companies/${companyId}/invoices/${id}`), {
        id,
        companyId,
        customerId: "customer-a",
        invoiceStatus: "confirmed",
        financialPosted: true,
        dueDate: Timestamp.fromMillis(now.toMillis() + index * 1000),
        invoiceDate: now,
        remainingAmount: 1,
        returnedReceivableAmount: 0,
        paidAmount: 0,
        receiptIds: [],
        salesRepId: adminUid,
      });
    }
    await batch.commit();
  }
  const result = await createReceiptTransaction(
    db,
    adminUid,
    companyId,
    "receipt_all_260",
    {
      customerId: "customer-a",
      amount: 260,
      paymentMethod: "bank",
      receiptDate: now,
      notes: "All invoices",
    },
  );
  const receipt = (await db.doc(
    `companies/${companyId}/receipts/${result.receiptId}`,
  ).get()).data();
  assert.equal(Object.keys(receipt.invoiceAllocations).length, 260);
  assert.equal(receipt.invoiceAllocations["invoice-259"], 1);
  assert.equal(receipt.invoiceAllocationDetails.length, 260);
  assert.equal(receipt.invoiceAllocationDetails[259].invoiceId, "invoice-259");
  assert.equal(receipt.resultingCustomerBalance, 0);
  const customer = (await db.doc(`companies/${companyId}/customers/customer-a`).get()).data();
  assert.equal(customer.currentBalance, 0);
  const replay = await createReceiptTransaction(
    db,
    adminUid,
    companyId,
    "receipt_all_260",
    {
      customerId: "customer-a",
      amount: 260,
      paymentMethod: "bank",
      receiptDate: now,
      notes: "All invoices",
    },
  );
  assert.equal(replay.alreadyPosted, true);
  await assert.rejects(() => createReceiptTransaction(
    db,
    adminUid,
    companyId,
    "receipt_all_260",
    {
      customerId: "customer-a",
      amount: 259,
      paymentMethod: "bank",
      receiptDate: now,
    },
  ));
});

test("expenses post once and approval never overdrafts cash", async () => {
  const companyId = "trusted-expense";
  const adminUid = "expense-admin";
  const repUid = "expense-rep";
  await seedUser(adminUid, "admin", companyId);
  await seedUser(repUid, "sales_rep", companyId);
  await db.doc(`companies/${companyId}/cash_balances/company_cash`).set({
    id: "company_cash",
    companyId,
    cashAccount: "company_cash",
    salesRepId: "",
    amount: 100,
  });
  const adminInput = {
    amount: 25,
    expenseDate: now,
    category: "office",
    description: "Printer supplies",
    fundingSource: "company_cash",
  };
  const results = await Promise.all([
    retryTransientTransaction(() => createExpenseTransaction(
      db,
      adminUid,
      companyId,
      "expense_admin_once",
      adminInput,
    )),
    retryTransientTransaction(() => createExpenseTransaction(
      db,
      adminUid,
      companyId,
      "expense_admin_once",
      adminInput,
    )),
  ]);
  assert.equal(results.filter((result) => result.alreadyPosted).length, 1);
  assert.equal((await db.doc(
    `companies/${companyId}/cash_balances/company_cash`,
  ).get()).data().amount, 75);
  assert.equal((await db.collection(
    `companies/${companyId}/cash_movements`,
  ).where("sourceCollection", "==", "expenses").get()).size, 1);
  await assert.rejects(() => createExpenseTransaction(
    db,
    adminUid,
    companyId,
    "expense_admin_once",
    {...adminInput, amount: 30},
  ));

  const personal = await createExpenseTransaction(
    db,
    repUid,
    companyId,
    "expense_rep_personal",
    {
      amount: 8,
      expenseDate: now,
      category: "parking",
      fundingSource: "personal_cash",
    },
  );
  await approveExpenseTransaction(db, adminUid, companyId, personal.expenseId);
  const personalData = (await db.doc(
    `companies/${companyId}/expenses/${personal.expenseId}`,
  ).get()).data();
  assert.equal(personalData.status, "approved");
  assert.equal(personalData.reimbursementStatus, "payable");
  assert.equal(personalData.cashMovementId, "");

  await db.doc(`companies/${companyId}/cash_balances/rep_${repUid}`).set({
    id: `rep_${repUid}`,
    companyId,
    cashAccount: "rep_cash",
    salesRepId: repUid,
    amount: 10,
  });
  const collected = await createExpenseTransaction(
    db,
    repUid,
    companyId,
    "expense_rep_overdraft",
    {
      amount: 15,
      expenseDate: now,
      category: "fuel",
      fundingSource: "rep_collected_cash",
    },
  );
  await assert.rejects(() => approveExpenseTransaction(
    db,
    adminUid,
    companyId,
    collected.expenseId,
  ));
  assert.equal((await db.doc(
    `companies/${companyId}/expenses/${collected.expenseId}`,
  ).get()).data().status, "pending");
  assert.equal((await db.doc(
    `companies/${companyId}/cash_balances/rep_${repUid}`,
  ).get()).data().amount, 10);
});

test("settlement is atomic, concurrency-safe, replay-safe, and balance checked", async () => {
  const companyId = "trusted-settlement";
  const adminUid = "settlement-admin";
  const repUid = "settlement-rep";
  await seedUser(adminUid, "admin", companyId);
  await seedUser(repUid, "sales_rep", companyId);
  await db.doc(`companies/${companyId}/cash_balances/rep_${repUid}`).set({
    id: `rep_${repUid}`,
    companyId,
    cashAccount: "rep_cash",
    salesRepId: repUid,
    amount: 100,
  });
  await db.doc(`companies/${companyId}/cash_balances/company_cash`).set({
    id: "company_cash",
    companyId,
    cashAccount: "company_cash",
    salesRepId: "",
    amount: 20,
  });
  const input = {
    salesRepId: repUid,
    amount: 60,
    settlementDate: now,
    notes: "Cash handover",
  };
  const results = await Promise.all([
    retryTransientTransaction(() => recordCashSettlementTransaction(
      db,
      adminUid,
      companyId,
      "settlement_replay_key",
      input,
    )),
    retryTransientTransaction(() => recordCashSettlementTransaction(
      db,
      adminUid,
      companyId,
      "settlement_replay_key",
      input,
    )),
  ]);
  assert.equal(results.filter((result) => result.alreadyPosted).length, 1);
  const movements = await db.collection(`companies/${companyId}/cash_movements`)
    .where("settlementId", "==", "settlement_settlement_replay_key")
    .get();
  assert.equal(movements.size, 2);
  assert.equal((await db.doc(`companies/${companyId}/cash_balances/rep_${repUid}`).get()).data().amount, 40);
  assert.equal((await db.doc(`companies/${companyId}/cash_balances/company_cash`).get()).data().amount, 80);
  await assert.rejects(() => recordCashSettlementTransaction(
    db,
    repUid,
    companyId,
    "settlement_rep_forbidden",
    input,
  ));
  await assert.rejects(() => recordCashSettlementTransaction(
    db,
    adminUid,
    companyId,
    "settlement_replay_key",
    {...input, amount: 61},
  ));
  await assert.rejects(() => recordCashSettlementTransaction(
    db,
    adminUid,
    companyId,
    "settlement_too_large",
    {...input, amount: 41},
  ));
  assert.equal((await db.doc(`companies/${companyId}/cash_balances/rep_${repUid}`).get()).data().amount, 40);
});

test("company cash opening balance is atomic, unique, replay-safe, and reconciled", async () => {
  const companyId = "trusted-company-cash-opening";
  const otherAdminUid = "opening-other-admin";
  await seedUser(
    COMPANY_CASH_OPENING_BALANCE_UID,
    "admin",
    companyId,
    {email: COMPANY_CASH_OPENING_BALANCE_EMAIL},
  );
  await seedUser(otherAdminUid, "admin", companyId, {
    email: "other-admin@example.com",
  });
  await seedCashMovement(companyId, "opening-existing-receipt", {
    amount: 20,
  });
  await db.doc(`companies/${companyId}/cash_balances/company_cash`).set({
    id: "company_cash",
    companyId,
    cashAccount: "company_cash",
    salesRepId: "",
    amount: 20,
    lastMovementId: "opening-existing-receipt",
  });

  const input = {amount: 100.125, note: "Migration opening cash"};
  const results = await Promise.all([
    retryTransientTransaction(() => postCompanyCashOpeningBalanceTransaction(
      db,
      COMPANY_CASH_OPENING_BALANCE_UID,
      companyId,
      input,
    )),
    retryTransientTransaction(() => postCompanyCashOpeningBalanceTransaction(
      db,
      COMPANY_CASH_OPENING_BALANCE_UID,
      companyId,
      input,
    )),
  ]);
  assert.equal(results.filter((result) => result.alreadyPosted).length, 1);
  assert.deepEqual(
    results.map((result) => result.balanceAfter),
    [120.125, 120.125],
  );

  const movementRef = db.doc(
    `companies/${companyId}/cash_movements/${COMPANY_CASH_OPENING_BALANCE_MOVEMENT_ID}`,
  );
  const movement = (await movementRef.get()).data();
  assert.equal(movement.type, "opening_balance");
  assert.equal(movement.movementType, "opening_balance");
  assert.equal(movement.direction, "in");
  assert.equal(movement.cashAccount, "company_cash");
  assert.equal(movement.amount, 100.125);
  assert.equal(movement.notes, input.note);
  assert.equal(movement.immutable, true);
  assert.equal(
    movement.effectiveDate.toMillis(),
    COMPANY_CASH_OPENING_BALANCE_DATE.toMillis(),
  );
  assert.equal(movement.date.toMillis(), COMPANY_CASH_OPENING_BALANCE_DATE.toMillis());
  assert.equal(movement.movementDate.toMillis(), COMPANY_CASH_OPENING_BALANCE_DATE.toMillis());
  assert.equal(movement.balanceBefore, 20);
  assert.equal(movement.balanceAfter, 120.125);
  assert.equal(
    (await db.doc(`companies/${companyId}/cash_balances/company_cash`).get())
      .data().amount,
    120.125,
  );

  const openingMovements = await db
    .collection(`companies/${companyId}/cash_movements`)
    .where("cashAccount", "==", "company_cash")
    .where("movementType", "==", "opening_balance")
    .get();
  assert.equal(openingMovements.size, 1);

  await assert.rejects(
    () => postCompanyCashOpeningBalanceTransaction(
      db,
      COMPANY_CASH_OPENING_BALANCE_UID,
      companyId,
      {...input, amount: 101},
    ),
    (error) => error.code === "already-exists",
  );
  await assert.rejects(
    () => postCompanyCashOpeningBalanceTransaction(
      db,
      otherAdminUid,
      companyId,
      input,
    ),
    (error) => error.code === "permission-denied",
  );
  await db.doc(`users/${COMPANY_CASH_OPENING_BALANCE_UID}`).update({
    email: "wrong@example.com",
  });
  await assert.rejects(
    () => postCompanyCashOpeningBalanceTransaction(
      db,
      COMPANY_CASH_OPENING_BALANCE_UID,
      companyId,
      input,
    ),
    (error) => error.code === "permission-denied",
  );

  const reconciliation = await buildCashReconciliationPlan({db, companyId});
  assert.equal(reconciliation.issueCount, 0);
  const companyCash = reconciliation.accounts.find(
    (account) => account.documentId === "company_cash",
  );
  assert.equal(companyCash.calculatedBalance, 120.125);
  assert.equal(companyCash.storedBalance, 120.125);
  assert.equal(companyCash.difference, 0);

  for (const collection of [
    "customers",
    "customer_transactions",
    "invoices",
    "receipts",
    "sales_returns",
    "stock_movements",
    "rep_inventory_movements",
  ]) {
    const snapshot = await db.collection(
      `companies/${companyId}/${collection}`,
    ).get();
    assert.equal(snapshot.size, 0, collection);
  }
});

test("cash refund uses the original admin collection account, not assigned rep cash", async () => {
  const companyId = "trusted-return";
  const adminUid = "return-admin";
  const repUid = "return-rep";
  const invoiceId = "return-source-invoice";
  await seedUser(adminUid, "admin", companyId);
  await seedUser(repUid, "sales_rep", companyId);
  await seedCustomer(companyId, "customer-a", adminUid, 0, {totalSales: 10, totalPaid: 10});
  await db.doc("items/return-item").set({
    id: "return-item",
    name: "Return item",
    code: "R",
    unit: "piece",
    active: true,
    deleted: false,
    trackStock: true,
    currentStock: 9,
  });
  const originalMovementId = `${invoiceId}_line_000_return-item_invoice_sale`;
  await db.doc(`companies/${companyId}/stock_movements/${originalMovementId}`).set({
    id: originalMovementId,
    companyId,
    itemId: "return-item",
    sourceLineId: `${invoiceId}_line_000`,
  });
  await db.doc(`companies/${companyId}/invoices/${invoiceId}`).set({
    id: invoiceId,
    companyId,
    invoiceNumber: "INV-1",
    invoiceStatus: "confirmed",
    financialPosted: true,
    inventoryPosted: true,
    customerId: "customer-a",
    customerSnapshot: {id: "customer-a", name: "Customer"},
    salesRepId: repUid,
    salesRepName: "Assigned Rep",
    createdByUid: adminUid,
    createdByRole: "admin",
    stockSourceType: "companyWarehouse",
    inventoryMovementIds: [originalMovementId],
    invoiceDate: now,
    remainingAmount: 0,
    paidAmount: 10,
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
      itemId: "return-item",
      itemName: "Return item",
      itemCode: "R",
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
  await db.doc(`companies/${companyId}/cash_movements/${invoiceId}_cash`).set({
    id: `${invoiceId}_cash`,
    companyId,
    amount: 10,
    cashAccount: "company_cash",
    salesRepId: "",
    direction: "in",
  });
  await db.doc(`companies/${companyId}/cash_balances/company_cash`).set({
    id: "company_cash",
    companyId,
    cashAccount: "company_cash",
    salesRepId: "",
    amount: 10,
  });
  const result = await confirmSalesReturnTransaction(
    db,
    adminUid,
    companyId,
    "return-refund-account",
    {
      originalInvoiceId: invoiceId,
      refundType: "cash_refund",
      returnDate: now,
      reason: "Customer return",
      items: [{
        originalInvoiceItemId: `${invoiceId}:0`,
        returnedQuantity: 1,
      }],
    },
  );
  const refund = (await db.doc(
    `companies/${companyId}/cash_movements/${result.returnId}_cash_refund`,
  ).get()).data();
  assert.equal(refund.cashAccount, "company_cash");
  assert.equal(refund.salesRepId, "");
  assert.equal((await db.doc(`companies/${companyId}/cash_balances/company_cash`).get()).data().amount, 0);
  assert.equal((await db.doc("items/return-item").get()).data().currentStock, 10);
  const replay = await confirmSalesReturnTransaction(
    db,
    adminUid,
    companyId,
    "return-refund-account",
    {
      originalInvoiceId: invoiceId,
      refundType: "cash_refund",
      returnDate: now,
      reason: "Customer return",
      items: [{
        originalInvoiceItemId: `${invoiceId}:0`,
        returnedQuantity: 1,
      }],
    },
  );
  assert.equal(replay.alreadyPosted, true);
  await assert.rejects(() => confirmSalesReturnTransaction(
    db,
    adminUid,
    companyId,
    "return-over-sold-quantity",
    {
      originalInvoiceId: invoiceId,
      refundType: "credit_customer_balance",
      returnDate: now,
      reason: "Duplicate return",
      items: [{
        originalInvoiceItemId: `${invoiceId}:0`,
        returnedQuantity: 1,
      }],
    },
  ));
  assert.equal((await db.doc("items/return-item").get()).data().currentStock, 10);
});

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

async function seedInventoryTransfer(
  companyId,
  transferId,
  adminUid,
  repUid,
  itemId,
  overrides = {},
) {
  const quantity = overrides.quantity ?? 1;
  await db.doc(
    `companies/${companyId}/inventory_transfers/${transferId}`,
  ).set({
    id: transferId,
    companyId,
    transferNumber: "TRN-2026-000001",
    year: 2026,
    type: overrides.type ?? "warehouseToRep",
    status: "draft",
    salesRepId: repUid,
    salesRepNameSnapshot: repUid,
    lines: [{
      itemId,
      modelSnapshot: "stale-code",
      itemNameSnapshot: "stale-name",
      unitSnapshot: "stale-unit",
      quantity,
    }],
    totalQuantity: quantity,
    notes: "Trusted inventory transfer",
    createdByUid: adminUid,
    createdByName: adminUid,
    createdAt: now,
    updatedAt: now,
    confirmedByUid: "",
    confirmedByName: "",
    confirmedAt: null,
    cancelledByUid: "",
    cancelledAt: null,
    effectsVersion: 1,
  });
}

async function seedCustomer(companyId, customerId, ownerUid, balance, overrides = {}) {
  await db.doc(`companies/${companyId}/customers/${customerId}`).set({
    id: customerId,
    companyId,
    name: "Customer",
    active: true,
    createdByUid: ownerUid,
    currentBalance: balance,
    totalSales: 0,
    totalPaid: 0,
    ...overrides,
  });
}

async function seedCashMovement(companyId, movementId, overrides = {}) {
  await db.doc(`companies/${companyId}/cash_movements/${movementId}`).set({
    id: movementId,
    companyId,
    movementType: "receipt",
    type: "receipt_cash",
    direction: "in",
    amount: 10,
    cashAccount: "company_cash",
    salesRepId: "",
    sourceCollection: "receipts",
    sourceId: movementId,
    referenceId: movementId,
    date: now,
    movementDate: now,
    createdAt: now,
    ...overrides,
  });
}

async function retryTransientTransaction(operation, attempts = 3) {
  let lastError;
  for (let attempt = 0; attempt < attempts; attempt += 1) {
    try {
      return await operation();
    } catch (error) {
      lastError = error;
      const message = String(error?.message ?? error).toLowerCase();
      if (!message.includes("transaction is invalid or closed") || attempt === attempts - 1) {
        throw error;
      }
    }
  }
  throw lastError;
}

function invoiceDraft({id, companyId, customerId, uid, quantity}) {
  return {
    id,
    companyId,
    invoiceNumber: `INV-${id}`,
    invoiceStatus: "draft",
    invoiceDate: now,
    createdByUid: uid,
    createdByName: uid,
    createdByRole: "admin",
    salesRepId: uid,
    salesRepName: uid,
    customerId,
    stockSourceType: "companyWarehouse",
    items: [{
      itemId: "item-a",
      itemName: "Forged name",
      itemCode: "forged",
      unit: "forged",
      quantity,
      unitPrice: 10,
      discount: 0,
      taxPercent: 0,
      subtotal: 1,
      taxAmount: 999,
      total: 999,
    }],
    subtotal: 1,
    totalDiscount: 0,
    totalTax: 999,
    grandTotal: 999,
    hasReceivedPayment: false,
    paidAmount: 0,
    remainingAmount: 999,
    financialPosted: false,
    inventoryPosted: false,
    isLocked: false,
    customerTransactionIds: [],
    cashMovementIds: [],
    inventoryMovementIds: [],
  };
}
