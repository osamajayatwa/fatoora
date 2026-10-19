"use strict";
const {FieldValue} = require("firebase-admin/firestore");
const {parseOptions, initializeFirestore, scanCollection} = require("./invoice_list_fields_common");
const {initialCustomerAssignment} = require("../lib/trusted/customer_assignment");

function legacyAssignmentUpdate(customer, creator, companyId) {
  if (customer.companyId !== companyId) throw new Error("Customer company identity requires review.");
  if (customer.assignmentVersion === 1) {
    if (typeof customer.assignedToUid !== "string" || !customer.assignedToUid ||
        !["admin", "sales_rep"].includes(customer.assignedToRole) || !Number.isSafeInteger(customer.assignmentRevision) || customer.assignmentRevision < 0) {
      throw new Error("Invalid versioned assignment requires review.");
    }
    return null;
  }
  if (Object.prototype.hasOwnProperty.call(customer, "assignedToUid")) {
    throw new Error("Unversioned legacy assignment fields require review; nothing was overwritten.");
  }
  if (!customer.createdByUid || customer.companyId !== companyId ||
      !creator || (creator.companyId ?? "default_company") !== companyId ||
      !["admin", "sales_rep"].includes(creator.role)) {
    throw new Error("Legacy creator identity requires review; no assignee was guessed.");
  }
  return {...initialCustomerAssignment(customer.createdByUid, creator.name || customer.createdByName || customer.createdByUid, creator.role),
    assignmentMigration: "legacy-creator-v1", assignmentMigratedAt: FieldValue.serverTimestamp()};
}

function legacyAssignmentRollback(customer, companyId) {
  if (customer.assignmentMigration !== "legacy-creator-v1") return null;
  if (customer.companyId !== companyId || customer.assignmentRevision !== 0 ||
      customer.assignedToUid !== customer.createdByUid || customer.lastAssignmentEventId) {
    throw new Error("Assignment changed after migration; rollback refused.");
  }
  return Object.fromEntries(["assignedToUid", "assignedToName", "assignedToRole", "assignmentVersion", "assignmentRevision",
    "assignmentMigration", "assignmentMigratedAt"].map((field) => [field, FieldValue.delete()]));
}

async function main() {
  const rollback = process.argv.includes("--rollback");
  const options = parseOptions(process.argv.slice(2).filter((arg) => arg !== "--rollback"));
  const db = initializeFirestore(options.projectId);
  const collection = db.collection(`companies/${options.companyId}/customers`);
  const counts = {planned: 0, skipped: 0, unresolved: 0, applied: 0};
  const creators = new Map();
  async function updateFor(data, documentId) {
    if (data.id !== documentId) throw new Error("Customer ID does not match document ID; review required.");
    if (rollback) return legacyAssignmentRollback(data, options.companyId);
    if (data.assignmentVersion === 1 || Object.prototype.hasOwnProperty.call(data, "assignedToUid")) {
      return legacyAssignmentUpdate(data, undefined, options.companyId);
    }
    const uid = data.createdByUid;
    if (typeof uid !== "string" || !uid || uid.includes("/")) throw new Error("Missing/invalid creator UID.");
    if (!creators.has(uid)) creators.set(uid, (await db.doc(`users/${uid}`).get()).data());
    return legacyAssignmentUpdate(data, creators.get(uid), options.companyId);
  }
  // Validate the complete paginated pass before allowing any apply writes.
  for await (const doc of scanCollection(collection, Math.min(options.pageSize, 500))) {
    try {
      if (await updateFor(doc.data(), doc.id)) counts.planned++; else counts.skipped++;
    } catch (error) {
      counts.unresolved++;
      console.error(JSON.stringify({customerId: doc.id, error: error.message}));
    }
  }
  console.log(JSON.stringify({project: options.projectId, company: options.companyId,
    operation: rollback ? "rollback" : "backfill", mode: options.apply ? "apply" : "dry-run", ...counts}, null, 2));
  if (!options.apply) return;
  if (counts.unresolved || counts.planned > options.maxWrites) throw new Error("Resolve validation issues/write limit before applying; no writes performed.");
  creators.clear();
  for await (const doc of scanCollection(collection, Math.min(options.pageSize, 500))) {
    const update = await updateFor(doc.data(), doc.id);
    if (!update) continue;
    if (counts.applied >= options.maxWrites) throw new Error("Write limit reached; rerun dry-run.");
    // The precondition also protects concurrent assignment/posting. A conflict
    // stops the pass; a repeated dry run safely resumes without overwriting.
    await doc.ref.update(update, {lastUpdateTime: doc.updateTime});
    counts.applied++;
  }
  console.log(JSON.stringify({applied: counts.applied}));
}
if (require.main === module) main().catch((error) => {console.error(error.message); process.exitCode = 1;});
module.exports = {legacyAssignmentUpdate, legacyAssignmentRollback};
