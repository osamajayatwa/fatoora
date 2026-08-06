const {
  executeCashReconciliation,
  initializeFirestore,
  parseOptions,
  serializablePlan,
} = require("./cash_reconciliation_common");

async function main() {
  const options = parseOptions(process.argv.slice(2));
  const mode = options.apply ? "APPLY" : "DRY_RUN";
  console.log(
    `[cash-reconciliation] project=${options.projectId} company=${options.companyId} mode=${mode}`,
  );
  const db = initializeFirestore(options.projectId);
  const result = await executeCashReconciliation({db, ...options});
  console.log(JSON.stringify(serializablePlan(result.plan), null, 2));

  if (!options.apply) {
    console.log("[cash-reconciliation] dry-run complete; no documents were changed");
    return;
  }
  console.log(
    `[cash-reconciliation] run=${result.runId} applied=${result.balanceWrites} balance document(s)`,
  );
}

main().catch((error) => {
  console.error(`[cash-reconciliation] failed: ${error.message}`);
  process.exitCode = 1;
});
