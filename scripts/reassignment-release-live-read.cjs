"use strict";
// Read-only staging metadata and query plans. No deployment or document writes.
const fs = require("node:fs"), path = require("node:path");
const root = path.resolve(__dirname, ".."), PROJECT = "fatoora-original-staging";
const load = require("node:module").createRequire(path.join(root, "functions/package.json"));
function check(ok, message) { if (!ok) throw new Error(message); }
async function inspect(requireReady = false) {
  check(!Object.entries(process.env).some(([k, v]) => v && (k.endsWith("_EMULATOR_HOST") ||
    ["GOOGLE_APPLICATION_CREDENTIALS", "FIREBASE_TOKEN", "FIRESTORE_URL"].includes(k))), "Unexpected credential/emulator override");
  for (const key of ["GCLOUD_PROJECT", "GOOGLE_CLOUD_PROJECT", "CLOUDSDK_CORE_PROJECT"]) {
    check(!process.env[key] || process.env[key] === PROJECT, "Unexpected project override");
  }
  const state = JSON.parse(fs.readFileSync(path.join(root, ".staging", PROJECT, "provisioning-state.json")));
  check(state.projectId === PROJECT && state.projectNumber === "5438538531", "Staging identity mismatch");
  const {client, verifyProject} = require("./staging-cloud.cjs");
  const c = await client();
  await verifyProject(c, state);
  async function get(url) {
    const u = new URL(url);
    check(u.protocol === "https:" && ["firestore.googleapis.com", "firebaserules.googleapis.com",
      "cloudfunctions.googleapis.com", "firebasehosting.googleapis.com"].includes(u.hostname), "Unexpected metadata API");
    check(u.pathname.includes(`/projects/${PROJECT}/`) || u.pathname.includes(`/sites/${PROJECT}/`), "Non-staging metadata path");
    return (await c.request({url, method: "GET", retry: true, retryConfig:{retry:2,noResponseRetries:2,retryDelay:1000},timeout:30000,
      agent:new(require("node:https").Agent)({family:4})})).data;
  }
  async function list(url, field) {
    const rows = []; let token;
    do {
      const data = await get(url + (token ? `${url.includes("?") ? "&" : "?"}pageToken=${encodeURIComponent(token)}` : ""));
      rows.push(...(data[field] || [])); token = data.nextPageToken;
    } while (token);
    return rows;
  }
  const indexes = await list(`https://firestore.googleapis.com/v1/projects/${PROJECT}/databases/(default)/collectionGroups/-/indexes`, "indexes");
  const release = await get(`https://firebaserules.googleapis.com/v1/projects/${PROJECT}/releases/cloud.firestore`);
  const rules = await get(`https://firebaserules.googleapis.com/v1/${release.rulesetName}`);
  const functions = await list(`https://cloudfunctions.googleapis.com/v2/projects/${PROJECT}/locations/us-central1/functions?pageSize=100`, "functions");
  const hosting = await list(`https://firebasehosting.googleapis.com/v1beta1/sites/${PROJECT}/releases?pageSize=1`, "releases");
  const currentHosting = hosting[0];
  check(currentHosting?.version?.name?.startsWith(`sites/${PROJECT}/versions/`), "Missing current Hosting version");
  const hostingFiles = await list(`https://firebasehosting.googleapis.com/v1beta1/${currentHosting.version.name}/files?pageSize=1000`, "files");
  const {Firestore, Filter} = load("@google-cloud/firestore");
  const db = new Firestore({projectId: PROJECT, authClient: c});
  const plans = [];
  async function explain(query, shape) {
    try {
      const result = await query.limit(1).explain({analyze: false});
      plans.push({...shape, status: "PASS", indexesUsed: result.metrics.planSummary.indexesUsed});
    } catch (error) {
      plans.push({...shape, status: "BLOCKED", code: error.code,
        reason: String(error.message).slice(0, 600),
        missingIndex: /requires an index|no matching index/i.test(error.message || "")});
    }
  }
  try {
    const invoices = db.collection("companies/default_company/invoices");
    for (const sort of ["invoiceNumberLower", "invoiceDate", "customerNameLower", "salesRepName", "grandTotal", "remainingAmount", "invoiceStatus", "createdAt"]) {
      for (const direction of ["asc", "desc"]) {
        for (const ranged of sort === "invoiceDate" ? [false, true] : [false]) {
          let query = invoices.where("customerId", "==", "release-plan-only").where("salesRepId", "==", "release-plan-only");
          if (ranged) query = query.where("invoiceDate", ">=", new Date("2026-01-01T00:00:00Z"));
          query = query.orderBy(sort, direction).orderBy("__name__", direction).limit(1);
          try {
            const result = await query.explain({analyze: false});
            plans.push({sort, direction, ranged, status: "PASS", indexesUsed: result.metrics.planSummary.indexesUsed});
          } catch (error) {
            plans.push({sort, direction, ranged, status: "BLOCKED", code: error.code,
              missingIndex: /requires an index/i.test(error.message || "")});
          }
        }
      }
    }
    for (const sort of ["invoiceNumberLower", "invoiceDate", "customerNameLower", "salesRepName", "grandTotal", "remainingAmount", "invoiceStatus", "createdAt"]) {
      for (const direction of ["asc", "desc"]) {
        for (const search of [false, true]) {
          for (const ranged of sort === "invoiceDate" ? [false, true] : [false]) {
            let query = invoices.where("customerId", "==", "release-plan-only").where(Filter.or(
              Filter.where("salesRepId", "==", "release-plan-only"), Filter.where("financialPosted", "==", true)));
            if (search) query = query.where("searchKeywords", "array-contains", "synthetic");
            if (ranged) query = query.where("invoiceDate", ">=", new Date("2026-01-01T00:00:00Z"));
            await explain(query.orderBy(sort, direction).orderBy("__name__", direction),
              {scope: "customer-history", sort, direction, search, ranged});
          }
        }
      }
    }
    for (const status of ["draft", "confirmed", "accepted"]) {
      for (const search of [false, true]) {
        let query = invoices.where("customerId", "==", "release-plan-only").where(Filter.or(
          Filter.where("salesRepId", "==", "release-plan-only"), Filter.where("financialPosted", "==", true)))
          .where("invoiceStatus", "==", status).where("invoiceType", "==", "electronic")
          .where("paymentStatus", "==", "unpaid").where("returnStatus", "==", "none")
          .where("invoiceDate", ">=", new Date("2026-01-01T00:00:00Z"));
        if (search) query = query.where("searchKeywords", "array-contains", "synthetic");
        await explain(query.orderBy("invoiceDate", "desc").orderBy("__name__", "desc"),
          {scope: "customer-history-all-filters", sort: "invoiceDate", direction: "desc", search, ranged: true, invoiceStatus: status});
      }
    }
    for (const sort of ["invoiceNumberLower", "invoiceDate", "customerNameLower", "salesRepName", "grandTotal", "remainingAmount", "invoiceStatus", "createdAt"]) {
      for (const direction of ["asc", "desc"]) {
        for (const ranged of sort === "invoiceDate" ? [false, true] : [false]) {
          let query = invoices.where("customerId", "==", "release-plan-only").where("salesRepId", "==", "release-plan-only")
            .where("searchKeywords", "array-contains", "synthetic");
          if (ranged) query = query.where("invoiceDate", ">=", new Date("2026-01-01T00:00:00Z"));
          await explain(query.orderBy(sort, direction).orderBy("__name__", direction),
            {scope: "own-customer-search", sort, direction, ranged, search: true});
        }
      }
    }
    for (const status of ["draft", "confirmed", "accepted"]) {
      for (const search of [false, true]) {
        let query = invoices.where("customerId", "==", "release-plan-only").where("salesRepId", "==", "release-plan-only")
          .where("invoiceStatus", "==", status).where("invoiceType", "==", "electronic")
          .where("paymentStatus", "==", "unpaid").where("returnStatus", "==", "none")
          .where("invoiceDate", ">=", new Date("2026-01-01T00:00:00Z"));
        if (search) query = query.where("searchKeywords", "array-contains", "synthetic");
        await explain(query.orderBy("invoiceDate", "desc").orderBy("__name__", "desc"),
          {scope: "own-customer-all-filters", sort: "invoiceDate", direction: "desc", ranged: true, search, invoiceStatus: status});
      }
    }
  } finally { await db.terminate(); }
  const output = {at: new Date().toISOString(), project: PROJECT, projectNumber: state.projectNumber,
    readOnly: true, documentWrites: 0, queryPlansAnalyze: false, indexes,
    rulesRelease: release, rules,
    functions: functions.map(f => ({name: f.name, state: f.state, labels: f.labels,
      buildConfig: {runtime: f.buildConfig?.runtime, entryPoint: f.buildConfig?.entryPoint, source: f.buildConfig?.source,
        serviceAccount: f.buildConfig?.serviceAccount},
      serviceConfig: {serviceAccountEmail: f.serviceConfig?.serviceAccountEmail, uri: f.serviceConfig?.uri,
        ingressSettings: f.serviceConfig?.ingressSettings, minInstanceCount: f.serviceConfig?.minInstanceCount}})),
    hosting: currentHosting, hostingFiles, queryPlans: plans};
  const directory = path.join(root, "build/reassignment-release-evidence");
  fs.mkdirSync(directory, {recursive: true});
  fs.writeFileSync(path.join(directory, requireReady ? "native-query-readiness.json" : "live-staging-read.json"), JSON.stringify(output, null, 2) + "\n");
  console.log(JSON.stringify({project: PROJECT, readOnly: true, documentWrites: 0,
    indexes: indexes.length, ready: indexes.filter(i => i.state === "READY").length,
    activeFunctions: functions.filter(f => f.state === "ACTIVE").length,
    plans: plans.length, missingIndexes: plans.filter(p => p.missingIndex).length,
    otherPlanFailures: plans.filter(p => p.status !== "PASS" && !p.missingIndex).length}));
  if (requireReady) check(plans.every(p => p.status === "PASS") && indexes.length === 300 && indexes.every(i => i.state === "READY"), "Candidate index readiness gate is not satisfied");
}
if (require.main === module) {
  check(process.argv.length === 2 || (process.argv.length === 3 && process.argv[2] === "--require-ready"), "Only read-only inspection or --require-ready is supported");
  inspect(process.argv[2] === "--require-ready").catch(error => {
  console.error(JSON.stringify({status: "BLOCKED", code: error.code, httpStatus: error.response?.status,
    reason: error.response?.data?.error?.message || error.message})); process.exitCode = 1;
  });
}
module.exports = {inspect};
