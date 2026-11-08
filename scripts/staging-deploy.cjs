"use strict";
// Keyless deployment as a staging-only service account. No saved CLI credentials.
const fs=require("node:fs"),path=require("node:path");
const {context,verifyProject,client,readState,save,hash,check,list,PROJECT,FORBIDDEN}=require("./staging-cloud.cjs");
const root=path.resolve(__dirname,"..");
const load=require("node:module").createRequire(path.join(root,"functions/package.json"));
function sourceFiles(folder) {
  return fs.readdirSync(path.join(root,folder),{withFileTypes:true}).flatMap(e=>e.isDirectory()?sourceFiles(`${folder}/${e.name}`):[`${folder}/${e.name}`]);
}
async function main() {
  const action=process.argv[2];check(process.argv.length===3 && ["rules","functions","canary","hosting"].includes(action),"Explicit reviewed deployment component required; force/deletion flags forbidden");
  context();let s=readState();const c=await client();await verifyProject(c,s);
  check(s.identitiesVerified && s.sdkVerified && s.authVerified && s.databaseVerified && s.siteVerified,"Foundation/identity gates are incomplete");
  const config=JSON.parse(fs.readFileSync(path.join(root,"firebase.staging.json")));
  check(config.functions.length===1 && config.functions[0].source==="build/staging/functions" && config.functions[0].codebase===PROJECT &&
    config.hosting.site===PROJECT && config.hosting.public==="build/staging/web" && config.firestore.rules==="firestore.rules" &&
    config.firestore.indexes==="firestore.indexes.json","Deployment configuration target mismatch");
  for(const platform of ["android","web"]) {
    const filename=path.join(root,`config/firebase/staging.${platform}.json`);
    const cfg=JSON.parse(fs.readFileSync(filename));
    check(hash(fs.readFileSync(filename))===s[`${platform}ConfigSha256`] && cfg.FATOORA_ENV==="staging" && cfg.FIREBASE_PROJECT_ID===PROJECT &&
      cfg.FIREBASE_PROJECT_ID_CONFIRM===PROJECT && cfg.FIREBASE_MESSAGING_SENDER_ID===s.projectNumber && cfg.FIREBASE_APP_ID===s.appOperations[platform].appId,"SDK pairing changed");
  }
  const baseline=JSON.parse(fs.readFileSync(path.join(root,"build/staging-plan/approved-preflight-online.json")));
  for(const f of [".firebaserc","firebase.json","lib/firebase_options.dart","android/app/google-services.json","firestore.rules","firestore.indexes.json","functions/src/index.ts"]) {
    check(hash(fs.readFileSync(path.join(root,f)))===baseline.localFiles.before[f],`Protected source/configuration changed: ${f}`);
  }
  check(!fs.readdirSync(path.join(root,"functions")).some(f=>f.startsWith(".env")&&f!==".env.example"),"Unreviewed Functions environment file detected");
  if(["functions","canary"].includes(action)){require("./staging-prepare-functions.cjs").prepare();s=readState();}
  if(["functions","canary"].includes(action)) {
    check(s.deployments?.rules?.completed && s.indexesVerified && s.extensionsVerified,"Rules/indexes and authoritative empty extension listing must be verified first");
    for(const version of ["v1","v2"]) {
      const functions=await list(c,`https://cloudfunctions.googleapis.com/${version}/projects/${PROJECT}/locations/-/functions`,"functions");
      check(functions.every(f=>f.labels?.["firebase-functions-codebase"]===PROJECT && s.deployments?.functions?.sourceHashes),"Unknown/pre-existing function collision");
    }
  }
  if(action==="hosting")check(s.seedVerified && s.adminActivated && s.acceptance?.backendPassed,"Hosting must remain unpublished until seed, admin, and backend acceptance pass");
  const inputs=["functions","canary"].includes(action) ? [...sourceFiles("functions/src"),...sourceFiles("functions/shared"),"functions/package.json","functions/package-lock.json","config/firebase/staging-runtime.cjs","scripts/staging-prepare-functions.cjs","scripts/staging-prepare-functions.ps1"] :
    action==="hosting" ? sourceFiles("build/staging/web") : ["firestore.rules","firestore.indexes.json"];
  check(inputs.length>0,"Missing deployment artifact");
  const sourceHashes=Object.fromEntries(inputs.sort().map(f=>[f,hash(fs.readFileSync(path.join(root,f)))]));
  s.deployments=s.deployments||{};
  if(action==="functions" && s.deployments.functions && !s.deployments.functions.sourceHashes["config/firebase/staging-runtime.cjs"] && s.runtimeCompatibility?.reviewed) {
    check(Object.entries(s.deployments.functions.sourceHashes).every(([file,sha])=>sourceHashes[file]===sha),"Original Functions source changed during compatibility fix");
    s.deployments.functions.originalSourceHashes={...s.deployments.functions.sourceHashes};
    s.deployments.functions.previousArtifact={...s.deployments.functions};
    s.deployments.functions.sourceHashes=sourceHashes;s.deployments.functions.completed=false;
    s.deployments.functions.configSha256=hash(fs.readFileSync(path.join(root,"firebase.staging.json")));
    s.functionsVerified=false;s.sourceArtifactsVerified=false;s.seedVerified=false;
  } else if(s.deployments[action])check(JSON.stringify(s.deployments[action].sourceHashes)===JSON.stringify(sourceHashes),"Artifact changed since the recorded deployment attempt");
  else s.deployments[action]={sourceHashes,configSha256:hash(fs.readFileSync(path.join(root,"firebase.staging.json"))),startedAt:new Date().toISOString()};
  save(s);
  const {Impersonated}=load("google-auth-library");
  const impersonated=new Impersonated({sourceClient:c,targetPrincipal:s.deployer,targetScopes:["https://www.googleapis.com/auth/cloud-platform"],lifetime:3600});
  const token=await impersonated.getAccessToken();check(token.token,"Impersonation failed");
  // Isolate Firebase CLI state; never load/copy its user credentials or remap aliases.
  process.env.XDG_CONFIG_HOME=path.join(root,"build/staging/firebase-cli-config");
  process.env.GOOGLE_CLOUD_QUOTA_PROJECT=PROJECT;
  process.env.FIREBASE_CLI_DISABLE_MOTD="1";
  delete process.env.DEBUG;
  process.env.IS_FIREBASE_CLI="1";
  const fbRoot=path.join(process.env.APPDATA,"npm/node_modules/firebase-tools");
  const fbLoad=require("node:module").createRequire(path.join(fbRoot,"package.json"));
  const apiv2=fbLoad("./lib/apiv2");
  apiv2.setAccessToken(token.token);apiv2.setRefreshToken("");
  const originalRequest=apiv2.Client.prototype.request;
  apiv2.Client.prototype.request=function(options) {
    const method=(options.method||"GET").toUpperCase();
    check(method!=="DELETE","Deployment attempted an unapproved deletion");
    if(!["GET","HEAD"].includes(method)) {
      check(!FORBIDDEN.some(p=>String(options.path||"").split(/[/:?]/).includes(p)),"CLI attempted a forbidden project mutation");
    }
    const apiPath=String(options.path||"").replace(/^\/+/,"");
    if(["POST","PATCH"].includes(method) && apiPath.startsWith(`projects/${PROJECT}/locations/us-central1/functions`) && options.body?.buildConfig) {
      check(s.buildIdentityVerified && s.buildServiceAccount?.startsWith(`projects/${PROJECT}/serviceAccounts/`),"Separate verified staging build identity required");
      check(options.body.name?.startsWith(`projects/${PROJECT}/locations/us-central1/functions/`),"Function resource target mismatch");
      options.body.buildConfig.serviceAccount=s.buildServiceAccount;
      if(options.queryParams?.updateMask && !options.queryParams.updateMask.includes("buildConfig.serviceAccount"))options.queryParams.updateMask+=",buildConfig.serviceAccount";
      console.log(JSON.stringify({status:"PINNED_BUILD_IDENTITY_APPLIED",function:options.body.name,buildServiceAccount:s.buildServiceAccount}));
    }
    return originalRequest.call(this,options);
  };
  const only={rules:"firestore:rules,firestore:indexes",functions:`functions:${PROJECT}`,canary:`functions:${PROJECT}:listAccessibleCustomers`,hosting:"hosting"}[action];
  const command=fbLoad("./lib/commands/deploy").command;
  // Optional image deletion policies are outside this approval; abort that step.
  fbLoad("./lib/deploy/functions/prompts").promptForCleanupPolicyDays=async()=>{throw Object.assign(new Error("STAGING_IMAGE_CLEANUP_NOT_APPROVED; verify deployed resources separately"),{code:"STAGING_OPTIONAL_CLEANUP_SKIPPED"});};
  const options={project:PROJECT,projectId:PROJECT,projectNumber:s.projectNumber,config:"firebase.staging.json",cwd:root,
    only,nonInteractive:!["functions","canary"].includes(action),interactive:["functions","canary"].includes(action),force:false,user:{email:s.deployer},tokens:{access_token:token.token,expires_at:Date.now()+3500000}};
  console.log(JSON.stringify({status:"DEPLOYING_VERIFIED_ARTIFACT",project:PROJECT,projectNumber:s.projectNumber,only,principal:s.deployer,artifactFiles:inputs.length}));
  await command.runner()(options);
  check(options.project===PROJECT && String(options.projectNumber)===s.projectNumber && options.user?.email===s.deployer,"CLI target/principal changed");
  const updated=readState();updated.deployments[action].completed=true;updated.deployments[action].completedAt=new Date().toISOString();save(updated);
  console.log(JSON.stringify({status:"DEPLOYMENT_COMPLETED",project:PROJECT,only}));
}
main().catch(e=>{console.error(JSON.stringify({status:"BLOCKED",code:e.code,message:e.message}));process.exitCode=1;});
