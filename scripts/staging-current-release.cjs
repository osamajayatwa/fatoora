"use strict";
const S=require("./staging-release-support.cjs");
const {fs,path,root,dir,PROJECT,NUMBER,load,mapLimit,check,hash,read,save,files,canonical,connect,publicRequest,logError}=S;
const cp=require("node:child_process"),zlib=require("node:zlib");
const candidate=path.join(dir,"candidate"),stateFile=path.join(dir,"release-state.json");
const state=()=>fs.existsSync(stateFile)?read(stateFile):{project:PROJECT,number:NUMBER,startedAt:new Date().toISOString()};
function update(key,value){const s=state();s[key]=value;save(stateFile,s);return s;}
function text(file){const b=fs.readFileSync(file);return b[0]===255?b.toString("utf16le").slice(1):b.toString("utf8");}
function tested(){
 check(/# pass 686\b/.test(text(path.join(dir,"evidence/backend-test.after.log")))&&/# fail 0\b/.test(text(path.join(dir,"evidence/backend-test.after.log"))),"Impacted backend regressions incomplete");
 check(/# pass 2\b/.test(text(path.join(dir,"evidence/http-e2e.after.log")))&&/# fail 0\b/.test(text(path.join(dir,"evidence/http-e2e.after.log"))),"Auth/HTTP/Rules/trigger regressions incomplete");
 const audit=JSON.parse(text(path.join(dir,"evidence/npm-audit.after.json")));check(audit.metadata.vulnerabilities.total===0,"Runtime audit must have zero findings");
 const prior=read(path.join(dir,"verification-checkpoint.json"));
 for(const [name,sha]of Object.entries(prior.sourceHashes)){
  const n=name.replaceAll("\\","/");if(n.startsWith("lib/")||n.startsWith("test/")&&n.endsWith(".dart")||n.startsWith("assets/")||n.startsWith("web/")||["pubspec.yaml","pubspec.lock"].includes(n))check(hash(fs.readFileSync(path.join(root,n)))===sha,`Reused Flutter evidence changed: ${n}`);
 }
 check(prior.checks.flutterTests.pass===573&&prior.checks.flutterAnalysis==="PASS","Missing unaffected Flutter evidence");
 check(read(path.join(dir,"rollback/verification.json")).status==="PASS_ARTIFACT_CAPTURE","Complete rollback capture required");
 check(read(path.join(dir,"evidence/runtime-before.json")).functions.length===35,"Actual deployed runtime baseline required");
}
function verify(){
 const manifest=read(path.join(candidate,"SHA256SUMS.json"));
 for(const [name,sha]of Object.entries(manifest))check(hash(fs.readFileSync(path.join(candidate,name)))===sha,`Candidate changed: ${name}`);
 return manifest;
}
function safety(){
 verify();tested();
 check(JSON.parse(text(path.join(dir,"evidence/production-audit.json"))).metadata.vulnerabilities.total===0,"Clean production install security gate failed");
 check(read(path.join(dir,"evidence/direct-framework-smoke.json")).passed===true,"Pinned framework authentication compatibility not verified");
 check(read(path.join(dir,"evidence/deployer-permissions.json")).passed===true,"Required staging deployer permissions missing");
 check(read(path.join(dir,"rollback/safe-rollback-plan.json")).reviewed===true,"Safe rollback plan not verified");
}
function prepare(){
 tested();check(!fs.existsSync(path.join(candidate,"SHA256SUMS.json")),"Candidate is sealed");
 for(const folder of ["src","shared","lib"])fs.cpSync(path.join(root,"functions",folder),path.join(candidate,"functions",folder),{recursive:true});
 const pkg=read(path.join(root,"functions/package.json"));pkg.main="lib/staging-entry.cjs";
 check(pkg.dependencies["firebase-admin"]==="^12.7.0"&&pkg.dependencies["firebase-functions"]==="^5.1.1"&&pkg.dependencies["@google-cloud/functions-framework"]==="3.5.1","Unreviewed SDK/framework upgrade");
 save(path.join(candidate,"functions/package.json"),pkg);
 fs.copyFileSync(path.join(root,"functions/package-lock.json"),path.join(candidate,"functions/package-lock.json"));
 fs.copyFileSync(path.join(root,"config/firebase/staging-runtime.cjs"),path.join(candidate,"functions/lib/staging-entry.cjs"));
 for(const file of ["firestore.rules","firestore.indexes.json"])fs.copyFileSync(path.join(root,file),path.join(candidate,file));
 check(fs.existsSync(path.join(candidate,"web/main.dart.js")),"Web build is incomplete");
 save(path.join(candidate,"firebase.json"),{functions:[{source:"functions",codebase:PROJECT}],firestore:{rules:"firestore.rules",indexes:"firestore.indexes.json"},hosting:{site:PROJECT,public:"web",rewrites:[{source:"**",destination:"/index.html"}]}});
 const manifest=Object.fromEntries(files(candidate).filter(f=>!f.includes(`${path.sep}node_modules${path.sep}`)).map(f=>[path.relative(candidate,f).replaceAll("\\","/"),hash(fs.readFileSync(f))]));
 save(path.join(candidate,"SHA256SUMS.json"),manifest);update("prepared",{at:new Date().toISOString(),manifestSha256:hash(fs.readFileSync(path.join(candidate,"SHA256SUMS.json"))),files:Object.keys(manifest).length});
 const zip=path.join(dir,"functions-current.zip");
 cp.execFileSync("python",["-c","import zipfile,sys,pathlib\nb=pathlib.Path(sys.argv[1])\nwith zipfile.ZipFile(sys.argv[2],'w',zipfile.ZIP_DEFLATED) as z:\n for p in sorted(b.rglob('*')):\n  if p.is_file() and 'node_modules' not in p.parts: z.write(p,p.relative_to(b).as_posix())",path.join(candidate,"functions"),zip]);
 update("sourceArchive",{path:zip,sha256:hash(fs.readFileSync(zip)),size:fs.statSync(zip).size});
 console.log(JSON.stringify({status:"SEALED_CURRENT_APPLICATION",files:Object.keys(manifest).length,functions:35}));
}
async function sdk(reader){
 const credential={getAccessToken:async()=>{const t=await reader.getAccessToken();return {access_token:t.token,expires_in:3300};}};
 const app=load("firebase-admin/app").initializeApp({projectId:PROJECT,credential},`release-${Date.now()}`);
 const db=new(load("@google-cloud/firestore").Firestore)({projectId:PROJECT,preferRest:true,auth:new(load("google-auth-library").GoogleAuth)({projectId:PROJECT,authClient:reader})});
 return {app,db,auth:load("firebase-admin/auth").getAuth(app)};
}
async function inventorySnapshot(db,auth){
 const documents={};let count=0;
 async function reliable(action){for(let attempt=0;;attempt++){try{return await action();}catch(e){if(attempt>=2||!["ECONNRESET","ETIMEDOUT","EAI_AGAIN",4,14].includes(e.code))throw e;await new Promise(r=>setTimeout(r,1000));}}}
 async function visit(collection){
  const refs=await reliable(()=>collection.listDocuments());
  const snapshots=[];for(let i=0;i<refs.length;i+=100)snapshots.push(...await reliable(()=>db.getAll(...refs.slice(i,i+100))));
  await mapLimit(snapshots,async d=>{if(d.exists){check(++count<20000,"Staging snapshot read limit exceeded");documents[d.ref.path]={hash:hash(Buffer.from(JSON.stringify(canonical(d.data())))),updateTime:d.updateTime.toDate().toISOString()};}
   for(const sub of await reliable(()=>d.ref.listCollections()))await visit(sub);
  },8);
 }
 await mapLimit(await reliable(()=>db.listCollections()),visit,3);
 const users=[];let nextPageToken;do{const page=await auth.listUsers(1000,nextPageToken);users.push(...page.users.map(u=>({uid:u.uid,email:u.email,disabled:u.disabled,customClaims:u.customClaims||{},providers:u.providerData})));nextPageToken=page.pageToken;}while(nextPageToken);
 return {at:new Date().toISOString(),project:PROJECT,documents,users:users.sort((a,b)=>a.uid.localeCompare(b.uid))};
}
async function baseline(){
 verify();const {reader,api}=await connect(),{app,db,auth}=await sdk(reader);
 try{
  const result=await inventorySnapshot(db,auth);save(path.join(dir,"evidence/data-before.json"),result);
  const rollback=read(path.join(dir,"rollback/baseline.json"));
  const current=await api(`https://firebasehosting.googleapis.com/v1beta1/${rollback.hosting.version.name}`);
  check(current.status==="FINALIZED","Rollback Hosting version is not retained");
  update("baseline",{at:new Date().toISOString(),existingDocuments:Object.keys(result.documents).length,existingUsers:result.users.length,hostingRollbackVersion:current.name});
  console.log(JSON.stringify({status:"STAGING_BASELINE_CAPTURED",documents:Object.keys(result.documents).length,users:result.users.length,hostingRollbackVersion:current.name}));
 }finally{await db.terminate();await load("firebase-admin/app").deleteApp(app);}
}
function indexKey(i){return JSON.stringify(canonical({collectionGroup:i.collectionGroup||i.name.split("/collectionGroups/")[1].split("/")[0],queryScope:i.queryScope,fields:i.fields.filter(f=>f.fieldPath!=="__name__")}));}
async function indexes(create){
 verify();check(state().baseline,"Data and rollback baseline required");const {api,list}=await connect(create);
 const url=`https://firestore.googleapis.com/v1/projects/${PROJECT}/databases/(default)/collectionGroups/-/indexes`;
 const existing=await list(url,"indexes"),desired=read(path.join(candidate,"firestore.indexes.json")).indexes;
 check(desired.length===300,"Unexpected index manifest");const desiredKeys=new Set(desired.map(indexKey)),liveKeys=new Set(existing.map(indexKey));
 check(existing.every(i=>desiredKeys.has(indexKey(i))),"Unexpected staging indexes; preserve and review drift");
 const missing=desired.filter(i=>!liveKeys.has(indexKey(i)));check(missing.length<=32&&missing.every(i=>i.collectionGroup==="invoices"&&i.queryScope==="COLLECTION"),"Unreviewed index additions");
 if(create){
  const previous=state().indexes||{operations:[]};
  for(const index of missing){
   const op=await api(`https://firestore.googleapis.com/v1/projects/${PROJECT}/databases/(default)/collectionGroups/invoices/indexes`,{method:"POST",write:true,data:{queryScope:index.queryScope,fields:index.fields}});
   previous.operations.push({name:op.name,index});update("indexes",previous);
  }
 }
 const ready=existing.length===300&&existing.every(i=>i.state==="READY")&&missing.length===0;
 if(ready)update("indexesReady",{at:new Date().toISOString(),count:300});
 console.log(JSON.stringify({status:ready?"INDEXES_READY":"INDEXES_PENDING",existing:existing.length,ready:existing.filter(i=>i.state==="READY").length,missing:missing.length,submitted:create?missing.length:0}));
}
async function rules(){
 safety();check(state().indexesReady&&read(path.join(dir,"evidence/native-query-readiness.json")).queryPlans.every(p=>p.status==="PASS"),"Native index/query readiness required");
 const {api}=await connect(true),content=fs.readFileSync(path.join(candidate,"firestore.rules"),"utf8");
 const previous=await api(`https://firebaserules.googleapis.com/v1/projects/${PROJECT}/releases/cloud.firestore`);
 const base=read(path.join(dir,"rollback/baseline.json"));check(previous.rulesetName===base.release.rulesetName,"Rules changed after review");
 const created=await api(`https://firebaserules.googleapis.com/v1/projects/${PROJECT}/rulesets`,{method:"POST",write:true,data:{source:{files:[{name:"firestore.rules",content}]}}});
 update("rulesAttempt",{ruleset:created.name});
 const release=await api(`https://firebaserules.googleapis.com/v1/projects/${PROJECT}/releases/cloud.firestore`,{method:"PATCH",write:true,data:{release:{name:`projects/${PROJECT}/releases/cloud.firestore`,rulesetName:created.name},updateMask:"rulesetName"}});
 const live=await api(`https://firebaserules.googleapis.com/v1/projects/${PROJECT}/releases/cloud.firestore`);check(live.rulesetName===created.name,"Rules activation not confirmed");
 update("rules",{at:new Date().toISOString(),ruleset:created.name});console.log(JSON.stringify({status:"RULES_RELEASED",ruleset:live.rulesetName}));
}
async function functions(){
 safety();check(state().rules&&state().indexesReady,"Rules and index gates required");const {api,writer}=await connect(true);
 const base=read(path.join(dir,"rollback/baseline.json")),source=state().sourceArchive,bytes=fs.readFileSync(source.path);check(hash(bytes)===source.sha256,"Functions archive changed");
 let upload=state().uploadedSource;
 if(!upload){
  let u;try{u=await api(`https://cloudfunctions.googleapis.com/v2/projects/${PROJECT}/locations/us-central1/functions:generateUploadUrl`,{method:"POST",write:true,data:{}});}catch(e){e.message=`Source-upload URL gate: ${e.response?.data?.error?.message||e.message}`;throw e;}
  const target=new URL(u.uploadUrl);check(target.protocol==="https:"&&target.hostname==="storage.googleapis.com"&&target.pathname.includes(NUMBER),"Upload bucket is not dedicated staging");
  try{await load("gaxios").request({url:u.uploadUrl,method:"PUT",data:bytes,headers:{"content-type":"application/zip"},responseType:"text",retry:false,timeout:60000,agent:new(require("node:https").Agent)({family:4})});}
  catch(e){const body=typeof e.response?.data==="string"?e.response.data:"";const code=body.match(/<Code>([^<]+)<\/Code>/)?.[1],message=body.match(/<Message>([^<]+)<\/Message>/)?.[1];e.message=`Signed staging source upload: ${code||e.response?.status||e.code}: ${message||"upload rejected"}`;throw e;}
  upload=u.storageSource;check(upload?.bucket?.includes(NUMBER),"Uploaded Functions source target mismatch");update("uploadedSource",upload);
 }
 const ordered=[...base.functions].sort((a,b)=>a.name.endsWith("/confirmSalesReturn")?-1:b.name.endsWith("/confirmSalesReturn")?1:a.name.localeCompare(b.name));
 async function deploy(f){
  let record=state().functions?.[f.name];if(record?.completed)return;
  const live=await api(`https://cloudfunctions.googleapis.com/v2/${f.name}`);
  if(!record){
   check(live.state==="ACTIVE","Function is not ready for a controlled update");
   check(live.serviceConfig.revision===f.serviceConfig.revision&&JSON.stringify(canonical(live.buildConfig.source))===JSON.stringify(canonical(f.buildConfig.source)),"Function changed since baseline");
   check(f.buildConfig.serviceAccount===`projects/${PROJECT}/serviceAccounts/fatoora-staging-builder@${PROJECT}.iam.gserviceaccount.com`,"Builder identity changed");
   const labels={...f.labels,"firebase-functions-hash":require("node:crypto").createHash("sha1").update(bytes).digest("hex")};
   const op=await api(`https://cloudfunctions.googleapis.com/v2/${f.name}?updateMask=buildConfig.source,buildConfig.serviceAccount,labels`,{method:"PATCH",write:true,data:{name:f.name,buildConfig:{source:{storageSource:upload},serviceAccount:f.buildConfig.serviceAccount},labels}});
   record={operation:op.name,startedAt:new Date().toISOString()};const s=state();s.functions||={};s.functions[f.name]=record;save(stateFile,s);
  }
  for(;;){const op=await api(`https://cloudfunctions.googleapis.com/v2/${record.operation}`);if(op.done){check(!op.error,`Function deployment failed: ${f.name}: ${op.error?.message}`);break;}await new Promise(r=>setTimeout(r,5000));}
  const done=await api(`https://cloudfunctions.googleapis.com/v2/${f.name}`);check(done.state==="ACTIVE"&&done.serviceConfig.serviceAccountEmail===f.serviceConfig.serviceAccountEmail,"Runtime activation/identity gate failed");
  const s=state();s.functions[f.name]={...record,completed:true,revision:done.serviceConfig.revision,build:done.buildConfig.build,completedAt:new Date().toISOString()};save(stateFile,s);
  console.log(JSON.stringify({status:"FUNCTION_ACTIVE",function:f.name.split("/").pop(),revision:done.serviceConfig.revision}));
 }
 // First activate the changed posting function, then patch the unchanged services.
 await deploy(ordered[0]);let failed=false;
 await mapLimit(ordered.slice(1),async f=>{if(failed)return;try{await deploy(f);}catch(e){failed=true;throw e;}},3);
 check(Object.values(state().functions||{}).filter(f=>f.completed).length===35,"Not all necessary Functions activated");update("functionsReady",{at:new Date().toISOString(),count:35});
}
async function hosting(){
 safety();check(state().functionsReady&&read(path.join(dir,"evidence/runtime-after.json")).status==="PASS_DEPLOYED_RUNTIME","Verified patched live runtimes required");
 check(read(path.join(dir,"evidence/live-acceptance.json")).passed===true,"Real backend acceptance required before Hosting activation");
 check(read(path.join(dir,"evidence/preservation-after-acceptance.json")).passed===true,"Final business-data preservation gate required");
 const {api}=await connect(true),site=`sites/${PROJECT}`,base=`https://firebasehosting.googleapis.com/v1beta1/${site}`;
 check(!state().hosting,"Hosting already activated");
 let version=state().hostingAttempt?await api(`https://firebasehosting.googleapis.com/v1beta1/${state().hostingAttempt.version}`):null;
 if(!version){version=await api(`${base}/versions`,{method:"POST",write:true,data:{config:{rewrites:[{glob:"**",path:"/index.html"}]},labels:{release:"current-application-security"}}});update("hostingAttempt",{version:version.name});}
 check(version.name.startsWith(site+"/versions/"),"Hosting target mismatch");
 const blobs=new Map(),fileMap={};for(const file of files(path.join(candidate,"web"))){const name="/"+path.relative(path.join(candidate,"web"),file).replaceAll("\\","/"),bytes=zlib.gzipSync(fs.readFileSync(file),{level:9}),sha=hash(bytes);fileMap[name]=sha;blobs.set(sha,bytes);}
 if(version.status!=="FINALIZED"){
 const populated=await api(`https://firebasehosting.googleapis.com/v1beta1/${version.name}:populateFiles`,{method:"POST",write:true,data:{files:fileMap}});
 const upload=new URL(populated.uploadUrl);check(upload.protocol==="https:"&&upload.hostname==="upload-firebasehosting.googleapis.com"&&upload.pathname.includes(`/sites/${PROJECT}/versions/`),"Hosting upload target mismatch");
 await mapLimit(populated.uploadRequiredHashes||[],async sha=>{check(blobs.has(sha),"Unknown requested upload");await api(`${populated.uploadUrl}/${sha}`,{method:"POST",write:true,data:blobs.get(sha),headers:{"content-type":"application/octet-stream"}});},4);
 await api(`https://firebasehosting.googleapis.com/v1beta1/${version.name}?updateMask=status`,{method:"PATCH",write:true,data:{status:"FINALIZED"}});
 }
 const latest=(await api(`${base}/releases?pageSize=1`)).releases?.[0];
 const release=latest?.version?.name===version.name?latest:await api(`${base}/releases?versionName=${encodeURIComponent(version.name)}`,{method:"POST",write:true,data:{message:"Current completed app and patched Node 22 dependencies"}});
 update("hosting",{at:new Date().toISOString(),version:version.name,release:release.name,fileCount:Object.keys(fileMap).length});console.log(JSON.stringify({status:"HOSTING_RELEASED",version:version.name,release:release.name}));
}
async function preserve(phase){
 const {reader}=await connect(),{app,db,auth}=await sdk(reader);try{
  const before=read(path.join(dir,"evidence/data-before.json")),now=await inventorySnapshot(db,auth),changed=Object.keys(before.documents).filter(k=>now.documents[k]?.hash!==before.documents[k].hash);
  const users=new Map(now.users.map(u=>[u.uid,u]));check(before.users.every(u=>JSON.stringify(canonical(users.get(u.uid)))===JSON.stringify(canonical(u))),"Existing authentication users changed");
  const repairFile=path.join(dir,"evidence/settings-repair.json"),repair=fs.existsSync(repairFile)?read(repairFile):null;
  const reviewedAdditions=phase==="after-acceptance"&&repair?.passed&&repair.allOriginalFieldValuesPreserved&&repair.beforeHash===before.documents[repair.documentPath]?.hash&&repair.afterHash===now.documents[repair.documentPath]?.hash?[repair.documentPath]:[];
  const unexpected=changed.filter(k=>!reviewedAdditions.includes(k));check(unexpected.length===0,`Pre-existing staging records changed unexpectedly: ${unexpected.join(", ")}`);
  const result={passed:true,phase,at:new Date().toISOString(),originalDocuments:Object.keys(before.documents).length,originalUsers:before.users.length,changedExistingDocumentHashes:changed,reviewedAdditiveConfiguration:reviewedAdditions,allOriginalFieldValuesPreserved:true,newDocuments:Object.keys(now.documents).length-Object.keys(before.documents).length,newUsers:now.users.length-before.users.length};
  save(path.join(dir,`evidence/preservation-${phase}.json`),result);console.log(JSON.stringify(result));
 }finally{await db.terminate();await load("firebase-admin/app").deleteApp(app);}
}
if(require.main===module){const action=process.argv[2];const actions={prepare,baseline,indexes:()=>indexes(true),"index-status":()=>indexes(false),rules,functions,hosting,"preserve-before-acceptance":()=>preserve("before-acceptance"),"preserve-after-acceptance":()=>preserve("after-acceptance")};check(process.argv.length===3&&actions[action],"Explicit release action required");Promise.resolve().then(actions[action]).catch(logError);}
module.exports={verify,sdk,inventorySnapshot};
