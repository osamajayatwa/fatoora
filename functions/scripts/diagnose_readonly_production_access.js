"use strict";

// No credential values, record bodies, writes, configuration changes or exports.
// Authentication is handled exclusively by the installed Google SDK and its
// existing Application Default Credentials. This does not import CLI tokens.
const dns = require("node:dns").promises;
const https = require("node:https");
const http2 = require("node:http2");

const PROJECT = "fatoora-6b192";
const TIMEOUT_MS = 8000;

function safeFailure(error) {
  const codes = [];
  for (let current = error, depth = 0; current && depth < 6; current = current.cause, depth++) {
    if (typeof current.code === "string" || typeof current.code === "number") codes.push(current.code);
  }
  let failingHost = null;
  try {failingHost = new URL(error.config?.url || error.cause?.config?.url || "").hostname;} catch {}
  return {codes, httpStatus: error.response?.status || null, failingHost};
}

function httpsProbe(host) {
  return new Promise((resolve) => {
    const start = Date.now();
    const request = https.get({hostname: host, path: "/", timeout: TIMEOUT_MS, agent: false}, (response) => {
      response.resume();
      resolve({host, probe: "HTTPS", httpStatus: response.statusCode, milliseconds: Date.now() - start});
    });
    request.on("timeout", () => request.destroy(Object.assign(new Error("timeout"), {code: "TIMEOUT"})));
    request.on("error", (error) => resolve({host, probe: "HTTPS", code: error.code || "ERROR", milliseconds: Date.now() - start}));
  });
}

function http2Probe() {
  return new Promise((resolve) => {
    const start = Date.now();
    const client = http2.connect("https://firestore.googleapis.com");
    const timer = setTimeout(() => {
      client.destroy();
      resolve({probe: "HTTP2", code: "TIMEOUT", milliseconds: Date.now() - start});
    }, TIMEOUT_MS);
    client.on("connect", () => {
      clearTimeout(timer); client.close();
      resolve({probe: "HTTP2", status: "CONNECTED", milliseconds: Date.now() - start});
    });
    client.on("error", (error) => {
      clearTimeout(timer); client.destroy();
      resolve({probe: "HTTP2", code: error.code || "ERROR", milliseconds: Date.now() - start});
    });
  });
}

async function diagnose(probeRead) {
  const result = {project: PROJECT, readOnly: true, network: [], authentication: null,
    query: {status: "NOT_REQUESTED", recordsRetrieved: 0}, writesPerformed: false};
  for (const host of ["firestore.googleapis.com", "oauth2.googleapis.com"]) {
    try {
      const addresses = await dns.lookup(host, {all: true});
      result.network.push({host, probe: "DNS", status: "RESOLVED", addressCount: addresses.length});
    } catch (error) {result.network.push({host, probe: "DNS", code: error.code || "ERROR"});}
  }
  result.network.push(...await Promise.all([httpsProbe("firestore.googleapis.com"), httpsProbe("oauth2.googleapis.com"), http2Probe()]));

  const {GoogleAuth} = require("google-auth-library");
  let timer;
  let client;
  try {
    const auth = new GoogleAuth({projectId: PROJECT, scopes: ["https://www.googleapis.com/auth/datastore"]});
    client = await Promise.race([auth.getClient(), new Promise((_, reject) => {
      timer = setTimeout(() => reject({code: "AUTH_DISCOVERY_TIMEOUT"}), TIMEOUT_MS);
    })]);
    result.authentication = {status: "CLIENT_FOUND", clientType: client.constructor.name,
      tokenValidity: "UNVERIFIED", credentialContentsExposed: false};
  } catch (error) {
    result.authentication = {status: "FAILED", ...safeFailure(error), credentialContentsExposed: false};
  } finally {clearTimeout(timer);}

  // No additional request if local network probes are already access-denied.
  if (probeRead && result.network.some((probe) => ["EACCES", "EPERM"].includes(probe.code))) {
    result.query.status = "BLOCKED_LOCAL_NETWORK_ACCESS_DENIED";
  } else if (probeRead && client?.constructor.name === "UserRefreshClient") {
    try {
      const response = await client.request({
        url: `https://firestore.googleapis.com/v1/projects/${PROJECT}/databases/(default)/documents:runQuery`,
        method: "POST", timeout: TIMEOUT_MS, retry: false,
        data: {structuredQuery: {
          from: [{collectionId: "users"}],
          select: {fields: [{fieldPath: "uid"}, {fieldPath: "role"}, {fieldPath: "companyId"}]},
          where: {fieldFilter: {field: {fieldPath: "name"}, op: "EQUAL", value: {stringValue: "Jihad"}}},
          limit: 1,
        }},
      });
      result.query = {status: "API_RESPONSE", httpStatus: response.status,
        recordsRetrieved: Array.isArray(response.data) ? response.data.filter((row) => row.document).length : 0,
        recordContentsLogged: false};
      result.authentication.tokenValidity = "REQUEST_AUTHENTICATED";
    } catch (error) {result.query = {status: "FAILED", ...safeFailure(error), recordsRetrieved: 0};}
  } else if (probeRead) {
    result.query.status = "BLOCKED_NO_EXISTING_USER_ADC_CLIENT";
  }
  return result;
}

async function main() {
  const arguments_ = process.argv.slice(2);
  if (arguments_.includes("--help")) {
    process.stdout.write("Usage: node scripts/diagnose_readonly_production_access.js --project=fatoora-6b192 [--probe-read]\n" +
      "Uses existing user ADC; --probe-read permits one read-only profile query (limit 1). Prints status/counts only.\n");
    return;
  }
  if (!arguments_.includes(`--project=${PROJECT}`) ||
    arguments_.some((argument) => ![`--project=${PROJECT}`, "--probe-read"].includes(argument))) {
    throw Object.assign(new Error("Explicit approved project argument required; no other options accepted."), {code: "INVALID_ARGUMENTS"});
  }
  if (process.env.FIRESTORE_EMULATOR_HOST || process.env.GOOGLE_APPLICATION_CREDENTIALS) {
    throw Object.assign(new Error("Unexpected emulator or explicit credential override; no connection attempted."), {code: "UNEXPECTED_CONTEXT"});
  }
  const result = await diagnose(arguments_.includes("--probe-read"));
  process.stdout.write(JSON.stringify(result, null, 2) + "\n");
  if (arguments_.includes("--probe-read") && result.query.status !== "API_RESPONSE") process.exitCode = 2;
}

if (require.main === module) {
  main().catch((error) => {
    process.stdout.write(JSON.stringify({status: "BLOCKED", ...safeFailure(error), recordsRetrieved: 0}) + "\n");
    process.exitCode = 2;
  });
}

module.exports = {diagnose};
