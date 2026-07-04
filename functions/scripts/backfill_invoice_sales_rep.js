const {
  auditInvoices,
  collectBackfillCandidates,
  initializeFirestore,
  parseOptions,
  serializableBackfillPlan,
  serializableSummary,
} = require("./invoice_sales_rep_common");

async function main() {
  const options = parseOptions(process.argv.slice(2));
  validateApplyConfirmation(options);

  const mode = options.apply ? "APPLY" : "DRY_RUN";
  console.log(
    `[backfill] project=${options.projectId} company=${options.companyId} mode=${mode}`,
  );
  const db = initializeFirestore(options.projectId);
  const { ownershipContext, summary } = await auditInvoices({ db, ...options });
  const plan = await collectBackfillCandidates({
    db,
    ...options,
    ownershipContext,
  });

  console.log("[backfill] audit summary");
  console.log(JSON.stringify(serializableSummary(summary), null, 2));
  console.log("[backfill] proposed salesRepId-only updates");
  console.log(JSON.stringify(serializableBackfillPlan(plan), null, 2));

  if (!options.apply) {
    console.log("[backfill] dry-run complete; no documents were changed");
    return;
  }
  if (plan.candidates.length > options.maxWrites) {
    throw new Error(
      `Refusing ${plan.candidates.length} writes; increase --max-writes after reviewing the dry-run`,
    );
  }

  await applyCandidates(db, plan.candidates);
  console.log(`[backfill] applied ${plan.candidates.length} salesRepId updates`);
}

function validateApplyConfirmation(options) {
  if (!options.apply) return;
  if (options.confirmProject !== options.projectId) {
    throw new Error("--confirm-project must exactly match --project in apply mode");
  }
  if (options.confirmCompany !== options.companyId) {
    throw new Error("--confirm-company must exactly match --company in apply mode");
  }
}

async function applyCandidates(db, candidates) {
  const batchSize = 200;
  for (let offset = 0; offset < candidates.length; offset += batchSize) {
    const batch = db.batch();
    const page = candidates.slice(offset, offset + batchSize);
    for (const candidate of page) {
      batch.update(
        candidate.document.ref,
        { salesRepId: candidate.salesRepId },
        { lastUpdateTime: candidate.document.updateTime },
      );
    }
    await batch.commit();
    console.log(`[backfill] committed ${offset + page.length}/${candidates.length}`);
  }
}

main().catch((error) => {
  console.error(`[backfill] failed: ${error.message}`);
  process.exitCode = 1;
});
