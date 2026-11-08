"use strict";
// Read-only, current-version rollback capture. No deployment or business writes.
const fs = require("node:fs"), path = require("node:path"), crypto = require("node:crypto");
const zlib = require("node:zlib"), cp = require("node:child_process");
const root = path.resolve(__dirname, ".."), PROJECT = "fatoora-original-staging";
const directory = path.join(root, ".staging", PROJECT, "current-release");
const load = require("node:module").createRequire(path.join(root, "functions/package.json"));
const sha = b => crypto.createHash("sha256").update(b).digest("hex");
const check = (ok, message) => { if (!ok) throw Error(message); };
const read = file => JSON.parse(fs.readFileSync(file, "utf8"));
function save(file, value) {
  fs.mkdirSync(path.dirname(file), {recursive: true});
  fs.writeFileSync(file, JSON.stringify(value, null, 2) + "\n");
}
function canonical(value, key = "") {
  if (Array.isArray(value)) {
    const rows=value.map(v=>canonical(v));
    return key === "eventFilters" ? rows.sort((a,b)=>JSON.stringify(a).localeCompare(JSON.stringify(b))) : rows;
  }
  if (value && typeof value === "object") return Object.fromEntries(Object.keys(value).sort().map(k=>[k,canonical(value[k],k)]));
  return value;
}
async function mapLimit(rows, action, count = 4) {
  const output = new Array(rows.length); let next = 0;
  await Promise.all(Array.from({length: Math.min(count, rows.length)}, async () => {
    for (;;) { const i = next++; if (i >= rows.length) return; output[i] = await action(rows[i], i); }
  }));
  return output;
}
function safeTarget(base, name) {
  check(!name.includes("\\") && !name.startsWith("/") && !name.split("/").includes(".."), "Unsafe artifact path");
  const result = path.resolve(base, name);
  check(result.startsWith(base + path.sep), "Artifact escapes rollback directory");
  return result;
}
async function snapshot(backendOnly = false) {
  check(!Object.entries(process.env).some(([k,v]) => v && (k.endsWith("_EMULATOR_HOST") ||
    ["GOOGLE_APPLICATION_CREDENTIALS", "FIREBASE_TOKEN", "FIRESTORE_URL"].includes(k))), "Unexpected credential/emulator override");
  for (const k of ["GCLOUD_PROJECT", "GOOGLE_CLOUD_PROJECT", "CLOUDSDK_CORE_PROJECT"]) {
    check(!process.env[k] || process.env[k] === PROJECT, "Unexpected target override");
  }
  const state = read(path.join(directory, "../provisioning-state.json"));
  check(state.projectId === PROJECT && state.projectNumber === "5438538531", "Staging identity mismatch");
  const {client, verifyProject} = require("./staging-cloud.cjs"), c = await client();
  await verifyProject(c, state);
  const bucket = `gcf-v2-sources-${state.projectNumber}-us-central1`;
  async function get(url, binary = false) {
    const u = new URL(url);
    const api = ["cloudfunctions.googleapis.com", "firebaserules.googleapis.com", "firestore.googleapis.com", "firebasehosting.googleapis.com"].includes(u.hostname) &&
      (u.pathname.includes(`/projects/${PROJECT}/`) || u.pathname.includes(`/sites/${PROJECT}/`));
    const source = u.hostname === "storage.googleapis.com" && u.pathname.startsWith(`/storage/v1/b/${bucket}/o/`);
    check(u.protocol === "https:" && (api || source), "Read outside approved staging resources refused");
    return (await c.request({url, method: "GET", retry: false, timeout: 30000,
      ...(binary ? {responseType: "arraybuffer"} : {})})).data;
  }
  async function list(url, field) {
    const rows = []; let token;
    do {
      const u = new URL(url); if (token) u.searchParams.set("pageToken", token);
      const data = await get(u.toString()); check(!data.unreachable?.length, "Incomplete resource listing");
      rows.push(...data[field] || []); token = data.nextPageToken;
    } while (token);
    return rows;
  }
  const functionsUrl = `https://cloudfunctions.googleapis.com/v2/projects/${PROJECT}/locations/us-central1/functions?pageSize=100`;
  const functions = await list(functionsUrl, "functions");
  check(functions.length === 35 && functions.every(f => f.state === "ACTIVE" && f.labels?.["firebase-functions-codebase"] === PROJECT), "Unexpected Functions baseline");
  const release = await get(`https://firebaserules.googleapis.com/v1/projects/${PROJECT}/releases/cloud.firestore`);
  const rules = await get(`https://firebaserules.googleapis.com/v1/${release.rulesetName}`);
  const indexes = await list(`https://firestore.googleapis.com/v1/projects/${PROJECT}/databases/(default)/collectionGroups/-/indexes`, "indexes");
  const hosting = (await list(`https://firebasehosting.googleapis.com/v1beta1/sites/${PROJECT}/releases?pageSize=1`, "releases"))[0];
  check(hosting?.version?.name?.startsWith(`sites/${PROJECT}/versions/`), "Missing Hosting version");
  const files = await list(`https://firebasehosting.googleapis.com/v1beta1/${hosting.version.name}/files?pageSize=1000`, "files");
  const rollback = path.join(directory, "rollback"), archiveDir = path.join(rollback, "archives");
  fs.mkdirSync(archiveDir, {recursive: true});
  const cached = fs.readdirSync(path.join(directory, "../artifacts")).filter(f => /^[a-f0-9]{64}\.zip$/.test(f)).map(f => {
    const bytes = fs.readFileSync(path.join(directory, "../artifacts", f));
    check(sha(bytes) === f.slice(0, -4), "Cached source checksum mismatch");
    return {bytes, md5: crypto.createHash("md5").update(bytes).digest("base64")};
  });
  const sources = await mapLimit(functions, async f => {
    const source = f.buildConfig?.source?.storageSource;
    check(source?.bucket === bucket && /^\d+$/.test(String(source.generation)), "Unexpected Function source location");
    const url = `https://storage.googleapis.com/storage/v1/b/${bucket}/o/${encodeURIComponent(source.object)}?generation=${source.generation}`;
    const meta = await get(url + "&fields=bucket,name,generation,md5Hash,size");
    check(meta.bucket === bucket && meta.name === source.object && meta.generation === String(source.generation) && Number(meta.size) < 10000000, "Source metadata mismatch");
    let bytes = cached.find(a => a.md5 === meta.md5Hash && a.bytes.length === Number(meta.size))?.bytes;
    if (!bytes) bytes = Buffer.from(await get(url + "&alt=media", true));
    check(bytes.length === Number(meta.size) && crypto.createHash("md5").update(bytes).digest("base64") === meta.md5Hash, "Source download integrity failure");
    const hash = sha(bytes); fs.writeFileSync(path.join(archiveDir, `${hash}.zip`), bytes);
    return {function: f.name, source, sha256: hash, md5: meta.md5Hash, size: bytes.length};
  });
  const ruleFile = rules.source.files.find(f => f.name === "firestore.rules"); check(ruleFile, "Missing deployed Rules source");
  fs.writeFileSync(path.join(rollback, "firestore.rules"), ruleFile.content);
  const captured = {at:new Date().toISOString(),project:PROJECT,projectNumber:state.projectNumber,
    functions,release,rules,indexes,hosting,sources,hostingFiles:files};
  save(path.join(rollback,"baseline.json"),captured);
  save(path.join(rollback,"backend-verification.json"),{status:"PASS_BACKEND_BYTES",project:PROJECT,remoteWrites:0,
    functions:functions.length,sourceArchives:[...new Set(sources.map(s=>s.sha256))],ruleset:release.rulesetName,
    hostingVersion:hosting.version.name,hostingAssetBytesVerified:false,rollbackExecutionApproved:false});
  if (backendOnly) { console.log(JSON.stringify({status:"PASS_BACKEND_BYTES",functions:functions.length,hostingAssetBytesVerified:false,remoteWrites:0})); return; }
  const web = await mapLimit(files, async file => {
    if (["/__/firebase/init.js", "/__/firebase/init.json"].includes(file.path)) return {...file, firebaseManaged: true};
    check(file.path.startsWith("/") && !file.path.startsWith("//"), "Unsafe Hosting file path");
    const target = safeTarget(path.join(rollback, "web"), file.path.slice(1));
    if (fs.existsSync(target)) {
      const bytes=fs.readFileSync(target);
      if (sha(zlib.gzipSync(bytes,{level:9})) === file.hash) return {...file,rawSha256:sha(bytes),verifiedGzipSha256:true};
    }
    const url = new URL(file.path, `https://${PROJECT}.web.app`);
    check(url.origin === `https://${PROJECT}.web.app`, "Hosting origin mismatch");
    // Anonymous HTTPS: do not attach the operator's OAuth token to a public site.
    const response = await load("gaxios").request({url:url.toString(),method:"GET",responseType:"arraybuffer",retry:false,timeout:30000,maxRedirects:0,
      agent:new (require("node:https").Agent)({family:4})});
    check(response.status === 200, `Hosting rollback asset unavailable: ${file.path}`);
    const bytes = Buffer.from(response.data);
    check(sha(zlib.gzipSync(bytes, {level: 9})) === file.hash, `Hosting rollback checksum mismatch: ${file.path}`);
    fs.mkdirSync(path.dirname(target), {recursive: true}); fs.writeFileSync(target, bytes);
    return {...file, rawSha256: sha(bytes), verifiedGzipSha256: true};
  });
  const currentFunctions = await list(functionsUrl, "functions");
  const currentHosting = (await list(`https://firebasehosting.googleapis.com/v1beta1/sites/${PROJECT}/releases?pageSize=1`, "releases"))[0];
  const currentRules = await get(`https://firebaserules.googleapis.com/v1/projects/${PROJECT}/releases/cloud.firestore`);
  const fingerprint = rows => JSON.stringify(canonical([...rows].sort((a,b)=>a.name.localeCompare(b.name))));
  save(path.join(rollback,"capture-final-read.json"),{functions:currentFunctions,hosting:currentHosting,release:currentRules});
  if(fingerprint(functions)!==fingerprint(currentFunctions)) console.log(JSON.stringify({changedMetadata:functions.filter(f=>JSON.stringify(canonical(f))!==JSON.stringify(canonical(currentFunctions.find(x=>x.name===f.name)))).map(f=>({name:f.name,fields:Object.keys(f).filter(k=>JSON.stringify(canonical(f[k]))!==JSON.stringify(canonical(currentFunctions.find(x=>x.name===f.name)?.[k])))}))}));
  check(fingerprint(functions) === fingerprint(currentFunctions) && currentHosting.name === hosting.name && currentRules.rulesetName === release.rulesetName, "Deployed revisions changed during rollback capture");
  save(path.join(rollback, "baseline.json"), {at: new Date().toISOString(), project: PROJECT, projectNumber: state.projectNumber,
    functions, release, rules, indexes, hosting, sources, web});
  // Additive indexes are retained during rollback; financial data is never restored.
  const result = {status: "PASS_ARTIFACT_CAPTURE", project: PROJECT, remoteWrites: 0,
    functions: functions.length, distinctSourceArchives: new Set(sources.map(s => s.sha256)).size,
    ruleset: release.rulesetName, hostingVersion: hosting.version.name, hostingFilesVerified: web.filter(f => f.verifiedGzipSha256).length,
    managedHostingFiles: web.filter(f => f.firebaseManaged).length,
    rollbackExecutionApproved: false, reason: "Captured bytes need safety review before any rollback execution; never restore financial data or unsafe posting/Rules."};
  save(path.join(rollback, "verification.json"), result); console.log(JSON.stringify(result));
}
function compare() {
  const rollback = path.join(directory, "rollback"), baseline = read(path.join(rollback, "baseline.json"));
  const hashes = [...new Set(baseline.sources.map(s => s.sha256))];
  check(baseline.project === PROJECT && hashes.length === 1, "Ambiguous deployed source; review each archive separately");
  const archive = path.join(rollback, "archives", `${hashes[0]}.zip`);
  check(sha(fs.readFileSync(archive)) === hashes[0], "Rollback source changed");
  const source = JSON.parse(cp.execFileSync("python", ["-c", [
    "import zipfile,json,sys",
    "with zipfile.ZipFile(sys.argv[1]) as z:",
    " print(json.dumps({n:z.read(n).decode('utf-8') for n in z.namelist() if n.endswith(('.ts','.js','.cjs')) and n.startswith(('src/','lib/','shared/')) or n in ('package.json','package-lock.json')}))",
  ].join("\n"), archive], {encoding: "utf8", maxBuffer: 10000000}));
  const extracted = path.join(rollback, "functions");
  for (const [name, content] of Object.entries(source)) {
    const target = safeTarget(extracted, name);
    fs.mkdirSync(path.dirname(target), {recursive: true}); fs.writeFileSync(target, content);
  }
  const changed = Object.keys(source).filter(n => n.startsWith("src/") &&
    (!fs.existsSync(path.join(root, "functions", n)) || sha(Buffer.from(source[n])) !== sha(fs.readFileSync(path.join(root, "functions", n))))).sort();
  check(JSON.stringify(changed) === JSON.stringify(["src/maintenance/rebuild_financial_ledger.ts", "src/trusted/confirm_sales_return.ts", "src/trusted/financial_ledger_mappings.ts"]), "Functions changes exceed reviewed posting scope");
  const diskFiles = folder => fs.readdirSync(folder, {withFileTypes:true}).flatMap(e => e.isDirectory() ? diskFiles(path.join(folder,e.name)) : [path.join(folder,e.name)]);
  const addedSources = diskFiles(path.join(root,"functions/src")).map(f => path.relative(path.join(root,"functions"),f).replaceAll("\\","/")).filter(f => !Object.hasOwn(source,f));
  check(addedSources.length === 0, "New unreviewed Functions source modules");
  check(source["package-lock.json"] === fs.readFileSync(path.join(root,"functions/package-lock.json"),"utf8"), "Functions dependency lock changed");
  const pkg = read(path.join(root,"functions/package.json")); pkg.main = "lib/staging-entry.cjs";
  const oldPkg = JSON.parse(source["package.json"]);
  check(JSON.stringify(oldPkg.dependencies) === JSON.stringify(pkg.dependencies) && JSON.stringify(oldPkg.engines) === JSON.stringify(pkg.engines) && oldPkg.main === pkg.main, "Runtime dependencies or entry point changed");
  check(sha(Buffer.from(source["lib/staging-entry.cjs"])) === sha(fs.readFileSync(path.join(root,"config/firebase/staging-runtime.cjs"))), "Runtime adapter changed");
  const ts = load("typescript");
  function bodies(text) {
    const ast = ts.createSourceFile("mapping.js", text, ts.ScriptTarget.Latest, true, ts.ScriptKind.JS);
    return Object.fromEntries(ast.statements.filter(ts.isFunctionDeclaration).filter(n => n.name).map(n => [n.name.text,n.getText(ast)]));
  }
  const before = bodies(source["lib/trusted/financial_ledger_mappings.js"]), after = bodies(fs.readFileSync(path.join(root,"functions/lib/trusted/financial_ledger_mappings.js"),"utf8"));
  const mappingChanges = Object.keys(before).filter(k => before[k] !== after[k]);
  check(JSON.stringify(mappingChanges) === '["buildSalesReturnFinancialLedgerEntries"]', "Shared mapper affects another posting path");
  const code = "const f=require(process.argv[1]);process.stdout.write(JSON.stringify(Object.fromEntries(Object.entries(f).map(([k,v])=>[k,v.__endpoint]))));";
  const env = {...process.env, NODE_PATH:path.join(root,"functions/node_modules"), FIREBASE_CONFIG:JSON.stringify({projectId:PROJECT}), GCLOUD_PROJECT:PROJECT, GOOGLE_CLOUD_PROJECT:PROJECT};
  const endpoints = file => JSON.parse(cp.execFileSync(process.execPath,["-e",code,file],{env,encoding:"utf8",maxBuffer:1000000}));
  const oldEndpoints = endpoints(path.join(extracted,"lib/staging-entry.cjs")), newEndpoints = endpoints(path.join(root,"functions/lib/index.js"));
  check(Object.keys(newEndpoints).length === 35 && JSON.stringify(oldEndpoints) === JSON.stringify(newEndpoints), "Exported endpoint metadata changed");
  for (const file of ["src/trusted/settlement_preflight.ts","src/trusted/settlement_journal_intent.ts","src/trusted/record_cash_settlement.ts","src/index.ts"]) {
    check(sha(Buffer.from(source[file])) === sha(fs.readFileSync(path.join(root,"functions",file))), `Accounting boundary changed: ${file}`);
  }
  const result = {status:"PASS_SOURCE_COMPATIBILITY",changedSources:changed,mappingChanges,exportsUnchanged:35,
    runtimeDependenciesUnchanged:true,experimentalAccountingUnchanged:true,maintenanceExecuted:false,
    necessaryFunctionDeployments:["confirmSalesReturn"],unrelatedFunctions:34};
  save(path.join(directory,"evidence/source-comparison.json"),result); console.log(JSON.stringify(result));
}
if (require.main === module) {
  check(process.argv.length === 3 && ["snapshot","snapshot-backend","compare"].includes(process.argv[2]), "Only read-only snapshot or offline compare is supported");
  Promise.resolve().then(() => process.argv[2] === "compare" ? compare() : snapshot(process.argv[2] === "snapshot-backend")).catch(e => {
    console.error(JSON.stringify({status: "BLOCKED", reason: e.message, code: e.code, httpStatus: e.response?.status})); process.exitCode = 1;
  });
}
module.exports = {safeTarget, mapLimit};
