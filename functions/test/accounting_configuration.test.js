const {test,after} = require("node:test");
const assert = require("node:assert/strict");
const {randomUUID} = require("node:crypto");
const {readFileSync} = require("node:fs");
const {join} = require("node:path");
if (!/^127\.0\.0\.1:\d+$/.test(process.env.FIRESTORE_EMULATOR_HOST || "")) throw new Error("Accounting configuration tests require a loopback emulator.");
const {initializeApp,deleteApp} = require("firebase-admin/app");
const {getFirestore} = require("firebase-admin/firestore");
const {accountingConfigurationTransaction: command,manageAccountingConfiguration: callable} = require("../lib/trusted/accounting_configuration");
const app = initializeApp({projectId:"demo-fatoora-phase2c"},"accounting-configuration-test"), db = getFirestore(app);
after(()=>deleteApp(app));
const fixtureData = () => JSON.parse(readFileSync(join(__dirname,"../../test/fixtures/accounting_configuration.json"),"utf8"));
async function fixture() {
  const companyId = `config-${randomUUID()}`, uid = `${companyId}-admin`, bookId = "draft-book", b = `companies/${companyId}/books/${bookId}`;
  await db.doc(`users/${uid}`).set({uid,companyId,role:"admin",active:true,approvalStatus:"approved"});
  await db.doc(`companies/${companyId}`).set({id:companyId,active:true});
  const input = {action:"save",companyId,bookId,expectedRevision:0,requestId:"request-1",configuration:fixtureData()};
  return {companyId,uid,bookId,b,input,save:(overrides={},actor=uid,database=db)=>command(database,actor,{...input,...overrides}),read:()=>command(db,uid,{action:"read",companyId,bookId})};
}
test("draft save atomically versions configuration, accounts, codes, periods, policies and audit without money",async()=>{
  const f=await fixture(), r=await f.save();assert.equal(r.revision,1);assert.equal(r.readiness.postingEnabled,false);
  const book=(await db.doc(f.b).get()).data();assert.equal(book.active,false);assert.equal(book.journalPostingEnabled,false);assert.equal(book.approvalStatus,"unreviewed");
  const company=(await db.doc(`companies/${f.companyId}`).get()).data();assert.equal(company.activeBookId,undefined);
  const paths=[f.b,`${f.b}/configuration_revisions/revision_1`,`${f.b}/policy_revisions/revision_1`,`${f.b}/account_mappings/revision_1`,`${f.b}/chart_accounts/company-cash`,`${f.b}/periods/nov-2026`,`${f.b}/audit_events/configuration_revision_1`];
  const snapshots=await db.getAll(...paths.map(p=>db.doc(p)));assert(snapshots.every(s=>s.exists));assert(snapshots.every(s=>s.updateTime.isEqual(snapshots[0].updateTime)));
  assert.deepEqual(await f.read(),r);
  for(const name of ["journal_entries","events","posting_lanes","open_items"]) assert.equal((await db.collection(`${f.b}/${name}`).get()).size,0);
  for(const name of ["cash_movements","cash_balances","stock_movements","settlements"]) assert.equal((await db.collection(`companies/${f.companyId}/${name}`).get()).size,0);
});
test("identical retry returns original revision with no duplicate audit",async()=>{
  const f=await fixture(), a=await f.save();assert.deepEqual(await f.save(),a);assert.equal((await db.collection(`${f.b}/audit_events`).get()).size,1);
  const c=fixtureData();c.name="Second revision";await f.save({expectedRevision:1,requestId:"request-2",configuration:c});assert.deepEqual(await f.save(),a);
});
test("reused request with different payload conflicts",async()=>{const f=await fixture();await f.save();const c=fixtureData();c.name="Changed";await assert.rejects(f.save({configuration:c}),e=>e.code==="already-exists");});
test("concurrent different saves against one revision have one winner",async()=>{
  const f=await fixture();const results=await Promise.allSettled([f.save(),f.save({requestId:"request-other"})]);
  assert.equal(results.filter(r=>r.status==="fulfilled").length,1);assert.equal(results.find(r=>r.status==="rejected").reason.code,"aborted");assert.equal((await f.read()).revision,1);
});
for(const [name,patch] of [["rep",{role:"sales_rep"}],["inactive",{active:false}],["pending",{approvalStatus:"pending"}],["foreign",{companyId:"other"}]]) test(`denies ${name} on read and save`,async()=>{
  const f=await fixture();await db.doc(`users/${f.uid}`).update(patch);
  await assert.rejects(f.save(),e=>e.code==="permission-denied");await assert.rejects(f.read(),e=>e.code==="permission-denied");assert.equal((await db.doc(f.b).get()).exists,false);
});
test("anonymous command is denied",async()=>{const f=await fixture();await assert.rejects(f.save({},null),e=>e.code==="unauthenticated");});
test("revoked administrator cannot replay successful request",async()=>{const f=await fixture();await f.save();await db.doc(`users/${f.uid}`).update({active:false});await assert.rejects(f.save(),e=>e.code==="permission-denied");});
for(const patch of [{active:true},{mode:"live"},{journalPostingEnabled:true},{settlementPreflightEnabled:true},{configurationLocked:true}]) test(`rejects editing enabled book ${JSON.stringify(patch)}`,async()=>{
  const f=await fixture();await f.save();await db.doc(f.b).update(patch);await assert.rejects(f.save({expectedRevision:1,requestId:"request-2"}),e=>e.code==="failed-precondition");
});
test("selected active book is protected",async()=>{const f=await fixture();await f.save();await db.doc(`companies/${f.companyId}`).update({activeBookId:f.bookId});await assert.rejects(f.save({expectedRevision:1,requestId:"request-2"}),e=>e.code==="failed-precondition");});
test("used accounts are protected",async()=>{const f=await fixture();await f.save();await db.doc(`${f.b}/chart_accounts/company-cash`).update({used:true});await assert.rejects(f.save({expectedRevision:1,requestId:"request-2"}),e=>e.code==="failed-precondition");});
test("reserved account code cannot move to a different identity",async()=>{
  const f=await fixture();await f.save();const c=fixtureData();c.accounts[1].code="1190";c.accounts.push({...c.accounts[1],id:"new-cash",code:"1100"});
  await assert.rejects(f.save({expectedRevision:1,requestId:"request-2",configuration:c}),e=>e.code==="already-exists");assert.equal((await f.read()).revision,1);
});
test("corrupted immutable configuration is detected",async()=>{const f=await fixture();await f.save();await db.doc(`${f.b}/configuration_revisions/revision_1`).update({"configuration.currency":"USD"});await assert.rejects(f.read(),e=>e.code==="data-loss");});
test("lost response retries the exact persisted identity",async()=>{
  const f=await fixture();let first=true;const wrapped=new Proxy(db,{get(target,name){if(name==="runTransaction")return async callback=>{const result=await target.runTransaction(callback);if(first){first=false;throw new Error("lost response");}return result;};const v=Reflect.get(target,name,target);return typeof v==="function"?v.bind(target):v;}});
  await assert.rejects(f.save({},f.uid,wrapped),/lost response/);assert.equal((await f.save()).revision,1);assert.equal((await db.collection(`${f.b}/audit_events`).get()).size,1);
});
test("SDK composition performs all reads before every write",async()=>{
  const f=await fixture();let writes=false;const wrapped=new Proxy(db,{get(target,name){if(name==="runTransaction")return callback=>target.runTransaction(tx=>callback(new Proxy(tx,{get(t,k){const v=Reflect.get(t,k,t);if(["get","getAll"].includes(k))return(...args)=>{assert.equal(writes,false);return v.apply(t,args);};if(["set","create","update","delete"].includes(k))return(...args)=>{writes=true;return v.apply(t,args);};return typeof v==="function"?v.bind(t):v;}})));const v=Reflect.get(target,name,target);return typeof v==="function"?v.bind(target):v;}});
  await f.save({},f.uid,wrapped);assert.equal(writes,true);
});
test("callable is unavailable by default before any database access",async()=>{
  const previous=process.env.FATOORA_ACCOUNTING_CONFIGURATION_ENABLED;
  delete process.env.FATOORA_ACCOUNTING_CONFIGURATION_ENABLED;
  try {await assert.rejects(callable.run({auth:{uid:"synthetic-admin"},data:{}}),e=>e.code==="failed-precondition");}
  finally {if(previous===undefined)delete process.env.FATOORA_ACCOUNTING_CONFIGURATION_ENABLED;else process.env.FATOORA_ACCOUNTING_CONFIGURATION_ENABLED=previous;}
});
test("concurrent identical requests commit one revision and return the same result",async()=>{
  const f=await fixture(), results=await Promise.all([f.save(),f.save()]);assert.deepEqual(results[0],results[1]);
  assert.equal((await db.collection(`${f.b}/audit_events`).get()).size,1);
});
test("exception during queued writes leaves no partial configuration",async()=>{
  const f=await fixture();const wrapped=new Proxy(db,{get(target,name){
    if(name==="runTransaction")return callback=>target.runTransaction(tx=>callback(new Proxy(tx,{get(t,k){
      if(k==="create")return(ref,...args)=>{if(ref.path.includes("/policy_revisions/"))throw new Error("synthetic interrupted commit");return t.create(ref,...args);};
      const v=Reflect.get(t,k,t);return typeof v==="function"?v.bind(t):v;
    }})));const v=Reflect.get(target,name,target);return typeof v==="function"?v.bind(target):v;
  }});
  await assert.rejects(f.save({},f.uid,wrapped),/synthetic interrupted commit/);
  assert.equal((await db.doc(f.b).get()).exists,false);
  assert.equal((await db.collection(`${f.b}/configuration_revisions`).get()).size,0);
  assert.equal((await db.collection(`${f.b}/chart_accounts`).get()).size,0);
});
test("maintenance lock and unrelated existing book cannot be overwritten",async()=>{
  const f=await fixture();await db.doc(`companies/${f.companyId}/maintenance_locks/accounting_configuration`).set({active:true});
  await assert.rejects(f.save(),e=>e.code==="failed-precondition");
  await db.doc(`companies/${f.companyId}/maintenance_locks/accounting_configuration`).update({active:false});
  await db.doc(f.b).set({companyId:f.companyId,bookId:f.bookId,id:f.bookId,mode:"live"});
  await assert.rejects(f.save(),e=>e.code==="failed-precondition");
});
test("existing account identities are retained through draft edits",async()=>{
  const f=await fixture();await f.save();const c=fixtureData();c.accounts=c.accounts.filter(a=>a.id!=="equity");
  await assert.rejects(f.save({configuration:c,expectedRevision:1,requestId:"request-2"}),e=>e.code==="failed-precondition");
});
