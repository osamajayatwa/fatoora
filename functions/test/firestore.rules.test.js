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
const repAUid = "rep-a";
const repBUid = "rep-b";

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
      setDoc(doc(db, "users", repAUid), approvedUser(repAUid, "sales_rep")),
      setDoc(doc(db, "users", repBUid), approvedUser(repBUid, "sales_rep")),
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

test("admin can directly read and list every protected collection", async () => {
  const db = authenticatedDb(adminUid);
  for (const [collectionName, documentId] of [
    ["invoices", "invoice-b"],
    ["receipts", "receipt-b"],
    ["cash_movements", "cash-b"],
    ["stock_movements", "stock-b"],
  ]) {
    await assertSucceeds(getDoc(businessDoc(db, collectionName, documentId)));
    await assertSucceeds(getDocs(businessCollection(db, collectionName)));
  }
});

test("rep A can directly read own documents and cannot read rep B documents", async () => {
  const db = authenticatedDb(repAUid);
  for (const [collectionName, ownId, otherId] of [
    ["invoices", "invoice-a", "invoice-b"],
    ["receipts", "receipt-a", "receipt-b"],
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
    ["invoices", "invoice-b", "invoice-a"],
    ["receipts", "receipt-b", "receipt-a"],
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
    for (const collectionName of ["invoices", "receipts", "cash_movements"]) {
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
  }
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
