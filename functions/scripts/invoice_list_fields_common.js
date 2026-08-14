const {applicationDefault, getApps, initializeApp} = require("firebase-admin/app");
const {FieldPath, getFirestore} = require("firebase-admin/firestore");

function parseOptions(argv) {
  const options = {
    apply: false,
    companyId: "default_company",
    confirmCompany: "",
    confirmProject: "",
    maxIssues: 100,
    maxWrites: 500,
    pageSize: 300,
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
  if (options.apply) {
    if (options.confirmProject !== options.projectId) {
      throw new Error(
        "--confirm-project must exactly match --project in apply mode",
      );
    }
    if (options.confirmCompany !== options.companyId) {
      throw new Error(
        "--confirm-company must exactly match --company in apply mode",
      );
    }
  }
  return options;
}

function initializeFirestore(projectId) {
  if (getApps().length === 0) {
    const configuration = {projectId};
    if (!process.env.FIRESTORE_EMULATOR_HOST) {
      configuration.credential = applicationDefault();
    }
    initializeApp(configuration);
  }
  return getFirestore();
}

function buildInvoiceListFieldUpdates(data, metadata = {}) {
  const updates = {};
  const unresolved = [];
  const invoiceNumber = text(data.invoiceNumber);
  const customerName = text(data.customerSnapshot?.name);
  const customerPhone = text(data.customerSnapshot?.phone);
  const salesRepName = text(data.salesRepName) || text(data.createdByName);

  setMissingText(updates, data, "invoiceNumberLower", normalize(invoiceNumber));
  setMissingText(updates, data, "customerNameLower", normalize(customerName));
  setMissingText(updates, data, "salesRepName", salesRepName);

  if (!text(data.customerId)) {
    const snapshotCustomerId = text(data.customerSnapshot?.id);
    if (snapshotCustomerId) updates.customerId = snapshotCustomerId;
    else unresolved.push("customerId");
  }
  if (!text(data.salesRepId)) unresolved.push("salesRepId");

  if (!hasTimestamp(data.createdAt)) {
    const createdAt = metadata.createTime ?? data.invoiceDate;
    if (hasTimestamp(createdAt)) updates.createdAt = createdAt;
    else unresolved.push("createdAt");
  }

  if (!validPaymentStatus(data.paymentStatus)) {
    const derivedPaymentStatus = derivePaymentStatus(data);
    if (derivedPaymentStatus) updates.paymentStatus = derivedPaymentStatus;
    else unresolved.push("paymentStatus");
  }

  if (!validReturnStatus(data.returnStatus)) {
    const derivedReturnStatus = deriveReturnStatus(data);
    if (derivedReturnStatus) updates.returnStatus = derivedReturnStatus;
    else unresolved.push("returnStatus");
  }

  for (const field of [
    "invoiceNumber",
    "invoiceDate",
    "invoiceStatus",
    "invoiceType",
    "grandTotal",
    "remainingAmount",
  ]) {
    if (!hasQueryableValue(data[field])) unresolved.push(field);
  }

  const requiredSearchKeywords = buildSearchKeywords([
    invoiceNumber,
    customerName,
    customerPhone,
    salesRepName,
  ]);
  const existingSearchKeywords = Array.isArray(data.searchKeywords)
    ? data.searchKeywords.filter((value) => typeof value === "string")
    : [];
  const mergedSearchKeywords = [...new Set([
    ...existingSearchKeywords,
    ...requiredSearchKeywords,
  ])].sort();
  if (!arraysEqual(existingSearchKeywords, mergedSearchKeywords)) {
    updates.searchKeywords = mergedSearchKeywords;
  }

  return {
    updates,
    unresolved: [...new Set(unresolved)].sort(),
  };
}

function derivePaymentStatus(data) {
  const grandTotal = finiteNumber(data.grandTotal);
  const paidAmount = finiteNumber(data.paidAmount);
  const remainingAmount = finiteNumber(data.remainingAmount);
  if (grandTotal === null || paidAmount === null) return null;
  if (remainingAmount !== null && remainingAmount <= 0 && grandTotal > 0) {
    return "paid";
  }
  if (paidAmount >= grandTotal && grandTotal > 0) return "paid";
  if (paidAmount > 0) return "partiallyPaid";
  return "unpaid";
}

function deriveReturnStatus(data) {
  const returnedTotal = finiteNumber(data.returnedTotal) ?? 0;
  const returnInvoiceIds = Array.isArray(data.returnInvoiceIds)
    ? data.returnInvoiceIds.filter((value) => text(value))
    : [];
  if (returnedTotal <= 0 && returnInvoiceIds.length === 0) return "none";
  return null;
}

function buildSearchKeywords(values) {
  const keywords = new Set();
  for (const value of values) {
    const normalized = normalize(value);
    if (!normalized) continue;
    keywords.add(normalized);
    for (const token of normalized.split(/[\s\-_/]+/u)) {
      if (!token) continue;
      keywords.add(token);
      for (let length = 1; length <= token.length && length <= 20; length += 1) {
        keywords.add(token.slice(0, length));
      }
    }
  }
  return [...keywords].sort();
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

function setMissingText(updates, data, field, value) {
  if (!text(data[field]) && value) updates[field] = value;
}

function validPaymentStatus(value) {
  return ["paid", "unpaid", "partiallyPaid"].includes(text(value));
}

function validReturnStatus(value) {
  return ["none", "partiallyReturned", "returned"].includes(text(value));
}

function hasTimestamp(value) {
  return Boolean(value && typeof value.toDate === "function") ||
    value instanceof Date;
}

function hasQueryableValue(value) {
  if (typeof value === "string") return value.trim().length > 0;
  if (typeof value === "number") return Number.isFinite(value);
  return hasTimestamp(value);
}

function finiteNumber(value) {
  return typeof value === "number" && Number.isFinite(value) ? value : null;
}

function arraysEqual(left, right) {
  return left.length === right.length &&
    left.every((value, index) => value === right[index]);
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

function normalize(value) {
  return text(value).toLowerCase();
}

module.exports = {
  buildInvoiceListFieldUpdates,
  buildSearchKeywords,
  initializeFirestore,
  parseOptions,
  scanCollection,
};
