const {
  auditInvoices,
  initializeFirestore,
  parseOptions,
  serializableSummary,
} = require("./invoice_sales_rep_common");

async function main() {
  const options = parseOptions(process.argv.slice(2));
  if (options.apply) {
    throw new Error("The audit command is read-only and does not accept --apply");
  }

  console.log(
    `[audit] project=${options.projectId} company=${options.companyId} mode=READ_ONLY`,
  );
  const db = initializeFirestore(options.projectId);
  const { summary } = await auditInvoices({ db, ...options });
  console.log(JSON.stringify(serializableSummary(summary), null, 2));
}

main().catch((error) => {
  console.error(`[audit] failed: ${error.message}`);
  process.exitCode = 1;
});
