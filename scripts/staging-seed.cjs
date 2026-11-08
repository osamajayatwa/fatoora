"use strict";
// Remote create-only bootstrap for the single approved, pinned staging project.
// The existing emulator-only bootstrap retains its independent remote-write refusal.
const fs=require("node:fs"),path=require("node:path"),crypto=require("node:crypto"),{spawnSync}=require("node:child_process");
const {context,validateLocal,verifyProject,client,readState,save,hash,check,PROJECT}=require("./staging-cloud.cjs");
const root=path.resolve(__dirname,".."),load=require("node:module").createRequire(path.join(root,"functions/package.json"));
const {validateBundle,targetItem}=load("./scripts/local_test_environment.js");
const COMPANY="default_company",EMAIL="admin@fatoora.com",NAME="Staging Administrator";
const HISTORY=["customers","invoices","quotations","receipts","sales_returns","expenses","cash_movements","cash_balances",
  "settlements","customer_transactions","inventory_transfers","rep_inventory_balances","rep_inventory_movements","stock_movements",
  "financial_ledger_entries","financial_ledger_search_entries","financial_books","financial_policies","financial_journals","receivables","custody"];
const passwordPath=path.join(root,".staging/fatoora-original-staging/admin-password.dpapi");
function passwordProcess(mode,input) {
  const r=spawnSync("powershell.exe",["-NoProfile","-NonInteractive","-ExecutionPolicy","Bypass","-File",path.join(__dirname,"staging-password.ps1"),"-Mode",mode],
    {input,encoding:"utf8",windowsHide:true});
  check(r.status===0 && r.stdout.length>0,"Windows DPAPI operation failed; no credential was printed");return r.stdout;
}
function getPassword(){return passwordProcess("Unprotect",fs.readFileSync(passwordPath,"utf8"));}
function stagingItem(row,uid,runId) {
  const data=targetItem(row);
  data.stagingCatalogHash=data.localTestCatalogHash;delete data.localTestCatalogHash;
  Object.assign(data,{createdBy:uid,createdByUid:uid,createdByName:NAME,updatedByUid:uid,updatedByName:NAME,stagingProvisioningRunId:runId});
  return data;
}
function equal(a,b){return JSON.stringify(stable(a))===JSON.stringify(stable(b));}
function stable(v){if(Array.isArray(v))return v.map(stable);if(v&&typeof v==="object")return Object.fromEntries(Object.keys(v).sort().map(k=>[k,stable(v[k])]));return v;}
async function emptyHistory(db) {
  for(const collection of HISTORY) for(const prefix of ["",`companies/${COMPANY}/`]) {
    check((await db.collection(prefix+collection).limit(1).get()).empty,`History is not empty: ${prefix+collection}; no overwrite or reset allowed`);
  }
  const companies=await db.collection("companies").get();check(companies.docs.every(d=>d.id===COMPANY),"Unexpected company exists");
  const allowed=["companies","users","items"];
  check((await db.listCollections()).every(c=>allowed.includes(c.id)),"Unexpected root collection exists");
}
async function sdk(c) {
  c.quotaProjectId=PROJECT;
  const {GoogleAuth}=load("google-auth-library");
  const {Firestore}=load("@google-cloud/firestore");
  const db=new Firestore({projectId:PROJECT,preferRest:true,auth:new GoogleAuth({authClient:c,projectId:PROJECT})});
  const {initializeApp}=load("firebase-admin/app");
  const app=initializeApp({projectId:PROJECT,credential:{getAccessToken:async()=>{
    const t=await c.getAccessToken();return {access_token:t.token,expires_in:Math.max(60,Math.floor(((c.credentials.expiry_date||Date.now()+3600000)-Date.now())/1000))};
  }}},"original-staging-provisioning");
  const auth=load("firebase-admin/auth").getAuth(app);
  check(db.projectId===PROJECT && auth.app.options.projectId===PROJECT,"SDK target mismatch");
  return {db,auth,app};
}
async function seed(s,m,db,auth) {
  check(s.functionsVerified && s.indexesVerified && !s.adminActivated,"Verified deployed backend required; active environments cannot be reseeded");
  await emptyHistory(db);
  const catalog=validateBundle(JSON.parse(fs.readFileSync(path.join(root,m.catalog.path))));
  check(catalog.items.length===91 && catalog.items.filter(r=>r.data.active&&!r.data.deleted).length===90 && catalog.items.filter(r=>r.data.deleted).length===1,"Catalog boundary mismatch");
  if(!s.adminUid) {
    check((await auth.listUsers(2)).users.length===0 && !fs.existsSync(passwordPath),"Unexpected existing Auth identity or credential file");
    s.adminUid=crypto.randomUUID();s.adminCreateAttempt={at:new Date().toISOString(),uid:s.adminUid};
    fs.writeFileSync(passwordPath,passwordProcess("Protect",`Aa7!${crypto.randomBytes(32).toString("base64url")}`),{flag:"wx"});save(s);
  }
  let account;
  try{account=await auth.getUser(s.adminUid);}catch(e){if(e.code!=="auth/user-not-found")throw e;}
  if(!account)account=await auth.createUser({uid:s.adminUid,email:EMAIL,password:getPassword(),displayName:NAME,disabled:true});
  check(account.uid===s.adminUid && account.email===EMAIL && account.disabled && !account.customClaims && account.providerData.every(p=>p.providerId==="password"),"Independent disabled admin identity mismatch");
  const {FieldValue}=load("firebase-admin/firestore"),stamp=()=>FieldValue.serverTimestamp();
  const profile={uid:s.adminUid,name:NAME,email:EMAIL,phone:"",photoUrl:"",role:"admin",approvalStatus:"approved",active:false,companyId:COMPANY,stagingProvisioningRunId:s.runId};
  const company={id:COMPANY,name:"Fatoora Original Staging",stagingProvisioningRunId:s.runId};
  const settings={companyId:COMPANY,schemaVersion:1,companySettings:{name:"Fatoora Original Staging",email:EMAIL,country:"",website:"",phone:"",address:"",logoEnabled:false},
    jofotaraStatusSettings:{enabled:false,status:"not_configured"},updatedByUid:s.adminUid,updatedByName:NAME,stagingProvisioningRunId:s.runId};
  const expected=new Map([[`companies/${COMPANY}`,company],[`companies/${COMPANY}/settings/app`,settings],[`users/${s.adminUid}`,profile],
    ...catalog.items.map(r=>[`items/${r.id}`,stagingItem(r,s.adminUid,s.runId)])]);
  const existingItems=await db.collection("items").get();
  check(existingItems.docs.every(d=>expected.has(d.ref.path)),"Unrelated catalog document exists");
  const users=await db.collection("users").get();check(users.docs.every(d=>d.id===s.adminUid),"Unexpected profile exists");
  const additions=[];
  for(const [p,wanted]of expected){const ref=db.doc(p),existing=await ref.get();if(existing.exists){check(Object.entries(wanted).every(([k,v])=>equal(existing.get(k),v)),`Owned document changed: ${p}; refusing to overwrite`);}else additions.push([ref,wanted]);}
  check(expected.size===94 && additions.length<=94,"Seed write budget exceeded");
  s.seedAttempt={at:new Date().toISOString(),createOnlyDocuments:additions.length};save(s);
  if(additions.length){const batch=db.batch();for(const [ref,data]of additions)batch.create(ref,{...data,createdAt:stamp(),updatedAt:stamp(),...(ref.parent.id==="items"?{inventoryUpdatedAt:stamp()}: {})});await batch.commit();}
  const marker=db.doc(`companies/${COMPANY}/financial_ledger_account_activity_metadata/current`);
  if(!(await marker.get()).exists) {
    const result=await load("./lib/maintenance/rebuild_financial_ledger_account_activity.js").runFinancialLedgerAccountActivityBackfill({projectId:PROJECT,companyId:COMPANY,apply:true,confirmProject:PROJECT,confirmCompany:COMPANY,pageSize:200,maxWrites:1},db);
    check(result.scannedEntries===0 && result.maximumPlannedWrites===1 && result.appliedEntries===0,"Empty-ledger one-write initializer failed");
  }
  s.seedCommitted=true;save(s);
  console.log(JSON.stringify({status:"CREATE_ONLY_SEED_COMMITTED",catalogItems:91,explicitDocuments:95,zeroInventory:true,historyDocumentsCreated:0,adminUid:s.adminUid,adminDisabled:true,passwordStorage:"Windows DPAPI; never logged"}));
}
async function verifySeed(s,m,db,auth) {
  check(s.seedCommitted,"Seed has not committed");await emptyHistory(db);
  const source=validateBundle(JSON.parse(fs.readFileSync(path.join(root,m.catalog.path))));
  const items=await db.collection("items").get();check(items.size===91,"Catalog count mismatch");
  const wanted=new Map(source.items.map(r=>[r.id,stagingItem(r,s.adminUid,s.runId)]));
  for(const doc of items.docs){const data=doc.data(),row=wanted.get(doc.id);check(row && Object.entries(row).every(([k,v])=>equal(data[k],v)),`Catalog/provenance/zero-stock mismatch: ${doc.id}`);
    check(data.createdAt?.toMillis()>=new Date(s.createdAt).getTime() && data.updatedAt?.toMillis()>=new Date(s.createdAt).getTime() && !Object.hasOwn(data,"localTestCatalogHash"),"Catalog source timestamps or emulator metadata survived");}
  const account=await auth.getUser(s.adminUid),profile=await db.doc(`users/${s.adminUid}`).get();
  check(account.uid===s.adminUid && account.email===EMAIL && profile.get("role")==="admin" && profile.get("approvalStatus")==="approved" && profile.get("companyId")===COMPANY,"Admin profile mismatch");
  check((await auth.listUsers(2)).users.length===1 && (await db.collection("users").get()).size===1,"Unexpected identity/profile count");
  check((await db.doc(`companies/${COMPANY}`).get()).get("stagingProvisioningRunId")===s.runId,"Company ownership mismatch");
  const settings=(await db.doc(`companies/${COMPANY}/settings/app`).get()).data();check(settings.companySettings.name==="Fatoora Original Staging" && settings.jofotaraStatusSettings.enabled===false,"Settings mismatch");
  const marker=await db.doc(`companies/${COMPANY}/financial_ledger_account_activity_metadata/current`).get();
  check(marker.get("status")==="ready" && marker.get("sourceEntryCount")===0,"Empty-ledger readiness marker mismatch");
  const audits=await db.collection(`companies/${COMPANY}/audit_events`).get();
  check(audits.size>=92,"Audit triggers have not completed or did not run");
  s.seedVerified=true;s.seedVerification={at:new Date().toISOString(),catalogDefinitions:91,activeDefinitions:90,deletedDefinitions:1,zeroStock:true,emptyHistory:true,companies:1,authUsers:1,auditEvents:audits.size};save(s);
  console.log(JSON.stringify({status:"STAGING_SEED_VERIFIED",...s.seedVerification,adminDisabled:account.disabled,profileActive:profile.get("active")}));
}
async function main(){const action=process.argv[2];check(process.argv.length===3&&["seed","verify"].includes(action),"Explicit seed/verify action required");const m=context();validateLocal();const s=readState(),c=await client();await verifyProject(c,s);const {db,auth,app}=await sdk(c);try{if(action==="seed")await seed(s,m,db,auth);else await verifySeed(s,m,db,auth);}finally{await db.terminate();await load("firebase-admin/app").deleteApp(app);}}
if(require.main===module)main().catch(e=>{console.error(JSON.stringify({status:"BLOCKED",code:e.code,message:e.message}));process.exitCode=1;});
module.exports={stagingItem,getPassword,sdk,emptyHistory,verifySeed};
