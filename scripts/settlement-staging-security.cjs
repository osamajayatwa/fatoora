"use strict";
// Phase 2B-15: exact staging control-plane scope. No financial write route.
const S = require("./staging-release-support.cjs");
const {fs,path,root,PROJECT,NUMBER,hash,read,save,check,connect,load,logError} = S;
const dir = path.join(root,".staging",PROJECT,"settlement-read-release");
const ACCOUNT = `fatoora-settlement-reader@${PROJECT}.iam.gserviceaccount.com`;
const ROLE = `projects/${PROJECT}/roles/fatooraSettlementReadOnly`;
const PERMISSIONS = Object.freeze(["datastore.databases.get","datastore.entities.get","datastore.entities.list","firebaseauth.users.get"]);
const WRITE_PERMISSIONS=Object.freeze(["datastore.entities.create","datastore.entities.update","datastore.entities.delete","datastore.databases.update","firebaseauth.users.create","firebaseauth.users.update","firebaseauth.users.delete"]);
const CONTROL = `projects/${PROJECT}/databases/(default)/documents/internal_read_controls/settlement_breakdown`;
const FN = `projects/${PROJECT}/locations/us-central1/functions/getSettlementBreakdown`;
const APP_CONFIGS=[
 `projects/${NUMBER}/apps/1:5438538531:web:1fb5d6aac646d3b1240296/recaptchaV3Config`,
 `projects/${NUMBER}/apps/1:5438538531:web:1fb5d6aac646d3b1240296/recaptchaEnterpriseConfig`,
 `projects/${NUMBER}/apps/1:5438538531:android:560f7feecdb97bf5240296/playIntegrityConfig`,
];
const policyChanges=new WeakMap();
const serviceOperations=new Set();
const SECURITY_SERVICES=["firebaseappcheck.googleapis.com","policytroubleshooter.googleapis.com"];
function guard(url,method="GET",data) {
 const u=new URL(url);check(u.protocol==="https:"&&!u.username&&!u.password&&!u.hash,"Pinned HTTPS required");
 const prefix=`/v1/projects/${PROJECT}`, iam=u.hostname==="iam.googleapis.com";
 const service=`${prefix}/serviceAccounts/${ACCOUNT}`, role=`${prefix}/roles/fatooraSettlementReadOnly`;
 const project=`/v3/projects/${PROJECT}`;
 const get = method==="GET" && (iam && [service,role].includes(u.pathname) ||
   u.hostname==="firebaseappcheck.googleapis.com" && APP_CONFIGS.some(name=>u.pathname===`/v1/${name}`) ||
   u.hostname==="serviceusage.googleapis.com"&&(SECURITY_SERVICES.some(s=>u.pathname===`/v1/projects/${NUMBER}/services/${s}`)||serviceOperations.has(u.pathname)));
 const enableAppCheck=method==="POST"&&u.hostname==="serviceusage.googleapis.com"&&
   SECURITY_SERVICES.some(s=>u.pathname===`/v1/projects/${NUMBER}/services/${s}:enable`)&&JSON.stringify(data)==="{}";
 const createSA = iam && method==="POST" && u.pathname===`${prefix}/serviceAccounts` &&
   data?.accountId==="fatoora-settlement-reader" && JSON.stringify(data.serviceAccount)==='{"displayName":"Settlement evidence read-only runtime"}' && Object.keys(data).length===2;
 const createRole = iam && method==="POST" && u.pathname===`${prefix}/roles` && data?.roleId==="fatooraSettlementReadOnly" &&
   data.role?.title==="Settlement evidence read only" && data.role.stage==="GA" &&
   JSON.stringify(data.role.includedPermissions)===JSON.stringify(PERMISSIONS) && Object.keys(data.role).length===3 && Object.keys(data).length===2;
 const getPolicy = method==="POST" && JSON.stringify(data)==="{}" && (iam && u.pathname===service+":getIamPolicy" ||
   u.hostname==="cloudresourcemanager.googleapis.com" && u.pathname===project+":getIamPolicy");
 const q=data?.structuredQuery;
 const troubleshoot=method==="POST"&&u.hostname==="policytroubleshooter.googleapis.com"&&u.pathname==="/v3/iam:troubleshoot"&&
   Object.keys(data||{}).length===1&&Object.keys(data.accessTuple||{}).length===3&&data.accessTuple.principal===ACCOUNT&&
   data.accessTuple.fullResourceName===`//cloudresourcemanager.googleapis.com/projects/${PROJECT}`&&[...PERMISSIONS,...WRITE_PERMISSIONS].includes(data.accessTuple.permission);
 const financialRead=method==="POST"&&u.hostname==="firestore.googleapis.com"&&
   u.pathname===`/v1/projects/${PROJECT}/databases/(default)/documents/companies/default_company:runQuery`&&
   Object.keys(data).length===1&&q&&Object.keys(q).length===2&&q.limit===65&&q.from?.length===1&&Object.keys(q.from[0]).length===1&&
   ["cash_movements","cash_balances","invoices","receipts","sales_returns","expenses","settlements","books"].includes(q.from[0].collectionId);
 const setPolicy = method==="POST" && (iam && u.pathname===service+":setIamPolicy" ||
   u.hostname==="cloudresourcemanager.googleapis.com" && u.pathname===project+":setIamPolicy");
 // IAM updates are additionally diff-checked against the just-read etag in security().
 check(get||createSA||createRole||getPolicy||setPolicy||financialRead||enableAppCheck||troubleshoot,"Outside settlement security control scope");
 if(setPolicy) {
   const change=policyChanges.get(data?.policy);
   check(data?.policy?.etag&&Array.isArray(data.policy.bindings)&&Object.keys(data).length===1&&change&&
     (iam?change.role==="roles/iam.serviceAccountUser"&&change.member===`serviceAccount:fatoora-staging-deployer@${PROJECT}.iam.gserviceaccount.com`:
       change.role===ROLE&&change.member===`serviceAccount:${ACCOUNT}`),"Fresh, diff-checked, target-bound IAM addition required");
 }
}
async function connection() {
 const c=await connect(false);
 c.reader.quotaProjectId=PROJECT;
 const request=async (url,method="GET",data) => {
   guard(url,method,data);const result=(await c.reader.request({url,method,data,retry:method==="GET",timeout:60000})).data;
   if(method==="POST"&&SECURITY_SERVICES.some(s=>url.endsWith(`/services/${s}:enable`))&&/^operations\/[A-Za-z0-9._-]+$/.test(result.name)) serviceOperations.add(`/v1/${result.name}`);
   return result;
 };
 return {...c,request};
}
async function inspect() {
 const c=await connection(), functions=await c.list(`https://cloudfunctions.googleapis.com/v2/projects/${PROJECT}/locations/us-central1/functions`,"functions");
 const documents=`https://firestore.googleapis.com/v1/projects/${PROJECT}/databases/(default)/documents`, records=[];
 const company=await c.api(documents+"/companies/default_company");records.push({name:company.name,sha256:hash(JSON.stringify(S.canonical(company)))});
 const collections={};
 for(const collection of ["cash_movements","cash_balances","invoices","receipts","sales_returns","expenses","settlements","books"]) {
   const rows=await c.request(documents+"/companies/default_company:runQuery","POST",{structuredQuery:{from:[{collectionId:collection}],limit:65}});
   const docs=rows.filter(r=>r.document).map(r=>r.document);check(docs.length<65,"Financial inspection bound exceeded; no partial baseline");collections[collection]=docs.length;
   records.push(...docs.map(d=>({name:d.name,sha256:hash(JSON.stringify(S.canonical(d)))})));
 }
 const appCheck=[];for(const name of APP_CONFIGS) {
   try {appCheck.push({name,configuration:await c.request(`https://firebaseappcheck.googleapis.com/v1/${name}`)});}
   catch(e){appCheck.push({name,unavailable:true,httpStatus:e.response?.status,reason:e.response?.data?.error?.status,
     details:e.response?.data?.error?.details?.map(d=>({reason:d.reason,domain:d.domain}))});}
 }
 const appCheckService=await c.request(`https://serviceusage.googleapis.com/v1/projects/${NUMBER}/services/firebaseappcheck.googleapis.com`);
 const iam=await c.request(`https://cloudresourcemanager.googleapis.com/v3/projects/${PROJECT}:getIamPolicy`,"POST",{});
 const result={project:PROJECT,at:new Date().toISOString(),collections,financialDigest:hash(JSON.stringify(records.sort((a,b)=>a.name.localeCompare(b.name)))),records,
   functions:functions.map(f=>({name:f.name,revision:f.serviceConfig?.revision,source:f.buildConfig?.source,serviceAccount:f.serviceConfig?.serviceAccountEmail})),
   appCheck,appCheckService:appCheckService.state,readerBindings:iam.bindings?.filter(b=>b.members?.includes(`serviceAccount:${ACCOUNT}`))||[]};
 const file=path.join(dir,"inspection-latest.json");save(file,result);
 if(!fs.existsSync(path.join(dir,"baseline.json"))) save(path.join(dir,"baseline.json"),result);
 console.log(JSON.stringify({status:"INSPECTED",collections,functions:functions.length,appCheck:appCheck.map(c=>({provider:c.name.split("/").at(-1),available:!c.unavailable,httpStatus:c.httpStatus})),financialDigest:result.financialDigest}));
 return result;
}
function addBinding(policy,role,member) {
 check(role===ROLE&&member===`serviceAccount:${ACCOUNT}`||role==="roles/iam.serviceAccountUser"&&
   member===`serviceAccount:fatoora-staging-deployer@${PROJECT}.iam.gserviceaccount.com`,"Unapproved IAM addition");
 check(policy.etag&&(policy.bindings===undefined||Array.isArray(policy.bindings)),"Incomplete IAM policy");
 const originalPolicy=policy;
 if(policy.bindings===undefined)policy={...policy,bindings:[]};
 const next=structuredClone(policy);let binding=next.bindings.find(b=>b.role===role&&!b.condition);
 if(!binding){binding={role,members:[]};next.bindings.push(binding);}if(!binding.members.includes(member))binding.members.push(member);
 // Preserve every original role/member/condition; precisely one allowlisted addition.
 const before=structuredClone(next),added=before.bindings.find(b=>b.role===role&&!b.condition);
 added.members=added.members.filter(m=>m!==member);
 const original=policy.bindings.find(b=>b.role===role&&!b.condition);
 if(original?.members.includes(member)) return originalPolicy;
 if(!original)before.bindings=before.bindings.filter(b=>b!==added);
 check(JSON.stringify(S.canonical(before))===JSON.stringify(S.canonical(policy)),"Unrelated IAM policy change refused");
 policyChanges.set(next,{role,member});return next;
}
async function security() {
 const c=await connection();check(fs.existsSync(path.join(dir,"baseline.json")),"Read-only baseline required");
 const accountUrl=`https://iam.googleapis.com/v1/projects/${PROJECT}/serviceAccounts/${ACCOUNT}`;
 let account;try{account=await c.request(accountUrl);}catch(e){if(e.response?.status!==404)throw e;
   account=await c.request(`https://iam.googleapis.com/v1/projects/${PROJECT}/serviceAccounts`,"POST",{accountId:"fatoora-settlement-reader",serviceAccount:{displayName:"Settlement evidence read-only runtime"}});}
 check(account.email===ACCOUNT&&account.projectId===PROJECT&&!account.disabled,"Read runtime identity mismatch");
 const roleUrl=`https://iam.googleapis.com/v1/${ROLE}`;let role;
 try{role=await c.request(roleUrl);}catch(e){if(e.response?.status!==404)throw e;
   role=await c.request(`https://iam.googleapis.com/v1/projects/${PROJECT}/roles`,"POST",{roleId:"fatooraSettlementReadOnly",role:{title:"Settlement evidence read only",stage:"GA",includedPermissions:PERMISSIONS}});}
 check(!role.deleted&&JSON.stringify([...role.includedPermissions].sort())===JSON.stringify([...PERMISSIONS].sort()),"Read-only role has unexpected permissions");
 for(const [url,roleName,member] of [
   [`https://cloudresourcemanager.googleapis.com/v3/projects/${PROJECT}`,ROLE,`serviceAccount:${ACCOUNT}`],
   [accountUrl,"roles/iam.serviceAccountUser",`serviceAccount:${c.state.deployer}`],
 ]) {
   const policy=await c.request(url+":getIamPolicy","POST",{}),next=addBinding(policy,roleName,member);
   if(next!==policy)await c.request(url+":setIamPolicy","POST",{policy:next});
 }
 const final=await c.request(`https://cloudresourcemanager.googleapis.com/v3/projects/${PROJECT}:getIamPolicy`,"POST",{});
 const bindings=final.bindings.filter(b=>b.members?.includes(`serviceAccount:${ACCOUNT}`));
 check(bindings.length===1&&bindings[0].role===ROLE&&!bindings[0].condition,"Unexpected runtime authority; deployment blocked");
 const result={project:PROJECT,account:ACCOUNT,role:ROLE,permissions:PERMISSIONS,bindings,at:new Date().toISOString()};save(path.join(dir,"security.json"),result);
 console.log(JSON.stringify({status:"READ_IDENTITY_READY",account:ACCOUNT,permissions:PERMISSIONS}));
}
async function verifyRuntimePermissions() {
 const c=await connection();
 const results=[];
 for(const permission of [...PERMISSIONS,...WRITE_PERMISSIONS]) {
   const r=await c.request("https://policytroubleshooter.googleapis.com/v3/iam:troubleshoot","POST",{accessTuple:{principal:ACCOUNT,
     fullResourceName:`//cloudresourcemanager.googleapis.com/projects/${PROJECT}`,permission}});
   results.push({permission,access:r.overallAccessState,allow:r.allowPolicyExplanation?.allowAccessState,deny:r.denyPolicyExplanation?.denyAccessState});
 }
 const proof={project:PROJECT,account:ACCOUNT,results,method:"read-only IAM policy troubleshooter; no impersonation grant or data-write probe",at:new Date().toISOString()};
 save(path.join(dir,"runtime-permissions.json"),proof);
 check(results.every(r=>r.access===(PERMISSIONS.includes(r.permission)?"CAN_ACCESS":"CANNOT_ACCESS")),"Effective runtime read/write policy check is incomplete or unsafe");
 console.log(JSON.stringify({status:"EFFECTIVE_READ_ONLY_VERIFIED",readPermissions:PERMISSIONS.length,writePermissionsDenied:WRITE_PERMISSIONS.length}));
}
async function enableAppCheck(service="firebaseappcheck.googleapis.com") {
 check(SECURITY_SERVICES.includes(service),"Unapproved security API");
 const c=await connection(),url=`https://serviceusage.googleapis.com/v1/projects/${NUMBER}/services/${service}`;
 const before=await c.request(url);let operation;
 if(before.state!=="ENABLED") {
   operation=await c.request(url+":enable","POST",{});save(path.join(dir,service+"-enable.json"),{project:PROJECT,operation:operation.name,at:new Date().toISOString()});
   for(let i=0;!operation.done&&i<20;i++){await new Promise(r=>setTimeout(r,2000));operation=await c.request(`https://serviceusage.googleapis.com/v1/${operation.name}`);}
   check(operation.done&&!operation.error,"App Check API activation not confirmed");
 }
 check((await c.request(url)).state==="ENABLED","Security API remains disabled");console.log(JSON.stringify({status:"SECURITY_API_ENABLED",service,project:PROJECT}));
}
if(require.main===module){const action=process.argv[2];Promise.resolve().then(()=>{check(["inspect","security","enable-appcheck","enable-policy-analysis","verify-runtime"].includes(action),"Explicit scoped action required");return action==="inspect"?inspect():action==="security"?security():action==="verify-runtime"?verifyRuntimePermissions():enableAppCheck(action==="enable-policy-analysis"?"policytroubleshooter.googleapis.com":"firebaseappcheck.googleapis.com");}).catch(logError);}
module.exports={guard,addBinding,PERMISSIONS,ACCOUNT,ROLE,CONTROL,FN,dir,connection,inspect,security};
