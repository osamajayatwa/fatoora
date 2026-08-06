const {randomUUID} = require("node:crypto");

const {applicationDefault, getApps, initializeApp} = require("firebase-admin/app");
const {
  FieldPath,
  FieldValue,
  getFirestore,
} = require("firebase-admin/firestore");

const CASH_RECONCILIATION_SCHEMA_VERSION = 1;
const CASH_RECONCILIATION_LOCK_ID = "cash_reconciliation";
const supportedMovementTypes = new Set([
  "expense",
  "invoice_payment",
  "receipt",
  "sales_return",
  "settlement_to_admin",
]);

function parseOptions(argv) {
  const options = {
    apply: false,
    companyId: "default_company",
    confirmCompany: "",
    confirmProject: "",
    maxIssues: 100,
    maxWrites: 400,
    pageSize: 400,
    projectId: "",
    resumeRun: "",
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
      case "--resume-run":
        options.resumeRun = value;
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
  validateApplyConfirmation(options);
  return options;
}

function validateApplyConfirmation(options) {
  if (!options.apply) return;
  if (options.confirmProject !== options.projectId) {
    throw new Error("--confirm-project must exactly match --project in apply mode");
  }
  if (options.confirmCompany !== options.companyId) {
    throw new Error("--confirm-company must exactly match --company in apply mode");
  }
  if (options.resumeRun && !/^[A-Za-z0-9-]{8,128}$/.test(options.resumeRun)) {
    throw new Error("--resume-run is invalid");
  }
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

function cashBalanceDocumentId(account, salesRepId = "") {
  if (account === "company_cash") return "company_cash";
  if (account === "rep_cash" && text(salesRepId)) {
    return `rep_${text(salesRepId)}`;
  }
  throw new Error("Representative cash requires a salesRepId");
}

function cashReconciliationLockPath(companyId) {
  return `companies/${companyId}/maintenance_locks/${CASH_RECONCILIATION_LOCK_ID}`;
}

function createAnalysisState(companyId, maxIssues = 100) {
  const state = {
    accounts: new Map(),
    companyId,
    issueCount: 0,
    issueCounts: new Map(),
    issues: [],
    maxIssues,
    scannedMovementCount: 0,
    seenEmbeddedIds: new Map(),
    seenLogicalKeys: new Map(),
    validMovementCount: 0,
  };
  ensureAccount(state, "company_cash", "");
  return state;
}

function addRepresentative(state, salesRepId) {
  const normalized = text(salesRepId);
  if (normalized) ensureAccount(state, "rep_cash", normalized);
}

function inspectStoredBalance(state, documentId, data) {
  const value = record(data);
  let account;
  let salesRepId = "";
  if (documentId === "company_cash") {
    account = "company_cash";
  } else if (documentId.startsWith("rep_") && documentId.length > 4) {
    account = "rep_cash";
    salesRepId = documentId.slice(4);
  } else {
    addIssue(state, "cash_balance", documentId, "unsupported_balance_document", "Document ID is not recognized.");
    return;
  }

  const summary = ensureAccount(state, account, salesRepId);
  summary.storedData = value;
  summary.storedExists = true;
  const amount = value.amount;
  if (typeof amount !== "number" || !Number.isFinite(amount)) {
    addIssue(state, "cash_balance", documentId, "malformed_stored_amount", "Stored amount must be finite.");
  } else {
    summary.storedBalance = roundMoney(amount);
  }
  if (
    value.id !== documentId ||
    value.companyId !== state.companyId ||
    value.cashAccount !== account ||
    text(value.salesRepId) !== salesRepId
  ) {
    addIssue(state, "cash_balance", documentId, "malformed_stored_identity", "Stored identity does not match its path.");
  }
}

function inspectCashMovement(state, documentId, data) {
  state.scannedMovementCount += 1;
  const value = record(data);
  let valid = true;
  const issue = (code, detail) => {
    valid = false;
    addIssue(state, "cash_movement", documentId, code, detail);
  };

  const embeddedId = text(value.id);
  if (!embeddedId || embeddedId !== documentId) {
    issue("malformed_movement_id", "The id field must exactly match the document ID.");
  } else if (state.seenEmbeddedIds.has(embeddedId)) {
    issue(
      "duplicate_movement_id",
      `The id field duplicates ${state.seenEmbeddedIds.get(embeddedId)}.`,
    );
  } else {
    state.seenEmbeddedIds.set(embeddedId, documentId);
  }

  if (value.companyId !== state.companyId) {
    issue("malformed_company_id", "companyId does not match the collection path.");
  }

  const amount = value.amount;
  if (typeof amount !== "number" || !Number.isFinite(amount) || amount <= 0) {
    issue("malformed_amount", "amount must be a finite number greater than zero.");
  }

  const direction = text(value.direction);
  if (direction !== "in" && direction !== "out") {
    issue("unsupported_direction", "direction must be exactly in or out.");
  }

  const account = text(value.cashAccount);
  let salesRepId = "";
  if (!account) {
    issue("ambiguous_cash_account", "cashAccount is missing and will not be inferred.");
  } else if (account === "rep_cash") {
    salesRepId = text(value.salesRepId);
    if (!salesRepId) {
      issue("missing_sales_rep_id", "rep_cash requires salesRepId.");
    }
  } else if (account !== "company_cash") {
    issue("unsupported_cash_account", `Unsupported cashAccount: ${account}`);
  }

  const movementType = text(value.movementType);
  if (!supportedMovementTypes.has(movementType)) {
    issue("unsupported_movement_type", `Unsupported movementType: ${movementType || "<missing>"}`);
  }

  const sourceCollection = text(value.sourceCollection);
  const sourceId = text(value.sourceId) || text(value.referenceId);
  if (!sourceCollection || !sourceId) {
    issue("ambiguous_movement_source", "sourceCollection and sourceId/referenceId are required.");
  }

  const movementDate = value.date ?? value.movementDate ?? value.createdAt;
  if (!isValidDateValue(movementDate)) {
    issue("malformed_movement_date", "date, movementDate, or createdAt must contain a valid date.");
  }

  if (account === "company_cash" || (account === "rep_cash" && salesRepId)) {
    ensureAccount(state, account, salesRepId);
  }

  if (sourceCollection && sourceId && movementType && (account === "company_cash" || account === "rep_cash")) {
    const logicalKey = [
      sourceCollection,
      sourceId,
      movementType,
      account,
      salesRepId,
      direction,
    ].join("|");
    const duplicate = state.seenLogicalKeys.get(logicalKey);
    if (duplicate) {
      issue("duplicate_logical_movement", `Posting identity duplicates ${duplicate}.`);
    } else {
      state.seenLogicalKeys.set(logicalKey, documentId);
    }
  }

  if (!valid) return;
  const summary = ensureAccount(state, account, salesRepId);
  summary.movementCount += 1;
  summary.lastMovementId = documentId;
  if (direction === "in") {
    summary.totalIn = roundMoney(summary.totalIn + amount);
  } else {
    summary.totalOut = roundMoney(summary.totalOut + amount);
  }
  state.validMovementCount += 1;
}

function finalizeAnalysis(state) {
  const accounts = [...state.accounts.values()]
    .map((account) => {
      const calculatedBalance = roundMoney(account.totalIn - account.totalOut);
      if (calculatedBalance < 0) {
        addIssue(
          state,
          "cash_account",
          account.documentId,
          "negative_calculated_balance",
          "Full movement history calculates a negative cash balance.",
        );
      }
      return {
        ...account,
        calculatedBalance,
        difference: account.storedBalance === null
          ? null
          : roundMoney(calculatedBalance - account.storedBalance),
      };
    })
    .sort((a, b) => {
      if (a.cashAccount !== b.cashAccount) return a.cashAccount === "company_cash" ? -1 : 1;
      return a.salesRepId.localeCompare(b.salesRepId);
    });
  return {
    accounts,
    companyId: state.companyId,
    issueCount: state.issueCount,
    issueCounts: mapToObject(state.issueCounts),
    issues: state.issues,
    scannedMovementCount: state.scannedMovementCount,
    schemaVersion: CASH_RECONCILIATION_SCHEMA_VERSION,
    validMovementCount: state.validMovementCount,
  };
}

function analyzeCashRecords({
  companyId,
  movements = [],
  representativeIds = [],
  storedBalances = [],
  maxIssues = 100,
}) {
  const state = createAnalysisState(companyId, maxIssues);
  for (const salesRepId of representativeIds) addRepresentative(state, salesRepId);
  for (const balance of storedBalances) {
    inspectStoredBalance(state, balance.id, balance.data);
  }
  for (const movement of movements) {
    inspectCashMovement(state, movement.id, movement.data);
  }
  return finalizeAnalysis(state);
}

async function buildCashReconciliationPlan({
  db,
  companyId,
  pageSize = 400,
  maxIssues = 100,
}) {
  const state = createAnalysisState(companyId, maxIssues);
  for await (const document of scanCollection(db.collection("users"), pageSize)) {
    const data = document.data();
    if (data.companyId === companyId && data.role === "sales_rep") {
      addRepresentative(state, document.id);
    }
  }

  const company = db.collection("companies").doc(companyId);
  for await (const document of scanCollection(company.collection("cash_balances"), pageSize)) {
    inspectStoredBalance(state, document.id, document.data());
  }
  for await (const document of scanCollection(company.collection("cash_movements"), pageSize)) {
    inspectCashMovement(state, document.id, document.data());
  }
  return finalizeAnalysis(state);
}

async function executeCashReconciliation({
  db,
  projectId,
  companyId,
  apply = false,
  pageSize = 400,
  maxIssues = 100,
  maxWrites = 400,
  resumeRun = "",
}) {
  const initialPlan = await buildCashReconciliationPlan({
    db,
    companyId,
    pageSize,
    maxIssues,
  });
  if (!apply) return {balanceWrites: 0, plan: initialPlan, runId: ""};
  refuseUnresolved(initialPlan);

  const runId = resumeRun || randomUUID();
  await acquireLock(db, {companyId, projectId, runId, resumeRun});
  let commitStarted = false;
  try {
    const lockedPlan = await buildCashReconciliationPlan({
      db,
      companyId,
      pageSize,
      maxIssues,
    });
    refuseUnresolved(lockedPlan);
    const changedAccounts = lockedPlan.accounts.filter((account) => !balanceMatches(account, companyId));
    if (changedAccounts.length > maxWrites) {
      throw new Error(
        `Refusing ${changedAccounts.length} balance writes; increase --max-writes after reviewing the dry-run`,
      );
    }

    const batch = db.batch();
    for (const account of changedAccounts) {
      const id = cashBalanceDocumentId(account.cashAccount, account.salesRepId);
      batch.set(
        db.doc(`companies/${companyId}/cash_balances/${id}`),
        desiredBalanceData(account, companyId),
        {merge: true},
      );
    }
    batch.set(db.doc(cashReconciliationLockPath(companyId)), {
      active: false,
      status: "completed",
      runId,
      schemaVersion: CASH_RECONCILIATION_SCHEMA_VERSION,
      projectId,
      companyId,
      accountCount: lockedPlan.accounts.length,
      balanceWriteCount: changedAccounts.length,
      movementCount: lockedPlan.scannedMovementCount,
      completedAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    }, {merge: true});
    commitStarted = true;
    await batch.commit();
    return {
      balanceWrites: changedAccounts.length,
      plan: lockedPlan,
      runId,
    };
  } catch (error) {
    if (!commitStarted) {
      await abortLock(db, companyId, runId, error);
    }
    if (commitStarted) {
      error.message = `${error.message} The reconciliation lock remains active; resume with --resume-run=${runId}.`;
    }
    throw error;
  }
}

function serializablePlan(plan) {
  return {
    schemaVersion: plan.schemaVersion,
    companyId: plan.companyId,
    scannedMovementCount: plan.scannedMovementCount,
    validMovementCount: plan.validMovementCount,
    unresolvedIssueCount: plan.issueCount,
    issuesByCode: plan.issueCounts,
    reportedIssues: plan.issues,
    accounts: plan.accounts.map((account) => ({
      path: `companies/${plan.companyId}/cash_balances/${account.documentId}`,
      cashAccount: account.cashAccount,
      salesRepId: account.salesRepId,
      movementCount: account.movementCount,
      totalIn: account.totalIn,
      totalOut: account.totalOut,
      calculatedBalance: account.calculatedBalance,
      storedBalance: account.storedBalance,
      difference: account.difference,
      lastMovementId: account.lastMovementId,
    })),
  };
}

function desiredBalanceData(account, companyId) {
  return {
    id: account.documentId,
    companyId,
    cashAccount: account.cashAccount,
    salesRepId: account.salesRepId,
    amount: account.calculatedBalance,
    lastMovementId: account.lastMovementId,
    schemaVersion: CASH_RECONCILIATION_SCHEMA_VERSION,
    reconciliation: {
      schemaVersion: CASH_RECONCILIATION_SCHEMA_VERSION,
      mode: "full_history",
      sourceCollection: "cash_movements",
      movementCount: account.movementCount,
      totalIn: account.totalIn,
      totalOut: account.totalOut,
      calculatedBalance: account.calculatedBalance,
      sourceLastMovementId: account.lastMovementId,
    },
    reconciledAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  };
}

function balanceMatches(account, companyId) {
  if (!account.storedExists || !account.storedData) return false;
  const data = account.storedData;
  const reconciliation = record(data.reconciliation);
  return data.id === account.documentId &&
    data.companyId === companyId &&
    data.cashAccount === account.cashAccount &&
    text(data.salesRepId) === account.salesRepId &&
    roundOptional(data.amount) === account.calculatedBalance &&
    data.lastMovementId === account.lastMovementId &&
    data.schemaVersion === CASH_RECONCILIATION_SCHEMA_VERSION &&
    reconciliation.schemaVersion === CASH_RECONCILIATION_SCHEMA_VERSION &&
    reconciliation.mode === "full_history" &&
    reconciliation.sourceCollection === "cash_movements" &&
    reconciliation.movementCount === account.movementCount &&
    roundOptional(reconciliation.totalIn) === account.totalIn &&
    roundOptional(reconciliation.totalOut) === account.totalOut &&
    roundOptional(reconciliation.calculatedBalance) === account.calculatedBalance &&
    reconciliation.sourceLastMovementId === account.lastMovementId;
}

async function acquireLock(db, {companyId, projectId, runId, resumeRun}) {
  const ref = db.doc(cashReconciliationLockPath(companyId));
  await db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(ref);
    const current = snapshot.data() ?? {};
    if (current.active === true) {
      if (!resumeRun || current.runId !== runId) {
        throw new Error(
          `Cash reconciliation lock is active for run ${text(current.runId) || "<unknown>"}`,
        );
      }
    }
    transaction.set(ref, {
      active: true,
      status: resumeRun ? "resumed" : "running",
      runId,
      schemaVersion: CASH_RECONCILIATION_SCHEMA_VERSION,
      projectId,
      companyId,
      tool: "reconcile_cash_balances",
      ...(resumeRun ? {resumedAt: FieldValue.serverTimestamp()} : {startedAt: FieldValue.serverTimestamp()}),
      updatedAt: FieldValue.serverTimestamp(),
    }, {merge: true});
  });
}

async function abortLock(db, companyId, runId, error) {
  const ref = db.doc(cashReconciliationLockPath(companyId));
  await db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(ref);
    const current = snapshot.data() ?? {};
    if (current.active !== true || current.runId !== runId) return;
    transaction.set(ref, {
      active: false,
      status: "aborted",
      error: String(error?.message ?? error).slice(0, 500),
      abortedAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    }, {merge: true});
  });
}

function refuseUnresolved(plan) {
  if (plan.issueCount > 0) {
    throw new Error(
      `Refusing apply mode because ${plan.issueCount} unresolved cash issue(s) exist`,
    );
  }
}

function ensureAccount(state, cashAccount, salesRepId) {
  const documentId = cashBalanceDocumentId(cashAccount, salesRepId);
  let account = state.accounts.get(documentId);
  if (!account) {
    account = {
      cashAccount,
      documentId,
      lastMovementId: "",
      movementCount: 0,
      salesRepId,
      storedBalance: null,
      storedData: null,
      storedExists: false,
      totalIn: 0,
      totalOut: 0,
    };
    state.accounts.set(documentId, account);
  }
  return account;
}

function addIssue(state, scope, documentId, code, detail) {
  state.issueCount += 1;
  state.issueCounts.set(code, (state.issueCounts.get(code) ?? 0) + 1);
  if (state.issues.length < state.maxIssues) {
    state.issues.push({scope, documentId, code, detail});
  }
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

function positiveInteger(value, name) {
  const number = Number(value);
  if (!Number.isInteger(number) || number <= 0) {
    throw new Error(`${name} must be a positive integer`);
  }
  return number;
}

function record(value) {
  return value && typeof value === "object" && !Array.isArray(value) ? value : {};
}

function text(value) {
  return typeof value === "string" ? value.trim() : "";
}

function roundMoney(value) {
  if (!Number.isFinite(value)) throw new Error("Money value is not finite");
  return Math.round((value + Number.EPSILON) * 1000) / 1000;
}

function roundOptional(value) {
  return typeof value === "number" && Number.isFinite(value) ? roundMoney(value) : null;
}

function isValidDateValue(value) {
  if (value instanceof Date) return !Number.isNaN(value.getTime());
  if (value && typeof value.toDate === "function") {
    const date = value.toDate();
    return date instanceof Date && !Number.isNaN(date.getTime());
  }
  if (typeof value === "string" || typeof value === "number") {
    return !Number.isNaN(new Date(value).getTime());
  }
  return false;
}

function mapToObject(map) {
  return Object.fromEntries([...map.entries()].sort(([a], [b]) => a.localeCompare(b)));
}

module.exports = {
  CASH_RECONCILIATION_LOCK_ID,
  CASH_RECONCILIATION_SCHEMA_VERSION,
  analyzeCashRecords,
  balanceMatches,
  buildCashReconciliationPlan,
  cashBalanceDocumentId,
  cashReconciliationLockPath,
  executeCashReconciliation,
  initializeFirestore,
  inspectCashMovement,
  parseOptions,
  serializablePlan,
};
