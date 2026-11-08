"use strict";
const fs=require("node:fs"),path=require("node:path"),crypto=require("node:crypto"),{spawnSync}=require("node:child_process");
const {check,request,hash,PROJECT}=require("./staging-cloud.cjs");
const root=path.resolve(__dirname,"..");
async function verifySourceArtifacts(c,s,functions) {
  const compatible=Boolean(s.runtimeCompatibility?.reviewed);
  const directory=path.join(root,compatible?"build/staging/deployed-source/runtime-compatible":"build/staging/deployed-source");fs.mkdirSync(directory,{recursive:true});
  const sources=new Map();
  for(const f of functions) {
    const source=f.buildConfig?.source?.storageSource;
    check(source?.bucket===s.sourceBucket && typeof source.object==="string" && /^\d+$/.test(String(source.generation)),"Deployed source bucket/generation is not pinned");
    sources.set(JSON.stringify(source),source);
  }
  const artifacts=[];
  for(const source of sources.values()) {
    const url=`https://storage.googleapis.com/storage/v1/b/${source.bucket}/o/${encodeURIComponent(source.object)}?generation=${source.generation}`;
    const meta=await request(c,url+"&fields=bucket,name,generation,md5Hash,size");
    check(meta.bucket===s.sourceBucket && meta.name===source.object && meta.generation===String(source.generation) && Number(meta.size)<10000000,"Source object metadata mismatch");
    const response=await c.request({url:url+"&alt=media",method:"GET",responseType:"arraybuffer",retry:false,timeout:30000});
    const bytes=Buffer.from(response.data);check(crypto.createHash("md5").update(bytes).digest("base64")===meta.md5Hash,"Source object integrity mismatch");
    const sha256=hash(bytes),file=path.join(directory,`${sha256}.zip`);
    if(fs.existsSync(file))check(hash(fs.readFileSync(file))===sha256,"Local source evidence changed");else fs.writeFileSync(file,bytes,{flag:"wx"});
    artifacts.push({...source,sha256,size:bytes.length});
  }
  const validation=spawnSync("powershell.exe",["-NoProfile","-NonInteractive","-ExecutionPolicy","Bypass","-File",path.join(__dirname,"staging-verify-source.ps1"),"-ArtifactDirectory",directory,"-SourceDirectory",path.join(root,compatible?"build/staging/functions":"functions")],{windowsHide:true,encoding:"utf8"});
  check(validation.status===0,`Deployed source verification failed: ${validation.stderr?.slice(0,700)}`);
  const result={project:PROJECT,artifacts,validation:JSON.parse(validation.stdout.trim())};
  fs.writeFileSync(path.join(root,"build/staging/source-artifact-verification.json"),JSON.stringify(result,null,2)+"\n");
  return result;
}
module.exports={verifySourceArtifacts};
