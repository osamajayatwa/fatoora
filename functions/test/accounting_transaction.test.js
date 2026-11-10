const {test,after}=require("node:test");
const assert=require("node:assert/strict");
if(!/^127\.0\.0\.1:\d+$/.test(process.env.FIRESTORE_EMULATOR_HOST||""))throw new Error("Accounting guard tests require the loopback emulator.");
const {initializeApp,deleteApp}=require("firebase-admin/app");
const {getFirestore}=require("firebase-admin/firestore");
const {accountingTransaction,assertAccountingControlContext,inheritAccountingTransactionScope,selectOpenChargePositions}=require("../lib/trusted/accounting_transaction");
const app=initializeApp({projectId:"demo-fatoora-phase2d"},"accounting-guard-tests"),db=getFirestore(app);
after(()=>deleteApp(app));
const b="companies/guard-company/books/guard-book";

test("control capabilities reject raw transactions and mismatched book scope",async()=>{
 await db.runTransaction(async raw=>{
  assert.throws(()=>assertAccountingControlContext(raw,"guard-company","guard-book"));
  assert.throws(()=>inheritAccountingTransactionScope({},raw));
  assert.throws(()=>selectOpenChargePositions(raw,"guard-company","guard-book","customer"));
  const{tx}=accountingTransaction(raw,db,"guard-company","guard-book",[]);
  assertAccountingControlContext(tx,"guard-company","guard-book");
  assert.throws(()=>assertAccountingControlContext(tx,"guard-company","other-book"));
  assert.throws(()=>selectOpenChargePositions(tx,"guard-company","guard-book","customer",101));
 });
});

test("the bounded open-item selector cannot read after any staged write",async()=>{
 await assert.rejects(db.runTransaction(async raw=>{
  const{tx}=accountingTransaction(raw,db,"guard-company","guard-book",[]);
  tx.create(db.doc(`${b}/events/query-after-write`),{test:true});
  await selectOpenChargePositions(tx,"guard-company","guard-book","customer");
 }));
 assert.equal((await db.doc(`${b}/events/query-after-write`).get()).exists,false);
});
test("cached reads still reject reads after the first write",async()=>{
 await assert.rejects(db.runTransaction(async t=>{const{tx}=accountingTransaction(t,db,"guard-company","guard-book",[]);
  await tx.get(db.doc(b));tx.create(db.doc(`${b}/events/never-committed`),{test:true});await tx.get(db.doc(b));}));
 assert.equal((await db.doc(`${b}/events/never-committed`).get()).exists,false);
});
test("cross-company, cross-book and query reads are denied",async()=>{
 for(const ref of[db.doc("companies/other-company"),db.doc("companies/guard-company/books/other-book"),db.collection(`${b}/events`).limit(1)]){
  await assert.rejects(db.runTransaction(async t=>{const{tx}=accountingTransaction(t,db,"guard-company","guard-book",[]);await tx.get(ref);}));
 }
});
test("undeclared business writes, cross-company manifests and deletion are denied",async()=>{
 for(const kind of["undeclared","foreign-manifest","delete"]){await assert.rejects(db.runTransaction(async t=>{
  const{tx}=accountingTransaction(t,db,"guard-company","guard-book",kind==="foreign-manifest"?["companies/other/cash_balances/cash"]:[]);
  if(kind==="delete")tx.delete(db.doc(`${b}/events/something`));else tx.set(db.doc("companies/guard-company/cash_balances/undeclared"),{test:true});
 }));}
});
test("write and per-document byte budgets abort the whole attempt",async()=>{
 await assert.rejects(db.runTransaction(async t=>{const{tx}=accountingTransaction(t,db,"guard-company","guard-book",[]);
  for(let i=0;i<481;i++)tx.create(db.doc(`${b}/events/write-${i}`),{index:i});}));
 assert.equal((await db.doc(`${b}/events/write-0`).get()).exists,false);
 await assert.rejects(db.runTransaction(async t=>{const{tx}=accountingTransaction(t,db,"guard-company","guard-book",[]);
  tx.create(db.doc(`${b}/events/oversized`),{data:"x".repeat(512*1024)});}));
});
test("read count and total byte budgets are enforced before SDK commit",async()=>{
 await assert.rejects(db.runTransaction(async t=>{const{tx}=accountingTransaction(t,db,"guard-company","guard-book",[]);
  await tx.getAll(...Array.from({length:601},(_,i)=>db.doc(`${b}/events/read-${i}`)));}));
 await assert.rejects(db.runTransaction(async t=>{const{tx}=accountingTransaction(t,db,"guard-company","guard-book",[]);
  for(let i=0;i<9;i++)tx.create(db.doc(`${b}/events/bytes-${i}`),{data:"x".repeat(500*1024)});}));
 assert.equal((await db.doc(`${b}/events/bytes-0`).get()).exists,false);
});
