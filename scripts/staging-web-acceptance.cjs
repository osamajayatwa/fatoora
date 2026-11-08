"use strict";
const fs=require("node:fs"),path=require("node:path");
const {context,validateLocal,readState,save,check,hash,client,verifyProject,request,PROJECT}=require("./staging-cloud.cjs");
const root=path.resolve(__dirname,".."),origin=`https://${PROJECT}.web.app`;
async function get(url,options={}) {
  const u=new URL(url);check(u.protocol==="https:"&&[`${PROJECT}.web.app`,`${PROJECT}.firebaseapp.com`,`us-central1-${PROJECT}.cloudfunctions.net`].includes(u.hostname),"Unexpected staging Web endpoint");
  try{return await fetch(u,{...options,redirect:"error",signal:AbortSignal.timeout(60000)});}
  catch(e){throw Error(`HTTPS verification failed at ${u.hostname}${u.pathname}: ${e.cause?.code||e.message}`);}
}
async function main(){
  context();validateLocal();const s=readState(),c=await client();await verifyProject(c,s);
  check(s.deployments?.hosting?.completed&&s.acceptance?.backendPassed&&s.callableTransport?.verified,"Published, accepted staging backend required");
  const release=await request(c,`https://firebasehosting.googleapis.com/v1beta1/sites/${PROJECT}/releases?pageSize=1`);
  const latest=release.releases?.[0];check(latest?.type==="DEPLOY"&&latest.version?.name?.startsWith(`sites/${PROJECT}/versions/`),"Unexpected Hosting release");
  const files=s.deployments.hosting.sourceHashes;
  check(Object.keys(files).length>5,"Missing reviewed Web artifact");
  const verified=[];
  // Verify the executable app, shell and manifests byte-for-byte over real HTTPS.
  const selected=["index.html","main.dart.js","flutter_bootstrap.js","flutter.js","manifest.json","assets/AssetManifest.bin","assets/FontManifest.json"];
  for(const relative of selected){
    const file=`build/staging/web/${relative}`;check(files[file]&&hash(fs.readFileSync(path.join(root,file)))===files[file],"Web artifact changed after deployment");
    const r=await get(`${origin}/${relative}`);check(r.status===200,`Web asset HTTP failure: ${relative}`);
    check(hash(Buffer.from(await r.arrayBuffer()))===files[file],`Published Web asset differs: ${relative}`);verified.push(relative);
  }
  const alias=await get(`https://${PROJECT}.firebaseapp.com/`);check(alias.status===200&&hash(Buffer.from(await alias.arrayBuffer()))===files["build/staging/web/index.html"],"Secondary Firebase domain mismatch");
  const deep=await get(`${origin}/staging-acceptance-route`);check(deep.status===200&&hash(Buffer.from(await deep.arrayBuffer()))===files["build/staging/web/index.html"],"SPA rewrite failed");
  const cors=await get(`https://us-central1-${PROJECT}.cloudfunctions.net/getDashboardSnapshot`,{method:"OPTIONS",headers:{Origin:origin,"Access-Control-Request-Method":"POST","Access-Control-Request-Headers":"authorization,content-type"}});
  check([200,204].includes(cors.status)&&[origin,"*"].includes(cors.headers.get("access-control-allow-origin")),"Callable browser preflight failed");
  const allowed=cors.headers.get("access-control-allow-headers")?.toLowerCase()||"";check(allowed.includes("authorization")&&allowed.includes("content-type"),"Callable preflight does not allow Firebase auth headers");
  s.acceptance.web={at:new Date().toISOString(),https:true,verifiedAssets:verified,secondaryDomain:true,spaRewrite:true,callableCors:true,hostingRelease:latest.name,hostingVersion:latest.version.name,browserUiExercised:false};
  save(s);fs.writeFileSync(path.join(root,"build/staging/acceptance-web.json"),JSON.stringify(s.acceptance.web,null,2)+"\n");
  console.log(JSON.stringify({status:"STAGING_WEB_HTTPS_ARTIFACT_AND_CORS_VERIFIED",...s.acceptance.web}));
}
main().catch(e=>{console.error(JSON.stringify({status:"BLOCKED",message:e.message}));process.exitCode=1;});
