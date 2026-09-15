import {getApps, initializeApp} from "firebase-admin/app";
import {
  FieldValue,
  FieldPath,
  Firestore,
  QueryDocumentSnapshot,
  getFirestore,
} from "firebase-admin/firestore";
import {
  ACCOUNT_ACTIVITY_METADATA_COLLECTION,
  ACCOUNT_ACTIVITY_PROJECTION_VERSION,
  ACCOUNT_ACTIVITY_STATE_COLLECTION,
  buildFinancialLedgerAccountActivity,
  reconcileFinancialLedgerAccountActivity,
} from "../trusted/financial_ledger_account_reporting";

const LEDGER_COLLECTION = "financial_ledger_entries";
const MAX_WRITES_PER_CHANGED_ENTRY = 25;

interface Options {
  projectId: string;
  companyId: string;
  apply: boolean;
  confirmProject: string;
  confirmCompany: string;
  pageSize: number;
  maxWrites: number;
}

interface BackfillPlan {
  scannedEntries: number;
  currentEntries: number;
  changedEntryIds: string[];
  maximumPlannedWrites: number;
}

export async function runFinancialLedgerAccountActivityBackfill(
  options: Options,
  firestore?: Firestore,
): Promise<Record<string, unknown>> {
  if (!firestore && getApps().length === 0) {
    initializeApp({projectId: options.projectId});
  }
  const db = firestore ?? getFirestore();
  const plan = await buildPlan(db, options);
  if (options.apply) {
    validateApply(options, plan);
    for (const entryId of plan.changedEntryIds) {
      await reconcileFinancialLedgerAccountActivity(
        db,
        options.companyId,
        entryId,
      );
    }
    await db.doc(
      `companies/${options.companyId}/${ACCOUNT_ACTIVITY_METADATA_COLLECTION}/current`,
    ).set({
      projectionVersion: ACCOUNT_ACTIVITY_PROJECTION_VERSION,
      status: "ready",
      companyId: options.companyId,
      sourceCollection: LEDGER_COLLECTION,
      sourceEntryCount: plan.scannedEntries,
      completedAt: FieldValue.serverTimestamp(),
    });
  }
  return {
    mode: options.apply ? "apply" : "dry-run",
    projectId: options.projectId,
    companyId: options.companyId,
    projectionOnly: true,
    sourceCollection: LEDGER_COLLECTION,
    targetCollections: [
      ACCOUNT_ACTIVITY_STATE_COLLECTION,
      "financial_ledger_account_activity_scopes",
      ACCOUNT_ACTIVITY_METADATA_COLLECTION,
    ],
    scannedEntries: plan.scannedEntries,
    currentEntries: plan.currentEntries,
    changedEntries: plan.changedEntryIds.length,
    maximumPlannedWrites: plan.maximumPlannedWrites,
    maxWrites: options.maxWrites,
    appliedEntries: options.apply ? plan.changedEntryIds.length : 0,
  };
}

async function buildPlan(
  firestore: Firestore,
  options: Options,
): Promise<BackfillPlan> {
  let cursor: QueryDocumentSnapshot | null = null;
  let scannedEntries = 0;
  let currentEntries = 0;
  const changedEntryIds: string[] = [];
  while (true) {
    let query = firestore
      .collection(`companies/${options.companyId}/${LEDGER_COLLECTION}`)
      .orderBy(FieldPath.documentId())
      .limit(options.pageSize);
    if (cursor) query = query.startAfter(cursor);
    const snapshot = await query.get();
    if (snapshot.empty) break;
    const stateRefs = snapshot.docs.map((entry) => firestore.doc(
      `companies/${options.companyId}/${ACCOUNT_ACTIVITY_STATE_COLLECTION}/${entry.id}`,
    ));
    const states = await firestore.getAll(...stateRefs);
    for (let index = 0; index < snapshot.docs.length; index += 1) {
      const entry = snapshot.docs[index];
      const expected = buildFinancialLedgerAccountActivity(entry.id, entry.data());
      const state = states[index];
      scannedEntries += 1;
      if (
        state.exists &&
        state.get("fingerprint") === expected.fingerprint &&
        state.get("projectionVersion") === 1
      ) {
        currentEntries += 1;
      } else {
        changedEntryIds.push(entry.id);
      }
    }
    cursor = snapshot.docs.at(-1) ?? null;
    if (snapshot.size < options.pageSize) break;
  }
  return {
    scannedEntries,
    currentEntries,
    changedEntryIds,
    maximumPlannedWrites:
      changedEntryIds.length * MAX_WRITES_PER_CHANGED_ENTRY + 1,
  };
}

function validateApply(options: Options, plan: BackfillPlan): void {
  if (
    options.confirmProject !== options.projectId ||
    options.confirmCompany !== options.companyId
  ) {
    throw new Error(
      "Apply requires exact --confirm-project and --confirm-company values.",
    );
  }
  if (plan.maximumPlannedWrites > options.maxWrites) {
    throw new Error(
      `Maximum planned writes ${plan.maximumPlannedWrites} exceed ` +
      `--max-writes=${options.maxWrites}.`,
    );
  }
}

function parseOptions(args: string[]): Options {
  const values = new Map<string, string>();
  let apply = false;
  for (const argument of args) {
    if (argument === "--apply") {
      apply = true;
    } else if (argument.startsWith("--") && argument.includes("=")) {
      const separator = argument.indexOf("=");
      values.set(argument.slice(2, separator), argument.slice(separator + 1));
    } else {
      throw new Error(`Unsupported argument: ${argument}`);
    }
  }
  const projectId = values.get("project") ?? "";
  const companyId = values.get("company") ?? "";
  if (!projectId || !companyId || companyId.includes("/")) {
    throw new Error("Valid --project and --company values are required.");
  }
  return {
    projectId,
    companyId,
    apply,
    confirmProject: values.get("confirm-project") ?? "",
    confirmCompany: values.get("confirm-company") ?? "",
    pageSize: positiveInteger(values.get("page-size"), 200),
    maxWrites: positiveInteger(values.get("max-writes"), 5_000),
  };
}

function positiveInteger(value: string | undefined, fallback: number): number {
  const parsed = Number(value ?? fallback);
  if (!Number.isInteger(parsed) || parsed <= 0) {
    throw new Error("Numeric options must be positive integers.");
  }
  return parsed;
}

async function main(): Promise<void> {
  const report = await runFinancialLedgerAccountActivityBackfill(
    parseOptions(process.argv.slice(2)),
  );
  process.stdout.write(`${JSON.stringify(report, null, 2)}\n`);
}

function errorMessage(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}

if (require.main === module) {
  void main().catch((error) => {
    process.stderr.write(`${errorMessage(error)}\n`);
    process.exitCode = 1;
  });
}
