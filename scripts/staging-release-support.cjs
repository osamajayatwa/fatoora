"use strict";
const fs=require("node:fs"),path=require("node:path"),crypto=require("node:crypto"),https=require("node:https");
const root=path.resolve(__dirname,".."),PROJECT="fatoora-original-staging",NUMBER="5438538531";
const dir=path.join(root,".staging",PROJECT,"current-release"),load=require("node:module").createRequire(path.join(root,"functions/package.json"));
const {mapLimit,safeTarget}=require("./staging-current-readiness.cjs");
const check=(ok,message)=>{if(!ok)throw Error(message);};
const hash=b=>crypto.createHash("sha256").update(b).digest("hex");
const read=file=>JSON.parse(fs.readFileSync(file,"utf8"));
function save(file,value){fs.mkdirSync(path.dirname(file),{recursive:true});fs.writeFileSync(file,JSON.stringify(value,null,2)+"\n");}
function files(base){return fs.readdirSync(base,{withFileTypes:true}).flatMap(e=>e.isDirectory()?files(path.join(base,e.name)):[path.join(base,e.name)]);}
function canonical(v,key=""){
 if(Array.isArray(v)){const rows=v.map(x=>canonical(x));return ["eventFilters","bindings","members"].includes(key)?rows.sort((a,b)=>JSON.stringify(a).localeCompare(JSON.stringify(b))):rows;}
 return v&&typeof v==="object"?Object.fromEntries(Object.keys(v).sort().map(k=>[k,canonical(v[k],k)])):v;
}
function allowed(url){
 const u=new URL(url),p=u.pathname;
 check(u.protocol==="https:"&&!u.username&&!u.password,"HTTPS staging URL required");
 check(!["fatoora-6b192","961957914773","fatoora-platform-staging","813911311333"].some(v=>decodeURIComponent(u.href).split(/[/:?&#=]/).includes(v)),"Protected project request refused");
 const api=["cloudfunctions.googleapis.com","run.googleapis.com","firestore.googleapis.com","firebaserules.googleapis.com","cloudbuild.googleapis.com","artifactregistry.googleapis.com","containeranalysis.googleapis.com","cloudresourcemanager.googleapis.com","identitytoolkit.googleapis.com"];
 const resource=api.includes(u.hostname)&&new RegExp(`/projects/(?:${PROJECT}|${NUMBER})(?:/|:|$)`).test(p);
 const hosting=u.hostname==="firebasehosting.googleapis.com"&&p.startsWith(`/v1beta1/sites/${PROJECT}/`);
 const hostingUpload=u.hostname==="upload-firebasehosting.googleapis.com"&&p.startsWith(`/upload/sites/${PROJECT}/versions/`);
 const image=u.hostname==="us-central1-docker.pkg.dev"&&p.startsWith(`/v2/${PROJECT}/gcf-artifacts/`);
 const storage=u.hostname==="storage.googleapis.com"&&p.startsWith(`/storage/v1/b/gcf-v2-sources-${NUMBER}-us-central1/o/`);
 check(resource||hosting||hostingUpload||image||storage,"Request outside dedicated staging resources refused");
 return u;
}
async function connect(deploy=false){
 check(!Object.entries(process.env).some(([k,v])=>v&&(k.endsWith("_EMULATOR_HOST")||["GOOGLE_APPLICATION_CREDENTIALS","FIREBASE_TOKEN","FIRESTORE_URL"].includes(k))),"Unexpected cloud credential/emulator override");
 for(const k of ["GCLOUD_PROJECT","GOOGLE_CLOUD_PROJECT","CLOUDSDK_CORE_PROJECT"])check(!process.env[k]||process.env[k]===PROJECT,"Project override mismatch");
 const state=read(path.join(dir,"../provisioning-state.json"));check(state.projectId===PROJECT&&state.projectNumber===NUMBER,"Staging identity mismatch");
 const {client,verifyProject}=require("./staging-cloud.cjs"),reader=await client();await verifyProject(reader,state);let writer;
 if(deploy){
  check(state.deployer===`fatoora-staging-deployer@${PROJECT}.iam.gserviceaccount.com`,"Deployer identity mismatch");
  writer=new (load("google-auth-library").Impersonated)({sourceClient:reader,targetPrincipal:state.deployer,targetScopes:["https://www.googleapis.com/auth/cloud-platform"],lifetime:3600});writer.quotaProjectId=PROJECT;
 }
 async function api(url,{method="GET",data,binary=false,text=false,write=false,headers={}}={}){
  allowed(url);check(!["DELETE","PUT"].includes(method),"Deletion/replacement outside release scope");check(!write||Boolean(writer),"Read-only connection cannot mutate resources");
  check(method==="GET"||write||url.includes(":getIamPolicy"),"Explicit deployment intent required");
  if(write)check(!/setIamPolicy|:delete|accounts:|\/documents/.test(url),"IAM, Auth or business writes forbidden in deployment client");
  return (await (write?writer:reader).request({url,method,data,headers,retry:method==="GET",retryConfig:{retry:2,noResponseRetries:2,retryDelay:1000},timeout:60000,agent:new https.Agent({family:4}),
   ...(binary?{responseType:"arraybuffer"}:text?{responseType:"text"}:{})})).data;
 }
 async function list(url,key){const rows=[];let token;do{const u=new URL(url);if(token)u.searchParams.set("pageToken",token);const r=await api(u.toString());check(!r.unreachable?.length,"Incomplete resource listing");rows.push(...r[key]||[]);token=r.nextPageToken;}while(token);return rows;}
 return {reader,writer,state,api,list};
}
async function publicRequest(url,options={}){
 const u=new URL(url);check(u.protocol==="https:"&&[`${PROJECT}.web.app`,`${PROJECT}.firebaseapp.com`,`us-central1-${PROJECT}.cloudfunctions.net`,"identitytoolkit.googleapis.com","firestore.googleapis.com"].includes(u.hostname),"Non-staging client origin refused");
 if(u.hostname==="identitytoolkit.googleapis.com")check(u.searchParams.get("key")===read(path.join(root,"config/firebase/staging.web.json")).FIREBASE_API_KEY,"Unpinned Firebase Auth key");
 if(u.hostname==="firestore.googleapis.com")check(u.pathname.startsWith(`/v1/projects/${PROJECT}/`),"Unpinned client Firestore path");
 return load("gaxios").request({url:u.toString(),retry:false,timeout:60000,maxRedirects:0,agent:new https.Agent({family:4}),...options});
}
function logError(e){const message=String(e.response?.data?.error?.message||e.message).replace(/(https:\/\/[^\s?]+)\?[^\s]+/g,"$1?[redacted]");console.error(JSON.stringify({status:"BLOCKED",message,code:e.code,httpStatus:e.response?.status}));process.exitCode=1;}
module.exports={fs,path,root,dir,PROJECT,NUMBER,load,mapLimit,safeTarget,check,hash,read,save,files,canonical,allowed,connect,publicRequest,logError};
