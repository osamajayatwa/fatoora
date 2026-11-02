"use strict";
const {readdirSync} = require("node:fs");
const {join} = require("node:path");
const {spawnSync} = require("node:child_process");

(async () => {
  const host = process.env.FIRESTORE_EMULATOR_HOST || "";
  if (!/^127\.0\.0\.1:\d+$/.test(host)) throw new Error("Use a dedicated loopback Firestore emulator.");
  // Only synthetic projects used by this repository's tests, on loopback.
  for (const project of ["fatoora-phase3-receipts-test", "fatoora-return-auth-test", "fatoora-rules-test",
    "fatoora-phase4-assignment-test", "fatoora-phase1-test", "fatoora-phase2-search-test", "fatoora-trusted-test",
    "demo-fatoora-integrity-regression"]) {
    const response = await fetch(`http://${host}/emulator/v1/projects/${project}/databases/(default)/documents`, {method: "DELETE"});
    if (!response.ok) throw new Error(`Cannot reset synthetic emulator project ${project}`);
  }
  const files = readdirSync(join(__dirname, "..", "test")).filter((file) => file.endsWith(".test.js"))
    .sort().map((file) => join(__dirname, "..", "test", file));
  const result = spawnSync(process.execPath, ["--test", "--test-concurrency=1", ...files], {stdio: "inherit"});
  if (result.error) throw result.error;
  process.exitCode = result.status ?? 1;
})().catch((error) => {process.stderr.write(error.message + "\n"); process.exitCode = 1;});
