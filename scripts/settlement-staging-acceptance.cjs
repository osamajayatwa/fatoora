"use strict";
// Controlled security acceptance only. No synthetic financial records, user
// mutations, provider bypass, data correction or positive financial certification.
const S=require("./staging-release-support.cjs"),Q=require("./settlement-staging-security.cjs");
const {PROJECT,root,path,fs,save,read,check,logError}=S;
const output=path.join(root,"output/phase2b15");
const loggingFilter='resource.type="cloud_run_revision" AND resource.labels.service_name="getsettlementbreakdown" AND (jsonPayload.event="settlement_reader_canary_passed" OR jsonPayload.event="settlement_reader_canary_failed" OR textPayload:"settlement_reader_canary")';
function guardLog(url,data) {
 check(url==="https://logging.googleapis.com/v2/entries:list"&&Object.keys(data||{}).sort().join(",")==="filter,orderBy,pageSize,resourceNames"&&
   JSON.stringify(data.resourceNames)===JSON.stringify([`projects/${PROJECT}`])&&data.filter===loggingFilter&&data.pageSize===20&&data.orderBy==="timestamp desc",
 "Only bounded settlement-reader canary logs are allowed");
}
async function canary(c) {
 const url="https://logging.googleapis.com/v2/entries:list",data={resourceNames:[`projects/${PROJECT}`],filter:loggingFilter,orderBy:"timestamp desc",pageSize:20};guardLog(url,data);
 const logs=(await c.reader.request({url,method:"POST",data,retry:false,timeout:30000})).data;
 const rows=(logs.entries||[]).map(e=>({at:e.timestamp,revision:e.resource?.labels?.revision_name,
   event:e.jsonPayload?.event||(/settlement_reader_canary_passed/.test(e.textPayload||"")?"settlement_reader_canary_passed":"settlement_reader_canary_failed")}));
 save(path.join(output,"runtime-canary.json"),{project:PROJECT,entries:rows});return rows;
}
async function run() {
 const c=await Q.connection(),deployment=read(path.join(Q.dir,"deployment-v2.json"));check(deployment.completedAt&&deployment.controlEnabled===false,"Closed completed deployment required");
 const before=await c.api(`https://firestore.googleapis.com/v1/${Q.CONTROL}`);check(before.fields?.enabled?.booleanValue===false,"Feature must remain closed");
 const url=`https://us-central1-${PROJECT}.cloudfunctions.net/getSettlementBreakdown`;
 const data={data:{schemaVersion:2,action:"start",companyId:"default_company",salesRepId:"unavailable",settlementId:"unavailable"}},results=[];
 async function probe(name,headers={}) {
   const start=performance.now();let response;
   try {response=await S.publicRequest(url,{method:"POST",data,headers:{"content-type":"application/json",...headers},validateStatus:()=>true});}
   catch(e){throw new Error(`Controlled ${name} probe failed (${e.code||"network"})`);}
   check([401,403].includes(response.status)&&!response.data?.result&&response.data?.error?.status==="UNAUTHENTICATED",`Unexpected sensitive or successful ${name} result`);
   results.push({case:name,httpStatus:response.status,status:response.data.error.status,milliseconds:Math.round(performance.now()-start),responseBytes:Buffer.byteLength(JSON.stringify(response.data))});
 }
 await probe("anonymous_missing_attestation");
 // Existing staging admin only. DPAPI plaintext and ID/refresh tokens remain in
 // memory and are never printed or saved. Sign-in changes Auth metadata only.
 const password=require("node:child_process").execFileSync("powershell.exe",["-NoProfile","-ExecutionPolicy","Bypass","-File",path.join(root,"scripts/staging-password.ps1"),"-Mode","Unprotect"],
   {input:fs.readFileSync(path.join(root,".staging",PROJECT,"admin-password.dpapi"),"utf8"),encoding:"utf8",windowsHide:true}).trim();
 const config=read(path.join(root,"config/firebase/staging.web.json"));
 const login=await S.publicRequest(`https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=${config.FIREBASE_API_KEY}`,
   {method:"POST",data:{email:"admin@fatoora.com",password,returnSecureToken:true},validateStatus:()=>true});
 check(login.status===200&&login.data?.localId===c.state.adminUid&&typeof login.data.idToken==="string","Existing staging admin sign-in not verified");
 await probe("authenticated_admin_missing_attestation",{authorization:`Bearer ${login.data.idToken}`});
 await probe("authenticated_admin_forged_attestation",{authorization:`Bearer ${login.data.idToken}`,"X-Firebase-AppCheck":"invalid"});
 const rows=await canary(c);check(rows.some(e=>e.event==="settlement_reader_canary_passed"&&e.revision===deployment.revision),"Actual runtime read canary has not passed for this revision");
 const after=await c.api(`https://firestore.googleapis.com/v1/${Q.CONTROL}`);check(after.updateTime===before.updateTime&&after.fields.enabled.booleanValue===false,"Control changed during acceptance");
 const report={project:PROJECT,revision:deployment.revision,scope:"security acceptance only; no financial result or PDF certified",featureEnabled:false,
   probes:results,runtimeCanary:"passed",financialWrites:0,productionRequests:0,authMetadataSignIns:1,at:new Date().toISOString()};
 save(path.join(output,"staging-security-acceptance.json"),report);console.log(JSON.stringify({status:"CLOSED_SECURITY_ACCEPTANCE_PASSED",probes:results.length,runtimeCanary:"passed",financialWrites:0}));
}
if(require.main===module)run().catch(logError);
module.exports={guardLog,run};
