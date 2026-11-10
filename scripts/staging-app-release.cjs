"use strict";
// Latest Original app release: exact project/site, no business-data write route.
const S=require("./staging-release-support.cjs"),Q=require("./settlement-staging-security.cjs");
const {fs,path,root,PROJECT,NUMBER,check,hash,read,save,files,canonical,load,connect,publicRequest,logError}=S;
const dir=path.join(root,".staging",PROJECT,"application-20261110"),stateFile=path.join(dir,"state.json");
const state=()=>fs.existsSync(stateFile)?read(stateFile):{project:PROJECT};
const put=(key,value)=>{const s=state();s[key]=value;save(stateFile,s);};
const fnName=`projects/${PROJECT}/locations/us-central1/functions/recordCashSettlement`;
async function connection(write=false){const c=await connect(write);c.reader.quotaProjectId=PROJECT;return c;}
async function baseline() {
 check(!fs.existsSync(path.join(dir,"baseline.json")),"Baseline already captured; retain it");const c=await connection();
 const functions=await c.list(`https://cloudfunctions.googleapis.com/v2/projects/${PROJECT}/locations/us-central1/functions`,"functions");check(functions.length===36,"Expected 35 business functions and breakdown");
 const hosting=(await c.api(`https://firebasehosting.googleapis.com/v1beta1/sites/${PROJECT}/releases?pageSize=1`)).releases[0];
 const version=await c.api(`https://firebasehosting.googleapis.com/v1beta1/${hosting.version.name}`);
 const rules=await c.api(`https://firebaserules.googleapis.com/v1/projects/${PROJECT}/releases/cloud.firestore`);
 const control=await c.api(`https://firestore.googleapis.com/v1/${Q.CONTROL}`);check(control.fields?.enabled?.booleanValue===false,"Breakdown must remain closed");
 const prior=path.join(root,".staging",PROJECT,"current-release/candidate");
 check(["firestore.rules","firestore.indexes.json"].every(f=>hash(fs.readFileSync(path.join(root,f)))===hash(fs.readFileSync(path.join(prior,f)))),"Rules/index source differs; independently review before release");
 const financial=await Q.inspect();
 save(path.join(dir,"baseline.json"),{project:PROJECT,at:new Date().toISOString(),functions,hosting,hostingConfig:version.config,rules,controlUpdateTime:control.updateTime,
   financialDigest:financial.financialDigest,rulesSourceSha256:hash(fs.readFileSync(path.join(root,"firestore.rules"))),indexesSourceSha256:hash(fs.readFileSync(path.join(root,"firestore.indexes.json")))});
 const rollback=path.join(root,".staging",PROJECT,"current-release/rollback/safe-functions-current.zip");
 check(hash(fs.readFileSync(rollback))==="2faa245e1544384652a31be142353ca37b91d4d2dc621aee126c705348026f97","Patched rollback source mismatch");
 console.log(JSON.stringify({status:"BASELINE_CAPTURED",functions:36,rulesAndIndexes:"unchanged",hostingRollback:hosting.version.name}));
}
function prepareBackend() {
 check(fs.existsSync(path.join(dir,"baseline.json")),"Baseline required");const folder=path.join(dir,"record-function"),archive=path.join(dir,"record-function.zip");
 check(!fs.existsSync(archive),"Sealed backend already exists");
 for(const f of files(path.join(root,"functions/lib")).filter(p=>p.endsWith(".js"))) {const out=path.join(folder,"lib",path.relative(path.join(root,"functions/lib"),f));fs.mkdirSync(path.dirname(out),{recursive:true});fs.copyFileSync(f,out,fs.constants.COPYFILE_EXCL);}
 const pkg=read(path.join(root,"functions/package.json"));pkg.main="lib/record-staging-entry.cjs";delete pkg.scripts;save(path.join(folder,"package.json"),pkg);
 fs.copyFileSync(path.join(root,"functions/package-lock.json"),path.join(folder,"package-lock.json"));
 fs.writeFileSync(path.join(folder,"lib/record-staging-entry.cjs"),`"use strict";\nconst p="${PROJECT}",c=JSON.parse(process.env.FIREBASE_CONFIG||"{}"),t=[process.env.GCLOUD_PROJECT,process.env.GOOGLE_CLOUD_PROJECT].filter(Boolean);\nif(c.projectId!==p||!t.length||t.some(v=>v!==p))throw Error("Staging target mismatch");\nconst a=require("firebase-admin/app").initializeApp();if(a.options.projectId!==p)throw Error("SDK target mismatch");\nrequire("firebase-admin/firestore").getFirestore(a).settings({ignoreUndefinedProperties:true});\nexports.recordCashSettlement=require("./trusted/record_cash_settlement.js").recordCashSettlement;\n`);
 require("node:child_process").execFileSync("python",["-c","import pathlib,sys,zipfile; r=pathlib.Path(sys.argv[1]); z=zipfile.ZipFile(sys.argv[2],'x',zipfile.ZIP_DEFLATED); [z.write(p,p.relative_to(r).as_posix()) for p in sorted(r.rglob('*')) if p.is_file()]; z.close()",folder,archive]);
 put("backendCandidate",{archive,sha256:hash(fs.readFileSync(archive)),files:files(folder).map(f=>({path:path.relative(folder,f),sha256:hash(fs.readFileSync(f))}))});
 console.log(JSON.stringify({status:"ONE_FUNCTION_SEALED",function:"recordCashSettlement"}));
}
async function backend() {
 const s=state(),c=await connection(true),b=read(path.join(dir,"baseline.json")),target=b.functions.find(f=>f.name===fnName),m=s.backendCandidate;
 check(target&&m&&hash(fs.readFileSync(m.archive))===m.sha256,"Reviewed source and baseline required");
 const live=await c.api(`https://cloudfunctions.googleapis.com/v2/${fnName}`);
 if(!s.backendOperation) {
  check(live.serviceConfig.revision===target.serviceConfig.revision,"Function changed since baseline");
  const u=await c.api(`https://cloudfunctions.googleapis.com/v2/projects/${PROJECT}/locations/us-central1/functions:generateUploadUrl`,{method:"POST",write:true,data:{}});
  const url=new URL(u.uploadUrl);check(url.protocol==="https:"&&url.hostname==="storage.googleapis.com"&&u.storageSource?.bucket===`gcf-v2-uploads-${NUMBER}.us-central1.cloudfunctions.appspot.com`,"Unpinned upload");
  await load("gaxios").request({url:u.uploadUrl,method:"PUT",data:fs.readFileSync(m.archive),headers:{"content-type":"application/zip"},retry:false,timeout:60000,maxRedirects:0});
  const op=await c.api(`https://cloudfunctions.googleapis.com/v2/${fnName}?updateMask=buildConfig.source,buildConfig.serviceAccount,labels`,{method:"PATCH",write:true,data:{name:fnName,
   buildConfig:{source:{storageSource:u.storageSource},serviceAccount:target.buildConfig.serviceAccount},labels:{...target.labels,"deployment-tool":"original-app-20261110"}}});
  put("backendOperation",op.name);
 }
 const op=await c.api(`https://cloudfunctions.googleapis.com/v2/${state().backendOperation}`);if(!op.done){console.log(JSON.stringify({status:"BACKEND_PENDING"}));return;}
 check(!op.error,`Backend deployment failure: ${op.error?.message}`);const done=await c.api(`https://cloudfunctions.googleapis.com/v2/${fnName}`);
 check(done.state==="ACTIVE"&&JSON.stringify(canonical(done.serviceConfig))===JSON.stringify(canonical({...target.serviceConfig,revision:done.serviceConfig.revision})),"Business runtime configuration drift");
 put("backend",{revision:done.serviceConfig.revision,source:done.buildConfig.source,at:new Date().toISOString()});console.log(JSON.stringify({status:"ONE_FUNCTION_UPDATED",revision:done.serviceConfig.revision}));
}
function sealWeb() {
 const folder=path.join(root,"build/original-staging-current/web");check(fs.existsSync(path.join(folder,"main.dart.js")),"Fresh web build missing");
 put("webCandidate",{folder,files:files(folder).map(f=>({path:path.relative(folder,f).replaceAll("\\","/"),sha256:hash(fs.readFileSync(f))}))});console.log(JSON.stringify({status:"WEB_SEALED"}));
}
async function hosting() {
 const s=state(),b=read(path.join(dir,"baseline.json")),m=s.webCandidate,c=await connection(true);check(s.backend&&m,"Backend and web candidate required");
 for(const f of m.files)check(hash(fs.readFileSync(path.join(m.folder,f.path)))===f.sha256,"Web candidate changed");
 const base=`https://firebasehosting.googleapis.com/v1beta1/sites/${PROJECT}`;
 let version=s.hostingAttempt?await c.api(`https://firebasehosting.googleapis.com/v1beta1/${s.hostingAttempt}`):null;
 if(!version){version=await c.api(base+"/versions",{method:"POST",write:true,data:{config:b.hostingConfig,labels:{release:"original-app-20261110"}}});put("hostingAttempt",version.name);}
 check(version.name.startsWith(`sites/${PROJECT}/versions/`),"Hosting scope mismatch");
 if(version.status!=="FINALIZED") {
  const blobs=new Map(),map={};for(const f of m.files){const bytes=require("node:zlib").gzipSync(fs.readFileSync(path.join(m.folder,f.path)),{level:9}),sha=hash(bytes);map["/"+f.path]=sha;blobs.set(sha,bytes);}
  const populated=await c.api(`https://firebasehosting.googleapis.com/v1beta1/${version.name}:populateFiles`,{method:"POST",write:true,data:{files:map}});
  const u=new URL(populated.uploadUrl);check(u.protocol==="https:"&&u.hostname==="upload-firebasehosting.googleapis.com"&&u.pathname.includes(`/sites/${PROJECT}/versions/`),"Hosting upload outside staging");
  await S.mapLimit(populated.uploadRequiredHashes||[],async sha=>{check(blobs.has(sha),"Unknown upload hash");await c.api(populated.uploadUrl+"/"+sha,{method:"POST",write:true,data:blobs.get(sha),headers:{"content-type":"application/octet-stream"}});},4);
  await c.api(`https://firebasehosting.googleapis.com/v1beta1/${version.name}?updateMask=status`,{method:"PATCH",write:true,data:{status:"FINALIZED"}});
 }
 const latest=(await c.api(base+"/releases?pageSize=1")).releases?.[0];
 check(latest?.version?.name===b.hosting.version.name||latest?.version?.name===version.name,"Concurrent Hosting release detected");
 const released=latest.version.name===version.name?latest:await c.api(base+`/releases?versionName=${encodeURIComponent(version.name)}`,{method:"POST",write:true,data:{message:"Latest completed Original app; experimental accounting and breakdown off"}});
 put("hosting",{version:version.name,release:released.name,at:new Date().toISOString()});console.log(JSON.stringify({status:"HOSTING_LIVE",version:version.name,url:`https://${PROJECT}.web.app`}));
}
async function verify() {
 const c=await connection(),s=state(),b=read(path.join(dir,"baseline.json"));check(s.backend&&s.hosting,"Release incomplete");
 const functions=await c.list(`https://cloudfunctions.googleapis.com/v2/projects/${PROJECT}/locations/us-central1/functions`,"functions");check(functions.length===36,"Function count changed");
 for(const f of b.functions){const n=functions.find(x=>x.name===f.name);check(n&&n.state==="ACTIVE","Missing/inactive existing function");
  if(f.name!==fnName)check(n.serviceConfig.revision===f.serviceConfig.revision&&JSON.stringify(canonical(n.buildConfig.source))===JSON.stringify(canonical(f.buildConfig.source)),"Unrelated function redeployed");}
 const rules=await c.api(`https://firebaserules.googleapis.com/v1/projects/${PROJECT}/releases/cloud.firestore`);check(rules.rulesetName===b.rules.rulesetName,"Rules changed unexpectedly");
 const control=await c.api(`https://firestore.googleapis.com/v1/${Q.CONTROL}`);check(control.fields.enabled.booleanValue===false&&control.updateTime===b.controlUpdateTime,"Breakdown gate changed");
 const current=(await c.api(`https://firebasehosting.googleapis.com/v1beta1/sites/${PROJECT}/releases?pageSize=1`)).releases[0];check(current.version.name===s.hosting.version,"Wrong Hosting version");
 const verified=[];for(const name of ["index.html","main.dart.js","flutter_bootstrap.js","manifest.json","assets/AssetManifest.bin"]){const f=s.webCandidate.files.find(f=>f.path===name);check(f,"Sealed asset absent");
  const r=await publicRequest(`https://${PROJECT}.web.app/${name}`,{responseType:"arraybuffer"});check(r.status===200&&hash(Buffer.from(r.data))===f.sha256,"Live web asset mismatch");verified.push(name);}
 const financial=await Q.inspect();check(financial.financialDigest===b.financialDigest,"Financial history changed during release; investigate without corrections");
 const result={project:PROJECT,hosting:s.hosting,backend:s.backend,unchangedFunctions:35,rulesUnchanged:true,indexSourceUnchanged:true,financialDataUnchanged:true,breakdownEnabled:false,verifiedAssets:verified,at:new Date().toISOString()};
 save(path.join(root,"output/staging-current-20261110/deployment-verification.json"),result);console.log(JSON.stringify({status:"RELEASE_VERIFIED",unchangedFunctions:35,financialWrites:0}));
}
async function rollbackHosting() {
 const c=await connection(true),s=state(),b=read(path.join(dir,"baseline.json"));check(s.hosting&&!s.hostingRollback,"One recorded release required");
 const base=`https://firebasehosting.googleapis.com/v1beta1/sites/${PROJECT}`,old=await c.api(`https://firebasehosting.googleapis.com/v1beta1/${b.hosting.version.name}`);
 check(old.status==="FINALIZED"&&old.name.startsWith(`sites/${PROJECT}/versions/`),"Retained rollback version unavailable");
 const current=(await c.api(base+"/releases?pageSize=1")).releases[0];check(current.version.name===s.hosting.version,"Concurrent Hosting change; inspect before rollback");
 const release=await c.api(base+`/releases?versionName=${encodeURIComponent(old.name)}`,{method:"POST",write:true,data:{message:"Restore retained Original staging application version only"}});
 put("hostingRollback",{release:release.name,version:old.name,at:new Date().toISOString()});console.log(JSON.stringify({status:"STAGING_HOSTING_ROLLED_BACK",version:old.name}));
}
if(require.main===module){const actions={baseline,"prepare-backend":prepareBackend,backend,"seal-web":sealWeb,hosting,verify,"rollback-hosting":rollbackHosting};Promise.resolve().then(()=>{check(actions[process.argv[2]],"Explicit scoped action required");return actions[process.argv[2]]();}).catch(logError);}
module.exports={dir,connection,baseline,verify};
