"use strict";
// New synthetic records only. All financial effects use deployed trusted callables.
const assert=require("node:assert/strict"),{randomUUID}=require("node:crypto"),cp=require("node:child_process");
const S=require("./staging-release-support.cjs"),{fs,path,root,dir,PROJECT,load,read,save,check,connect,publicRequest,logError}=S;
const {sdk:adminSdk}=require("./staging-current-release.cjs");
const money=n=>Math.round(n*1000)/1000,runId=`acceptance-${randomUUID()}`,results=[];
const resumeInventory=process.argv[2]==="--resume-inventory";
const cfg=read(path.join(root,"config/firebase/staging.web.json"));
const docs=`https://firestore.googleapis.com/v1/projects/${PROJECT}/databases/(default)/documents`;
function value(v){if(v===null)return {nullValue:null};if(v instanceof Date)return {timestampValue:v.toISOString()};if(Array.isArray(v))return {arrayValue:{values:v.map(value)}};if(typeof v==="object")return {mapValue:{fields:fields(v)}};if(typeof v==="string")return {stringValue:v};if(typeof v==="boolean")return {booleanValue:v};return Number.isInteger(v)?{integerValue:String(v)}:{doubleValue:v};}
function fields(data){return Object.fromEntries(Object.entries(data).filter(([,v])=>v!==undefined).map(([k,v])=>[k,value(v)]));}
async function request(url,{token,method="GET",data}={}){
 const r=await publicRequest(url,{method,data,headers:{...(token?{authorization:`Bearer ${token}`}:{})},validateStatus:()=>true,responseType:"text"});
 let body;try{body=JSON.parse(r.data);}catch{throw Error(`Non-JSON response from staging: ${new URL(url).pathname}, status ${r.status}`);}return {status:r.status,body};
}
async function main(){
 check(process.argv.length===2||process.argv.length===3&&resumeInventory,"No custom target or credentials accepted");
 const release=read(path.join(dir,"release-state.json"));check(release.functionsReady&&release.rules&&release.indexesReady,"Deployed index/Rules/Functions gates required");
 check(read(path.join(dir,"evidence/runtime-after.json")).status==="PASS_DEPLOYED_RUNTIME","Actual patched runtime verification required");
 check(read(path.join(dir,"evidence/backend-deployment-verification.json")).passed&&read(path.join(dir,"evidence/preservation-before-acceptance.json")).passed,"Exact deployment and data preservation gates required");
 const {reader}=await connect(),{app,db,auth}=await adminSdk(reader);
 save(path.join(dir,"evidence/live-acceptance-run.json"),{runId,project:PROJECT,startedAt:new Date().toISOString(),syntheticOnly:true,cleanupDeletes:false});
 async function fixture(label,companyId=`release-${randomUUID()}`){
  if(companyId!=="default_company")await db.doc(`companies/${companyId}`).create({id:companyId,companyId,name:`Synthetic ${label}`,active:true,syntheticReleaseRunId:runId});
  const users={},tokens={};
  const roles=label==="inventory"?[["admin","admin"],["a","sales_rep"],["b","sales_rep"]]:[["admin","admin"],["a","sales_rep"],["b","sales_rep"],["inactive","sales_rep"],["foreign","sales_rep"]];
  for(const [name,role]of roles){
   const uid=`${runId}-${label}-${name}`,email=`${randomUUID()}@synthetic.invalid`,password=`Synthetic-${randomUUID()}!`;
   await auth.createUser({uid,email,password,emailVerified:true});
   const profile={uid,name:`Synthetic ${label} ${name}`,role,email,companyId:name==="foreign"?`foreign-${runId}`:companyId,active:true,approvalStatus:"approved",syntheticReleaseRunId:runId};
   await db.doc(`users/${uid}`).create(profile);
   const login=await request(`https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=${cfg.FIREBASE_API_KEY}`,{method:"POST",data:{email,password,returnSecureToken:true}});
   assert.equal(login.status,200,`Synthetic ${name} login failed`);assert.equal(login.body.localId,uid);
   const claims=await auth.verifyIdToken(login.body.idToken);assert.equal(claims.aud,PROJECT);assert.equal(claims.iss,`https://securetoken.google.com/${PROJECT}`);
   users[name]={uid,name:profile.name,email,password};tokens[name]=login.body.idToken;
  }
  const ref=(collection,id)=>db.doc(`companies/${companyId}/${collection}/${id}`);
  async function call(name,fn,data={},expected){
   const r=await request(`https://us-central1-${PROJECT}.cloudfunctions.net/${fn}`,{method:"POST",token:name?tokens[name]:undefined,data:{data:{companyId,...data}}});
   if(expected){assert.equal(r.body.error?.status,expected,`${fn}: ${JSON.stringify(r.body)}`);return;}
   assert.equal(r.status,200,`${fn}: ${JSON.stringify(r.body)}`);return r.body.result;
  }
  async function create(name,collection,id,data){
   const r=await request(`${docs}:commit?key=${cfg.FIREBASE_API_KEY}`,{method:"POST",token:tokens[name],data:{writes:[{update:{name:`projects/${PROJECT}/databases/(default)/documents/companies/${companyId}/${collection}/${id}`,fields:fields(data)},updateTransforms:[{fieldPath:"createdAt",setToServerValue:"REQUEST_TIME"},{fieldPath:"updatedAt",setToServerValue:"REQUEST_TIME"}],currentDocument:{exists:false}}]}});
   assert.equal(r.status,200,`Client draft create: ${JSON.stringify(r.body)}`);
  }
  async function get(name,collection,id,denied=false){
   const r=await request(`${docs}/companies/${companyId}/${collection}/${id}?key=${cfg.FIREBASE_API_KEY}`,{token:tokens[name]});assert.equal(r.status,denied?403:200);return r.body;
  }
  async function query(name,collection,filter,orderBy=[],startAt,denied=false){
   const r=await request(`${docs}/companies/${companyId}:runQuery?key=${cfg.FIREBASE_API_KEY}`,{method:"POST",token:tokens[name],data:{structuredQuery:{from:[{collectionId:collection}],where:filter,orderBy,limit:10,...(startAt?{startAt}:{})}}});assert.equal(r.status,denied?403:200,`Rules query: ${JSON.stringify(r.body)}`);return denied?[]:r.body.filter(x=>x.document).map(x=>x.document);
  }
  const eq=(field,val)=>({fieldFilter:{field:{fieldPath:field},op:"EQUAL",value:value(val)}});
  const customer=async name=>(await call(name,"createCustomer",{idempotencyKey:`customer-${randomUUID()}`,name:`Synthetic ${label} customer`,active:true})).customerId;
  async function allocate(owner,kind,prefix){
   const id=`${kind}_2026`,url=`${docs}/companies/${companyId}/counters/${id}?key=${cfg.FIREBASE_API_KEY}`,current=await request(url,{token:tokens[owner]});
   assert.ok([200,404].includes(current.status));const next=current.status===200?Number(current.body.fields.lastNumber.integerValue||current.body.fields.lastNumber.doubleValue)+1:1;
   const data={id,companyId,year:2026,lastNumber:next,prefix};
   const result=await request(`${docs}:commit?key=${cfg.FIREBASE_API_KEY}`,{method:"POST",token:tokens[owner],data:{writes:[{update:{name:`projects/${PROJECT}/databases/(default)/documents/companies/${companyId}/counters/${id}`,fields:fields(data)},updateTransforms:[{fieldPath:"updatedAt",setToServerValue:"REQUEST_TIME"}],currentDocument:current.status===200?{updateTime:current.body.updateTime}:{exists:false}}]}});
   assert.equal(result.status,200);return `${prefix}-2026-${String(next).padStart(6,"0")}`;
  }
  async function draft(owner,id,customerId,{price=10,quantity=3,tax=16,discount=3,paid=0,item=null}={}){
   const uid=users[owner].uid,admin=owner==="admin",subtotal=price*quantity,grandTotal=money((subtotal-discount)*(1+tax/100));
   const invoiceNumber=await allocate(owner,"invoices","INV");
   await create(owner,"invoices",id,{id,companyId,invoiceNumber,invoiceType:"regular",invoiceStatus:"draft",paymentType:"credit",paymentStatus:"unpaid",hasReceivedPayment:paid>0,
    invoiceDate:new Date("2026-11-06T09:00:00Z"),dueDate:new Date("2026-11-30T09:00:00Z"),createdByUid:uid,createdByName:users[owner].name,createdByRole:admin?"admin":"sales_rep",salesRepId:uid,salesRepName:users[owner].name,customerId,customerSnapshot:{id:customerId,name:`Synthetic ${label} customer`},
    items:[{lineId:"line",lineType:item?"catalog":"custom",itemId:item,itemName:"Synthetic item",description:"Synthetic service",unit:"pcs",quantity,unitPrice:price,discount,taxPercent:tax}],subtotal,totalDiscount:discount,totalTax:money((subtotal-discount)*tax/100),grandTotal,paidAmount:paid,remainingAmount:money(grandTotal-paid),
    returnStatus:"none",returnedTotal:0,returnedSubtotal:0,returnedDiscount:0,returnedTax:0,returnedReceivableAmount:0,customerCreditAmount:0,cashRefundAmount:0,returnInvoiceIds:[],latestReturnAt:null,receiptIds:[],lastReceiptId:"",isLocked:false,financialPosted:false,financialPostedAt:null,financialPostedByUid:"",financialPostedByName:"",customerTransactionIds:[],cashMovementIds:[],inventoryPosted:false,inventoryPostedAt:null,inventoryPostedByUid:"",inventoryPostedByName:"",inventoryMovementIds:[],stockSourceType:admin?"companyWarehouse":"salesRep",stockSourceId:admin?"default_warehouse":uid,stockSourceSalesRepId:admin?"":uid,searchKeywords:["synthetic"],invoiceNumberLower:id,customerNameLower:"synthetic"});
  }
  const dashboard=name=>call(name,"getDashboardSnapshot",{from:0,to:Date.now()});
  return {companyId,users,tokens,ref,call,create,get,query,eq,customer,draft,dashboard,allocate};
 }
 async function ledger(f,expected){
  for(let i=0;i<90;i++){const s=await f.call("admin","getFinancialLedgerSummary",{from:0,to:Date.now()});if(Object.entries(expected).every(([k,v])=>s[k]===v))return s;await new Promise(r=>setTimeout(r,1000));}throw Error("Staging reporting projections did not reconcile");
 }
 try{
  let priorRunId;
  if(resumeInventory){const prior=read(path.join(dir,"evidence/live-acceptance.failure.json"));check(prior.completed.length===3,"Only the already-verified first three scenarios can be reused");results.push(...prior.completed);priorRunId=prior.runId;check(read(path.join(dir,"evidence/settings-repair.json")).passed,"Configuration repair not verified");}
  if(!resumeInventory){
  const f=await fixture("transfer"),customerId=await f.customer("a"),uidA=f.users.a.uid,uidB=f.users.b.uid;
  await f.draft("a","old",customerId);await f.draft("a","stale",customerId);await f.call("a","confirmInvoice",{invoiceId:"old"});
  await ledger(f,{metricSales:31.32,metricReceivables:31.32});
  const before=(await f.ref("invoices","old").get()).data(),balance=(await f.ref("customers",customerId).get()).get("currentBalance");
  const transfer={customerId,assignedToUid:uidB,expectedAssignedToUid:uidA,expectedAssignmentRevision:0,idempotencyKey:`transfer-${randomUUID()}`,reason:runId};
  await f.call("a","reassignCustomer",transfer,"PERMISSION_DENIED");await f.call("admin","reassignCustomer",transfer);
  assert.deepEqual((await f.ref("invoices","old").get()).data(),before);assert.equal((await f.ref("customers",customerId).get()).get("currentBalance"),balance);
  await f.get("a","customers",customerId,true);await f.get("a","invoices","old");await f.get("b","invoices","old");await f.get("b","invoices","stale",true);await f.get("foreign","invoices","old",true);
  await f.query("a","customer_transactions",f.eq("customerId",customerId),[],undefined,true);assert.ok((await f.query("b","customer_transactions",f.eq("customerId",customerId))).length>0);
  await f.call("a","confirmInvoice",{invoiceId:"stale"},"PERMISSION_DENIED");
  const receipt=await f.call("b","createReceipt",{idempotencyKey:`receipt-${randomUUID()}`,customerId,amount:31.32,paymentMethod:"cash",receiptDate:"2026-11-07T09:00:00Z"});assert.deepEqual((await f.ref("receipts",receipt.receiptId).get()).get("invoiceAllocations"),{old:31.32});
  await f.draft("b","new",customerId,{price:15,quantity:1,discount:0});await f.call("b","confirmInvoice",{invoiceId:"new"});
  const input={idempotencyKey:`return-${randomUUID()}`,originalInvoiceId:"old",refundType:"cash_refund",reason:runId,returnDate:"2026-11-07T10:00:00Z",items:[{originalInvoiceItemId:"old:line:line",returnedQuantity:1}]};
  await f.call("b","confirmSalesReturn",input,"PERMISSION_DENIED");const posted=await f.call("admin","confirmSalesReturn",input);assert.equal((await f.call("admin","confirmSalesReturn",input)).alreadyPosted,true);
  const returned=(await f.ref("sales_returns",posted.returnId).get()).data();assert.equal(returned.salesRepId,uidA);assert.equal(returned.cashRefundAmount,10.44);assert.equal(returned.returnDate.toDate().toISOString(),"2026-11-07T10:00:00.000Z");
  assert.equal((await f.ref("cash_balances",`rep_${uidB}`).get()).get("amount"),20.88);assert.equal((await f.ref("invoices","old").get()).get("invoiceDate").toMillis(),before.invoiceDate.toMillis());
  const refund=(await f.ref("financial_ledger_entries",`sales_return_${posted.returnId}_cash_refund`).get()).data();assert.equal(refund.salesRepId,uidB);assert.equal(refund.metricSales,0);
  const historicalFilter={compositeFilter:{op:"AND",filters:[f.eq("customerId",customerId),{compositeFilter:{op:"OR",filters:[f.eq("salesRepId",uidB),f.eq("financialPosted",true)]}}]}};
  const order=[{field:{fieldPath:"invoiceDate"},direction:"ASCENDING"},{field:{fieldPath:"__name__"},direction:"ASCENDING"}];
  const history=await f.query("b","invoices",historicalFilter,order);assert.equal(history.length,2);
  assert.equal((await f.dashboard("admin")).totalSales,38.28);assert.equal((await f.dashboard("a")).totalSales,20.88);assert.equal((await f.dashboard("b")).totalSales,17.4);
  await ledger(f,{metricSales:38.28,metricRepCashOut:10.44,metricReceivables:17.4});
  const extra=await f.call("b","createReceipt",{idempotencyKey:`receipt-${randomUUID()}`,customerId,amount:3,paymentMethod:"cash",receiptDate:"2026-11-07T11:00:00Z"});
  await f.call("b","cancelReceipt",{receiptId:extra.receiptId,reason:runId},"PERMISSION_DENIED");await f.call("admin","cancelReceipt",{receiptId:extra.receiptId,reason:runId});assert.equal((await f.call("admin","cancelReceipt",{receiptId:extra.receiptId,reason:runId})).alreadyCancelled,true);
  assert.equal((await f.ref("cash_balances",`rep_${uidB}`).get()).get("amount"),20.88);assert.equal((await f.ref("customers",customerId).get()).get("currentBalance"),17.4);
  await ledger(f,{metricSales:38.28,metricReceivables:17.4,metricReceipts:31.32});
  await f.call("admin","reassignCustomer",{...transfer,assignedToUid:f.users.admin.uid,expectedAssignedToUid:uidB,expectedAssignmentRevision:1,idempotencyKey:`transfer-${randomUUID()}`});
  await f.get("b","invoices","old",true);await f.get("b","invoices","new");await f.query("b","invoices",historicalFilter,order,{values:[history[0].fields.invoiceDate,{referenceValue:history[0].name}],before:false},true);
  await f.call(null,"getDashboardSnapshot",{from:0,to:Date.now()},"UNAUTHENTICATED");
  const wrong=await request(`https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=${cfg.FIREBASE_API_KEY}`,{method:"POST",data:{email:f.users.a.email,password:`Wrong-${randomUUID()}`,returnSecureToken:true}});assert.equal(wrong.status,400);
  results.push({scenario:"transfer-history-refund-receipt-cancellation",companyId:f.companyId,netBilledIncludingTax:38.28,sellerA:20.88,sellerB:17.4,collectorCash:20.88,receivable:17.4,cashRefund:10.44,originalDatesAndSellerPreserved:true});console.log("PASS: live transfer, history, authorization, refund and receipt reconciliation");

  const g=await fixture("categories"),invoices=[];
  for(const [owner,price,quantity,paid]of [["admin",50,1,58],["a",100,1,0],["inactive",12.5,2,10]]){const customer=await g.customer(owner);await g.draft(owner,owner,customer,{price,quantity,paid,discount:0});await g.call(owner,"confirmInvoice",{invoiceId:owner});invoices.push((await g.ref("invoices",owner).get()).data());}
  await db.doc(`users/${g.users.inactive.uid}`).update({active:false});await g.call("inactive","getDashboardSnapshot",{from:0,to:Date.now()},"PERMISSION_DENIED");
  await g.call("admin","confirmSalesReturn",{idempotencyKey:`return-${randomUUID()}`,originalInvoiceId:"inactive",refundType:"cash_refund",reason:runId,returnDate:"2026-11-07T10:00:00Z",items:[{originalInvoiceItemId:"inactive:line:line",returnedQuantity:1}]});
  const returns=(await db.collection(`companies/${g.companyId}/sales_returns`).get()).docs.map(d=>d.data());
  const sellerNet=Object.fromEntries(["admin","a","inactive"].map(name=>[name,money(invoices.filter(i=>i.salesRepId===g.users[name].uid).reduce((n,i)=>n+i.grandTotal,0)-returns.filter(r=>r.salesRepId===g.users[name].uid).reduce((n,r)=>n+r.grandTotal,0))]));assert.deepEqual(sellerNet,{admin:58,a:116,inactive:14.5});
  const dash=await g.dashboard("admin"),tax=money(invoices.reduce((n,i)=>n+i.totalTax,0)-returns.reduce((n,r)=>n+r.totalTax,0));
  assert.equal(dash.totalSales,188.5);assert.equal(dash.totalReceivables,120.5);assert.equal(dash.companyCash,58);assert.equal(dash.repCashOutstanding,10);assert.equal(dash.receiptCount,0);assert.equal(tax,26);assert.equal(money(dash.totalSales-tax),162.5);assert.equal(money(dash.salesByRepSummary.reduce((n,r)=>n+r.totalSales,0)),116);
  await ledger(g,{metricSales:188.5,metricReceivables:120.5});
  results.push({scenario:"admin-active-inactive-reconciliation",companyId:g.companyId,grossBilledIncludingTax:203,returnsIncludingTax:14.5,netBilledIncludingTax:188.5,netTax:26,netSalesExcludingTax:162.5,collections:68,receivables:120.5,sellerNet,activeRepTableSubtotal:116});console.log("PASS: live Admin, active and inactive reconciliation");

  const originalRepInvoice=invoices.find(i=>i.id==="a");
  await g.call("admin","createReceipt",{idempotencyKey:`receipt-${randomUUID()}`,customerId:originalRepInvoice.customerId,amount:100,paymentMethod:"cash",receiptDate:"2026-11-07T11:00:00Z"});
  const companyReturn=await g.call("admin","confirmSalesReturn",{idempotencyKey:`return-${randomUUID()}`,originalInvoiceId:"a",refundType:"cash_refund",reason:runId,returnDate:"2026-11-07T12:00:00Z",items:[{originalInvoiceItemId:"a:line:line",returnedQuantity:0.5}]});
  const companyRefund=(await g.ref("sales_returns",companyReturn.returnId).get()).data();assert.equal(companyRefund.salesRepId,g.users.a.uid);assert.equal(companyRefund.cashRefundAmount,42);assert.equal(companyRefund.receivableReduction,16);
  const companyRefundEntry=(await g.ref("financial_ledger_entries",`sales_return_${companyReturn.returnId}_cash_refund`).get()).data();assert.equal(companyRefundEntry.metricRepCashOut,0);assert.equal(companyRefundEntry.metricCompanyCashNet,-42);assert.equal((await g.ref("invoices","admin").get()).get("returnedTotal"),0);
  const companyDash=await g.dashboard("admin");assert.equal(companyDash.totalSales,130.5);assert.equal(companyDash.companyCash,116);assert.equal(companyDash.repCashOutstanding,10);assert.equal(companyDash.totalReceivables,4.5);
  await ledger(g,{metricSales:130.5,metricReceivables:4.5,metricCompanyCashNet:116});
  assert.equal(130.5,116+10+4.5);
  results.push({scenario:"company-cash-refund-for-original-representative",companyId:g.companyId,netBilledIncludingTax:130.5,companyCash:116,repCash:10,receivables:4.5,cashRefund:42,receivableReduction:16,adminSalesRetained:58});console.log("PASS: live company cash refund and original seller reconciliation");
  }

  const h=await fixture("inventory","default_company"),rep=h.users.a.uid;
  const existingLedger=await h.call("admin","getFinancialLedgerSummary",{from:0,to:Date.now()});
  const item=(await h.call("admin","createItem",{idempotencyKey:`item-${randomUUID()}`,name:`Synthetic acceptance ${runId}`,code:`SYN-${randomUUID()}`,description:runId,unit:"pcs",price:10,taxRate:16,currentStock:30,openingStock:30,minStock:0,costPrice:2,trackStock:true,active:true})).itemId;
  for(const adjustmentType of ["increase_stock","decrease_stock"])await h.call("admin","adjustStock",{idempotencyKey:`stock-${randomUUID()}`,itemId:item,adjustmentType,quantity:1,notes:runId});
  const transferId=`synthetic-${randomUUID()}`;
  const transferNumber=await h.allocate("admin","inventory_transfers","TRN");
  await h.create("admin","inventory_transfers",transferId,{id:transferId,companyId:h.companyId,transferNumber,year:2026,type:"warehouseToRep",status:"draft",salesRepId:rep,salesRepNameSnapshot:h.users.a.name,lines:[{itemId:item,quantity:10}],totalQuantity:10,notes:runId,createdByUid:h.users.admin.uid,createdByName:h.users.admin.name,confirmedByUid:"",confirmedByName:"",confirmedAt:null,cancelledByUid:"",cancelledAt:null,effectsVersion:1});
  await h.call("a","confirmInventoryTransfer",{transferId},"PERMISSION_DENIED");await h.call("admin","confirmInventoryTransfer",{transferId});assert.equal((await h.call("admin","confirmInventoryTransfer",{transferId})).alreadyPosted,true);
  const customer=await h.customer("a"),invoice=`synthetic-${randomUUID()}`;await h.draft("a",invoice,customer,{item});await h.call("a","confirmInvoice",{invoiceId:invoice});
  await h.call("admin","reassignCustomer",{customerId:customer,assignedToUid:h.users.b.uid,expectedAssignedToUid:rep,expectedAssignmentRevision:0,idempotencyKey:`transfer-${randomUUID()}`,reason:runId});
  assert.equal((await h.ref("rep_inventory_balances",`${rep}_${item}`).get()).get("quantity"),7);
  const returnInput={idempotencyKey:`return-${randomUUID()}`,originalInvoiceId:invoice,refundType:"credit_customer_balance",reason:runId,returnDate:"2026-11-07T10:00:00Z",items:[{originalInvoiceItemId:`${invoice}:line:line`,returnedQuantity:1}]};
  await h.call("b","confirmSalesReturn",returnInput,"PERMISSION_DENIED");
  const r=await h.call("admin","confirmSalesReturn",returnInput);
  assert.equal((await h.ref("sales_returns",r.returnId).get()).get("salesRepId"),rep);assert.equal((await db.doc(`items/${item}`).get()).get("currentStock"),20);assert.equal((await h.ref("rep_inventory_balances",`${rep}_${item}`).get()).get("quantity"),8);assert.equal((await h.ref("customers",customer).get()).get("currentBalance"),20.88);
  await h.get("b","rep_inventory_balances",`${rep}_${item}`,true);
  await h.get("b","invoices",invoice);await h.get("a","customers",customer,true);assert.equal((await h.dashboard("a")).totalSales,20.88);assert.equal((await h.dashboard("b")).totalSales,0);
  await ledger(h,{metricSales:money(existingLedger.metricSales+20.88),metricReceivables:money(existingLedger.metricReceivables+20.88)});
  const privatePassword=h.users.admin.password,command="Add-Type -AssemblyName System.Security; $v=[Console]::In.ReadToEnd(); [Console]::Out.Write([Convert]::ToBase64String([Security.Cryptography.ProtectedData]::Protect([Text.Encoding]::UTF8.GetBytes($v),$null,[Security.Cryptography.DataProtectionScope]::CurrentUser)))";
  fs.writeFileSync(path.join(dir,"ui-password.dpapi.b64"),cp.execFileSync("powershell.exe",["-NoProfile","-NonInteractive","-Command",command],{input:privatePassword,encoding:"utf8",windowsHide:true}));
  save(path.join(dir,"evidence/ui-login.json"),{email:h.users.admin.email,uid:h.users.admin.uid,companyId:h.companyId,syntheticOnly:true});
  results.push({scenario:"trusted-inventory-posting-and-return",companyId:h.companyId,itemId:item,warehouseQuantity:20,originalSellerCustodyQuantity:8,receivable:20.88,financialBalanceDirectWrites:0});console.log("PASS: live stock adjustment, custody, invoice and return");
  const output={passed:true,runId,runIds:[...(priorRunId?[priorRunId]:[]),runId],at:new Date().toISOString(),project:PROJECT,syntheticOnly:true,postedHistoryDeleted:false,results};save(path.join(dir,"evidence/live-acceptance.json"),output);console.log(JSON.stringify({status:"PASS_REAL_STAGING_ACCEPTANCE",scenarios:results.length,runId}));
 }finally{await db.terminate();await load("firebase-admin/app").deleteApp(app);}
}
if(require.main===module)main().catch(e=>{save(path.join(dir,"evidence/live-acceptance.failure.json"),{at:new Date().toISOString(),runId,completed:results,message:e.message});logError(e);});
