"use strict";
// Local synthetic emulator harness only. Never starts services or deploys.
const fs = require("node:fs"), path = require("node:path"), crypto = require("node:crypto");
const root = path.resolve(__dirname, "../../.."), target = path.join(root, "build/phase2b12-functions");
fs.mkdirSync(target, {recursive: true});
const built = path.join(root, "functions/lib/trusted/settlement_transport.js");
if (!fs.existsSync(built)) throw new Error("Build functions before preparing the emulator.");
fs.writeFileSync(path.join(target, "package.json"), JSON.stringify({name: "phase2b12-emulator-only", private: true, main: "index.js", engines: {node: "22"},
  dependencies: {"firebase-admin": "^12.7.0", "firebase-functions": "^5.1.1"}}, null, 2));
fs.writeFileSync(path.join(target, "index.js"), 'require("firebase-admin/app").initializeApp();\nexports.getSettlementBreakdown = require("../../functions/lib/trusted/settlement_transport").getSettlementBreakdown;\n' +
  `// Transport build: ${crypto.createHash("sha256").update(fs.readFileSync(built)).digest("hex")}\n`);
const modules = path.join(target, "node_modules");
if (!fs.existsSync(modules)) fs.symlinkSync(path.join(root, "functions/node_modules"), modules, process.platform === "win32" ? "junction" : "dir");
fs.copyFileSync(path.join(root, "firestore.rules"), path.join(root, "build/phase2b12-firestore.rules"));
fs.copyFileSync(path.join(root, "firestore.indexes.json"), path.join(root, "build/phase2b12-firestore.indexes.json"));
fs.writeFileSync(path.join(root, "build/phase2b12-emulators.json"), JSON.stringify({functions: [{source: "phase2b12-functions", codebase: "default"}],
  firestore: {rules: "phase2b12-firestore.rules", indexes: "phase2b12-firestore.indexes.json"}, emulators: {
    auth: {host: "127.0.0.1", port: 9098}, firestore: {host: "127.0.0.1", port: 8192}, functions: {host: "127.0.0.1", port: 5005},
    hub: {host: "127.0.0.1", port: 4405}, logging: {host: "127.0.0.1", port: 4505}, ui: {enabled: false}, singleProjectMode: true}}, null, 2));
console.log("Prepared callable-only demo emulator configuration: build/phase2b12-emulators.json");
