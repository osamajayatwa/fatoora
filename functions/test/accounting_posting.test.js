const {test,after}=require("node:test");
const assert=require("node:assert/strict");
if(!/^127\.0\.0\.1:\d+$/.test(process.env.FIRESTORE_EMULATOR_HOST||""))throw new Error("Foundation posting tests require a dedicated loopback emulator.");
const {initializeApp,deleteApp}=require("firebase-admin/app");
const {getFirestore,Firestore}=require("firebase-admin/firestore");
const {accountingFoundationFixture}=require("./helpers/accounting_foundation_fixture");
const {assertAccountingEmulator}=require("../lib/trusted/accounting_transaction");
const app=initializeApp({projectId:"demo-fatoora-phase2d"},"foundation-engine-tests"),db=getFirestore(app);
const callableApp=initializeApp({projectId:"demo-fatoora-phase2d"});
after(async()=>{await deleteApp(app);await deleteApp(callableApp);});
const fixture=()=>accountingFoundationFixture(db);
const code=expected=>error=>{assert.equal(error.code,expected,error.stack);return true;};
const sourcePath=f=>`${f.root}/settlements/settlement_${f.input.operationId}`;
async function journalCount(f){return(await db.collection(`${f.b}/journal_entries`).get()).size;}
async function unchanged(f){assert.equal(await journalCount(f),0);assert.equal((await db.doc(`${f.root}/cash_balances/rep_${f.rep}`).get()).data().amountUnits,"100000");assert.equal((await db.doc(sourcePath(f)).get()).exists,false);}
function proxyDb(run){return new Proxy(db,{get(target,key){if(key==="runTransaction")return callback=>run(callback);const v=Reflect.get(target,key,target);return typeof v==="function"?v.bind(target):v;}});}
function proxyTx(tx,overrides){return new Proxy(tx,{get(target,key){const v=overrides[key]||Reflect.get(target,key,target);return typeof v==="function"?v.bind(target):v;}});}

test("settlement commits one balanced exact journal with cash, source, audit, outbox and lane together",async()=>{
 const f=await fixture(), r=await f.post();assert.equal(r.alreadyPosted,false);assert.equal(r.result.sourceId,"settlement_operation-first");assert(r.committedAt.seconds>0);
 const event=await db.doc(`${f.b}/events/${r.result.eventId}`).get(),entry=await db.doc(`${f.b}/journal_entries/${r.result.journalId}`).get();
 const journal=entry.data().journal;assert.equal(journal.lines.length,2);assert.equal(journal.debitUnits,"1234");assert.equal(journal.creditUnits,"1234");assert.equal(journal.accountingDate,"2026-11-10");
 const rep=(await db.doc(`${f.root}/cash_balances/rep_${f.rep}`).get()).data(),company=(await db.doc(`${f.root}/cash_balances/company_cash`).get()).data();
 assert.equal(rep.amountUnits,"98766");assert.equal(company.amountUnits,"21234");assert.equal(BigInt(rep.amountUnits)+BigInt(company.amountUnits),120000n);assert.equal(rep.accountSequence,2);
 const effects=event.data().effects.filter(e=>e.immutable);assert.equal(effects.length,4);
 for(const p of[`${f.b}/source_keys/${r.result.eventId}`,`${f.b}/audit_events/${r.result.eventId}`,`${f.b}/outbox/${r.result.eventId}`,...effects.map(e=>e.path)]){
  const s=await db.doc(p).get();assert(s.exists,p);assert(s.createTime.isEqual(event.createTime),p);assert(s.updateTime.isEqual(event.createTime),p);
 }
 assert(entry.createTime.isEqual(event.createTime));assert.equal((await db.doc(f.b).get()).data().journalPostingEnabled,false);
 assert.equal((await db.doc(`companies/${f.companyId}`).get()).data().activeBookId,undefined);
});
test("same request and economic action retry return one original journal and observed commit",async()=>{
 const f=await fixture(), a=await f.post(),b=await f.post();assert.equal(b.alreadyPosted,true);assert.deepEqual(a.result,b.result);assert.deepEqual(a.committedAt,b.committedAt);assert.equal(await journalCount(f),1);
});
test("different request key aliases the same economic action without another cash effect",async()=>{
 const f=await fixture(),a=await f.post(),b=await f.post({idempotencyKey:"request-alias"});assert.deepEqual(a.result,b.result);assert.equal(b.alreadyPosted,true);assert.equal(await journalCount(f),1);
 assert.equal((await db.collection(`${f.b}/request_keys`).get()).size,2);assert.equal((await db.doc(`${f.root}/cash_balances/company_cash`).get()).data().amountUnits,"21234");
});
test("two genuine identical settlements retain distinct business identities",async()=>{
 const f=await fixture(),a=await f.post(),b=await f.post({idempotencyKey:"request-second",operationId:"operation-second"});assert.notEqual(a.result.eventId,b.result.eventId);assert.equal(await journalCount(f),2);
 assert.equal((await db.doc(`${f.root}/cash_balances/company_cash`).get()).data().amountUnits,"22468");
});
for(const change of[{amount:"2.000"},{notes:"Conflicting meaning"},{salesRepId:"another-rep"},{expectedConfigurationDigest:"b".repeat(64)}])test(`economic identity rejects changed intent ${JSON.stringify(change)}`,async()=>{
 const f=await fixture();await f.post();await assert.rejects(f.post({...change,idempotencyKey:"request-other"}),code("already-exists"));assert.equal(await journalCount(f),1);
});
test("request key cannot be reused for another genuine action",async()=>{const f=await fixture();await f.post();await assert.rejects(f.post({operationId:"other-operation"}),code("already-exists"));assert.equal(await journalCount(f),1);});
test("concurrent identical submissions have exactly one journal and cash pair",async()=>{
 const f=await fixture(),r=await Promise.all([f.post(),f.post()]);assert.deepEqual(r[0].result,r[1].result);assert.equal(await journalCount(f),1);
});
test("concurrent request aliases cannot duplicate the same settlement",async()=>{
 const f=await fixture(),r=await Promise.all([f.post(),f.post({idempotencyKey:"parallel-alias"})]);assert.deepEqual(r[0].result,r[1].result);assert.equal(await journalCount(f),1);
});
test("competing outflows serialize on exact cash availability",async()=>{
 const f=await fixture(),r=await Promise.allSettled([f.post({amount:"80.000"}),f.post({amount:"80.000",operationId:"second-outflow",idempotencyKey:"request-second"})]);
 assert.equal(r.filter(x=>x.status==="fulfilled").length,1);assert.equal(await journalCount(f),1);assert.equal((await db.doc(`${f.root}/cash_balances/rep_${f.rep}`).get()).data().amountUnits,"20000");
});
test("lost acknowledgement recovers the committed result without another write",async()=>{
 const f=await fixture();let lose=true;const wrapped=proxyDb(async callback=>{const result=await db.runTransaction(callback);if(lose){lose=false;throw new Error("synthetic lost acknowledgement");}return result;});
 await assert.rejects(f.post({},f.admin,wrapped),/lost acknowledgement/);const retry=await f.post();assert.equal(retry.alreadyPosted,true);assert.equal(await journalCount(f),1);
});
test("SDK callback retry rebuilds plans while keeping stable action IDs",async()=>{
 const f=await fixture();let interrupt=true,attempts=0;
 const wrapped=proxyDb(callback=>db.runTransaction(async tx=>{attempts++;const result=await callback(tx);if(interrupt){interrupt=false;throw Object.assign(new Error("synthetic contention"),{code:10});}return result;}));
 await f.post({},f.admin,wrapped);assert(attempts>=3);assert.equal(await journalCount(f),1);
});
test("failure after queued cash writes aborts every journal and domain effect",async()=>{
 const f=await fixture(),wrapped=proxyDb(callback=>db.runTransaction(tx=>callback(proxyTx(tx,{create(ref,data){if(ref.path.includes("/events/"))throw new Error("synthetic mid-commit interruption");return tx.create(ref,data);}}))));
 await assert.rejects(f.post({},f.admin,wrapped),/mid-commit/);await unchanged(f);assert.equal((await db.collection(`${f.b}/events`).get()).size,0);
});
test("recovery is read-only and absent sources never enter posting",async()=>{
 const f=await fixture();await assert.rejects(f.recover(),code("failed-precondition"));await unchanged(f);
});
test("closed periods, inactive old accounts and later cash changes do not invalidate an authorized replay",async()=>{
 const f=await fixture(),a=await f.post();await db.doc(`${f.b}/periods/nov-2026`).update({status:"closed"});await db.doc(`${f.b}/chart_accounts/company-cash`).update({active:false});
 await db.doc(`${f.root}/cash_balances/company_cash`).update({amount:999,amountUnits:"999000"});await db.doc(`users/${f.rep}`).update({active:false});
 const b=await f.post();assert.deepEqual(a.result,b.result);assert.equal(await journalCount(f),1);
});
for(const patch of[{role:"sales_rep"},{active:false},{approvalStatus:"pending"},{companyId:"foreign-company"}])test(`current authorization rejects ${JSON.stringify(patch)}`,async()=>{
 const f=await fixture();await db.doc(`users/${f.admin}`).update(patch);await assert.rejects(f.post(),code("permission-denied"));await unchanged(f);
});
test("revoked authority cannot recover or replay a committed result",async()=>{const f=await fixture();await f.post();await db.doc(`users/${f.admin}`).update({active:false});await assert.rejects(f.post(),code("permission-denied"));await assert.rejects(f.recover(),code("permission-denied"));});
test("another current administrator can recover the original actor's posting",async()=>{
 const f=await fixture(),original=await f.post(),viewer=`${f.companyId}-viewer`;
 await db.doc(`users/${viewer}`).set({uid:viewer,companyId:f.companyId,role:"admin",name:"Current administrator",active:true,approvalStatus:"approved"});
 await db.doc(`users/${f.admin}`).update({active:false});const recovered=await f.post({},viewer);assert.deepEqual(recovered.result,original.result);assert.equal(await journalCount(f),1);
});
test("anonymous posting fails before business effects",async()=>{const f=await fixture();await assert.rejects(f.post({},null),code("unauthenticated"));await unchanged(f);});
for(const patch of[{foundationEngineEmulatorEnabled:false},{configurationLocked:false},{mode:"live"},{active:true},{journalPostingEnabled:true},{foundationPostingLaneCount:0}])test(`book guard rejects ${JSON.stringify(patch)}`,async()=>{
 const f=await fixture();await db.doc(f.b).update(patch);await assert.rejects(f.post());await unchanged(f);
});
test("phase 2C configuration editing remains locked after reconstruction setup",async()=>{
 const f=await fixture();const{accountingConfigurationTransaction}=require("../lib/trusted/accounting_configuration");
 await assert.rejects(accountingConfigurationTransaction(db,f.admin,{action:"save",companyId:f.companyId,bookId:f.bookId,expectedRevision:1,requestId:"change-config",configuration:f.configured.configuration}),code("failed-precondition"));
});
test("closed period and pre-cutover business dates reject new postings",async()=>{
 const f=await fixture();await db.doc(`${f.b}/periods/nov-2026`).update({status:"closed"});await assert.rejects(f.post());await unchanged(f);
 const g=await fixture();await assert.rejects(g.post({settlementDate:{seconds:Date.parse("2026-11-09T20:59:59Z")/1000,nanoseconds:0}}));await unchanged(g);
});
test("Amman boundary posts into the configured local date",async()=>{const f=await fixture(),r=await f.post({settlementDate:{seconds:Date.parse("2026-11-09T21:00:00Z")/1000,nanoseconds:0}});assert.equal((await db.doc(`${f.b}/journal_entries/${r.result.journalId}`).get()).data().journal.accountingDate,"2026-11-10");});
for(const change of[{amount:1.234},{amount:"1.2340"},{amount:"0.000"},{amount:"-1.000"},{amount:"999999999999999999.000"},{lines:[]},{operationId:"../unsafe"}])test(`settlement input rejects ${JSON.stringify(change)}`,async()=>{
 const f=await fixture();await assert.rejects(f.post(change));await unchanged(f);
});
test("missing exact cash evidence does not default to zero",async()=>{const f=await fixture();await db.doc(`${f.root}/cash_balances/company_cash`).delete();await assert.rejects(f.post());assert.equal(await journalCount(f),0);});
test("numeric and exact cash disagreement blocks posting",async()=>{const f=await fixture();await db.doc(`${f.root}/cash_balances/rep_${f.rep}`).update({amount:99});await assert.rejects(f.post());assert.equal(await journalCount(f),0);});
test("missing opening evidence blocks posting",async()=>{const f=await fixture();await db.doc(`${f.b}/synthetic_openings/synthetic-rep-opening`).delete();await assert.rejects(f.post());await unchanged(f);});
test("mutated source, journal or event evidence blocks replay",async()=>{
 for(const target of["source","journal","event"]){const f=await fixture(),r=await f.post();const path=target==="source"?sourcePath(f):`${f.b}/${target==="journal"?"journal_entries":"events"}/${r.result.eventId}`;
  await db.doc(path).update({tampered:true});await assert.rejects(f.post());assert.equal(await journalCount(f),1);}
});
test("missing original receipt blocks replay instead of reposting",async()=>{const f=await fixture(),r=await f.post();const event=(await db.doc(`${f.b}/events/${r.result.eventId}`).get()).data();await db.doc(event.originalRequestPath).delete();await assert.rejects(f.post());assert.equal(await journalCount(f),1);});
test("recreated configuration or posting seal cannot masquerade as original evidence",async()=>{
 for(const suffix of["configuration_revisions/revision_1","posting_contracts/foundation-v1"]){
  const f=await fixture();await f.post();const ref=db.doc(`${f.b}/${suffix}`),data=(await ref.get()).data();await ref.delete();await ref.set(data);
  await assert.rejects(f.post(),code("data-loss"));assert.equal(await journalCount(f),1);
 }
});
test("missing posting contract blocks the next genuine action",async()=>{const f=await fixture();await f.post();await db.doc(`${f.b}/posting_contracts/foundation-v1`).delete();await assert.rejects(f.post({operationId:"next-action",idempotencyKey:"next-request"}));assert.equal(await journalCount(f),1);});
test("unbound legacy settlement cannot acquire another financial posting",async()=>{const f=await fixture();await db.doc(sourcePath(f)).set({salesRepId:f.rep,amount:1.234});await assert.rejects(f.post());assert.equal(await journalCount(f),0);});
test("lane prefix advances and links immutable hashes for consecutive actions",async()=>{
 const f=await fixture();await db.doc(f.b).update({foundationPostingLaneCount:1});const a=await f.post(),b=await f.post({operationId:"next-action",idempotencyKey:"next-request"});
 assert.equal(a.result.laneSequence,1);assert.equal(b.result.laneSequence,2);const event=(await db.doc(`${f.b}/events/${b.result.eventId}`).get()).data();assert.equal(event.lane.previousEventId,a.result.eventId);
 assert.equal(event.lane.previousEventHash,(await db.doc(`${f.b}/events/${a.result.eventId}`).get()).data().eventHash);
});
test("default-off and resolved transport guards reject nonisolated clients",async()=>{
 const f=await fixture();await assert.rejects(f.post({},f.admin,db,{}),code("failed-precondition"));
 const savedHost=process.env.FIRESTORE_EMULATOR_HOST;let remote;
 try{delete process.env.FIRESTORE_EMULATOR_HOST;remote=new Firestore({projectId:"demo-fatoora-phase2d",host:"example.invalid:443",ssl:true});}finally{process.env.FIRESTORE_EMULATOR_HOST=savedHost;}
 assert.throws(()=>assertAccountingEmulator(remote,{enableEmulatorPosting:true}));
 const fake=new Proxy(db,{get(t,k){if(k==="projectId")return"production-like-project";const v=Reflect.get(t,k,t);return typeof v==="function"?v.bind(t):v;}});assert.throws(()=>assertAccountingEmulator(fake,{enableEmulatorPosting:true}));
 await unchanged(f);
});
test("existing settlement callable selects the foundation writer only with explicit emulator opt-in",async()=>{
 const f=await fixture(),{recordCashSettlement}=require("../lib/trusted/record_cash_settlement"),previous=process.env.FATOORA_ACCOUNTING_ENGINE_EMULATOR;
 try{process.env.FATOORA_ACCOUNTING_ENGINE_EMULATOR="true";const result=await recordCashSettlement.run({auth:{uid:f.admin},data:f.input});assert.equal(result.result.sourceId,"settlement_operation-first");assert.equal(await journalCount(f),1);}
 finally{if(previous===undefined)delete process.env.FATOORA_ACCOUNTING_ENGINE_EMULATOR;else process.env.FATOORA_ACCOUNTING_ENGINE_EMULATOR=previous;}
});
test("existing settlement callable preserves its default numeric contract and does not dual-post",async()=>{
 const f=await fixture(),{recordCashSettlement}=require("../lib/trusted/record_cash_settlement"),previous=process.env.FATOORA_ACCOUNTING_ENGINE_EMULATOR;
 try{delete process.env.FATOORA_ACCOUNTING_ENGINE_EMULATOR;const result=await recordCashSettlement.run({auth:{uid:f.admin},data:{companyId:f.companyId,idempotencyKey:"ordinary-legacy-key",salesRepId:f.rep,amount:1,settlementDate:"2026-11-10T10:00:00Z"}});
  assert.equal(result.settlementId,"settlement_ordinary-legacy-key");assert.equal(await journalCount(f),0);assert.equal((await db.doc(`${f.root}/cash_balances/company_cash`).get()).data().amount,21);}
 finally{if(previous===undefined)delete process.env.FATOORA_ACCOUNTING_ENGINE_EMULATOR;else process.env.FATOORA_ACCOUNTING_ENGINE_EMULATOR=previous;}
});
