const { readFileSync } = require("node:fs");
const { join } = require("node:path");
const { after, before, beforeEach, test } = require("node:test");

const {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} = require("@firebase/rules-unit-testing");
const {
  collection,
  deleteDoc,
  doc,
  getDoc,
  getDocs,
  query,
  serverTimestamp,
  setDoc,
  updateDoc,
  where,
  writeBatch,
} = require("firebase/firestore");

const projectId = "fatoora-rules-test";
const companyId = "default_company";
const adminUid = "admin";
const legacyAdminUid = "legacy-admin";
const repAUid = "rep-a";
const repBUid = "rep-b";
const pendingUid = "pending";
const inactiveUid = "inactive";

let testEnvironment;

before(async () => {
  testEnvironment = await initializeTestEnvironment({
    projectId,
    firestore: {
      rules: readFileSync(join(__dirname, "..", "..", "firestore.rules"), "utf8"),
    },
  });
});

after(async () => {
  await testEnvironment.cleanup();
});

beforeEach(async () => {
  await testEnvironment.clearFirestore();
  await testEnvironment.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await Promise.all([
      setDoc(doc(db, "users", adminUid), approvedUser(adminUid, "admin")),
      setDoc(doc(db, "users", legacyAdminUid), {
        uid: legacyAdminUid,
        role: "admin",
        active: true,
      }),
      setDoc(doc(db, "users", repAUid), approvedUser(repAUid, "sales_rep")),
      setDoc(doc(db, "users", repBUid), approvedUser(repBUid, "sales_rep")),
      setDoc(doc(db, "users", pendingUid), {
        ...approvedUser(pendingUid, "pending_sales_rep"),
        active: false,
        approvalStatus: "pending",
      }),
      setDoc(doc(db, "users", inactiveUid), {
        ...approvedUser(inactiveUid, "admin"),
        active: false,
      }),
      setDoc(
        businessDoc(db, "customers", "customer-a"),
        createdByOwned("customer-a", repAUid),
      ),
      setDoc(
        businessDoc(db, "customers", "customer-b"),
        createdByOwned("customer-b", repBUid),
      ),
      setDoc(
        businessDoc(db, "invoices", "invoice-a"),
        salesRepOwned("invoice-a", repAUid, repAUid),
      ),
      setDoc(
        businessDoc(db, "invoices", "invoice-b"),
        salesRepOwned("invoice-b", repBUid, repBUid),
      ),
      setDoc(
        businessDoc(db, "invoices", "invoice-admin-for-a"),
        salesRepOwned("invoice-admin-for-a", repAUid, adminUid),
      ),
      setDoc(
        businessDoc(db, "invoices", "invoice-created-a-owned-b"),
        salesRepOwned("invoice-created-a-owned-b", repBUid, repAUid),
      ),
      setDoc(
        businessDoc(db, "receipts", "receipt-a"),
        salesRepOwned("receipt-a", repAUid, repAUid),
      ),
      setDoc(
        businessDoc(db, "receipts", "receipt-b"),
        salesRepOwned("receipt-b", repBUid, repBUid),
      ),
      setDoc(
        businessDoc(db, "cash_movements", "cash-a"),
        {
          ...salesRepOwned("cash-a", repAUid, repAUid),
          cashAccount: "rep_cash",
        },
      ),
      setDoc(
        businessDoc(db, "cash_movements", "cash-b"),
        {
          ...salesRepOwned("cash-b", repBUid, repBUid),
          cashAccount: "rep_cash",
        },
      ),
      setDoc(
        businessDoc(db, "cash_movements", "company-cash-for-a"),
        {
          ...salesRepOwned("company-cash-for-a", repAUid, adminUid),
          cashAccount: "company_cash",
        },
      ),
      setDoc(
        businessDoc(db, "expenses", "expense-a"),
        expenseOwned("expense-a", repAUid, repAUid),
      ),
      setDoc(
        businessDoc(db, "expenses", "expense-b"),
        expenseOwned("expense-b", repBUid, repBUid),
      ),
      setDoc(
        businessDoc(db, "expenses", "expense-personal-a"),
        expenseOwned("expense-personal-a", repAUid, repAUid, {
          fundingSource: "personal_cash",
        }),
      ),
      setDoc(
        businessDoc(db, "expenses", "expense-admin"),
        expenseOwned("expense-admin", adminUid, adminUid, {
          salesRepId: "",
          fundingSource: "company_cash",
          status: "posted",
          cashMovementId: "expense-admin_cash_out",
        }),
      ),
      setDoc(
        businessDoc(db, "sales_returns", "return-a"),
        salesRepOwned("return-a", repAUid, repAUid),
      ),
      setDoc(
        businessDoc(db, "sales_returns", "return-b"),
        salesRepOwned("return-b", repBUid, repBUid),
      ),
      setDoc(
        businessDoc(db, "customer_transactions", "transaction-a"),
        {
          ...salesRepOwned("transaction-a", repAUid, repAUid),
          customerId: "customer-a",
        },
      ),
      setDoc(
        businessDoc(db, "customer_transactions", "transaction-b"),
        {
          ...salesRepOwned("transaction-b", repBUid, repBUid),
          customerId: "customer-b",
        },
      ),
      setDoc(
        businessDoc(db, "customer_transactions", "transaction-orphan"),
        {
          ...salesRepOwned("transaction-orphan", repAUid, repAUid),
          customerId: "missing-customer",
        },
      ),
      setDoc(
        businessDoc(db, "customer_transactions", "transaction-legacy-a"),
        {
          ...createdByOwned("transaction-legacy-a", adminUid),
          customerId: "customer-a",
        },
      ),
      setDoc(
        businessDoc(db, "stock_movements", "stock-a"),
        createdByOwned("stock-a", repAUid),
      ),
      setDoc(
        businessDoc(db, "stock_movements", "stock-b"),
        createdByOwned("stock-b", repBUid),
      ),
      setDoc(doc(db, "items", "item-a"), {
        id: "item-a",
        createdBy: adminUid,
        createdAt: new Date("2026-07-01T10:00:00.000Z"),
        updatedAt: new Date("2026-07-01T10:00:00.000Z"),
        currentStock: 10,
        trackStock: true,
        deleted: false,
      }),
      setDoc(doc(db, "items", "item-confirm"), {
        id: "item-confirm",
        createdBy: adminUid,
        createdAt: new Date("2026-07-01T10:00:00.000Z"),
        updatedAt: new Date("2026-07-01T10:00:00.000Z"),
        currentStock: 10,
        trackStock: true,
        deleted: false,
      }),
      setDoc(
        businessDoc(db, "inventory_transfers", "transfer-a"),
        salesRepOwned("transfer-a", repAUid, adminUid),
      ),
      setDoc(
        businessDoc(db, "inventory_transfers", "transfer-b"),
        salesRepOwned("transfer-b", repBUid, adminUid),
      ),
      setDoc(
        businessDoc(db, "rep_inventory_balances", `${repAUid}_item-a`),
        {
          ...salesRepOwned(`${repAUid}_item-a`, repAUid, adminUid),
          itemId: "item-a",
          quantity: 5,
        },
      ),
      setDoc(
        businessDoc(db, "rep_inventory_balances", `${repBUid}_item-a`),
        {
          ...salesRepOwned(`${repBUid}_item-a`, repBUid, adminUid),
          itemId: "item-a",
          quantity: 7,
        },
      ),
      setDoc(
        businessDoc(db, "rep_inventory_movements", "rep-movement-a"),
        salesRepOwned("rep-movement-a", repAUid, adminUid),
      ),
      setDoc(
        businessDoc(db, "rep_inventory_movements", "rep-movement-b"),
        salesRepOwned("rep-movement-b", repBUid, adminUid),
      ),
    ]);
  });
});

test("approved active admin can read every financial repository collection", async () => {
  const db = authenticatedDb(adminUid);
  for (const [collectionName, documentId] of [
    ["customers", "customer-b"],
    ["invoices", "invoice-b"],
    ["receipts", "receipt-b"],
    ["sales_returns", "return-b"],
    ["customer_transactions", "transaction-orphan"],
    ["cash_movements", "cash-b"],
    ["cash_movements", "company-cash-for-a"],
    ["expenses", "expense-b"],
    ["stock_movements", "stock-b"],
  ]) {
    await assertSucceeds(getDoc(businessDoc(db, collectionName, documentId)));
    await assertSucceeds(getDocs(businessCollection(db, collectionName)));
  }
});

test("legacy active admin profile remains compatible with default company", async () => {
  const db = authenticatedDb(legacyAdminUid);
  await assertSucceeds(getDocs(businessCollection(db, "invoices")));
  await assertSucceeds(
    getDocs(businessCollection(db, "customer_transactions")),
  );
});

test("rep A can directly read own documents and cannot read rep B documents", async () => {
  const db = authenticatedDb(repAUid);
  for (const [collectionName, ownId, otherId] of [
    ["customers", "customer-a", "customer-b"],
    ["invoices", "invoice-a", "invoice-b"],
    ["receipts", "receipt-a", "receipt-b"],
    ["sales_returns", "return-a", "return-b"],
    ["customer_transactions", "transaction-a", "transaction-b"],
    ["cash_movements", "cash-a", "cash-b"],
    ["expenses", "expense-a", "expense-b"],
    ["stock_movements", "stock-a", "stock-b"],
  ]) {
    await assertSucceeds(getDoc(businessDoc(db, collectionName, ownId)));
    await assertFails(getDoc(businessDoc(db, collectionName, otherId)));
  }
});

test("rep B has the inverse direct-read boundary", async () => {
  const db = authenticatedDb(repBUid);
  for (const [collectionName, ownId, otherId] of [
    ["customers", "customer-b", "customer-a"],
    ["invoices", "invoice-b", "invoice-a"],
    ["receipts", "receipt-b", "receipt-a"],
    ["sales_returns", "return-b", "return-a"],
    ["customer_transactions", "transaction-b", "transaction-a"],
    ["cash_movements", "cash-b", "cash-a"],
    ["expenses", "expense-b", "expense-a"],
    ["stock_movements", "stock-b", "stock-a"],
  ]) {
    await assertSucceeds(getDoc(businessDoc(db, collectionName, ownId)));
    await assertFails(getDoc(businessDoc(db, collectionName, otherId)));
  }
});

test("sales reps must use owner-constrained collection queries", async () => {
  for (const uid of [repAUid, repBUid]) {
    const db = authenticatedDb(uid);
    const otherUid = uid === repAUid ? repBUid : repAUid;
    for (const collectionName of [
      "invoices",
      "receipts",
      "sales_returns",
      "customer_transactions",
    ]) {
      await assertSucceeds(
        getDocs(
          query(
            businessCollection(db, collectionName),
            where("salesRepId", "==", uid),
          ),
        ),
      );
      await assertFails(
        getDocs(
          query(
            businessCollection(db, collectionName),
            where("salesRepId", "==", otherUid),
          ),
        ),
      );
      await assertFails(getDocs(businessCollection(db, collectionName)));
    }
    await assertSucceeds(
      getDocs(
        query(
          businessCollection(db, "cash_movements"),
          where("salesRepId", "==", uid),
          where("cashAccount", "==", "rep_cash"),
        ),
      ),
    );
    await assertFails(
      getDocs(
        query(
          businessCollection(db, "cash_movements"),
          where("salesRepId", "==", uid),
        ),
      ),
    );
    await assertFails(
      getDocs(
        query(
          businessCollection(db, "cash_movements"),
          where("salesRepId", "==", otherUid),
          where("cashAccount", "==", "rep_cash"),
        ),
      ),
    );
    await assertFails(
      getDocs(
        query(
          businessCollection(db, "cash_movements"),
          where("salesRepId", "==", uid),
          where("cashAccount", "==", "company_cash"),
        ),
      ),
    );
    await assertFails(getDocs(businessCollection(db, "cash_movements")));

    await assertSucceeds(
      getDocs(
        query(
          businessCollection(db, "expenses"),
          where("paidByUid", "==", uid),
        ),
      ),
    );
    await assertFails(
      getDocs(
        query(
          businessCollection(db, "expenses"),
          where("paidByUid", "==", otherUid),
        ),
      ),
    );
    await assertFails(getDocs(businessCollection(db, "expenses")));
    await assertSucceeds(
      getDocs(
        query(
          businessCollection(db, "stock_movements"),
          where("createdByUid", "==", uid),
        ),
      ),
    );
    await assertFails(
      getDocs(
        query(
          businessCollection(db, "stock_movements"),
          where("createdByUid", "==", otherUid),
        ),
      ),
    );
    await assertFails(getDocs(businessCollection(db, "stock_movements")));

    await assertSucceeds(
      getDocs(
        query(
          businessCollection(db, "customers"),
          where("createdByUid", "==", uid),
        ),
      ),
    );
    await assertSucceeds(
      getDocs(
        query(
          businessCollection(db, "customers"),
          where("active", "==", true),
          where("phoneNormalized", "==", "0790000000"),
          where("createdByUid", "==", uid),
        ),
      ),
    );
    await assertFails(getDocs(businessCollection(db, "customers")));
  }
});

test("pending and inactive users cannot read financial data", async () => {
  for (const uid of [pendingUid, inactiveUid]) {
    const db = authenticatedDb(uid);
    for (const [collectionName, documentId] of [
      ["customers", "customer-a"],
      ["invoices", "invoice-a"],
      ["receipts", "receipt-a"],
      ["sales_returns", "return-a"],
      ["customer_transactions", "transaction-a"],
      ["cash_movements", "cash-a"],
      ["expenses", "expense-a"],
      ["stock_movements", "stock-a"],
    ]) {
      await assertFails(getDoc(businessDoc(db, collectionName, documentId)));
      await assertFails(getDocs(businessCollection(db, collectionName)));
    }
  }
});

test("sales representatives read only their own custody documents", async () => {
  const db = authenticatedDb(repAUid);

  for (const [collectionName, ownId, otherId] of [
    ["inventory_transfers", "transfer-a", "transfer-b"],
    [
      "rep_inventory_balances",
      `${repAUid}_item-a`,
      `${repBUid}_item-a`,
    ],
    ["rep_inventory_movements", "rep-movement-a", "rep-movement-b"],
  ]) {
    await assertSucceeds(getDoc(businessDoc(db, collectionName, ownId)));
    await assertFails(getDoc(businessDoc(db, collectionName, otherId)));
  }
});

test("approved users can check missing custody posting documents", async () => {
  for (const uid of [adminUid, repAUid]) {
    const db = authenticatedDb(uid);
    await assertSucceeds(
      getDoc(businessDoc(db, "rep_inventory_balances", "missing-balance")),
    );
    await assertSucceeds(
      getDoc(businessDoc(db, "rep_inventory_movements", "missing-movement")),
    );
  }
});

test("admin reads all representative custody documents", async () => {
  const db = authenticatedDb(adminUid);

  await assertSucceeds(
    getDoc(businessDoc(db, "inventory_transfers", "transfer-b")),
  );
  await assertSucceeds(
    getDoc(
      businessDoc(
        db,
        "rep_inventory_balances",
        `${repBUid}_item-a`,
      ),
    ),
  );
  await assertSucceeds(
    getDoc(businessDoc(db, "rep_inventory_movements", "rep-movement-b")),
  );
});

test("pending and inactive users cannot read representative custody", async () => {
  for (const uid of [pendingUid, inactiveUid]) {
    const db = authenticatedDb(uid);
    await assertFails(
      getDoc(businessDoc(db, "inventory_transfers", "transfer-a")),
    );
    await assertFails(
      getDoc(
        businessDoc(db, "rep_inventory_balances", `${repAUid}_item-a`),
      ),
    );
  }
});

test("approved admin can create, edit, cancel, and delete transfer drafts", async () => {
  const db = authenticatedDb(adminUid);
  const editableRef = businessDoc(db, "inventory_transfers", "draft-editable");
  const deletableRef = businessDoc(db, "inventory_transfers", "draft-delete");

  await assertSucceeds(
    setDoc(editableRef, transferDraftPayload("draft-editable")),
  );
  await assertSucceeds(
    updateDoc(editableRef, {
      notes: "Updated draft",
      updatedAt: serverTimestamp(),
    }),
  );
  await assertSucceeds(
    updateDoc(editableRef, {
      status: "cancelled",
      cancelledByUid: adminUid,
      cancelledAt: serverTimestamp(),
      updatedAt: serverTimestamp(),
    }),
  );
  await assertSucceeds(
    setDoc(deletableRef, transferDraftPayload("draft-delete")),
  );
  await assertSucceeds(deleteDoc(deletableRef));
});

test("representatives cannot manage transfers or directly change balances", async () => {
  const db = authenticatedDb(repAUid);

  await assertFails(
    setDoc(
      businessDoc(db, "inventory_transfers", "rep-created"),
      transferDraftPayload("rep-created", repAUid),
    ),
  );
  await assertFails(
    updateDoc(businessDoc(db, "inventory_transfers", "transfer-a"), {
      notes: "Tampered",
      updatedAt: serverTimestamp(),
    }),
  );
  await assertFails(
    updateDoc(
      businessDoc(db, "rep_inventory_balances", `${repAUid}_item-a`),
      {
        quantity: 999,
        updatedAt: serverTimestamp(),
      },
    ),
  );
});

test("representative movements are immutable for admins and reps", async () => {
  for (const uid of [adminUid, repAUid]) {
    const db = authenticatedDb(uid);
    const movementRef = businessDoc(
      db,
      "rep_inventory_movements",
      "rep-movement-a",
    );
    await assertFails(updateDoc(movementRef, { quantity: 999 }));
    await assertFails(deleteDoc(movementRef));
  }
});

test("admin can atomically confirm a warehouse-to-representative transfer", async () => {
  const db = authenticatedDb(adminUid);
  const transferId = "confirm-delivery";
  const itemId = "item-confirm";
  const companyMovementId = `${transferId}_${itemId}_warehouse`;
  const repMovementId = `${transferId}_${repAUid}_${itemId}`;
  const transferRef = businessDoc(
    db,
    "inventory_transfers",
    transferId,
  );
  const balanceRef = businessDoc(
    db,
    "rep_inventory_balances",
    `${repAUid}_${itemId}`,
  );
  const draftPayload = transferDraftPayload(transferId);
  draftPayload.lines[0].itemId = itemId;
  await assertSucceeds(
    setDoc(transferRef, draftPayload),
  );

  const batch = writeBatch(db);
  batch.update(doc(db, "items", itemId), {
    currentStock: 8,
    inventoryUpdatedAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
    lastInventoryReferenceType: "inventoryTransfer",
    lastInventoryReferenceId: transferId,
    lastStockMovementId: companyMovementId,
  });
  batch.set(balanceRef, {
    id: `${repAUid}_${itemId}`,
    companyId,
    salesRepId: repAUid,
    itemId,
    quantity: 2,
    modelSnapshot: "A-1",
    itemNameSnapshot: "Item A",
    unitSnapshot: "piece",
    createdAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
    lastMovementId: repMovementId,
    lastReferenceType: "inventoryTransfer",
    lastReferenceId: transferId,
  });
  batch.set(businessDoc(db, "stock_movements", companyMovementId), {
    id: companyMovementId,
    companyId,
    warehouseId: "default_warehouse",
    itemId,
    itemName: "Item A",
    itemCode: "A-1",
    movementType: "inventory_transfer",
    direction: "out",
    quantity: 2,
    quantityBefore: 10,
    quantityAfter: 8,
    referenceType: "inventory_transfer",
    referenceId: transferId,
    referenceNumber: "TRN-2026-000001",
    movementDate: serverTimestamp(),
    notes: "",
    createdByUid: adminUid,
    createdByName: "Admin",
    createdByRole: "admin",
    createdAt: serverTimestamp(),
  });
  batch.set(businessDoc(db, "rep_inventory_movements", repMovementId), {
    id: repMovementId,
    companyId,
    salesRepId: repAUid,
    salesRepNameSnapshot: "Rep A",
    itemId,
    modelSnapshot: "A-1",
    itemNameSnapshot: "Item A",
    unitSnapshot: "piece",
    direction: "in",
    quantity: 2,
    quantityBefore: 0,
    quantityAfter: 2,
    reason: "warehouseDelivery",
    referenceType: "inventoryTransfer",
    referenceId: transferId,
    referenceNumber: "TRN-2026-000001",
    transferType: "warehouseToRep",
    createdByUid: adminUid,
    createdByName: "Admin",
    createdAt: serverTimestamp(),
  });
  batch.update(transferRef, {
    status: "confirmed",
    lines: [
      {
        itemId,
        modelSnapshot: "A-1",
        itemNameSnapshot: "Item A",
        unitSnapshot: "piece",
        quantity: 2,
        warehouseQuantityBefore: 10,
        warehouseQuantityAfter: 8,
        repQuantityBefore: 0,
        repQuantityAfter: 2,
        companyMovementId,
        repMovementId,
      },
    ],
    confirmedByUid: adminUid,
    confirmedByName: "Admin",
    confirmedAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
    effectsVersion: 1,
  });

  await assertSucceeds(batch.commit());
});

test("stock movement queries are scoped only by createdByUid", async () => {
  const db = authenticatedDb(repAUid);
  await assertSucceeds(
    getDocs(
      query(
        businessCollection(db, "stock_movements"),
        where("createdByUid", "==", repAUid),
      ),
    ),
  );
  await assertFails(
    getDocs(
      query(
        businessCollection(db, "stock_movements"),
        where("createdByUid", "==", repBUid),
      ),
    ),
  );
});

test("customer owner fallback supports legacy transactions without salesRepId", async () => {
  const repADb = authenticatedDb(repAUid);
  const repBDb = authenticatedDb(repBUid);
  const transaction = ["customer_transactions", "transaction-legacy-a"];

  await assertSucceeds(getDoc(businessDoc(repADb, ...transaction)));
  await assertFails(getDoc(businessDoc(repBDb, ...transaction)));
});

test("admin can atomically post a customer-owes opening balance", async () => {
  await seedOpeningCustomer("opening-admin-customer", repAUid);
  const db = authenticatedDb(adminUid);

  await assertSucceeds(
    commitOpeningBalance(db, {
      customerId: "opening-admin-customer",
      actorUid: adminUid,
      actorName: "Admin",
      actorRole: "admin",
      type: "customer_owes",
      amount: 1500,
      balanceBefore: 25,
      balanceAfter: 1525,
    }),
  );

  const customer = await getDoc(
    businessDoc(db, "customers", "opening-admin-customer"),
  );
  if (customer.data().currentBalance !== 1525) {
    throw new Error("Opening debit was not applied to the customer balance");
  }
  if (customer.data().totalSales !== 100 || customer.data().totalPaid !== 40) {
    throw new Error("Opening balance changed sales or paid totals");
  }
});

test("sales rep can post customer credit only for an owned customer", async () => {
  await seedOpeningCustomer("opening-rep-customer", repAUid);
  await seedOpeningCustomer("opening-other-customer", repBUid);
  const db = authenticatedDb(repAUid);

  await assertSucceeds(
    commitOpeningBalance(db, {
      customerId: "opening-rep-customer",
      actorUid: repAUid,
      actorName: "Rep A",
      actorRole: "sales_rep",
      type: "customer_credit",
      amount: 75.5,
      balanceBefore: 25,
      balanceAfter: -50.5,
    }),
  );
  await assertFails(
    commitOpeningBalance(db, {
      customerId: "opening-other-customer",
      actorUid: repAUid,
      actorName: "Rep A",
      actorRole: "sales_rep",
      type: "customer_owes",
      amount: 20,
      balanceBefore: 25,
      balanceAfter: 45,
    }),
  );
});

test("opening balance requires its matching customer update and ledger create", async () => {
  await seedOpeningCustomer("opening-linked-customer", repAUid);
  const db = authenticatedDb(adminUid);
  const transactionId = "opening-linked-customer_opening_balance";

  await assertFails(
    setDoc(
      businessDoc(db, "customer_transactions", transactionId),
      openingBalancePayload({
        customerId: "opening-linked-customer",
        actorUid: adminUid,
        actorName: "Admin",
        actorRole: "admin",
        type: "customer_owes",
        amount: 10,
        balanceBefore: 25,
        balanceAfter: 35,
      }),
    ),
  );
  await assertFails(
    updateDoc(businessDoc(db, "customers", "opening-linked-customer"), {
      currentBalance: 35,
      lastOpeningBalanceTransactionId: transactionId,
      updatedAt: serverTimestamp(),
    }),
  );
});

test("opening balance cannot change sales totals or be posted twice", async () => {
  await seedOpeningCustomer("opening-once-customer", repAUid);
  const db = authenticatedDb(adminUid);
  const options = {
    customerId: "opening-once-customer",
    actorUid: adminUid,
    actorName: "Admin",
    actorRole: "admin",
    type: "customer_owes",
    amount: 10,
    balanceBefore: 25,
    balanceAfter: 35,
  };

  const tampered = writeBatch(db);
  tampered.update(businessDoc(db, "customers", options.customerId), {
    currentBalance: 35,
    totalSales: 999,
    lastOpeningBalanceTransactionId:
      "opening-once-customer_opening_balance",
    updatedAt: serverTimestamp(),
  });
  tampered.set(
    businessDoc(
      db,
      "customer_transactions",
      "opening-once-customer_opening_balance",
    ),
    openingBalancePayload(options),
  );
  await assertFails(tampered.commit());

  await assertSucceeds(commitOpeningBalance(db, options));
  await assertFails(
    commitOpeningBalance(db, {
      ...options,
      balanceBefore: 35,
      balanceAfter: 45,
    }),
  );
});

test("an admin-created invoice assigned to rep A is visible only to rep A", async () => {
  const repADb = authenticatedDb(repAUid);
  const repBDb = authenticatedDb(repBUid);
  const documentPath = ["invoices", "invoice-admin-for-a"];

  await assertSucceeds(getDoc(businessDoc(repADb, ...documentPath)));
  await assertFails(getDoc(businessDoc(repBDb, ...documentPath)));

  const repAQuery = await assertSucceeds(
    getDocs(
      query(
        businessCollection(repADb, "invoices"),
        where("salesRepId", "==", repAUid),
      ),
    ),
  );
  const ids = repAQuery.docs.map((snapshot) => snapshot.id);
  if (!ids.includes("invoice-admin-for-a")) {
    throw new Error("Assigned admin-created invoice was missing from rep A query");
  }
});

test("invoice ownership follows salesRepId rather than createdByUid", async () => {
  const repADb = authenticatedDb(repAUid);
  const repBDb = authenticatedDb(repBUid);
  const documentPath = ["invoices", "invoice-created-a-owned-b"];

  await assertFails(getDoc(businessDoc(repADb, ...documentPath)));
  await assertSucceeds(getDoc(businessDoc(repBDb, ...documentPath)));
});

test("sales reps cannot read company cash movements even when salesRepId matches", async () => {
  const repADb = authenticatedDb(repAUid);
  const adminDb = authenticatedDb(adminUid);

  await assertFails(
    getDoc(businessDoc(repADb, "cash_movements", "company-cash-for-a")),
  );
  await assertSucceeds(
    getDoc(businessDoc(adminDb, "cash_movements", "company-cash-for-a")),
  );
});

test("sales reps can create only pending own expenses", async () => {
  const db = authenticatedDb(repAUid);

  await assertSucceeds(
    setDoc(
      businessDoc(db, "expenses", "new-rep-expense"),
      expenseCreatePayload("new-rep-expense", repAUid, "sales_rep"),
    ),
  );
  await assertFails(
    setDoc(
      businessDoc(db, "expenses", "bad-company-expense"),
      expenseCreatePayload("bad-company-expense", repAUid, "sales_rep", {
        fundingSource: "company_cash",
        status: "posted",
        salesRepId: "",
        salesRepName: "",
        cashMovementId: "bad-company-expense_cash_out",
        approvedByUid: repAUid,
        approvedByName: "Rep A",
        approvedAt: serverTimestamp(),
      }),
    ),
  );
});

test("admin can create posted company cash expenses", async () => {
  const db = authenticatedDb(adminUid);

  await assertSucceeds(
    setDoc(
      businessDoc(db, "expenses", "new-admin-expense"),
      expenseCreatePayload("new-admin-expense", adminUid, "admin"),
    ),
  );
});

test("admin can approve collected-cash and personal-cash rep expenses", async () => {
  const adminDb = authenticatedDb(adminUid);
  const repDb = authenticatedDb(repAUid);

  await assertSucceeds(
    updateDoc(businessDoc(adminDb, "expenses", "expense-a"), {
      status: "approved",
      cashMovementId: "expense-a_cash_out",
      reimbursementStatus: "none",
      approvedByUid: adminUid,
      approvedByName: "Admin",
      approvedAt: serverTimestamp(),
      updatedAt: serverTimestamp(),
    }),
  );
  await assertSucceeds(
    updateDoc(businessDoc(adminDb, "expenses", "expense-personal-a"), {
      status: "approved",
      cashMovementId: "",
      reimbursementStatus: "payable",
      approvedByUid: adminUid,
      approvedByName: "Admin",
      approvedAt: serverTimestamp(),
      updatedAt: serverTimestamp(),
    }),
  );
  await assertFails(
    updateDoc(businessDoc(repDb, "expenses", "expense-b"), {
      status: "approved",
      cashMovementId: "expense-b_cash_out",
      reimbursementStatus: "none",
      approvedByUid: repAUid,
      approvedByName: "Rep A",
      approvedAt: serverTimestamp(),
      updatedAt: serverTimestamp(),
    }),
  );
});

test("admin can reject pending expenses without changing financial fields", async () => {
  const adminDb = authenticatedDb(adminUid);

  await assertSucceeds(
    updateDoc(businessDoc(adminDb, "expenses", "expense-a"), {
      status: "rejected",
      reimbursementStatus: "none",
      rejectedByUid: adminUid,
      rejectedByName: "Admin",
      rejectedAt: serverTimestamp(),
      rejectionReason: "Missing receipt",
      updatedAt: serverTimestamp(),
    }),
  );
  await assertFails(
    updateDoc(businessDoc(adminDb, "expenses", "expense-b"), {
      status: "rejected",
      amount: 999,
      reimbursementStatus: "none",
      rejectedByUid: adminUid,
      rejectedByName: "Admin",
      rejectedAt: serverTimestamp(),
      rejectionReason: "Bad amount",
      updatedAt: serverTimestamp(),
    }),
  );
});

test("audit events are admin-readable and immutable to every client", async () => {
  const auditPath = (db) => doc(
    db, "companies", companyId, "audit_events", "event-1",
  );
  await testEnvironment.withSecurityRulesDisabled(async (context) => {
    await setDoc(auditPath(context.firestore()), {
      schemaVersion: 1,
      companyId,
      eventId: "event-1",
      action: "invoice.confirmed",
      occurredAt: new Date("2026-07-29T10:00:00.000Z"),
    });
  });

  await assertSucceeds(getDoc(auditPath(authenticatedDb(adminUid))));
  await assertSucceeds(getDoc(auditPath(authenticatedDb(legacyAdminUid))));
  await assertFails(getDoc(auditPath(authenticatedDb(repAUid))));
  await assertFails(getDoc(auditPath(authenticatedDb(pendingUid))));
  await assertFails(getDoc(auditPath(authenticatedDb(inactiveUid))));
  await assertFails(getDoc(auditPath(
    testEnvironment.unauthenticatedContext().firestore(),
  )));

  const adminRef = auditPath(authenticatedDb(adminUid));
  await assertFails(setDoc(doc(
    authenticatedDb(adminUid), "companies", companyId, "audit_events", "new",
  ), {action: "forged"}));
  await assertFails(updateDoc(adminRef, {action: "forged"}));
  await assertFails(deleteDoc(adminRef));
});

function authenticatedDb(uid) {
  return testEnvironment.authenticatedContext(uid, {
    email: `${uid}@example.test`,
  }).firestore();
}

async function seedOpeningCustomer(customerId, ownerUid) {
  await testEnvironment.withSecurityRulesDisabled(async (context) => {
    await setDoc(businessDoc(context.firestore(), "customers", customerId), {
      id: customerId,
      companyId,
      name: "Legacy Customer",
      phone: "",
      addressText: "",
      city: "",
      area: "",
      notes: "",
      active: true,
      createdByUid: ownerUid,
      createdByName: ownerUid === repAUid ? "Rep A" : "Rep B",
      createdByRole: "sales_rep",
      createdAt: new Date("2026-01-01T00:00:00.000Z"),
      updatedAt: new Date("2026-01-01T00:00:00.000Z"),
      currentBalance: 25,
      totalSales: 100,
      totalPaid: 40,
      searchKeywords: ["legacy"],
      nameLower: "legacy customer",
      phoneNormalized: "",
      cityLower: "",
      areaLower: "",
    });
  });
}

function commitOpeningBalance(db, options) {
  const transactionId = `${options.customerId}_opening_balance`;
  const batch = writeBatch(db);
  batch.update(businessDoc(db, "customers", options.customerId), {
    currentBalance: options.balanceAfter,
    lastOpeningBalanceTransactionId: transactionId,
    updatedAt: serverTimestamp(),
  });
  batch.set(
    businessDoc(db, "customer_transactions", transactionId),
    openingBalancePayload(options),
  );
  return batch.commit();
}

function openingBalancePayload(options) {
  const transactionId = `${options.customerId}_opening_balance`;
  const isDebit = options.type === "customer_owes";
  return {
    id: transactionId,
    companyId,
    customerId: options.customerId,
    customerName: "Legacy Customer",
    transactionType: "opening_balance",
    type: "opening_balance",
    sourceCollection: "customer_transactions",
    sourceId: transactionId,
    sourceNumber: "OPENING",
    transactionDate: new Date("2025-12-31T00:00:00.000Z"),
    debitAmount: isDebit ? options.amount : 0,
    creditAmount: isDebit ? 0 : options.amount,
    balanceBefore: options.balanceBefore,
    balanceAfter: options.balanceAfter,
    openingBalanceType: options.type,
    amount: options.amount,
    signedAmount: isDebit ? options.amount : -options.amount,
    invoiceId: "",
    invoiceNumber: "",
    returnInvoiceId: "",
    returnNumber: "",
    originalInvoiceId: "",
    originalInvoiceNumber: "",
    receiptId: "",
    receiptNumber: "",
    notes: "Imported legacy balance",
    createdByUid: options.actorUid,
    createdByName: options.actorName,
    createdByRole: options.actorRole,
    salesRepId: options.actorRole === "sales_rep" ? options.actorUid : "",
    salesRepName: options.actorRole === "sales_rep" ? options.actorName : "",
    createdAt: serverTimestamp(),
    referenceId: transactionId,
  };
}

function approvedUser(uid, role) {
  return {
    uid,
    role,
    active: true,
    approvalStatus: "approved",
    companyId,
  };
}

function salesRepOwned(id, salesRepId, createdByUid) {
  return {
    id,
    companyId,
    salesRepId,
    createdByUid,
  };
}

function createdByOwned(id, createdByUid) {
  return {
    id,
    companyId,
    createdByUid,
  };
}

function expenseOwned(id, paidByUid, createdByUid, overrides = {}) {
  const role = createdByUid === adminUid ? "admin" : "sales_rep";
  const name = createdByUid === adminUid ? "Admin" : `Rep ${createdByUid}`;
  return {
    id,
    companyId,
    amount: 10,
    expenseDate: new Date("2026-07-01T10:00:00.000Z"),
    category: "fuel",
    categoryName: "fuel",
    customCategoryName: "",
    description: "Fuel",
    notes: "Fuel",
    paidByUid,
    paidByName: name,
    paidByRole: role,
    salesRepId: role === "sales_rep" ? paidByUid : "",
    salesRepName: role === "sales_rep" ? name : "",
    paymentMethod: "cash",
    fundingSource: role === "admin" ? "company_cash" : "rep_collected_cash",
    status: role === "admin" ? "posted" : "pending",
    cashMovementId: role === "admin" ? `${id}_cash_out` : "",
    reimbursementStatus: "none",
    approvedByUid: role === "admin" ? adminUid : "",
    approvedByName: role === "admin" ? "Admin" : "",
    rejectedByUid: "",
    rejectedByName: "",
    rejectionReason: "",
    createdByUid,
    createdByName: name,
    createdByRole: role,
    createdAt: new Date("2026-07-01T10:00:00.000Z"),
    updatedAt: new Date("2026-07-01T10:00:00.000Z"),
    ...overrides,
  };
}

function expenseCreatePayload(id, uid, role, overrides = {}) {
  const name = role === "admin" ? "Admin" : uid === repAUid ? "Rep A" : "Rep B";
  const isAdmin = role === "admin";
  const payload = {
    id,
    companyId,
    amount: 12.5,
    expenseDate: serverTimestamp(),
    category: "fuel",
    categoryName: "fuel",
    customCategoryName: "",
    description: "Fuel refill",
    notes: "Fuel refill",
    paidByUid: uid,
    paidByName: name,
    paidByRole: role,
    salesRepId: isAdmin ? "" : uid,
    salesRepName: isAdmin ? "" : name,
    paymentMethod: "cash",
    fundingSource: isAdmin ? "company_cash" : "rep_collected_cash",
    status: isAdmin ? "posted" : "pending",
    cashMovementId: isAdmin ? `${id}_cash_out` : "",
    reimbursementStatus: "none",
    approvedByUid: isAdmin ? uid : "",
    approvedByName: isAdmin ? name : "",
    rejectedByUid: "",
    rejectedByName: "",
    rejectionReason: "",
    createdByUid: uid,
    createdByName: name,
    createdByRole: role,
    createdAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
    ...overrides,
  };
  if (isAdmin || overrides.approvedAt) {
    payload.approvedAt = overrides.approvedAt ?? serverTimestamp();
  }
  return payload;
}

function transferDraftPayload(id, createdByUid = adminUid) {
  return {
    id,
    companyId,
    transferNumber: `TRN-2026-${id === "draft-delete" ? "000002" : "000001"}`,
    year: 2026,
    type: "warehouseToRep",
    status: "draft",
    salesRepId: repAUid,
    salesRepNameSnapshot: "Rep A",
    lines: [
      {
        itemId: "item-a",
        modelSnapshot: "A-1",
        itemNameSnapshot: "Item A",
        unitSnapshot: "piece",
        quantity: 2,
        warehouseQuantityBefore: null,
        warehouseQuantityAfter: null,
        repQuantityBefore: null,
        repQuantityAfter: null,
        companyMovementId: "",
        repMovementId: "",
      },
    ],
    totalQuantity: 2,
    notes: "",
    createdByUid,
    createdByName: createdByUid === adminUid ? "Admin" : "Rep A",
    createdAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
    confirmedByUid: "",
    confirmedByName: "",
    confirmedAt: null,
    cancelledByUid: "",
    cancelledAt: null,
    effectsVersion: 1,
  };
}

function businessCollection(db, collectionName) {
  return collection(db, "companies", companyId, collectionName);
}

function businessDoc(db, collectionName, documentId) {
  return doc(db, "companies", companyId, collectionName, documentId);
}
