"use strict";
const fs=require("node:fs"),path=require("node:path"),{spawnSync}=require("node:child_process");
const {context,readState,save,hash,check,PROJECT}=require("./staging-cloud.cjs");
const root=path.resolve(__dirname,".."),destination=path.join(root,"build/staging/functions");
function prepare() {
  const manifest=context();const s=readState();check(s.projectId===PROJECT && (s.functionsVerified || s.runtimeCompatibility?.reviewed),"A verified original staging artifact is required");
  const adapterHash=hash(fs.readFileSync(path.join(root,"config/firebase/staging-runtime.cjs")));
  const tests=JSON.parse(fs.readFileSync(path.join(root,"build/staging/runtime-compatibility-tests.json")));
  check(tests.passed && tests.adapterSha256===adapterHash,"Native serialization and staging-only runtime guard tests must pass");
  for(const [file,sha]of Object.entries(s.deployments.functions.originalSourceHashes||s.deployments.functions.sourceHashes)) {
    if(file.startsWith("functions/"))check(hash(fs.readFileSync(path.join(root,file)))===sha,"Original reviewed Functions source changed");
  }
  const sourceSha=s.originalSourceArtifactHash||s.sourceArtifactHashes?.[0];check(/^[a-f0-9]{64}$/.test(sourceSha),"Missing verified original source archive");
  const archive=path.join(root,`build/staging/deployed-source/${sourceSha}.zip`);check(hash(fs.readFileSync(archive))===sourceSha,"Verified original archive changed");
  const marker=path.join(destination,".staging-artifact-owner.json");
  if(fs.existsSync(destination))check(fs.existsSync(marker)&&JSON.parse(fs.readFileSync(marker)).runId===s.runId,"Unknown staging artifact ownership");
  else {fs.mkdirSync(destination,{recursive:true});fs.writeFileSync(marker,JSON.stringify({runId:s.runId,project:PROJECT,sourceSha})+"\n",{flag:"wx"});}
  const extract=spawnSync("powershell.exe",["-NoProfile","-NonInteractive","-ExecutionPolicy","Bypass","-File",path.join(__dirname,"staging-prepare-functions.ps1"),"-Archive",archive,"-Destination",destination],{windowsHide:true,encoding:"utf8"});
  check(extract.status===0,"Verified artifact extraction failed");
  const original=JSON.parse(fs.readFileSync(path.join(root,"functions/package.json")));
  fs.writeFileSync(path.join(destination,"package.json"),JSON.stringify({...original,main:"lib/staging-entry.cjs"},null,2)+"\n");
  fs.copyFileSync(path.join(root,"config/firebase/staging-runtime.cjs"),path.join(destination,"lib/staging-entry.cjs"));
  const dependencies=path.join(destination,"node_modules");
  if(!fs.existsSync(dependencies))fs.symlinkSync(path.join(root,"functions/node_modules"),dependencies,"junction");
  s.originalSourceArtifactHash=sourceSha;
  s.runtimeCompatibility={reviewed:true,stagingOnly:true,adapterSha256:adapterHash,setting:"ignoreUndefinedProperties",reason:"Native Firestore rejected undefined create-audit before-values",originalBusinessSourceUnchanged:true};
  manifest.functions.source="build/staging/functions";manifest.functions.originalSource="functions";manifest.functions.stagingRuntimeAdapter="config/firebase/staging-runtime.cjs";
  fs.writeFileSync(path.join(root,"config/firebase/staging-plan.review.json"),JSON.stringify(manifest,null,2)+"\n");
  save(s);console.log(JSON.stringify({status:"STAGING_ONLY_RUNTIME_ARTIFACT_PREPARED",source:destination,adapterSha256:adapterHash,originalBusinessSourceUnchanged:true}));
}
if(require.main===module)try{prepare();}catch(e){console.error(JSON.stringify({status:"BLOCKED",code:e.code,message:e.message}));process.exitCode=1;}
module.exports={prepare};
