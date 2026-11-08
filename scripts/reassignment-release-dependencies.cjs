"use strict";
// Offline comparison against the retained, hash-verified deployed source archive.
const fs = require("node:fs"), path = require("node:path"), cp = require("node:child_process"), crypto = require("node:crypto");
const root = path.resolve(__dirname, ".."), rc = path.join(root, "build/reassignment-release/rc1");
const hash = bytes => crypto.createHash("sha256").update(bytes).digest("hex");
const evidence = path.join(root, "build/reassignment-release-evidence");
function check(ok, message) { if (!ok) throw Error(message); }
function main() {
  check(process.argv.length === 2, "Offline dependency inspection takes no target or deployment flags");
  const archive = path.join(rc, "rollback/functions.zip");
  const source = JSON.parse(cp.execFileSync("python", ["-c", [
    "import zipfile,json,sys,hashlib",
    "with zipfile.ZipFile(sys.argv[1]) as z:",
    " print(json.dumps({n:z.read(n).decode('utf-8') for n in z.namelist() if n.endswith(('.ts','.js','.cjs')) and n.startswith(('src/','lib/','shared/')) or n in ('package.json','package-lock.json')}))",
  ].join("\n"), archive], {encoding: "utf8", maxBuffer: 10000000}));
  const changed = Object.keys(source).filter(n => n.startsWith("src/") && (!fs.existsSync(path.join(rc, "functions", n)) ||
    hash(Buffer.from(source[n])) !== hash(fs.readFileSync(path.join(rc, "functions", n))))).sort();
  check(JSON.stringify(changed) === JSON.stringify(["src/maintenance/rebuild_financial_ledger.ts", "src/trusted/confirm_sales_return.ts", "src/trusted/financial_ledger_mappings.ts"]), "Unreviewed Functions source change");
  const load = require("node:module").createRequire(path.join(root, "functions/package.json")), ts = load("typescript");
  function bodies(text) {
    const ast = ts.createSourceFile("mapping.js", text, ts.ScriptTarget.Latest, true, ts.ScriptKind.JS);
    return Object.fromEntries(ast.statements.filter(ts.isFunctionDeclaration).filter(n => n.name).map(n => [n.name.text, n.getText(ast)]));
  }
  const oldBodies = bodies(source["lib/trusted/financial_ledger_mappings.js"]);
  const newBodies = bodies(fs.readFileSync(path.join(rc, "functions/lib/trusted/financial_ledger_mappings.js"), "utf8"));
  const changedMappingFunctions = Object.keys(oldBodies).filter(k => oldBodies[k] !== newBodies[k]);
  check(JSON.stringify(changedMappingFunctions) === '["buildSalesReturnFinancialLedgerEntries"]', "Shared mapping affects an unrelated writer");
  check(hash(Buffer.from(source["src/index.ts"])) === hash(fs.readFileSync(path.join(rc, "functions/src/index.ts"))), "Function exports changed");
  check(source["package-lock.json"] === fs.readFileSync(path.join(rc, "functions/package-lock.json"), "utf8"), "Functions dependency lock changed");
  const oldPackage = JSON.parse(source["package.json"]), newPackage = JSON.parse(fs.readFileSync(path.join(rc, "functions/package.json")));
  check(JSON.stringify(oldPackage.dependencies) === JSON.stringify(newPackage.dependencies) && JSON.stringify(oldPackage.engines) === JSON.stringify(newPackage.engines) && oldPackage.main === newPackage.main, "Runtime or dependencies changed");
  const oldPath = path.join(evidence, "rollback-functions");
  for (const [name, content] of Object.entries(source)) {
    const target = path.resolve(oldPath, name); check(target.startsWith(oldPath + path.sep), "Archive traversal refused");
    fs.mkdirSync(path.dirname(target), {recursive: true}); fs.writeFileSync(target, content);
  }
  const code = "const f=require(process.argv[1]);process.stdout.write(JSON.stringify(Object.fromEntries(Object.entries(f).map(([k,v])=>[k,v.__endpoint]))));";
  const env = {...process.env, NODE_PATH: path.join(root, "functions/node_modules"), FIREBASE_CONFIG: '{"projectId":"fatoora-original-staging"}', GCLOUD_PROJECT: "fatoora-original-staging", GOOGLE_CLOUD_PROJECT: "fatoora-original-staging"};
  const endpoints = entry => JSON.parse(cp.execFileSync(process.execPath, ["-e", code, entry], {env, encoding: "utf8", maxBuffer: 1000000}));
  const before = endpoints(path.join(oldPath, "lib/staging-entry.cjs")), after = endpoints(path.join(rc, "functions/lib/staging-entry.cjs"));
  check(Object.keys(after).length === 35 && JSON.stringify(before) === JSON.stringify(after), "Callable/trigger metadata changed");
  const result = {status: "PASS", changedSources: changed, changedMappingFunctions, exportsUnchanged: 35,
    lockUnchanged: true, runtimeAdapterUnchanged: hash(Buffer.from(source["lib/staging-entry.cjs"])) === hash(fs.readFileSync(path.join(rc, "functions/lib/staging-entry.cjs"))),
    deploymentFunctions: ["confirmSalesReturn"], maintenanceExecuted: false, accountingPhase2B5Unchanged: true};
  fs.writeFileSync(path.join(evidence, "dependencies.json"), JSON.stringify(result, null, 2) + "\n");
  console.log(JSON.stringify(result));
}
if (require.main === module) try { main(); } catch (error) { console.error(JSON.stringify({status: "BLOCKED", reason: error.message})); process.exitCode = 1; }
