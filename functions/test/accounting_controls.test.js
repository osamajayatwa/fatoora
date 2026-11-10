const {test,after}=require("node:test");const assert=require("node:assert/strict");
if(!/^127\.0\.0\.1:\d+$/.test(process.env.FIRESTORE_EMULATOR_HOST||""))throw new Error("Control tests require the loopback accounting emulator.");
const {initializeApp,deleteApp}=require("firebase-admin/app");const{getFirestore}=require("firebase-admin/firestore");
const {controlsFixture}=require("./helpers/accounting_controls_fixture");
const app=initializeApp({projectId:"demo-fatoora-phase2d"},"control-tests"),db=getFirestore(app);after(()=>deleteApp(app));
const fixture=options=>controlsFixture(db,options);const data=async path=>(await db.doc(path).get()).data();

test("invoice principal, initial cash, allocation and remaining AR commit as one balanced event",async()=>{
 const f=await fixture(),r=await f.operation("charge","initial-sale",{amountUnits:"100000",initialPaymentUnits:"25000"});
 const p=await data(f.partyPath);assert.equal(p.receivableUnits,"75000");assert.equal((await data(`${f.root}/cash_balances/company_cash`)).amountUnits,"45000");
 const id=f.itemIdFor("charge","initial-sale"),original=await db.doc(`${f.b}/open_items/${id}`).get(),position=await db.doc(`${f.b}/open_item_positions/${id}`).get();
 assert.equal(original.data().originalUnits,"100000");assert.equal(position.data().remainingUnits,"75000");assert(original.createTime.isEqual(position.createTime));
 const entry=await data(`${f.b}/journal_entries/${r.result.journalId}`);assert.equal(entry.journal.lines.length,4);assert.equal((await db.collection(`${f.b}/allocations`).get()).size,1);
});
test("cash receipt allocates oldest due dates with immutable originals and exact closures",async()=>{
 const f=await fixture();await f.operation("charge","later",{amountUnits:"5000",dueDate:"2026-11-25"});await f.operation("charge","earlier",{amountUnits:"3000",dueDate:"2026-11-15"});
 await f.operation("receipt","collection",{amountUnits:"4000"});
 assert.equal((await data(f.partyPath)).receivableUnits,"4000");assert.equal((await data(`${f.b}/open_item_positions/${f.itemIdFor("charge","earlier")}`)).remainingUnits,"0");
 assert.equal((await data(`${f.b}/open_item_positions/${f.itemIdFor("charge","later")}`)).remainingUnits,"4000");
 assert.equal((await data(`${f.b}/open_items/${f.itemIdFor("charge","earlier")}`)).originalUnits,"3000");
});
test("customer credit application consumes liability and AR once without moving cash",async()=>{
 const f=await fixture();await f.operation("charge","debt",{amountUnits:"10000"});await f.operation("return_credit","credit",{amountUnits:"4000"});
 const before=await data(f.partyPath),cashBefore=await data(`${f.root}/cash_balances/company_cash`);
 await f.operation("apply_credit","apply",{amountUnits:"3000",creditItemId:f.itemIdFor("return_credit","credit")});
 const after=await data(f.partyPath);assert.equal(before.signedDebtUnits,after.signedDebtUnits);assert.equal(after.receivableUnits,"7000");assert.equal(after.returnCreditUnits,"1000");
 assert.deepEqual(await data(`${f.root}/cash_balances/company_cash`),cashBefore);
});
test("unpaid return reduces its original charge instead of allocating unrelated debt",async()=>{
 const f=await fixture();await f.operation("charge","first",{amountUnits:"10000"});await f.operation("charge","second",{amountUnits:"5000"});
 await f.operation("return_reduction","return",{amountUnits:"2000",chargeItemId:f.itemIdFor("charge","second")});
 assert.equal((await data(`${f.b}/open_item_positions/${f.itemIdFor("charge","first")}`)).remainingUnits,"10000");assert.equal((await data(f.partyPath)).receivableUnits,"13000");
});
test("receipt and credit overconsumption leave cash, journals and positions unchanged",async()=>{
 const f=await fixture();await f.operation("charge","debt",{amountUnits:"5000"});await f.operation("return_credit","credit",{amountUnits:"2000"});
 const before=await data(f.partyPath),cash=await data(`${f.root}/cash_balances/company_cash`);
 await assert.rejects(f.operation("receipt","too-much",{amountUnits:"4000"}));
 await assert.rejects(f.operation("apply_credit","too-much-credit",{amountUnits:"3000",creditItemId:f.itemIdFor("return_credit","credit")}));
 assert.deepEqual(await data(f.partyPath),before);assert.deepEqual(await data(`${f.root}/cash_balances/company_cash`),cash);
});
test("concurrent collections cannot overallocate the same open item",async()=>{
 const f=await fixture();await f.operation("charge","debt",{amountUnits:"10000"});
 const results=await Promise.allSettled([f.operation("receipt","a",{amountUnits:"8000"}),f.operation("receipt","b",{amountUnits:"8000"})]);
 assert.equal(results.filter(r=>r.status==="fulfilled").length,1);assert.equal((await data(f.partyPath)).receivableUnits,"2000");
});
test("missing or tampered customer positions fail without assuming an opening",async()=>{
 const f=await fixture();await db.doc(f.partyPath).delete();await assert.rejects(f.operation("charge","missing",{amountUnits:"1000"}));
 const g=await fixture();await g.operation("charge","debt",{amountUnits:"1000"});await db.doc(g.partyPath).update({receivableUnits:"2000",signedDebtUnits:"2000"});await assert.rejects(g.operation("receipt","bad",{amountUnits:"1000"}));
});
test("quantity-only transfer conserves each item without a monetary journal or purchase cost",async()=>{
 const f=await fixture(),r=await f.operation("transfer","transfer",{changes:f.transferChanges()});assert.equal(r.result.journalId,null);
 const item=await data(`items/${f.itemIds[0]}`),rep=await data(`${f.root}/rep_inventory_balances/${f.rep}_${f.itemIds[0]}`);
 assert.equal(item.currentStockUnits,"98750000");assert.equal(rep.quantityUnits,"1250000");assert.equal(item.price,7.5);assert.equal(item.costPrice,undefined);
 assert.equal((await db.collection(`${f.b}/journal_entries`).get()).size,0);assert.equal((await db.collection(`${f.b}/events`).get()).size,1);
});
test("quantity retry and request alias never repeat either movement leg",async()=>{
 const f=await fixture(),input={changes:f.transferChanges()},a=await f.operation("transfer","same",input),b=await f.operation("transfer","same",input,{requestId:"other-request"});
 assert.deepEqual(a.result,b.result);assert.equal((await data(`items/${f.itemIds[0]}`)).currentStockUnits,"98750000");
});
test("price edits preserve the stock proof and never reprice historical quantities",async()=>{
 const f=await fixture();await f.operation("transfer","first",{changes:f.transferChanges()});await db.doc(`items/${f.itemIds[0]}`).update({price:11.125,name:"Updated reference"});
 await f.operation("transfer","second",{changes:f.transferChanges()});assert.equal((await data(`items/${f.itemIds[0]}`)).currentStockUnits,"97500000");
});
test("shortage and missing custody evidence block all quantity effects",async()=>{
 const f=await fixture();await assert.rejects(f.operation("transfer","shortage",{changes:f.transferChanges("100000001")}));assert.equal((await data(`items/${f.itemIds[0]}`)).currentStockUnits,"100000000");
 await db.doc(`${f.root}/rep_inventory_balances/${f.rep}_${f.itemIds[0]}`).delete();await assert.rejects(f.operation("transfer","missing",{changes:f.transferChanges()}));
});
test("unbalanced transfer legs are rejected before source or stock writes",async()=>{
 const f=await fixture(),changes=f.transferChanges();changes[1].quantityUnits="1000000";await assert.rejects(f.operation("transfer","unbalanced",{changes}));
 assert.equal((await db.doc(`${f.root}/inventory_transfers/source-unbalanced`).get()).exists,false);assert.equal((await data(`items/${f.itemIds[0]}`)).currentStockUnits,"100000000");
});
test("100 distinct transfer lines remain atomic within measured budgets and recover chunked evidence",async()=>{
 const f=await fixture({stockCount:100}),changes=f.transferChanges(),stats=[];
 const database=new Proxy(db,{get(t,k){if(k==="runTransaction")return callback=>db.runTransaction(async tx=>{const s={reads:0,writes:0,bytes:0};stats.push(s);
  return callback(new Proxy(tx,{get(target,key){const value=Reflect.get(target,key,target);
   if(key==="getAll")return(...refs)=>{s.reads+=refs.length;return value.apply(target,refs);};
   if(["create","set","update"].includes(key))return(ref,body,...rest)=>{s.writes++;s.bytes+=Buffer.byteLength(JSON.stringify(body));return value.call(target,ref,body,...rest);};
   return typeof value==="function"?value.bind(target):value;}}));});const v=Reflect.get(t,k,t);return typeof v==="function"?v.bind(t):v;}});
 const r=await f.operation("transfer","hundred",{changes},{},database);
 assert.equal(r.result.journalId,null);const event=await data(`${f.b}/events/${r.result.eventId}`);assert(event.effectChunks.length>0);assert.equal(event.effects.length,0);
 const replay=await f.operation("transfer","hundred",{changes});assert.deepEqual(replay.result,r.result);
 assert.equal((await data(`items/${f.itemIds[99]}`)).currentStockUnits,"98750000");
 const committed=stats.find(s=>s.writes>0);assert(committed.reads<=600);assert(committed.writes<=480);assert(committed.bytes<=4*1024*1024);
 const budgetPath=require("node:path").join(__dirname,"../../output/phase2e/transfer-budget.json");require("node:fs").mkdirSync(require("node:path").dirname(budgetPath),{recursive:true});
 require("node:fs").writeFileSync(budgetPath,JSON.stringify({...committed,chunks:event.effectChunks.length,lines:100},null,2));
});
test("fully paid invoice closes its charge without fabricating a later receipt",async()=>{
 const f=await fixture();await f.operation("charge","cash-sale",{amountUnits:"5000",initialPaymentUnits:"5000"});
 assert.equal((await data(f.partyPath)).receivableUnits,"0");assert.equal((await data(`${f.b}/open_item_positions/${f.itemIdFor("charge","cash-sale")}`)).state,"closed");
 assert.equal((await db.collection(`${f.root}/receipts`).get()).size,0);
});
test("journal controls reject a missing cash effect even when debit and credit balance",async()=>{
 const f=await fixture();await f.operation("charge","debt",{amountUnits:"5000"});const before=await data(f.partyPath);
 await assert.rejects(f.operation("receipt","forged",{amountUnits:"1000"},{},db,f.admin,false,p=>({...p,controlEffects:p.controlEffects.filter(e=>e.kind!=="cash")})));
 assert.deepEqual(await data(f.partyPath),before);
});
test("party balances cannot change without corresponding open-item position changes",async()=>{
 const f=await fixture();await assert.rejects(f.operation("charge","forged",{amountUnits:"5000"},{},db,f.admin,false,p=>({...p,writes:b=>p.writes(b).filter(w=>!w.path.includes("/open_item_positions/"))})));
 assert.equal((await data(f.partyPath)).receivableUnits,"0");
});
test("orphan stock-leg create preconditions abort every source and quantity write",async()=>{
 const f=await fixture(),changes=f.transferChanges(),{exactStockMovementId}=require("../lib/trusted/inventory");
 const id=exactStockMovementId({system:"fatoora",type:"inventory_transfers",id:"source-orphan",revision:"1",action:"transfer"},changes[0]);
 await db.doc(`${f.root}/stock_movements/${id}`).set({companyId:f.companyId,orphan:true});
 await assert.rejects(f.operation("transfer","orphan",{changes}));assert.equal((await data(`items/${f.itemIds[0]}`)).currentStockUnits,"100000000");
 assert.equal((await db.doc(`${f.root}/inventory_transfers/source-orphan`).get()).exists,false);
});
test("repeated product lines preserve distinct movement provenance and cumulative balances",async()=>{
 const f=await fixture(),first=f.transferChanges(),second=first.map(ch=>({...ch,lineId:"another-line"}));
 await f.operation("transfer","repeated",{changes:[...first,...second]});assert.equal((await data(`items/${f.itemIds[0]}`)).currentStockUnits,"97500000");
 const legs=await db.collection(`${f.root}/stock_movements`).where("sourceId","==","source-repeated").get();assert.equal(legs.size,2);
});
test("tampered immutable charge principals prevent later allocation",async()=>{
 const f=await fixture();await f.operation("charge","debt",{amountUnits:"5000"});await db.doc(`${f.b}/open_items/${f.itemIdFor("charge","debt")}`).update({originalUnits:"6000"});
 await assert.rejects(f.operation("receipt","bad",{amountUnits:"1000"}));assert.equal((await data(f.partyPath)).receivableUnits,"5000");
});
test("interruption after cash/allocations are queued leaves the whole collection uncommitted",async()=>{
 const f=await fixture();await f.operation("charge","debt",{amountUnits:"5000"});
 const database=new Proxy(db,{get(t,k){if(k==="runTransaction")return cb=>db.runTransaction(tx=>cb(new Proxy(tx,{get(target,key){if(key==="create")return(ref,body)=>{if(ref.path.includes("/events/"))throw new Error("interrupted control commit");return target.create(ref,body);};const v=Reflect.get(target,key,target);return typeof v==="function"?v.bind(target):v;}})));const v=Reflect.get(t,k,t);return typeof v==="function"?v.bind(t):v;}});
 await assert.rejects(f.operation("receipt","interrupted",{amountUnits:"2000"},{},database),/interrupted control commit/);
 assert.equal((await data(f.partyPath)).receivableUnits,"5000");assert.equal((await data(`${f.root}/cash_balances/company_cash`)).amountUnits,"20000");assert.equal((await db.collection(`${f.b}/allocations`).get()).size,0);
});
test("missing/corrupted evidence chunks prevent replay of a large quantity event",async()=>{
 const f=await fixture({stockCount:30}),changes=f.transferChanges(),r=await f.operation("transfer","chunks",{changes});const event=await data(`${f.b}/events/${r.result.eventId}`);assert(event.effectChunks.length>0);
 await db.doc(event.effectChunks[0].path).delete();await assert.rejects(f.operation("transfer","chunks",{changes}));assert.equal((await data(`items/${f.itemIds[0]}`)).currentStockUnits,"98750000");
});
test("oldest-due ties are ordered by original date and stable item ID",async()=>{
 const f=await fixture();await f.operation("charge","alpha",{amountUnits:"3000",dueDate:"2026-11-15"});await f.operation("charge","beta",{amountUnits:"3000",dueDate:"2026-11-15"});
 const ids=[f.itemIdFor("charge","alpha"),f.itemIdFor("charge","beta")].sort();await f.operation("receipt","tie",{amountUnits:"1000"});
 assert.equal((await data(`${f.b}/open_item_positions/${ids[0]}`)).remainingUnits,"2000");assert.equal((await data(`${f.b}/open_item_positions/${ids[1]}`)).remainingUnits,"3000");
});
test("committed invoice and quantity events recover after later position changes",async()=>{
 const f=await fixture(),charge={amountUnits:"6000"},stock={changes:f.transferChanges()};
 const original=await f.operation("charge","original",charge),transfer=await f.operation("transfer","original",stock);
 await f.operation("receipt","later",{amountUnits:"2000"});await f.operation("transfer","later",stock);
 assert.deepEqual((await f.operation("charge","original",charge)).result,original.result);assert.deepEqual((await f.operation("transfer","original",stock)).result,transfer.result);
});
test("mixed physical purposes cannot bypass transfer conservation",async()=>{
 const f=await fixture(),changes=f.transferChanges();changes[1].purpose="receipt";await assert.rejects(f.operation("transfer","mixed",{changes}));assert.equal((await data(`items/${f.itemIds[0]}`)).currentStockUnits,"100000000");
});
test("partial return splits remaining debt and paid credit in a single atomic party update",async()=>{
 const f=await fixture();await f.operation("charge","partial",{amountUnits:"100000",initialPaymentUnits:"40000"});
 const cash=await data(`${f.root}/cash_balances/company_cash`);await f.operation("return_split","return",{chargeItemId:f.itemIdFor("charge","partial"),receivableReductionUnits:"60000",creditUnits:"20000"});
 const party=await data(f.partyPath);assert.equal(party.receivableUnits,"0");assert.equal(party.returnCreditUnits,"20000");assert.equal(party.signedDebtUnits,"-20000");
 assert.deepEqual(await data(`${f.root}/cash_balances/company_cash`),cash);
});
test("sale source, cash, AR and warehouse quantities share one commit",async()=>{
 const f=await fixture(),change={...f.transferChanges()[0],purpose:"sale",quantityUnits:"2000000"};
 const result=await f.operation("charge","stock-sale",{amountUnits:"10000",initialPaymentUnits:"2000",changes:[change]});
 assert.equal((await data(f.partyPath)).receivableUnits,"8000");assert.equal((await data(`items/${f.itemIds[0]}`)).currentStockUnits,"98000000");
 const event=await db.doc(`${f.b}/events/${result.result.eventId}`).get(),item=await db.doc(`items/${f.itemIds[0]}`).get();assert(item.updateTime.isEqual(event.createTime));
});
