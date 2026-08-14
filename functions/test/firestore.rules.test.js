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
      setDoc(businessDoc(db, "cash_balances", "rep_rep-a"), {
        id: "rep_rep-a",
        companyId,
        cashAccount: "rep_cash",
        salesRepId: repAUid,
        amount: 25,
      }),
      setDoc(businessDoc(db, "cash_balances", "rep_rep-b"), {
        id: "rep_rep-b",
        companyId,
        cashAccount: "rep_cash",
        salesRepId: repBUid,
        amount: 30,
      }),
      setDoc(businessDoc(db, "cash_balances", "company_cash"), {
        id: "company_cash",
        companyId,
        cashAccount: "company_cash",
        salesRepId: "",
        amount: 100,
      }),
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
  await assertSucceeds(
    getDoc(businessDoc(db, "cash_balances", "rep_rep-a")),
  );
  await assertFails(getDoc(businessDoc(db, "cash_balances", "rep_rep-b")));
  await assertFails(getDoc(businessDoc(db, "cash_balances", "company_cash")));
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

test("clients cannot probe missing function-owned custody documents", async () => {
  for (const uid of [adminUid, repAUid]) {
    const db = authenticatedDb(uid);
    await assertFails(
      getDoc(businessDoc(db, "rep_inventory_balances", "missing-balance")),
    );
    await assertFails(
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

test("client-side inventory transfer posting is denied atomically", async () => {
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

  await assertFails(batch.commit());

  await testEnvironment.withSecurityRulesDisabled(async (context) => {
    const serverDb = context.firestore();
    const item = await getDoc(doc(serverDb, "items", itemId));
    const transfer = await getDoc(businessDoc(
      serverDb,
      "inventory_transfers",
      transferId,
    ));
    const balance = await getDoc(businessDoc(
      serverDb,
      "rep_inventory_balances",
      `${repAUid}_${itemId}`,
    ));
    const companyMovement = await getDoc(businessDoc(
      serverDb,
      "stock_movements",
      companyMovementId,
    ));
    const repMovement = await getDoc(businessDoc(
      serverDb,
      "rep_inventory_movements",
      repMovementId,
    ));
    if (item.data().currentStock !== 10 || transfer.data().status !== "draft") {
      throw new Error("Denied transfer posting changed source documents");
    }
    if (balance.exists() || companyMovement.exists() || repMovement.exists()) {
      throw new Error("Denied transfer posting created an effect document");
    }
  });
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

test("clients cannot post an opening balance directly", async () => {
  await seedOpeningCustomer("opening-admin-customer", repAUid);
  const db = authenticatedDb(adminUid);

  await assertFails(
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
});

test("sales rep cannot directly post customer credit", async () => {
  await seedOpeningCustomer("opening-rep-customer", repAUid);
  await seedOpeningCustomer("opening-other-customer", repBUid);
  const db = authenticatedDb(repAUid);

  await assertFails(
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

  await assertFails(commitOpeningBalance(db, options));
  await assertFails(
    commitOpeningBalance(db, {
      ...options,
      balanceBefore: 35,
      balanceAfter: 45,
    }),
  );
});

test("clients cannot directly mutate customer financial projections", async () => {
  await seedOpeningCustomer("forged-financial-customer", repAUid);
  const db = authenticatedDb(repAUid);

  await assertFails(
    updateDoc(businessDoc(db, "customers", "forged-financial-customer"), {
      currentBalance: 9999,
      totalSales: 9999,
      totalPaid: 9999,
      updatedAt: serverTimestamp(),
    }),
  );
});

test("customer profiles and phone reservations are server-owned", async () => {
  const firstDb = authenticatedDb(repAUid);
  const phone = "0799999999";
  await assertFails(customerCreateBatch(firstDb, "phone-race-a", phone).commit());
  await assertFails(setDoc(
    businessDoc(firstDb, "customer_phone_reservations", phone),
    {
      companyId,
      phoneNormalized: phone,
      customerId: "phone-race-a",
      createdAt: serverTimestamp(),
    },
  ));
  await seedOpeningCustomer("profile-update-customer", repAUid);
  await assertFails(updateDoc(
    businessDoc(firstDb, "customers", "profile-update-customer"),
    {name: "Forged profile", updatedAt: serverTimestamp()},
  ));
});

test("clients cannot create an arbitrary customer ledger entry", async () => {
  const db = authenticatedDb(repAUid);
  const payload = {
    ...openingBalancePayload({
      customerId: "customer-a",
      actorUid: repAUid,
      actorName: "Rep A",
      actorRole: "sales_rep",
      type: "customer_owes",
      amount: 5000,
      balanceBefore: 0,
      balanceAfter: 5000,
    }),
    id: "forged-ledger-entry",
    transactionType: "invoice",
    type: "invoice",
    sourceCollection: "invoices",
    sourceId: "missing-invoice",
    referenceId: "missing-invoice",
  };

  await assertFails(
    setDoc(
      businessDoc(db, "customer_transactions", "forged-ledger-entry"),
      payload,
    ),
  );
});

test("clients cannot create arbitrary or partial settlement cash movements", async () => {
  const db = authenticatedDb(adminUid);

  await assertFails(
    setDoc(
      businessDoc(db, "cash_movements", "forged-company-cash"),
      cashMovementPayload("forged-company-cash", {
        type: "invoice_payment",
        cashAccount: "company_cash",
        direction: "in",
        amount: 5000,
      }),
    ),
  );

  await assertFails(
    setDoc(
      businessDoc(db, "cash_movements", "partial-settlement-rep-out"),
      cashMovementPayload("partial-settlement-rep-out", {
        type: "settlement_to_admin",
        cashAccount: "rep_cash",
        direction: "out",
        amount: 50,
        salesRepId: repAUid,
        settlementId: "partial-settlement",
      }),
    ),
  );
});

test("clients cannot forge warehouse invoice or return stock deltas", async () => {
  const db = authenticatedDb(repAUid);
  const item = doc(db, "items", "item-a");

  await assertFails(
    updateDoc(item, {
      currentStock: 1,
      inventoryUpdatedAt: serverTimestamp(),
      updatedAt: serverTimestamp(),
    }),
  );
  await assertFails(
    updateDoc(item, {
      currentStock: 1000,
      inventoryUpdatedAt: serverTimestamp(),
      updatedAt: serverTimestamp(),
    }),
  );
});

test("all client-side stock corrections are denied", async () => {
  const db = authenticatedDb(adminUid);
  const item = doc(db, "items", "item-a");
  const standaloneId = "standalone-adjustment";

  await assertFails(
    setDoc(
      businessDoc(db, "stock_movements", standaloneId),
      stockMovementPayload(standaloneId, {
        quantity: 1,
        quantityBefore: 10,
        quantityAfter: 9,
      }),
    ),
  );

  const mismatchedId = "mismatched-adjustment";
  const mismatchedBatch = writeBatch(db);
  mismatchedBatch.update(item, {
    currentStock: 8,
    inventoryUpdatedAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
    lastInventoryReferenceType: "manualAdjustment",
    lastInventoryReferenceId: mismatchedId,
    lastStockMovementId: mismatchedId,
  });
  mismatchedBatch.set(
    businessDoc(db, "stock_movements", mismatchedId),
    stockMovementPayload(mismatchedId, {
      quantity: 1,
      quantityBefore: 10,
      quantityAfter: 8,
    }),
  );
  await assertFails(mismatchedBatch.commit());

  const movementId = "matched-adjustment";
  const batch = writeBatch(db);
  batch.update(item, {
    currentStock: 8,
    inventoryUpdatedAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
    lastInventoryReferenceType: "manualAdjustment",
    lastInventoryReferenceId: movementId,
    lastStockMovementId: movementId,
  });
  batch.set(
    businessDoc(db, "stock_movements", movementId),
    stockMovementPayload(movementId, {
      quantity: 2,
      quantityBefore: 10,
      quantityAfter: 8,
    }),
  );
  await assertFails(batch.commit());
});

test("opening stock creation is reserved for the trusted server", async () => {
  const db = authenticatedDb(adminUid);
  const itemId = "new-stocked-item";
  const movementId = `${itemId}_opening_balance`;
  const itemPayload = {
    id: itemId,
    createdBy: adminUid,
    createdAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
    currentStock: 5,
    openingStock: 5,
    trackStock: true,
    deleted: false,
    lastInventoryReferenceType: "openingBalance",
    lastInventoryReferenceId: itemId,
    lastStockMovementId: movementId,
  };

  await assertFails(setDoc(doc(db, "items", itemId), itemPayload));

  const batch = writeBatch(db);
  batch.set(doc(db, "items", itemId), itemPayload);
  batch.set(
    businessDoc(db, "stock_movements", movementId),
    stockMovementPayload(movementId, {
      movementType: "opening_balance",
      quantity: 5,
      quantityBefore: 0,
      quantityAfter: 5,
      referenceType: "item",
      referenceId: itemId,
      itemId,
    }),
  );
  await assertFails(batch.commit());
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

test("expense creation is callable-owned for every client role", async () => {
  const db = authenticatedDb(repAUid);

  await assertFails(
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

test("admin cannot directly create posted company cash expenses", async () => {
  const db = authenticatedDb(adminUid);

  await assertFails(
    setDoc(
      businessDoc(db, "expenses", "new-admin-expense"),
      expenseCreatePayload("new-admin-expense", adminUid, "admin"),
    ),
  );
});

test("expense approval financial effects are server-only", async () => {
  const adminDb = authenticatedDb(adminUid);
  const repDb = authenticatedDb(repAUid);

  await assertFails(
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
  await assertFails(
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

test("unauthenticated users cannot read or write application data", async () => {
  const db = testEnvironment.unauthenticatedContext().firestore();

  await assertFails(getDoc(doc(db, "items", "item-a")));
  await assertFails(getDoc(doc(db, "users", adminUid)));
  await assertFails(getDoc(businessDoc(db, "invoices", "invoice-a")));
  await assertFails(
    setDoc(
      businessDoc(db, "invoices", "unauthenticated-draft"),
      invoiceDraftPayload("unauthenticated-draft", repAUid),
    ),
  );
});

test("safe profile, preference, user-management, and settings writes remain available", async () => {
  const repDb = authenticatedDb(repAUid);
  const adminDb = authenticatedDb(adminUid);
  const preferences = doc(repDb, "users", repAUid, "preferences", "app");

  await assertSucceeds(setDoc(preferences, {
    language: "en",
    themeMode: "system",
    defaultInvoiceNote: "",
    defaultReceiptNote: "",
    updatedAt: serverTimestamp(),
  }));
  await assertFails(setDoc(
    doc(repDb, "users", repBUid, "preferences", "app"),
    {
      language: "en",
      themeMode: "system",
      defaultInvoiceNote: "",
      defaultReceiptNote: "",
      updatedAt: serverTimestamp(),
    },
  ));
  await assertSucceeds(updateDoc(doc(repDb, "users", repAUid), {
    name: "Rep A",
    phone: "0790000001",
    photoUrl: "",
    updatedAt: serverTimestamp(),
  }));
  await assertFails(updateDoc(doc(repDb, "users", repAUid), {
    role: "admin",
    updatedAt: serverTimestamp(),
  }));

  await testEnvironment.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(context.firestore(), "users", "managed-user"), {
      uid: "managed-user",
      name: "Managed User",
      email: "managed@example.test",
      phone: "",
      photoUrl: "",
      role: "pending_sales_rep",
      active: false,
      approvalStatus: "pending",
      companyId,
      createdAt: new Date("2026-01-01T00:00:00.000Z"),
      updatedAt: new Date("2026-01-01T00:00:00.000Z"),
    });
  });
  await assertSucceeds(updateDoc(doc(adminDb, "users", "managed-user"), {
    role: "sales_rep",
    active: true,
    approvalStatus: "approved",
    approvedAt: serverTimestamp(),
    approvedByUid: adminUid,
    updatedAt: serverTimestamp(),
  }));

  await assertSucceeds(setDoc(
    businessDoc(adminDb, "settings", "app"),
    appSettingsPayload(adminUid),
  ));
  await assertFails(setDoc(
    businessDoc(repDb, "settings", "app"),
    appSettingsPayload(repAUid),
  ));
});

test("admin catalog edits remain allowed but inventory effects are server-owned", async () => {
  await testEnvironment.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(context.firestore(), "items", "catalog-item"), {
      id: "catalog-item",
      name: "Catalog Item",
      code: "CAT-1",
      description: "",
      unit: "piece",
      price: 10,
      taxRate: 0,
      active: true,
      currentStock: 5,
      openingStock: 5,
      minStock: 1,
      trackStock: true,
      costPrice: 7,
      barcode: null,
      category: null,
      warehouseId: "default_warehouse",
      deleted: false,
      createdBy: adminUid,
      createdAt: new Date("2026-01-01T00:00:00.000Z"),
      updatedAt: new Date("2026-01-01T00:00:00.000Z"),
    });
  });

  const adminRef = doc(authenticatedDb(adminUid), "items", "catalog-item");
  await assertSucceeds(updateDoc(adminRef, {
    name: "Updated Catalog Item",
    updatedAt: serverTimestamp(),
  }));
  await assertFails(updateDoc(adminRef, {
    currentStock: 999,
    updatedAt: serverTimestamp(),
  }));
  await assertFails(updateDoc(
    doc(authenticatedDb(repAUid), "items", "catalog-item"),
    {active: false, updatedAt: serverTimestamp()},
  ));
});

test("invoice drafts support current Flutter CRUD but direct posting is denied", async () => {
  await seedDraftCustomer("draft-customer", repAUid);
  const db = authenticatedDb(repAUid);
  const invoiceId = "invoice-draft";
  const invoiceRef = businessDoc(db, "invoices", invoiceId);
  const counterRef = businessDoc(db, "counters", "invoices_2026");
  const create = writeBatch(db);
  create.set(counterRef, counterPayload("invoices_2026", "INV", 1));
  create.set(invoiceRef, invoiceDraftPayload(
    invoiceId,
    repAUid,
    {customerId: "draft-customer"},
  ));
  await assertSucceeds(create.commit());

  await assertSucceeds(updateDoc(invoiceRef, {
    notes: "Edited draft",
    updatedAt: serverTimestamp(),
  }));
  await assertFails(updateDoc(invoiceRef, {
    invoiceStatus: "confirmed",
    financialPosted: true,
    inventoryPosted: true,
    isLocked: true,
    updatedAt: serverTimestamp(),
  }));
  await assertFails(updateDoc(invoiceRef, {
    customerTransactionIds: ["forged-ledger"],
    cashMovementIds: ["forged-cash"],
    inventoryMovementIds: ["forged-stock"],
    updatedAt: serverTimestamp(),
  }));
  await assertSucceeds(deleteDoc(invoiceRef));
});

test("confirmed and legacy financial documents are readable but immutable", async () => {
  await testEnvironment.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await setDoc(businessDoc(db, "invoices", "confirmed-invoice"), {
      id: "confirmed-invoice",
      companyId,
      invoiceStatus: "confirmed",
      financialPosted: true,
      inventoryPosted: true,
      salesRepId: repAUid,
      createdByUid: repAUid,
    });
  });

  const repRef = businessDoc(
    authenticatedDb(repAUid),
    "invoices",
    "confirmed-invoice",
  );
  await assertSucceeds(getDoc(repRef));
  await assertFails(updateDoc(repRef, {notes: "tampered"}));
  await assertFails(deleteDoc(repRef));
});

test("sales return drafts remain editable and confirmation remains callable-only", async () => {
  await seedDraftCustomer("return-customer", repAUid);
  await seedConfirmedInvoice("return-source", "return-customer", repAUid);
  const db = authenticatedDb(repAUid);
  const returnId = "return-draft";
  const returnRef = businessDoc(db, "sales_returns", returnId);

  const create = writeBatch(db);
  create.set(
    businessDoc(db, "counters", "sales_returns_2026"),
    counterPayload("sales_returns_2026", "RET", 1),
  );
  create.set(
    returnRef,
    returnDraftPayload(returnId, "return-source", "return-customer", repAUid),
  );
  await assertSucceeds(create.commit());
  await assertSucceeds(updateDoc(returnRef, {
    reason: "Updated return reason",
    updatedAt: serverTimestamp(),
  }));
  await assertFails(updateDoc(returnRef, {
    status: "confirmed",
    financialPosted: true,
    inventoryPosted: true,
    customerTransactionIds: ["forged"],
    updatedAt: serverTimestamp(),
  }));
});

test("quotation draft and status workflow remains client-owned", async () => {
  await seedDraftCustomer("quote-customer", repAUid);
  const db = authenticatedDb(repAUid);
  const quotationId = "quotation-draft";
  const quotationRef = businessDoc(db, "quotations", quotationId);

  const create = writeBatch(db);
  create.set(
    businessDoc(db, "counters", "quotations_2026"),
    counterPayload("quotations_2026", "QUO", 1),
  );
  create.set(
    quotationRef,
    quotationDraftPayload(quotationId, "quote-customer", repAUid),
  );
  await assertSucceeds(create.commit());
  await assertSucceeds(updateDoc(quotationRef, {
    notes: "Edited quotation",
    updatedAt: serverTimestamp(),
  }));
  await assertSucceeds(updateDoc(quotationRef, {
    status: "sent",
    updatedAt: serverTimestamp(),
  }));
  await assertFails(updateDoc(quotationRef, {
    status: "converted",
    convertedInvoiceId: "missing-invoice",
    convertedInvoiceNumber: "FORGED",
    updatedAt: serverTimestamp(),
  }));

  const invoiceId = "quote-invoice";
  const conversion = writeBatch(db);
  conversion.set(
    businessDoc(db, "counters", "invoices_2026"),
    counterPayload("invoices_2026", "INV", 1),
  );
  conversion.set(
    businessDoc(db, "invoices", invoiceId),
    invoiceDraftPayload(invoiceId, repAUid, {
      customerId: "quote-customer",
      invoiceNumber: "INV-2026-000001",
    }),
  );
  conversion.update(quotationRef, {
    status: "converted",
    convertedInvoiceId: invoiceId,
    convertedInvoiceNumber: "INV-2026-000001",
    updatedAt: serverTimestamp(),
  });
  await assertSucceeds(conversion.commit());
});

test("all posting, balance, reservation, audit, and lock paths fail closed", async () => {
  const db = authenticatedDb(adminUid);
  for (const [collectionName, documentId] of [
    ["customers", "forged-customer"],
    ["customer_phone_reservations", "0791234567"],
    ["customer_transactions", "forged-ledger"],
    ["receipts", "forged-receipt"],
    ["cash_movements", "forged-cash"],
    ["cash_balances", "forged-balance"],
    ["settlements", "forged-settlement"],
    ["stock_movements", "forged-stock"],
    ["rep_inventory_balances", "forged-rep-balance"],
    ["rep_inventory_movements", "forged-rep-movement"],
    ["audit_events", "forged-audit"],
    ["maintenance_locks", "forged-lock"],
  ]) {
    await assertFails(setDoc(
      businessDoc(db, collectionName, documentId),
      {
        id: documentId,
        companyId,
        salesRepId: repAUid,
        createdByUid: adminUid,
      },
    ));
  }
  await assertFails(setDoc(
    doc(
      db,
      "companies",
      companyId,
      "audit_events",
      "event",
      "details",
      "detail",
    ),
    {forged: true},
  ));
  await assertFails(setDoc(
    businessDoc(db, "counters", "receipts_2026"),
    counterPayload("receipts_2026", "REC", 1),
  ));
});

test("cross-company reads and writes are denied", async () => {
  const otherCompany = "other_company";
  await testEnvironment.withSecurityRulesDisabled(async (context) => {
    await setDoc(
      doc(context.firestore(), "companies", otherCompany, "invoices", "x"),
      {companyId: otherCompany, salesRepId: repAUid},
    );
  });
  const db = authenticatedDb(repAUid);
  await assertFails(getDoc(
    doc(db, "companies", otherCompany, "invoices", "x"),
  ));
  await assertFails(setDoc(
    doc(db, "companies", otherCompany, "invoices", "draft"),
    invoiceDraftPayload("draft", repAUid, {companyId: otherCompany}),
  ));
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

async function seedDraftCustomer(customerId, ownerUid) {
  await testEnvironment.withSecurityRulesDisabled(async (context) => {
    await setDoc(businessDoc(context.firestore(), "customers", customerId), {
      id: customerId,
      companyId,
      name: "Draft Customer",
      active: true,
      createdByUid: ownerUid,
    });
  });
}

async function seedConfirmedInvoice(invoiceId, customerId, salesRepId) {
  await testEnvironment.withSecurityRulesDisabled(async (context) => {
    await setDoc(businessDoc(context.firestore(), "invoices", invoiceId), {
      id: invoiceId,
      companyId,
      invoiceNumber: "INV-2026-000099",
      invoiceStatus: "confirmed",
      customerId,
      salesRepId,
      financialPosted: true,
      inventoryPosted: true,
    });
  });
}

function counterPayload(id, prefix, lastNumber) {
  return {
    id,
    companyId,
    year: 2026,
    lastNumber,
    prefix,
    updatedAt: serverTimestamp(),
  };
}

function invoiceDraftPayload(id, uid, overrides = {}) {
  const isAdmin = uid === adminUid;
  const customerId = overrides.customerId ?? "draft-customer";
  return {
    id,
    companyId: overrides.companyId ?? companyId,
    invoiceNumber: overrides.invoiceNumber ?? "INV-2026-000001",
    invoiceType: "regular",
    invoiceStatus: "draft",
    paymentType: "credit",
    paymentStatus: "unpaid",
    hasReceivedPayment: false,
    invoiceDate: new Date("2026-08-01T00:00:00.000Z"),
    dueDate: new Date("2026-08-31T00:00:00.000Z"),
    createdAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
    createdByUid: uid,
    createdByName: isAdmin ? "Admin" : "Rep A",
    createdByRole: isAdmin ? "admin" : "sales_rep",
    salesRepId: uid,
    salesRepName: isAdmin ? "Admin" : "Rep A",
    customerId,
    customerSnapshot: {id: customerId, name: "Draft Customer"},
    items: [{
      itemId: "item-a",
      itemName: "Item A",
      itemCode: "A-1",
      unit: "piece",
      quantity: 1,
      unitPrice: 100,
      discount: 0,
      taxPercent: 0,
      subtotal: 100,
      taxAmount: 0,
      total: 100,
    }],
    subtotal: 100,
    totalDiscount: 0,
    totalTax: 0,
    grandTotal: 100,
    paidAmount: 0,
    remainingAmount: 100,
    returnStatus: "none",
    returnedTotal: 0,
    returnedSubtotal: 0,
    returnedDiscount: 0,
    returnedTax: 0,
    returnedReceivableAmount: 0,
    customerCreditAmount: 0,
    cashRefundAmount: 0,
    returnInvoiceIds: [],
    latestReturnAt: null,
    receiptIds: [],
    lastReceiptId: "",
    notes: "",
    paymentMethod: "credit",
    isLocked: false,
    financialPosted: false,
    financialPostedAt: null,
    financialPostedByUid: "",
    financialPostedByName: "",
    customerTransactionIds: [],
    cashMovementIds: [],
    inventoryPosted: false,
    inventoryPostedAt: null,
    inventoryPostedByUid: "",
    inventoryPostedByName: "",
    inventoryMovementIds: [],
    stockSourceType: isAdmin ? "companyWarehouse" : "salesRep",
    stockSourceId: isAdmin ? "default_warehouse" : uid,
    stockSourceSalesRepId: isAdmin ? "" : uid,
    searchKeywords: ["draft"],
    customerNameLower: "draft customer",
    itemNamesLower: ["item a"],
    invoiceNumberLower: "inv-2026-000001",
    dateString: "2026-08-01",
    government: null,
  };
}

function returnDraftPayload(id, invoiceId, customerId, uid) {
  return {
    id,
    companyId,
    returnNumber: "RET-2026-000001",
    returnInvoiceId: id,
    originalInvoiceId: invoiceId,
    originalInvoiceNumber: "INV-2026-000099",
    originalInvoiceDate: new Date("2026-07-01T00:00:00.000Z"),
    customerId,
    customerSnapshot: {id: customerId, name: "Draft Customer"},
    items: [{itemId: "item-a", returnedQuantity: 1}],
    subtotal: 100,
    totalDiscount: 0,
    totalTax: 0,
    grandTotal: 100,
    receivableReduction: 0,
    customerCreditAmount: 0,
    cashRefundAmount: 0,
    refundType: "credit_customer_balance",
    returnDate: new Date("2026-08-02T00:00:00.000Z"),
    reason: "Customer return",
    status: "draft",
    salesRepId: uid,
    salesRepName: "Rep A",
    createdByUid: uid,
    createdByName: "Rep A",
    createdByRole: "sales_rep",
    financialPosted: false,
    inventoryPosted: false,
    financialPostedAt: null,
    inventoryPostedAt: null,
    stockMovementIds: [],
    customerTransactionIds: [],
    cashMovementIds: [],
    createdAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
  };
}

function quotationDraftPayload(id, customerId, uid) {
  return {
    id,
    companyId,
    quotationNumber: "QUO-2026-000001",
    quotationDate: new Date("2026-08-01T00:00:00.000Z"),
    validUntil: new Date("2026-08-31T00:00:00.000Z"),
    customerId,
    customerSnapshot: {id: customerId, name: "Draft Customer"},
    items: [{itemId: "item-a", quantity: 1, total: 100}],
    subtotal: 100,
    totalDiscount: 0,
    totalTax: 0,
    grandTotal: 100,
    notes: "",
    terms: "",
    status: "draft",
    salesRepId: uid,
    salesRepName: "Rep A",
    createdByUid: uid,
    createdByName: "Rep A",
    createdByRole: "sales_rep",
    convertedInvoiceId: "",
    convertedInvoiceNumber: "",
    createdAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
    searchKeywords: ["draft"],
  };
}

function appSettingsPayload(uid) {
  return {
    companySettings: {
      name: "Fatoora",
      country: "Jordan",
      email: "",
      website: "",
      phone: "",
      address: "",
      logoEnabled: false,
    },
    documentSettings: {
      invoicePrefix: "INV",
      receiptPrefix: "REC",
      quotationPrefix: "QUO",
      salesReturnPrefix: "RET",
      defaultDueDays: 30,
      defaultTaxPercent: 0,
      allowDiscount: true,
      allowSalesRepPriceEdit: false,
    },
    inventorySettings: {
      defaultWarehouseId: "default_warehouse",
      allowNegativeStock: false,
      lowStockAlertsEnabled: true,
      defaultMinStock: 0,
      trackStockByDefault: true,
    },
    pdfSettings: {
      showLogo: false,
      showCompanyInfo: true,
      pdfLanguageMode: "app_language",
      invoiceFooterText: "",
      quotationTerms: "",
      receiptFooterText: "",
      statementFooterText: "",
      defaultNotes: "",
    },
    permissionSettings: {
      allowSalesRepCreateCustomers: true,
      allowSalesRepCreateReceipts: true,
      allowSalesRepCreateReturns: true,
      allowSalesRepCreateQuotations: true,
      allowSalesRepPriceEdit: false,
      allowSalesRepDiscount: false,
    },
    jofotaraStatusSettings: {enabled: false, status: "disabled"},
    schemaVersion: 1,
    updatedAt: serverTimestamp(),
    updatedByUid: uid,
    updatedByName: uid === adminUid ? "Admin" : "Rep A",
  };
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

function customerCreateBatch(db, customerId, phoneNormalized) {
  const batch = writeBatch(db);
  batch.set(
    businessDoc(db, "customers", customerId),
    customerCreatePayload(customerId, phoneNormalized),
  );
  batch.set(
    businessDoc(db, "customer_phone_reservations", phoneNormalized),
    {
      companyId,
      phoneNormalized,
      customerId,
      createdAt: serverTimestamp(),
    },
  );
  return batch;
}

function customerCreatePayload(customerId, phoneNormalized) {
  return {
    id: customerId,
    companyId,
    name: `Customer ${customerId}`,
    phone: phoneNormalized,
    addressText: "",
    city: "",
    area: "",
    notes: "",
    active: true,
    createdByUid: repAUid,
    createdByName: "Rep A",
    createdByRole: "sales_rep",
    createdAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
    currentBalance: 0,
    totalSales: 0,
    totalPaid: 0,
    searchKeywords: [phoneNormalized],
    nameLower: `customer ${customerId}`,
    phoneNormalized,
    cityLower: "",
    areaLower: "",
  };
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

function cashMovementPayload(id, overrides = {}) {
  return {
    id,
    companyId,
    type: "adjustment",
    movementType: "adjustment",
    direction: "in",
    amount: 1,
    cashAccount: "company_cash",
    salesRepId: "",
    salesRepName: "",
    customerId: "",
    customerName: "",
    referenceId: id,
    referenceNumber: id,
    sourceCollection: "cash_movements",
    sourceId: id,
    sourceNumber: id,
    settlementId: "",
    notes: "forged client write",
    date: serverTimestamp(),
    movementDate: serverTimestamp(),
    createdByUid: adminUid,
    createdByName: "Admin",
    createdByRole: "admin",
    createdAt: serverTimestamp(),
    ...overrides,
  };
}

function stockMovementPayload(id, overrides = {}) {
  return {
    id,
    companyId,
    warehouseId: "default_warehouse",
    itemId: "item-a",
    itemName: "Item A",
    itemCode: "A-1",
    movementType: "manual_adjustment_out",
    direction: "out",
    quantity: 1,
    quantityBefore: 10,
    quantityAfter: 9,
    referenceType: "manual_adjustment",
    referenceId: id,
    referenceNumber: "",
    movementDate: serverTimestamp(),
    notes: "stock correction",
    createdByUid: adminUid,
    createdByName: "Admin",
    createdByRole: "admin",
    createdAt: serverTimestamp(),
    ...overrides,
  };
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
