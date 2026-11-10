"use strict";
// One new read-only callable, closed by security configuration. Never a whole
// Firebase deployment, financial write, Rules/index change or Hosting release.
const S=require("./staging-release-support.cjs"),Q=require("./settlement-staging-security.cjs");
const {fs,path,root,PROJECT,NUMBER,hash,read,save,check,load,logError}=S;
const candidate=path.join(Q.dir,"candidate-v2"),manifestFile=path.join(Q.dir,"candidate-manifest-v2.json"),stateFile=path.join(Q.dir,"deployment-v2.json");
const functionUrl=`https://cloudfunctions.googleapis.com/v2/${Q.FN}`;
const runService=`projects/${PROJECT}/locations/us-central1/services/getsettlementbreakdown`;
const uploadBucket=`gcf-v2-uploads-${NUMBER}.us-central1.cloudfunctions.appspot.com`;
function guard(url,method,data) {
 const u=new URL(url);check(u.protocol==="https:"&&!u.username&&!u.password&&!u.hash,"Pinned staging HTTPS required");
 const create=u.hostname==="cloudfunctions.googleapis.com"&&u.pathname===`/v2/projects/${PROJECT}/locations/us-central1/functions`&&u.search==="?functionId=getSettlementBreakdown"&&method==="POST";
 const control=u.hostname==="firestore.googleapis.com"&&u.pathname===`/v1/${Q.CONTROL}`&&method==="PATCH";
 const invoker=u.hostname==="run.googleapis.com"&&u.pathname===`/v2/${runService}:setIamPolicy`&&method==="POST";
 check(create||control||invoker,"Outside single settlement deployment scope");
 if(create) {
   check(data?.name===Q.FN&&data.buildConfig?.runtime==="nodejs22"&&data.buildConfig.entryPoint==="getSettlementBreakdown"&&
     data.buildConfig.serviceAccount===`projects/${PROJECT}/serviceAccounts/fatoora-staging-builder@${PROJECT}.iam.gserviceaccount.com`&&
     data.buildConfig.source?.storageSource?.bucket===uploadBucket&&
     data.serviceConfig?.serviceAccountEmail===Q.ACCOUNT&&data.serviceConfig.maxInstanceCount===1&&data.serviceConfig.maxInstanceRequestConcurrency===2&&
     data.serviceConfig.availableMemory==="512Mi"&&data.serviceConfig.availableCpu==="1"&&data.serviceConfig.timeoutSeconds===60&&
     JSON.stringify(data.serviceConfig.environmentVariables)===JSON.stringify({GCLOUD_PROJECT:PROJECT,FATOORA_SETTLEMENT_READ_TRANSPORT:"phase2b15-staging-pilot",FATOORA_SETTLEMENT_RUNTIME_ACCOUNT:Q.ACCOUNT})&&
     Object.keys(data).sort().join(",")==="buildConfig,labels,name,serviceConfig"&&Object.keys(data.buildConfig).sort().join(",")==="entryPoint,runtime,serviceAccount,source"&&
     Object.keys(data.serviceConfig).sort().join(",")==="availableCpu,availableMemory,environmentVariables,maxInstanceCount,maxInstanceRequestConcurrency,serviceAccountEmail,timeoutSeconds",
   "Unreviewed runtime, entry point, resource limits or environment");
 }
 if(control) {
   check(u.searchParams.get("currentDocument.exists")==="false"&&[...u.searchParams].length===1&&data?.name===Q.CONTROL&&Object.keys(data).length===2,
     "Only creation of the initially CLOSED security document is permitted");
   const f=data.fields;check(f&&Object.keys(f).sort().join(",")==="allowedAppIds,allowedUids,companyId,enabled,expiresAtMillis,revision,schemaVersion"&&
     JSON.stringify(f.enabled)==='{"booleanValue":false}'&&JSON.stringify(f.companyId)==='{"stringValue":"default_company"}'&&JSON.stringify(f.schemaVersion)==='{"integerValue":"1"}'&&
     /^[a-f0-9]{64}$/.test(f.revision?.stringValue)&&/^\d{13}$/.test(f.expiresAtMillis?.integerValue)&&
     f.allowedUids?.arrayValue?.values?.length===1&&/^[A-Za-z0-9_-]{1,128}$/.test(f.allowedUids.arrayValue.values[0]?.stringValue)&&
     JSON.stringify(f.allowedAppIds)==='{"arrayValue":{"values":[{"stringValue":"1:5438538531:web:1fb5d6aac646d3b1240296"},{"stringValue":"1:5438538531:android:560f7feecdb97bf5240296"}]}}',
   "Unapproved or financial security document contents");
 }
 if(invoker)check(data?.policy?.etag&&data.policy.bindings?.length===1&&JSON.stringify(data.policy.bindings[0])==='{"role":"roles/run.invoker","members":["allUsers"]}'&&
   Object.keys(data).length===1,"Only the new App-Check-enforced callable may receive public invocation");
}
function prepare() {
 check(!fs.existsSync(manifestFile),"Candidate already sealed; do not overwrite evidence");
 const copy=(source,target)=>{fs.mkdirSync(path.dirname(target),{recursive:true});fs.copyFileSync(source,target,fs.constants.COPYFILE_EXCL);};
 for(const f of S.files(path.join(root,"functions/lib")).filter(f=>f.endsWith(".js")))copy(f,path.join(candidate,"lib",path.relative(path.join(root,"functions/lib"),f)));
 const pkg=read(path.join(root,"functions/package.json"));pkg.main="lib/settlement_read_entry.js";delete pkg.scripts;
 save(path.join(candidate,"package.json"),pkg);copy(path.join(root,"functions/package-lock.json"),path.join(candidate,"package-lock.json"));
 check(fs.readFileSync(path.join(candidate,"lib/settlement_read_entry.js"),"utf8").includes('Object.defineProperty(exports, "getSettlementBreakdown"'),"Dedicated read entry missing");
 const entries=S.files(candidate).map(f=>({path:path.relative(candidate,f).replaceAll("\\","/"),sha256:hash(fs.readFileSync(f))})).sort((a,b)=>a.path.localeCompare(b.path));
 const archive=path.join(Q.dir,"settlement-read-only-v2.zip");
 require("node:child_process").execFileSync("python",["-c","import pathlib,sys,zipfile; r=pathlib.Path(sys.argv[1]); z=zipfile.ZipFile(sys.argv[2],'x',zipfile.ZIP_DEFLATED); [z.write(p,p.relative_to(r).as_posix()) for p in sorted(r.rglob('*')) if p.is_file()]; z.close()",candidate,archive]);
 save(manifestFile,{project:PROJECT,function:Q.FN,main:pkg.main,financialWrites:false,controlEnabled:false,entries,archive:{path:archive,sha256:hash(fs.readFileSync(archive))},at:new Date().toISOString()});
 console.log(JSON.stringify({status:"SEALED",files:entries.length,archiveSha256:hash(fs.readFileSync(archive))}));
}
function sealed() {
 const m=read(manifestFile);check(m.project===PROJECT&&m.function===Q.FN&&m.financialWrites===false&&m.controlEnabled===false,"Candidate identity mismatch");
 check(S.files(candidate).length===m.entries.length&&m.entries.every(e=>hash(fs.readFileSync(path.join(candidate,e.path)))===e.sha256)&&hash(fs.readFileSync(m.archive.path))===m.archive.sha256,"Sealed candidate changed");return m;
}
async function deploy() {
 const m=sealed(),baseline=read(path.join(Q.dir,"baseline.json")),permissions=read(path.join(Q.dir,"runtime-permissions.json"));
 check(permissions.results.length===11&&permissions.results.every(p=>["datastore.databases.get","datastore.entities.get","datastore.entities.list","firebaseauth.users.get"].includes(p.permission)?
   p.allow==="ALLOW_ACCESS_STATE_GRANTED"&&["CAN_ACCESS","UNKNOWN_INFO"].includes(p.access):p.access==="CANNOT_ACCESS"),"Read grants and effective write denials required; runtime canary must verify read availability before activation");
 const c=await S.connect(true);c.reader.quotaProjectId=PROJECT;
 const stage=fs.existsSync(stateFile)?read(stateFile):{};
 const current=await c.list(`https://cloudfunctions.googleapis.com/v2/projects/${PROJECT}/locations/us-central1/functions`,"functions");
 check(baseline.functions.length===35&&baseline.functions.every(f=>current.some(n=>n.name===f.name&&n.serviceConfig?.revision===f.revision)),"Existing functions changed; stop deployment");
 // Creating this security document is the ONLY Firestore mutation in this tool.
 const controlUrl=`https://firestore.googleapis.com/v1/${Q.CONTROL}`;
 let control;try{control=await c.api(controlUrl);}catch(e){if(e.response?.status!==404)throw e;}
 if(!control) {
   const data={name:Q.CONTROL,fields:{schemaVersion:{integerValue:"1"},enabled:{booleanValue:false},companyId:{stringValue:"default_company"},
     revision:{stringValue:require("node:crypto").randomBytes(32).toString("hex")},expiresAtMillis:{integerValue:String(Date.now()+3600000)},
     allowedUids:{arrayValue:{values:[{stringValue:c.state.adminUid}]}},allowedAppIds:{arrayValue:{values:[
       {stringValue:"1:5438538531:web:1fb5d6aac646d3b1240296"},{stringValue:"1:5438538531:android:560f7feecdb97bf5240296"}]}}}};
   const url=controlUrl+"?currentDocument.exists=false";guard(url,"PATCH",data);
   control=(await c.reader.request({url,method:"PATCH",data,retry:false,timeout:30000})).data;
 }
 check(control.fields?.enabled?.booleanValue===false,"Closed security control required");
 if(!stage.operation) {
   check(!current.some(f=>f.name===Q.FN),"Function already exists without this operation record; inspect instead of replacing");
   if(!stage.upload) {
     const u=await c.api(`https://cloudfunctions.googleapis.com/v2/projects/${PROJECT}/locations/us-central1/functions:generateUploadUrl`,{method:"POST",write:true,data:{}});
     const target=new URL(u.uploadUrl);check(target.protocol==="https:"&&target.hostname==="storage.googleapis.com"&&target.pathname.includes(NUMBER)&&u.storageSource?.bucket===uploadBucket,"Unpinned source upload");
     await load("gaxios").request({url:u.uploadUrl,method:"PUT",data:fs.readFileSync(m.archive.path),headers:{"content-type":"application/zip"},retry:false,timeout:60000,maxRedirects:0});
     stage.upload=u.storageSource;save(stateFile,stage);
   }
   const data={name:Q.FN,buildConfig:{runtime:"nodejs22",entryPoint:"getSettlementBreakdown",source:{storageSource:stage.upload},
     serviceAccount:`projects/${PROJECT}/serviceAccounts/fatoora-staging-builder@${PROJECT}.iam.gserviceaccount.com`},
     serviceConfig:{serviceAccountEmail:Q.ACCOUNT,availableMemory:"512Mi",availableCpu:"1",timeoutSeconds:60,maxInstanceCount:1,maxInstanceRequestConcurrency:2,
       environmentVariables:{GCLOUD_PROJECT:PROJECT,FATOORA_SETTLEMENT_READ_TRANSPORT:"phase2b15-staging-pilot",FATOORA_SETTLEMENT_RUNTIME_ACCOUNT:Q.ACCOUNT}},
     labels:{"deployment-tool":"phase2b15-read-only","firebase-functions-codebase":"settlement-read-only"}};
   const url=functionUrl.replace("/getSettlementBreakdown","")+"?functionId=getSettlementBreakdown";guard(url,"POST",data);
   const op=await c.api(url,{method:"POST",write:true,data});stage.operation=op.name;stage.archiveSha256=m.archive.sha256;save(stateFile,stage);
 }
 const operation=await c.api(`https://cloudfunctions.googleapis.com/v2/${stage.operation}`);
 if(!operation.done){console.log(JSON.stringify({status:"DEPLOYMENT_PENDING",operation:stage.operation}));return;}
 check(!operation.error,`Deployment failed: ${operation.error?.message}`);
 const fn=await c.api(functionUrl);check(fn.state==="ACTIVE"&&fn.serviceConfig?.serviceAccountEmail===Q.ACCOUNT&&fn.serviceConfig.maxInstanceCount===1&&
   fn.serviceConfig.maxInstanceRequestConcurrency===2&&fn.serviceConfig.environmentVariables.FATOORA_SETTLEMENT_READ_TRANSPORT==="phase2b15-staging-pilot"&&
   fn.serviceConfig.service===runService,"Deployed runtime differs from reviewed configuration");
 const policyUrl=`https://run.googleapis.com/v2/${runService}:getIamPolicy`,policy=await c.api(policyUrl);
 if(!policy.bindings?.some(b=>b.role==="roles/run.invoker"&&b.members?.includes("allUsers"))) {
   check(!policy.bindings?.length,"Unexpected new-service policy; do not replace");
   const data={policy:{...policy,bindings:[{role:"roles/run.invoker",members:["allUsers"]}]}};
   const url=policyUrl.replace(":getIamPolicy",":setIamPolicy");guard(url,"POST",data);
   await c.reader.request({url,method:"POST",data,retry:false,timeout:30000});
 }
 stage.completedAt=new Date().toISOString();stage.revision=fn.serviceConfig.revision;stage.controlEnabled=false;save(stateFile,stage);
 console.log(JSON.stringify({status:"DEPLOYED_CLOSED",function:"getSettlementBreakdown",revision:stage.revision}));
}
if(require.main===module)Promise.resolve().then(()=>{const action=process.argv[2];check(["prepare","deploy"].includes(action),"Explicit single-function action required");return action==="prepare"?prepare():deploy();}).catch(logError);
module.exports={guard,prepare,sealed,deploy};
