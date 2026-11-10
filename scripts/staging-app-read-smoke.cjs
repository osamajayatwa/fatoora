"use strict";
// Existing administrator and bounded reads only. No posting probe or fixtures.
const S=require("./staging-release-support.cjs"),{root,path,fs,PROJECT,check,read,save,publicRequest,logError}=S;
const out=path.join(root,"output/staging-current-20261110/read-smoke.json");
async function run(){
 const config=read(path.join(root,"config/firebase/staging.web.json"));
 const password=require("node:child_process").execFileSync("powershell.exe",["-NoProfile","-ExecutionPolicy","Bypass","-File",path.join(root,"scripts/staging-password.ps1"),"-Mode","Unprotect"],
  {input:fs.readFileSync(path.join(root,".staging",PROJECT,"admin-password.dpapi"),"utf8"),encoding:"utf8",windowsHide:true}).trim();
 const login=await publicRequest(`https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=${config.FIREBASE_API_KEY}`,{method:"POST",data:{email:"admin@fatoora.com",password,returnSecureToken:true}});
 const expected=read(path.join(root,".staging",PROJECT,"provisioning-state.json")).adminUid;
 check(login.status===200&&login.data.localId===expected,"Existing admin authentication failed");
 const token=login.data.idToken,headers={authorization:`Bearer ${token}`},results=[];
 const parent=`https://firestore.googleapis.com/v1/projects/${PROJECT}/databases/(default)/documents/companies/default_company`;
 for(const collection of ["invoices","receipts","sales_returns","expenses","items","inventory_transfers","cash_movements","settlements","financial_ledger_entries"]){
  const queryParent=collection==="items"?parent.split("/companies/")[0]:parent;
  const start=performance.now(),r=await publicRequest(queryParent+":runQuery",{method:"POST",headers,data:{structuredQuery:{from:[{collectionId:collection}],limit:20}},validateStatus:()=>true});
  check(r.status===200&&Array.isArray(r.data),`Authorized ${collection} read failed (${r.status})`);
  const docs=r.data.filter(d=>d.document);check(docs.every(d=>d.document.name.startsWith(`projects/${PROJECT}/databases/(default)/documents/${collection==="items"?"":"companies/default_company/"}${collection}/`)),"Mixed-company result");
  results.push({area:collection,status:"PASS",returned:docs.length,boundedAt:20,milliseconds:Math.round(performance.now()-start)});
 }
 const dates={companyId:"default_company",from:"2026-01-01T00:00:00Z",to:"2026-12-31T23:59:59Z"};
 for(const [name,data]of [["getDashboardSnapshot",dates],["getFinancialLedgerSummary",dates],["listAccessibleCustomers",{companyId:"default_company",pageSize:10,order:"id"}]]) {
  const start=performance.now(),r=await publicRequest(`https://us-central1-${PROJECT}.cloudfunctions.net/${name}`,{method:"POST",headers,data:{data},validateStatus:()=>true});
  check(r.status===200&&r.data.result!==undefined&&!r.data.error,`Read callable ${name} failed (${r.data.error?.status||r.status})`);
  results.push({area:name,status:"PASS",withoutAppCheck:true,milliseconds:Math.round(performance.now()-start)});
 }
 const cors=await publicRequest(`https://us-central1-${PROJECT}.cloudfunctions.net/getDashboardSnapshot`,{method:"OPTIONS",headers:{Origin:`https://${PROJECT}.web.app`,"Access-Control-Request-Method":"POST","Access-Control-Request-Headers":"authorization,content-type"},validateStatus:()=>true});
 check([200,204].includes(cors.status),"Browser CORS preflight failed");
 const result={project:PROJECT,existingUserAuthentication:"PASS",results,browserCors:"PASS",financialWrites:0,authProvider:"existing staging administrator; no credentials saved",at:new Date().toISOString()};save(out,result);console.log(JSON.stringify({status:"AUTH_AND_BUSINESS_READS_PASS",checks:results.length,financialWrites:0}));
}
if(require.main===module)run().catch(logError);
