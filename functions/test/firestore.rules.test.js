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
  doc,
  getDoc,
  getDocs,
  query,
  setDoc,
  where,
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
        salesRepOwned("cash-a", repAUid, repAUid),
      ),
      setDoc(
        businessDoc(db, "cash_movements", "cash-b"),
        salesRepOwned("cash-b", repBUid, repBUid),
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
      "cash_movements",
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
      ["stock_movements", "stock-a"],
    ]) {
      await assertFails(getDoc(businessDoc(db, collectionName, documentId)));
      await assertFails(getDocs(businessCollection(db, collectionName)));
    }
  }
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

function authenticatedDb(uid) {
  return testEnvironment.authenticatedContext(uid, {
    email: `${uid}@example.test`,
  }).firestore();
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

function businessCollection(db, collectionName) {
  return collection(db, "companies", companyId, collectionName);
}

function businessDoc(db, collectionName, documentId) {
  return doc(db, "companies", companyId, collectionName, documentId);
}
