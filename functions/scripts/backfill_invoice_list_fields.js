const {
  buildInvoiceListFieldUpdates,
  initializeFirestore,
  parseOptions,
  scanCollection,
} = require("./invoice_list_fields_common");

async function main() {
  const options = parseOptions(process.argv.slice(2));
  const db = initializeFirestore(options.projectId);
  const invoices = db
    .collection("companies")
    .doc(options.companyId)
    .collection("invoices");

  console.log(
    `[invoice-list-fields] project=${options.projectId} company=${options.companyId} mode=${options.apply ? "APPLY" : "DRY_RUN"}`,
  );
  const audit = await auditInvoices(invoices, options);
  console.log(JSON.stringify(audit, null, 2));

  if (!options.apply) {
    console.log("[invoice-list-fields] dry-run complete; no documents changed");
    return;
  }
  if (audit.updateCount > options.maxWrites) {
    throw new Error(
      `Refusing ${audit.updateCount} writes; increase --max-writes after reviewing the dry-run`,
    );
  }

  await applyUpdates(db, invoices, options, audit.updateCount);
}

async function auditInvoices(invoices, options) {
  const issueCounts = new Map();
  const issues = [];
  let scannedCount = 0;
  let updateCount = 0;
  for await (const document of scanCollection(invoices, options.pageSize)) {
    scannedCount += 1;
    const result = buildInvoiceListFieldUpdates(document.data(), {
      createTime: document.createTime,
    });
    if (Object.keys(result.updates).length > 0) updateCount += 1;
    for (const field of result.unresolved) {
      issueCounts.set(field, (issueCounts.get(field) ?? 0) + 1);
    }
    if (result.unresolved.length > 0 && issues.length < options.maxIssues) {
      issues.push({invoiceId: document.id, fields: result.unresolved});
    }
  }
  return {
    scannedCount,
    updateCount,
    unresolvedCounts: Object.fromEntries([...issueCounts.entries()].sort()),
    unresolvedExamples: issues,
  };
}

async function applyUpdates(db, invoices, options, expectedCount) {
  let batch = db.batch();
  let batchCount = 0;
  let appliedCount = 0;
  for await (const document of scanCollection(invoices, options.pageSize)) {
    const result = buildInvoiceListFieldUpdates(document.data(), {
      createTime: document.createTime,
    });
    if (Object.keys(result.updates).length === 0) continue;
    batch.update(document.ref, result.updates, {
      lastUpdateTime: document.updateTime,
    });
    batchCount += 1;
    if (batchCount < 200) continue;
    await batch.commit();
    appliedCount += batchCount;
    console.log(
      `[invoice-list-fields] committed ${appliedCount}/${expectedCount}`,
    );
    batch = db.batch();
    batchCount = 0;
  }
  if (batchCount > 0) {
    await batch.commit();
    appliedCount += batchCount;
  }
  console.log(`[invoice-list-fields] applied ${appliedCount} updates`);
}

main().catch((error) => {
  console.error(`[invoice-list-fields] failed: ${error.message}`);
  process.exitCode = 1;
});
