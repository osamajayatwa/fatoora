"use strict";
// Emulator-only RPC accounting. Counts returned documents and empty-query minimums,
// not a cloud invoice; aggregate index scans are reported separately.
const {AsyncLocalStorage} = require("node:async_hooks");
const context = new AsyncLocalStorage();
const {profileSettlementRead} = require("../../lib/trusted/settlement_read_profile");
function profiledDatabase(db) {
  const record = async (kind, run) => {
    const at = performance.now();let value;
    try {value = await run();return value;} finally {
      const m = context.getStore();
      if (m) {
        m.rpcMillis += performance.now() - at;m[kind]++;
        const docs = Array.isArray(value) ? value : value?.docs ?? (value?.ref ? [value] : []);
        m.documentReads += docs.length;
        m.minimumDocumentReadUnits += Math.max(docs.length, kind === "aggregateQueries" ? 0 : 1);
        if (kind === "aggregateQueries" && value) {const count = value.data().count;m.aggregateEntries += count;m.aggregateReadUnits += Math.max(1, Math.ceil(count / 1000));}
        const serial = performance.now();
        for (const d of docs) m.returnedDataBytes += Buffer.byteLength(JSON.stringify(d.data() ?? null));
        m.profilingSerializationMillis += performance.now() - serial;
      }
    }
  };
  return new Proxy(db, {get(target, p) {
    if (p === "runTransaction") return (callback, options) => target.runTransaction(raw => {
      const m = context.getStore();if (m) m.transactions++;
      return callback(new Proxy(raw, {get(tx, prop) {
        if (prop === "get") return q => record(q.path ? "documentGets" : q.query ? "aggregateQueries" : "queries", () => tx.get(q));
        if (prop === "getAll") return (...refs) => record("getAllCalls", () => tx.getAll(...refs));
        const value = Reflect.get(tx, prop, tx);return typeof value === "function" ? value.bind(tx) : value;
      }}));
    }, options);
    const value = Reflect.get(target, p, target);return typeof value === "function" ? value.bind(target) : value;
  }});
}
async function measure(run) {
  const m = {transactions: 0, documentGets: 0, getAllCalls: 0, queries: 0, aggregateQueries: 0, documentReads: 0,
    minimumDocumentReadUnits: 0, aggregateEntries: 0, aggregateReadUnits: 0, returnedDataBytes: 0, rpcMillis: 0, profilingSerializationMillis: 0};
  const at = performance.now(), cpu = process.cpuUsage();
  const observed = await context.run(m, () => profileSettlementRead(run)), result = observed.result;const serialize = performance.now();m.stages = observed.stages;
  m.responseBytes = Buffer.byteLength(JSON.stringify(result));m.responseSerializationMillis = performance.now() - serialize;
  m.millis = performance.now() - at;const used = process.cpuUsage(cpu);m.cpuMillis = (used.user + used.system) / 1000;
  const memory = process.memoryUsage();m.heapUsedBytes = memory.heapUsed;m.rssBytes = memory.rss;
  return {result, metrics: m};
}
module.exports = {profiledDatabase, measure};
