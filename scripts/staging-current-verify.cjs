"use strict";
const S=require("./staging-release-support.cjs"),{fs,path,dir,PROJECT,NUMBER,mapLimit,check,hash,read,save,canonical,connect,publicRequest,logError}=S;
const crypto=require("node:crypto");
const equal=(a,b)=>JSON.stringify(canonical(a))===JSON.stringify(canonical(b));
async function backend(){
 const {api,list}=await connect(),before=read(path.join(dir,"rollback/baseline.json")),runtimeBefore=read(path.join(dir,"evidence/runtime-before.json")),runtimeAfter=read(path.join(dir,"evidence/runtime-after.json"));
 check(runtimeAfter.status==="PASS_DEPLOYED_RUNTIME","Actual runtime security inspection incomplete");
 const functions=await list(`https://cloudfunctions.googleapis.com/v2/projects/${PROJECT}/locations/us-central1/functions?pageSize=100`,"functions");
 check(functions.length===35&&equal(functions.map(f=>f.name).sort(),before.functions.map(f=>f.name).sort()),"Function creation/deletion or naming drift");
 const archive=fs.readFileSync(read(path.join(dir,"release-state.json")).sourceArchive.path),md5=crypto.createHash("md5").update(archive).digest("base64");
 const checked=await mapLimit(functions,async f=>{
  const old=before.functions.find(x=>x.name===f.name);check(f.state==="ACTIVE"&&f.buildConfig.runtime===old.buildConfig.runtime&&f.buildConfig.entryPoint===old.buildConfig.entryPoint&&f.buildConfig.serviceAccount===old.buildConfig.serviceAccount,"Function runtime/build identity changed");
  for(const key of ["serviceAccountEmail","timeoutSeconds","availableMemory","availableCpu","maxInstanceCount","minInstanceCount","maxInstanceRequestConcurrency","ingressSettings","environmentVariables","secretEnvironmentVariables"]){check(equal(f.serviceConfig[key],old.serviceConfig[key]),`Unrelated function configuration changed: ${f.name}/${key}`);}
  check(equal(f.eventTrigger,old.eventTrigger),`Event trigger changed: ${f.name}`);
  const a=runtimeBefore.functions.find(x=>x.function===f.name).policy,b=runtimeAfter.functions.find(x=>x.function===f.name).policy;
  check(equal({bindings:a.bindings,version:a.version},{bindings:b.bindings,version:b.version}),`Invocation permissions changed: ${f.name}`);
  const source=f.buildConfig.sourceProvenance?.resolvedStorageSource||f.buildConfig.source.storageSource;
  check(source.bucket===`gcf-v2-sources-${NUMBER}-us-central1`&&/^\d+$/.test(String(source.generation)),"Unexpected deployed source provenance");
  const metadata=await api(`https://storage.googleapis.com/storage/v1/b/${source.bucket}/o/${encodeURIComponent(source.object)}?generation=${source.generation}&fields=md5Hash,size,generation`);
  check(metadata.md5Hash===md5&&Number(metadata.size)===archive.length,"Deployed source bytes differ from sealed artifact");
  return {function:f.name.split("/").pop(),revision:f.serviceConfig.revision,build:f.buildConfig.build,source,sourceMd5:metadata.md5Hash,iamUnchanged:true,configurationUnchanged:true};
 },4);
 const release=await api(`https://firebaserules.googleapis.com/v1/projects/${PROJECT}/releases/cloud.firestore`),rules=await api(`https://firebaserules.googleapis.com/v1/${release.rulesetName}`);
 check(hash(Buffer.from(rules.source.files.find(f=>f.name==="firestore.rules").content))===hash(fs.readFileSync(path.join(dir,"candidate/firestore.rules"))),"Deployed Rules differ from reviewed source");
 const result={passed:true,at:new Date().toISOString(),project:PROJECT,functions:checked,ruleset:release.rulesetName,invocationPermissionsUnchanged:true,unrelatedConfigurationUnchanged:true,sourceArchiveSha256:hash(archive)};
 save(path.join(dir,"evidence/backend-deployment-verification.json"),result);console.log(JSON.stringify({status:"PASS_EXACT_BACKEND_DEPLOYMENT",functions:checked.length,iamUnchanged:true,configurationUnchanged:true}));
}
async function web(){
 const state=read(path.join(dir,"release-state.json"));check(state.hosting,"Hosting is not released");const manifest=read(path.join(dir,"candidate/SHA256SUMS.json")),verified=[];
 for(const [name,sha]of Object.entries(manifest).filter(([n])=>n.startsWith("web/"))){const relative=name.slice(4),r=await publicRequest(`https://${PROJECT}.web.app/${relative}`,{responseType:"arraybuffer"});check(hash(Buffer.from(r.data))===sha,`Published Web asset mismatch: ${relative}`);verified.push(relative);}
 const shell=manifest["web/index.html"];
 for(const url of [`https://${PROJECT}.firebaseapp.com/`,`https://${PROJECT}.web.app/synthetic-acceptance-route`]){const r=await publicRequest(url,{responseType:"arraybuffer"});check(hash(Buffer.from(r.data))===shell,"Hosting alias/SPA rewrite mismatch");}
 const init=await publicRequest(`https://${PROJECT}.web.app/__/firebase/init.json`,{responseType:"text"});check(JSON.parse(init.data).projectId===PROJECT,"Reserved Hosting Firebase configuration targets another project");
 const cors=await publicRequest(`https://us-central1-${PROJECT}.cloudfunctions.net/getDashboardSnapshot`,{method:"OPTIONS",headers:{Origin:`https://${PROJECT}.web.app`,"Access-Control-Request-Method":"POST","Access-Control-Request-Headers":"authorization,content-type"}});check([200,204].includes(cors.status)&&["*",`https://${PROJECT}.web.app`].includes(cors.headers["access-control-allow-origin"]),"Browser callable CORS failed");
 const allowedHeaders=String(cors.headers["access-control-allow-headers"]||"").toLowerCase();check(allowedHeaders.includes("authorization")&&allowedHeaders.includes("content-type"),"Browser authentication headers are not allowed by CORS");
 const result={passed:true,at:new Date().toISOString(),project:PROJECT,...state.hosting,verifiedAssets:verified,secondaryDomain:true,spaRewrite:true,reservedConfigurationStaging:true,callableCors:true,visualBrowserAcceptance:"BLOCKED_AUTOMATION_URL_POLICY"};
 save(path.join(dir,"evidence/web-deployment-verification.json"),result);console.log(JSON.stringify({status:"PASS_PUBLISHED_WEB_ARTIFACTS_AND_TRANSPORT",assets:verified.length,version:state.hosting.version,visualBrowserAcceptance:result.visualBrowserAcceptance}));
}
if(require.main===module){check(process.argv.length===3&&["backend","web"].includes(process.argv[2]),"Explicit backend/web verification required");(process.argv[2]==="backend"?backend():web()).catch(logError);}
