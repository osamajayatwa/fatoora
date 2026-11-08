"use strict";
// Offline artifact preparation/verification only. Deliberately no deploy mode.
const fs = require("node:fs"), path = require("node:path"), cp = require("node:child_process"), crypto = require("node:crypto"), zlib = require("node:zlib");
const root = path.resolve(__dirname, ".."), output = path.join(root, "build/reassignment-release/rc1");
const policyFile = "config/firebase/reassignment-release.review.json";
const sha = value => crypto.createHash("sha256").update(value).digest("hex");
const json = file => JSON.parse(fs.readFileSync(file));
function check(ok, message) { if (!ok) throw Error(message); }
function files(directory) {
  return fs.readdirSync(directory, {withFileTypes: true}).flatMap(entry => {
    const filename = path.join(directory, entry.name); check(!entry.isSymbolicLink(), "Artifact symlink refused");
    return entry.isDirectory() ? files(filename) : [filename];
  });
}
function policy() {
  const p = json(path.join(root, policyFile));
  check(p.projectId === "fatoora-original-staging" && p.projectNumber === "5438538531" && p.region === "us-central1" &&
    p.deployAllowed === false && p.productionAllowed === false && p.historicalWritesAllowed === false &&
    p.accountingImplementationAllowed === false && JSON.stringify(p.scope.functions) === '["confirmSalesReturn"]' &&
    p.scope.firestoreIndexAdditions === 32 && p.scope.existingIndexesRemoved === 0 && p.scope.codebase === p.projectId &&
    p.scope.hostingSite === p.projectId, "Release scope/hold changed");
  return p;
}
function copy(source, destination) {
  fs.mkdirSync(path.dirname(destination), {recursive: true}); fs.copyFileSync(source, destination);
}
function copyTree(source, destination) {
  for (const filename of files(source)) copy(filename, path.join(destination, path.relative(source, filename)));
}
function prepare() {
  const p = policy(), evidence = json(path.join(root, "build/reassignment-release-evidence/live-staging-read.json"));
  check(evidence.project === p.projectId && evidence.projectNumber === p.projectNumber && evidence.readOnly && evidence.documentWrites === 0, "Missing read-only staging baseline");
  check(evidence.indexes.length === 268 && evidence.indexes.every(i => i.state === "READY") &&
    evidence.functions.length === 35 && evidence.functions.every(f => f.state === "ACTIVE"), "Staging baseline drift");
  if (fs.existsSync(output)) {
    check(json(path.join(output, ".candidate-owner.json")).releaseId === p.releaseId &&
      !fs.existsSync(path.join(output, "SHA256SUMS.json")), "Sealed or unknown candidate cannot be overwritten");
  }
  fs.mkdirSync(output, {recursive: true});
  fs.writeFileSync(path.join(output, ".candidate-owner.json"), JSON.stringify({releaseId: p.releaseId, projectId: p.projectId}) + "\n");
  for (const dir of ["src", "lib", "shared"]) copyTree(path.join(root, "functions", dir), path.join(output, "functions", dir));
  const pkg = json(path.join(root, "functions/package.json")); pkg.main = "lib/staging-entry.cjs";
  fs.writeFileSync(path.join(output, "functions/package.json"), JSON.stringify(pkg, null, 2) + "\n");
  copy(path.join(root, "functions/package-lock.json"), path.join(output, "functions/package-lock.json"));
  copy(path.join(root, "config/firebase/staging-runtime.cjs"), path.join(output, "functions/lib/staging-entry.cjs"));
  for (const f of ["firestore.rules", "firestore.indexes.json"]) copy(path.join(root, f), path.join(output, f));
  copy(path.join(root, policyFile), path.join(output, "release-scope.json"));
  for (const platform of ["web", "android"]) {
    const source = path.join(root, `config/firebase/staging.${platform}.json`), cfg = json(source);
    check(cfg.FATOORA_ENV === "staging" && cfg.FIREBASE_PROJECT_ID === p.projectId && cfg.FIREBASE_PROJECT_ID_CONFIRM === p.projectId && cfg.FIREBASE_MESSAGING_SENDER_ID === p.projectNumber, "Staging SDK pairing changed");
    copy(source, path.join(output, `inputs/staging.${platform}.json`));
  }
  for (const dir of ["lib", "assets", "web"]) copyTree(path.join(root, dir), path.join(output, "client-source", dir));
  for (const f of ["pubspec.yaml", "pubspec.lock", "android/app/build.gradle.kts"]) copy(path.join(root, f), path.join(output, "client-source", f));
  copy(path.join(root, "android/app/src/staging/google-services.json"), path.join(output, "inputs/google-services.staging.json"));
  fs.writeFileSync(path.join(output, "firebase.json"), JSON.stringify({
    functions: [{source: "functions", codebase: p.scope.codebase, ignore: ["node_modules", "test", "scripts", ".env*", "*.local"]}],
    firestore: {rules: "firestore.rules", indexes: "firestore.indexes.json"},
    hosting: {site: p.projectId, public: "web", ignore: ["**/.*", "**/node_modules/**"], rewrites: [{source: "**", destination: "/index.html"}]},
  }, null, 2) + "\n");
  const archived = json(path.join(root, "build/staging/source-artifact-verification.json"));
  const archiveHash = archived.artifacts[0].sha256;
  check(archived.project === p.projectId && archived.artifacts.every(a => a.sha256 === archiveHash), "Ambiguous rollback Functions source");
  const archive = path.join(root, `build/staging/deployed-source/runtime-compatible/${archiveHash}.zip`);
  check(sha(fs.readFileSync(archive)) === archiveHash, "Rollback Functions archive hash mismatch");
  check(evidence.functions.every(f => archived.artifacts.some(a => a.object === f.buildConfig.source.storageSource.object &&
    String(a.generation) === String(f.buildConfig.source.storageSource.generation))), "Live Functions no longer match the retained rollback archives");
  copy(archive, path.join(output, "rollback/functions.zip"));
  const rule = evidence.rules.source.files.find(f => f.name === "firestore.rules"); check(rule, "Rollback Rules missing");
  fs.mkdirSync(path.join(output, "rollback"), {recursive: true});
  fs.writeFileSync(path.join(output, "rollback/firestore.rules"), rule.content);
  fs.writeFileSync(path.join(output, "rollback/firestore.indexes.json"), cp.execFileSync("git", ["show", "HEAD:firestore.indexes.json"], {cwd: root}));
  for (const file of evidence.hostingFiles) {
    // Firebase injects these two bootstrap resources. Rollback reuses the pinned
    // immutable Hosting version, which includes them; they are not local assets.
    if (["/__/firebase/init.js", "/__/firebase/init.json"].includes(file.path)) continue;
    const filename = path.resolve(root, "build/staging/web", file.path.replace(/^\//, ""));
    check(filename.startsWith(path.join(root, "build/staging/web") + path.sep), "Unsafe Hosting rollback path");
    // Hosting API hashes the CLI's gzip-9 upload bytes, not the decoded asset.
    check(sha(zlib.gzipSync(fs.readFileSync(filename), {level: 9})) === file.hash, `Rollback Hosting byte mismatch: ${file.path}`);
    copy(filename, path.join(output, "rollback/web", file.path.replace(/^\//, "")));
  }
  const oldApk = path.join(root, "build/app/outputs/flutter-apk/app-staging-debug.apk");
  check(sha(fs.readFileSync(oldApk)) === "79b86cfdc945ac8f89a188b30d00a660082fc03fe3bf91cfc45a8927f5c3ad87", "Rollback APK changed");
  copy(oldApk, path.join(output, "rollback/app-staging-debug.apk"));
  copy(path.join(root, "build/reassignment-release-evidence/live-staging-read.json"), path.join(output, "rollback/live-baseline.json"));
  const sourceHashes = Object.fromEntries([...files(path.join(root, "functions/src")), ...files(path.join(root, "functions/shared")),
    ...files(path.join(root, "lib")), ...files(path.join(root, "assets")), ...files(path.join(root, "web")),
    ...["firestore.rules", "firestore.indexes.json", "functions/package.json", "functions/package-lock.json", "pubspec.yaml", "pubspec.lock", "android/app/build.gradle.kts", "config/firebase/staging-runtime.cjs", "config/firebase/staging.android.json", "config/firebase/staging.web.json", "android/app/src/staging/google-services.json", policyFile].map(f => path.join(root, f))]
    .map(f => [path.relative(root, f).replaceAll("\\", "/"), sha(fs.readFileSync(f))]));
  fs.writeFileSync(path.join(output, "source-inputs.json"), JSON.stringify(sourceHashes, null, 2) + "\n");
  return {status: "PREPARED_NOT_DEPLOYABLE", candidate: output, project: p.projectId};
}
function seal() {
  const p = policy();
  check(json(path.join(output, ".candidate-owner.json")).releaseId === p.releaseId, "Unknown candidate ownership");
  check(!fs.existsSync(path.join(output, "SHA256SUMS.json")), "Candidate is already sealed");
  check(fs.existsSync(path.join(output, "web/main.dart.js")) && fs.existsSync(path.join(output, "android/app-staging-debug.apk")), "Client builds incomplete");
  for (const [file, hash] of Object.entries(json(path.join(output, "source-inputs.json")))) {
    check(sha(fs.readFileSync(path.join(root, file))) === hash, `Source changed during build: ${file}`);
  }
  copyTree(path.join(root, "build/reassignment-release-evidence"), path.join(output, "evidence"));
  const sums = Object.fromEntries(files(output).map(f => [path.relative(output, f).replaceAll("\\", "/"), sha(fs.readFileSync(f))]));
  fs.writeFileSync(path.join(output, "SHA256SUMS.json"), JSON.stringify(sums, null, 2) + "\n");
  return verify();
}
function verify() {
  const p = policy(), sums = json(path.join(output, "SHA256SUMS.json"));
  for (const [file, hash] of Object.entries(sums)) {
    const target = path.resolve(output, file); check(target.startsWith(output + path.sep), "Artifact traversal refused");
    check(sha(fs.readFileSync(target)) === hash, `Frozen artifact changed: ${file}`);
  }
  check(files(output).length === Object.keys(sums).length + 1, "Unreviewed artifact added");
  check(sha(fs.readFileSync(path.join(output, "release-scope.json"))) === sha(fs.readFileSync(path.join(root, policyFile))), "Review policy changed");
  return {status: "PASS_LOCAL_CANDIDATE", deployAllowed: false, project: p.projectId, candidate: output, files: Object.keys(sums).length,
    manifestSha256: sha(fs.readFileSync(path.join(output, "SHA256SUMS.json")))};
}
if (require.main === module) {
  try {
    check(process.argv.length === 3 && ["prepare", "seal", "verify"].includes(process.argv[2]), "Only offline prepare/seal/verify actions exist");
    console.log(JSON.stringify(({prepare, seal, verify})[process.argv[2]]()));
  } catch (error) { console.error(JSON.stringify({status: "BLOCKED", reason: error.message})); process.exitCode = 1; }
}
module.exports = {policy, expectedOutput: output, prepare, seal, verify};
