"use strict";
// Inspect exact staging container digests, not just the submitted lockfile.
const {fs,path,dir,PROJECT,load,mapLimit,check,hash,read,save,connect,logError}=require("./staging-release-support.cjs");
const cp=require("node:child_process");
async function inspect(phase){
 check(["before","after"].includes(phase),"Explicit before/after inspection required");
 const {api,list}=await connect(),folder=path.join(dir,"runtime");fs.mkdirSync(folder,{recursive:true});
 const functions=await list(`https://cloudfunctions.googleapis.com/v2/projects/${PROJECT}/locations/us-central1/functions?pageSize=100`,"functions");
 check(functions.length===35&&functions.every(f=>f.state==="ACTIVE"),"All 35 existing Functions must be ACTIVE");
 const services=await mapLimit(functions,async f=>{
  const service=f.serviceConfig.service,revision=`${service}/revisions/${f.serviceConfig.revision}`;
  check(service.startsWith(`projects/${PROJECT}/locations/us-central1/services/`),"Wrong runtime service");
  const r=await api(`https://run.googleapis.com/v2/${revision}`);
  const policy=await api(`https://run.googleapis.com/v2/${service}:getIamPolicy`);
  check(r.containers?.length===1&&r.containers[0].image.startsWith(`us-central1-docker.pkg.dev/${PROJECT}/gcf-artifacts/`),"Wrong runtime image");
  return {function:f.name,revision,image:r.containers[0].image,policy,build:f.buildConfig.build,source:f.buildConfig.source};
 });
 const images=await mapLimit([...new Set(services.map(s=>s.image))],async image=>{
  const remainder=image.slice("us-central1-docker.pkg.dev/".length),i=remainder.indexOf("@");check(i>0&&/^sha256:[a-f0-9]{64}$/.test(remainder.slice(i+1)),"Immutable image digest required");
  const base=`https://us-central1-docker.pkg.dev/v2/${remainder.slice(0,i)}`,digest=remainder.slice(i+1);
  const raw=await api(`${base}/manifests/${digest}`,{text:true,headers:{Accept:"application/vnd.docker.distribution.manifest.v2+json"}});
  check(`sha256:${hash(Buffer.from(raw))}`===digest,"Image manifest integrity failure");const manifest=JSON.parse(raw);
  const configBytes=Buffer.from(await api(`${base}/blobs/${manifest.config.digest}`,{binary:true}));
  check(`sha256:${hash(configBytes)}`===manifest.config.digest,"Image configuration integrity failure");
  const config=JSON.parse(configBytes),meta=JSON.parse(config.config.Labels["io.buildpacks.lifecycle.metadata"]);
  const framework=JSON.parse(config.config.Labels["google.functions-framework-version"]);
  const layerHashes=[...meta.app.map(a=>a.sha),...Object.values(meta.buildpacks.find(b=>b.key==="google.nodejs.functions-framework")?.layers||{}).map(l=>l.sha)];
  const packages=[];
  for(const layerHash of layerHashes){
   const index=config.rootfs.diff_ids.indexOf(layerHash);check(index>=0,"Missing runtime dependency layer");const layer=manifest.layers[index];check(layer.size<50000000,"Unexpected dependency layer size");
   const file=path.join(folder,`${layer.digest.slice(7)}.tgz`),parsed=path.join(folder,`${layer.digest.slice(7)}.packages.json`);
   if(!fs.existsSync(file)){const bytes=Buffer.from(await api(`${base}/blobs/${layer.digest}`,{binary:true}));check(`sha256:${hash(bytes)}`===layer.digest,"Image dependency layer integrity failure");fs.writeFileSync(file,bytes);}
   else check(`sha256:${hash(fs.readFileSync(file))}`===layer.digest,"Cached layer changed");
   if(!fs.existsSync(parsed)){
    const code="import tarfile,json,sys\nwith tarfile.open(sys.argv[1]) as t:\n print(json.dumps([{'path':e.name,'package':json.load(t.extractfile(e))} for e in t.getmembers() if e.isfile() and e.name.endswith('/package.json') and e.size<2000000]))";
    fs.writeFileSync(parsed,cp.execFileSync("python",["-c",code,file],{encoding:"utf8",maxBuffer:20000000}));
   }
   packages.push(...read(parsed).filter(p=>p.package.name&&p.package.version));
  }
  const versions={};for(const {package:p} of packages){versions[p.name]||=[];if(!versions[p.name].includes(p.version))versions[p.name].push(p.version);}
  // npm's advisory bulk endpoint is public and receives package names/versions only.
  const advisoryRaw=(await load("gaxios").request({url:"https://registry.npmjs.org/-/npm/v1/security/advisories/bulk",method:"POST",data:versions,responseType:"text",retry:false,timeout:30000})).data;
  const advisory=JSON.parse(advisoryRaw);
  save(path.join(folder,`${digest.slice(7)}.json`),{image,manifest,framework,packages,advisory});
  if(phase==="after"){
   check(framework.version==="3.5.1"&&framework.injected===false,"Uncontrolled injected Functions Framework remains");
   check(Object.keys(advisory).length===0,"Deployed runtime still has vulnerable dependencies");
   const expected=read(path.join(dir,"candidate/functions/package.json")).overrides;
   for(const [name,version] of Object.entries(expected))check(versions[name]?.every(v=>v===version),`Patched runtime version mismatch: ${name}`);
  }
  return {image,framework,packageCount:packages.length,advisoryPackages:Object.keys(advisory),versions};
 },2);
 const result={at:new Date().toISOString(),phase,project:PROJECT,functions:services,images,status:phase==="after"?"PASS_DEPLOYED_RUNTIME":"CAPTURED_DEPLOYED_RUNTIME"};
 save(path.join(dir,`evidence/runtime-${phase}.json`),result);
 console.log(JSON.stringify({status:result.status,functions:services.length,images:images.length,frameworkVersions:[...new Set(images.map(x=>x.framework.version))],injected:images.some(x=>x.framework.injected),advisoryPackages:[...new Set(images.flatMap(x=>x.advisoryPackages))]}));
}
if(require.main===module)inspect(process.argv[2]).catch(logError);
