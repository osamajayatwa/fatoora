const { applicationDefault, getApps, initializeApp } = require("firebase-admin/app");
const { FieldPath, getFirestore } = require("firebase-admin/firestore");

const allowedOwnerRoles = new Set(["admin", "sales_rep"]);

function parseOptions(argv) {
  const options = {
    apply: false,
    companyId: "default_company",
    confirmCompany: "",
    confirmProject: "",
    maxIssues: 100,
    maxWrites: 500,
    pageSize: 400,
    projectId: "",
  };

  for (const argument of argv) {
    if (argument === "--apply") {
      options.apply = true;
      continue;
    }
    const [name, ...valueParts] = argument.split("=");
    const value = valueParts.join("=").trim();
    switch (name) {
      case "--project":
        options.projectId = value;
        break;
      case "--company":
        options.companyId = value;
        break;
      case "--confirm-project":
        options.confirmProject = value;
        break;
      case "--confirm-company":
        options.confirmCompany = value;
        break;
      case "--max-issues":
        options.maxIssues = positiveInteger(value, name);
        break;
      case "--max-writes":
        options.maxWrites = positiveInteger(value, name);
        break;
      case "--page-size":
        options.pageSize = positiveInteger(value, name);
        break;
      default:
        throw new Error(`Unknown argument: ${argument}`);
    }
  }

  if (!options.projectId) {
    throw new Error("--project=<firebase-project-id> is required");
  }
  if (!options.companyId) {
    throw new Error("--company=<company-id> cannot be empty");
  }
  return options;
}

function initializeFirestore(projectId) {
  if (getApps().length === 0) {
    const configuration = { projectId };
    if (!process.env.FIRESTORE_EMULATOR_HOST) {
      configuration.credential = applicationDefault();
    }
    initializeApp(configuration);
  }
  return getFirestore();
}

async function loadOwnershipContext(db, companyId, pageSize) {
  const quotationOwners = new Map();
  const users = new Map();

  for await (const snapshot of scanCollection(
    db.collection("users"),
    pageSize,
  )) {
    const data = snapshot.data();
    users.set(snapshot.id, {
      role: text(data.role),
      name: text(data.name),
    });
  }

  const quotations = db
    .collection("companies")
    .doc(companyId)
    .collection("quotations");
  for await (const snapshot of scanCollection(quotations, pageSize)) {
    const data = snapshot.data();
    const invoiceId = text(data.convertedInvoiceId);
    const salesRepId = text(data.salesRepId);
    if (!invoiceId || !salesRepId) continue;

    const owners = quotationOwners.get(invoiceId) ?? new Map();
    const entry = owners.get(salesRepId) ?? {
      quotationIds: [],
      salesRepName: text(data.salesRepName),
    };
    entry.quotationIds.push(snapshot.id);
    owners.set(salesRepId, entry);
    quotationOwners.set(invoiceId, owners);
  }

  return { quotationOwners, users };
}

async function auditInvoices({ db, companyId, pageSize, maxIssues }) {
  const ownershipContext = await loadOwnershipContext(db, companyId, pageSize);
  const invoices = db
    .collection("companies")
    .doc(companyId)
    .collection("invoices");
  const summary = emptySummary();

  for await (const snapshot of scanCollection(invoices, pageSize)) {
    const result = analyzeInvoiceOwnership(
      snapshot.id,
      snapshot.data(),
      ownershipContext,
    );
    addAuditResult(summary, result, maxIssues);
  }

  return { ownershipContext, summary };
}

async function collectBackfillCandidates({
  db,
  companyId,
  pageSize,
  ownershipContext,
}) {
  const invoices = db
    .collection("companies")
    .doc(companyId)
    .collection("invoices");
  const candidates = [];
  const skipped = new Map();

  for await (const snapshot of scanCollection(invoices, pageSize)) {
    const decision = inferBackfillOwner(
      snapshot.id,
      snapshot.data(),
      ownershipContext,
    );
    if (decision.action === "update") {
      candidates.push({
        document: snapshot,
        invoiceId: snapshot.id,
        salesRepId: decision.salesRepId,
        source: decision.source,
      });
    } else if (decision.action === "skip") {
      increment(skipped, decision.reason);
    }
  }

  return { candidates, skipped };
}

function analyzeInvoiceOwnership(invoiceId, data, ownershipContext) {
  const hasSalesRepId = Object.prototype.hasOwnProperty.call(data, "salesRepId");
  const salesRepId = text(data.salesRepId);
  const createdByUid = text(data.createdByUid);
  const quotationOwnerIds = ownerIdsForInvoice(
    ownershipContext.quotationOwners,
    invoiceId,
  );
  const mismatchReasons = [];

  if (quotationOwnerIds.length > 1) {
    mismatchReasons.push("ambiguous_quotation_owners");
  } else if (
    salesRepId &&
    quotationOwnerIds.length === 1 &&
    salesRepId !== quotationOwnerIds[0]
  ) {
    mismatchReasons.push("differs_from_converted_quotation");
  } else if (
    salesRepId &&
    quotationOwnerIds.length === 0 &&
    createdByUid &&
    salesRepId !== createdByUid
  ) {
    mismatchReasons.push("differs_from_created_by");
  }

  return {
    createdByRole: text(data.createdByRole),
    createdByUid,
    hasSalesRepId,
    invoiceId,
    invoiceStatus: text(data.invoiceStatus) || "unknown",
    invoiceType: text(data.invoiceType) || "unknown",
    mismatchReasons,
    quotationOwnerIds,
    salesRepId,
    salesRepName: text(data.salesRepName),
  };
}

function inferBackfillOwner(invoiceId, data, ownershipContext) {
  const currentSalesRepId = text(data.salesRepId);
  if (currentSalesRepId) return { action: "unchanged" };

  const quotationOwnerIds = ownerIdsForInvoice(
    ownershipContext.quotationOwners,
    invoiceId,
  );
  if (quotationOwnerIds.length > 1) {
    return { action: "skip", reason: "ambiguous_quotation_owners" };
  }
  if (quotationOwnerIds.length === 1) {
    return validatedOwnerDecision(
      quotationOwnerIds[0],
      "converted_quotation",
      ownershipContext.users,
    );
  }

  const createdByUid = text(data.createdByUid);
  if (createdByUid) {
    return validatedOwnerDecision(
      createdByUid,
      "created_by_uid",
      ownershipContext.users,
    );
  }

  if (text(data.salesRepName)) {
    return { action: "skip", reason: "sales_rep_name_without_uid" };
  }
  return { action: "skip", reason: "no_confident_owner" };
}

function validatedOwnerDecision(salesRepId, source, users) {
  const user = users.get(salesRepId);
  if (!user) return { action: "skip", reason: "owner_user_missing" };
  if (!allowedOwnerRoles.has(user.role)) {
    return { action: "skip", reason: "owner_role_not_allowed" };
  }
  return { action: "update", salesRepId, source };
}

function addAuditResult(summary, result, maxIssues) {
  summary.total += 1;
  increment(summary.byType, result.invoiceType);
  increment(summary.byStatus, result.invoiceStatus);

  const groupKey = `${result.invoiceType} / ${result.invoiceStatus}`;
  if (!result.hasSalesRepId) {
    summary.missingField += 1;
    increment(summary.missingByTypeStatus, groupKey);
  }
  if (!result.salesRepId) {
    summary.emptyOrNull += 1;
    increment(summary.emptyByTypeStatus, groupKey);
  }
  if (result.mismatchReasons.length > 0) {
    summary.mismatch += 1;
    for (const reason of result.mismatchReasons) {
      increment(summary.mismatchByReason, reason);
    }
  }

  if (
    summary.issues.length < maxIssues &&
    (!result.hasSalesRepId || !result.salesRepId || result.mismatchReasons.length)
  ) {
    summary.issues.push(result);
  }
}

function emptySummary() {
  return {
    total: 0,
    missingField: 0,
    emptyOrNull: 0,
    mismatch: 0,
    byType: new Map(),
    byStatus: new Map(),
    missingByTypeStatus: new Map(),
    emptyByTypeStatus: new Map(),
    mismatchByReason: new Map(),
    issues: [],
  };
}

function serializableSummary(summary) {
  return {
    total: summary.total,
    missingSalesRepIdField: summary.missingField,
    emptyOrNullSalesRepId: summary.emptyOrNull,
    ownershipMismatches: summary.mismatch,
    countsByInvoiceType: mapToObject(summary.byType),
    countsByInvoiceStatus: mapToObject(summary.byStatus),
    missingByTypeAndStatus: mapToObject(summary.missingByTypeStatus),
    emptyByTypeAndStatus: mapToObject(summary.emptyByTypeStatus),
    mismatchByReason: mapToObject(summary.mismatchByReason),
    reportedIssues: summary.issues,
  };
}

function serializableBackfillPlan(plan) {
  const bySource = new Map();
  for (const candidate of plan.candidates) increment(bySource, candidate.source);
  return {
    candidateCount: plan.candidates.length,
    candidatesBySource: mapToObject(bySource),
    skippedByReason: mapToObject(plan.skipped),
    candidates: plan.candidates.map(({ invoiceId, salesRepId, source }) => ({
      invoiceId,
      salesRepId,
      source,
    })),
  };
}

async function* scanCollection(collectionReference, pageSize) {
  let lastDocument;
  while (true) {
    let query = collectionReference
      .orderBy(FieldPath.documentId())
      .limit(pageSize);
    if (lastDocument) query = query.startAfter(lastDocument);
    const snapshot = await query.get();
    if (snapshot.empty) return;
    for (const document of snapshot.docs) yield document;
    if (snapshot.size < pageSize) return;
    lastDocument = snapshot.docs[snapshot.docs.length - 1];
  }
}

function ownerIdsForInvoice(quotationOwners, invoiceId) {
  return [...(quotationOwners.get(invoiceId)?.keys() ?? [])].sort();
}

function increment(map, key) {
  map.set(key, (map.get(key) ?? 0) + 1);
}

function mapToObject(map) {
  return Object.fromEntries([...map.entries()].sort(([a], [b]) => a.localeCompare(b)));
}

function positiveInteger(value, name) {
  const number = Number(value);
  if (!Number.isInteger(number) || number <= 0) {
    throw new Error(`${name} must be a positive integer`);
  }
  return number;
}

function text(value) {
  return typeof value === "string" ? value.trim() : "";
}

module.exports = {
  analyzeInvoiceOwnership,
  auditInvoices,
  collectBackfillCandidates,
  inferBackfillOwner,
  initializeFirestore,
  parseOptions,
  serializableBackfillPlan,
  serializableSummary,
};
