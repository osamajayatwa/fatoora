"use strict";
// All cloud mutations are scoped to the approved original-app staging project.
// Existing-project requests are read-only metadata fingerprints, never SDK writes.
const fs = require("node:fs");
const path = require("node:path");
const crypto = require("node:crypto");
const root = path.resolve(__dirname, "..");
const load = require("node:module").createRequire(path.join(root, "functions/package.json"));
const PROJECT = "fatoora-original-staging", PARENT = "organizations/81973318356";
const BILLING = "0104EE-737092-D9DBF0";
const FORBIDDEN = ["fatoora-6b192", "961957914773", "fatoora-platform-staging", "813911311333"];
const durableRoot = path.join(root, ".staging/fatoora-original-staging");
const statePath = path.join(durableRoot, "provisioning-state.json");
const manifestPath = path.join(root, "config/firebase/staging-plan.review.json");
const hash = v => crypto.createHash("sha256").update(v).digest("hex");
function check(ok, message) {if (!ok) throw Object.assign(new Error(message), {code: "STAGING_GUARD"});}
function context() {
  check(!Object.entries(process.env).some(([k,v]) => v && (k.endsWith("_EMULATOR_HOST") || /^FIREBASE_.*(?:URL|ORIGIN|HOST)$/.test(k) ||
    ["GOOGLE_APPLICATION_CREDENTIALS", "CLOUDSDK_AUTH_IMPERSONATE_SERVICE_ACCOUNT", "FIREBASE_TOKEN","FIRESTORE_URL","CLOUD_RUN_URL","FUNCTIONS_EMULATOR"].includes(k))), "Unexpected emulator, credential or API-origin override");
  for (const key of ["GOOGLE_CLOUD_PROJECT", "GCLOUD_PROJECT", "CLOUDSDK_CORE_PROJECT"]) {
    check(!process.env[key] || process.env[key] === PROJECT, `Mismatched environment target: ${key}`);
  }
  const m = JSON.parse(fs.readFileSync(manifestPath, "utf8"));
  check(m.project.id === PROJECT && m.project.parent === PARENT && m.project.createNew && !m.project.reuseExisting &&
    m.billing.accountId === BILLING && m.companyId === "default_company" && m.approval?.source === "explicit_user_approval_in_session" &&
    !m.accountingImplementationAllowed && FORBIDDEN.every(v => m.forbiddenProjects.some(p => p.id === v || p.number === v)), "Approval manifest mismatch");
  check(m.catalog.fileSha256==="1763b2233f03dc76f06c4ff9a1c757006dc4fc41a891e139109aa51c10555f35" && m.catalog.path==="build/local-test/catalog.json","Catalog approval changed");
  const catalogPath=path.join(root,m.catalog.path);
  if(!fs.existsSync(catalogPath) && fs.existsSync(path.join(durableRoot,"catalog.json"))) {
    const bytes=fs.readFileSync(path.join(durableRoot,"catalog.json"));check(hash(bytes)===m.catalog.fileSha256,"Durable catalog evidence changed");
    fs.mkdirSync(path.dirname(catalogPath),{recursive:true});fs.writeFileSync(catalogPath,bytes,{flag:"wx"});
  }
  check(hash(fs.readFileSync(catalogPath)) === m.catalog.fileSha256, "Approved catalog hash mismatch");
  return m;
}
function readState() {
  if(!fs.existsSync(statePath))return null;
  const s=JSON.parse(fs.readFileSync(statePath,"utf8"));
  const sha=s.originalSourceArtifactHash;
  if(/^[a-f0-9]{64}$/.test(sha||"")) {
    const cached=path.join(durableRoot,`artifacts/${sha}.zip`),working=path.join(root,`build/staging/deployed-source/${sha}.zip`);
    if(!fs.existsSync(working)&&fs.existsSync(cached)){const bytes=fs.readFileSync(cached);check(hash(bytes)===sha,"Durable source evidence changed");fs.mkdirSync(path.dirname(working),{recursive:true});fs.writeFileSync(working,bytes,{flag:"wx"});}
  }
  const tests=path.join(root,"build/staging/runtime-compatibility-tests.json"),cachedTests=path.join(durableRoot,"runtime-compatibility-tests.json");
  if(!fs.existsSync(tests)&&fs.existsSync(cachedTests)){fs.mkdirSync(path.dirname(tests),{recursive:true});fs.copyFileSync(cachedTests,tests,fs.constants.COPYFILE_EXCL);}
  const baseline=path.join(root,"build/staging-plan/approved-preflight-online.json"),cachedBaseline=path.join(durableRoot,"approved-preflight-online.json");
  if(!fs.existsSync(baseline)&&fs.existsSync(cachedBaseline)){check(hash(fs.readFileSync(cachedBaseline))===s.localBaselineSha256,"Durable preflight evidence changed");fs.mkdirSync(path.dirname(baseline),{recursive:true});fs.copyFileSync(cachedBaseline,baseline,fs.constants.COPYFILE_EXCL);}
  return s;
}
function validateLocal() {
  const m=context(),s=readState();
  check(s?.projectId===PROJECT && s.projectNumber===m.project.number && s.sdkVerified,"Missing pinned local staging state");
  const configs={};
  for(const platform of ["android","web"]) {
    const filename=path.join(root,`config/firebase/staging.${platform}.json`),bytes=fs.readFileSync(filename);
    const cfg=JSON.parse(bytes);
    check(hash(bytes)===s[`${platform}ConfigSha256`] && cfg.FATOORA_ENV==="staging" && cfg.FIREBASE_PROJECT_ID===PROJECT &&
      cfg.FIREBASE_PROJECT_ID_CONFIRM===PROJECT && cfg.FIREBASE_MESSAGING_SENDER_ID===s.projectNumber &&
      cfg.FIREBASE_APP_ID===s.appOperations[platform].appId && cfg.FIREBASE_APP_ID===m[platform].appId &&
      typeof cfg.FIREBASE_API_KEY==="string" && cfg.FIREBASE_API_KEY.length>20,"Invalid or changed staging SDK configuration");
    configs[platform]=cfg;
  }
  const native=JSON.parse(fs.readFileSync(path.join(root,m.android.nativeConfig)));
  check(native.project_info?.project_id===PROJECT && native.project_info.project_number===s.projectNumber && native.client?.length===1 &&
    native.client[0].client_info?.mobilesdk_app_id===configs.android.FIREBASE_APP_ID &&
    native.client[0].client_info?.android_client_info?.package_name===m.android.packageName &&
    native.client[0].api_key?.[0]?.current_key===configs.android.FIREBASE_API_KEY,"Native/Dart staging mismatch");
  return {project:PROJECT,projectNumber:s.projectNumber,androidPackage:m.android.packageName};
}
function save(s) {fs.mkdirSync(path.dirname(statePath), {recursive: true}); fs.writeFileSync(statePath + ".tmp", JSON.stringify(s,null,2)+"\n");fs.renameSync(statePath+".tmp",statePath);}
async function client() {
  const c = await new (load("google-auth-library").GoogleAuth)({projectId:PROJECT,
    scopes:["https://www.googleapis.com/auth/cloud-platform"]}).getClient();
  check(c.constructor.name === "UserRefreshClient", "Existing user ADC required; no exported keys");
  // Never silently use the ADC's existing production quota project.
  c.quotaProjectId = undefined;
  return c;
}
async function request(c, url, method="GET", data) {
  const u = new URL(url);
  check(u.protocol === "https:" && u.hostname.endsWith(".googleapis.com"), "Unexpected API origin");
  check(method!=="DELETE","Deletion is outside the approved provisioning scope");
  const stagingLogRead=method==="POST" && u.hostname==="logging.googleapis.com" && u.pathname==="/v2/entries:list" &&
    data?.resourceNames?.length===1 && data.resourceNames[0]===`projects/${PROJECT}`;
  if (method !== "GET" && !u.pathname.endsWith(":testIamPermissions") && !u.pathname.endsWith(":getIamPolicy") && !stagingLogRead) {
    check(!FORBIDDEN.some(p => u.pathname.split(/[/:]/).includes(p)), "Forbidden mutation target");
    const s = readState();
    const creation = method === "POST" && url === "https://cloudresourcemanager.googleapis.com/v3/projects" &&
      data?.projectId === PROJECT && data?.parent === PARENT && s?.creationAttempt?.status === "submitted_once";
    const authProvision = method === "POST" && url === "https://firebase.googleapis.com/v1alpha/firebase:provisionFirebaseApp" &&
      s?.siteVerified && data?.parent===`projects/${PROJECT}` && data?.appNamespace===s.appOperations?.web?.appId && data?.webInput &&
      data?.firebaseAuthInput?.emailAuthProviderMode==="PROVIDER_ENABLED" && Object.keys(data).every(k=>["parent","appNamespace","webInput","firebaseAuthInput","requestId"].includes(k));
    const buildBucketPolicy=method==="PUT" && s?.sourceBucket?.startsWith(`gcf-v2-sources-${s.projectNumber}-`) &&
      u.hostname==="storage.googleapis.com" && u.pathname===`/storage/v1/b/${s.sourceBucket}/iam`;
    check(creation || authProvision || buildBucketPolicy || (s?.projectNumber && [PROJECT,s.projectNumber].some(p=>u.pathname.split(/[/:]/).includes(p) && u.pathname.includes(`/projects/${p}`))), "Mutation outside pinned staging project");
  }
  const response = await c.request({url, method, data, retry:false, timeout:30000});
  return response.data;
}
async function list(c,url,field) {
  const rows=[];let token;
  do {const u=new URL(url);if(token)u.searchParams.set("pageToken",token);const r=await request(c,u.toString());check(!r.unreachable?.length,"Listing has unreachable resources; refusing to assume absence");rows.push(...r[field]||[]);token=r.nextPageToken;} while(token);
  return rows;
}
async function fingerprint(c) {
  const result={};
  for(const p of [FORBIDDEN[0],FORBIDDEN[2]]) for(const [kind,url] of [
    ["project",`https://cloudresourcemanager.googleapis.com/v3/projects/${p}`],
    ["firebase",`https://firebase.googleapis.com/v1beta1/projects/${p}`],
    ["billing",`https://cloudbilling.googleapis.com/v1/projects/${p}/billingInfo`],
    ["apps",`https://firebase.googleapis.com/v1beta1/projects/${p}:searchApps?pageSize=100`],
  ]) result[`${p}/${kind}`]=hash(JSON.stringify(await request(c,url)));
  return result;
}
async function preflight(c,m) {
  check(!readState(), "Provisioning state already exists; inspect it instead of starting again");
  const [org,billing,orgPermissions,billingPermissions,metrics]=await Promise.all([
    request(c,`https://cloudresourcemanager.googleapis.com/v3/${PARENT}`),
    request(c,`https://cloudbilling.googleapis.com/v1/billingAccounts/${BILLING}`),
    request(c,`https://cloudresourcemanager.googleapis.com/v3/${PARENT}:testIamPermissions`,"POST",{permissions:["resourcemanager.projects.create","resourcemanager.projects.list","resourcemanager.folders.list"]}),
    request(c,`https://cloudbilling.googleapis.com/v1/billingAccounts/${BILLING}:testIamPermissions`,"POST",{permissions:["billing.resourceAssociations.create"]}),
    request(c,`https://serviceusage.googleapis.com/v1beta1/${PARENT}/services/cloudresourcemanager.googleapis.com/consumerQuotaMetrics?view=FULL`),
  ]);
  check(org.name===PARENT && org.state==="ACTIVE" && billing.name===`billingAccounts/${BILLING}` && billing.open, "Parent/billing status mismatch");
  check(["resourcemanager.projects.create","resourcemanager.projects.list","resourcemanager.folders.list"].every(p => orgPermissions.permissions?.includes(p)) &&
    billingPermissions.permissions?.includes("billing.resourceAssociations.create"), "Missing creation, listing or billing-link permission");
  async function descendants(parent) {
    const projects=await list(c,`https://cloudresourcemanager.googleapis.com/v3/projects?parent=${parent}&showDeleted=true&pageSize=100`,"projects");
    const folders=await list(c,`https://cloudresourcemanager.googleapis.com/v3/folders?parent=${parent}&showDeleted=true&pageSize=100`,"folders");
    for(const folder of folders)projects.push(...await descendants(folder.name));
    return projects;
  }
  const projects=await descendants(PARENT);
  check(!projects.some(p=>p.projectId===PROJECT), "Target exists already; ownership not established");
  const quota=metrics.metrics?.find(q=>q.metric==="cloudresourcemanager.googleapis.com/projects_count");
  const limit=Number(quota?.consumerQuotaLimits?.find(q=>q.unit==="1/{organization}")?.quotaBuckets?.[0]?.effectiveLimit);
  check(Number.isFinite(limit) && projects.length<limit, "Creation quota could not be verified or is exhausted");
  let lookupStatus;
  try {await request(c,`https://cloudresourcemanager.googleapis.com/v3/projects/${PROJECT}`);throw Error("Target exists; refusing adoption");}
  catch(e){lookupStatus=e.response?.status;check([403,404].includes(lookupStatus),"Candidate lookup inconclusive for an unexpected reason");}
  const site=await c.request({url:`https://firebasehosting.googleapis.com/v1beta1/sites/${PROJECT}`,method:"GET",retry:false,timeout:15000,validateStatus:()=>true});
  check(site.status===404,"Expected Hosting site is already present or inaccessible");
  const s={schemaVersion:1,projectId:PROJECT,parent:PARENT,billingAccountId:BILLING,runId:crypto.randomUUID(),
    manifestSha256:hash(fs.readFileSync(manifestPath)),catalogSha256:m.catalog.fileSha256,createdAt:new Date().toISOString(),
    preflight:{quotaLimit:limit,organizationProjectCountIncludingDeleted:projects.length,lookupStatus,siteLookupStatus:site.status,
      availability:"checked_by_single_atomic_create_no_name_fallback",permissionsVerified:true},protectedBefore:await fingerprint(c),events:[]};
  save(s);console.log(JSON.stringify({status:"PREFLIGHT_PASSED",...s.preflight}));
}
async function verifyProject(c,s) {
  check(s?.projectId===PROJECT && s.parent===PARENT && s.billingAccountId===BILLING && s.projectNumber && !FORBIDDEN.includes(s.projectNumber), "Missing pinned project identity");
  const p=await request(c,`https://cloudresourcemanager.googleapis.com/v3/projects/${PROJECT}`);
  check(p.name===`projects/${s.projectNumber}` && p.projectId===PROJECT && p.parent===PARENT && p.state==="ACTIVE" &&
    p.labels?.["fatoora-provisioning"]===s.runId, "Project identity/ownership mismatch");
  return p;
}
async function create(c) {
  const s=readState();check(s && !s.creationAttempt && !s.projectNumber,"Creation was already attempted; no automatic retry");
  s.creationAttempt={status:"submitted_once",at:new Date().toISOString()};save(s);
  const operation=await request(c,"https://cloudresourcemanager.googleapis.com/v3/projects","POST",{
    projectId:PROJECT,parent:PARENT,displayName:"Fatoora Original Staging",
    labels:{"fatoora-environment":"staging","fatoora-application":"original","fatoora-provisioning":s.runId},
  });
  check(/^operations\//.test(operation.name),"Unexpected creation operation");
  s.creationAttempt.operation=operation.name;save(s);console.log(JSON.stringify({status:"CREATION_OPERATION_RECORDED",operation:operation.name}));
}
async function pollCreate(c) {
  const s=readState();check(s?.creationAttempt?.operation && !s.projectNumber,"No pending recorded creation operation");
  const op=await request(c,`https://cloudresourcemanager.googleapis.com/v3/${s.creationAttempt.operation}`);
  check(!op.error,`Creation failed: ${JSON.stringify(op.error)}`);
  if(!op.done){console.log(JSON.stringify({status:"CREATION_PENDING"}));return;}
  const p=op.response;
  check(p?.projectId===PROJECT && p.parent===PARENT && p.labels?.["fatoora-provisioning"]===s.runId && /^projects\/\d+$/.test(p.name),"Creation operation identity mismatch");
  s.projectNumber=p.name.split("/")[1];s.creationAttempt.status="verified_complete";save(s);
  await verifyProject(c,s);
  const m=JSON.parse(fs.readFileSync(manifestPath));m.project.number=s.projectNumber;m.project.availability.globallyAvailable=true;m.project.availability.reserved=true;
  fs.writeFileSync(manifestPath,JSON.stringify(m,null,2)+"\n");
  console.log(JSON.stringify({status:"PROJECT_CREATED_AND_PINNED",project:PROJECT,projectNumber:s.projectNumber,parent:PARENT}));
}
async function linkBilling(c) {
  const s=readState();await verifyProject(c,s);
  const url=`https://cloudbilling.googleapis.com/v1/projects/${PROJECT}/billingInfo`;
  const prior=await request(c,url);
  check(!prior.billingAccountName || prior.billingAccountName===`billingAccounts/${BILLING}`,"Unapproved billing assignment");
  if(!prior.billingEnabled) {
    check(!s.billingAttempt,"Billing assignment was already attempted; inspect before retry");
    s.billingAttempt={at:new Date().toISOString(),account:BILLING};save(s);
    await request(c,url,"PUT",{billingAccountName:`billingAccounts/${BILLING}`});
  }
  const result=await request(c,url);
  check(result.projectId===PROJECT && result.billingEnabled && result.billingAccountName===`billingAccounts/${BILLING}`,"Billing assignment verification failed");
  s.billingVerified=true;save(s);console.log(JSON.stringify({status:"APPROVED_BILLING_LINKED",project:PROJECT,billingAccount:BILLING}));
}
async function addFirebase(c) {
  const s=readState();await verifyProject(c,s);check(s.billingVerified && !s.firebaseAttempt,"Firebase addition gate or retry blocked");
  s.firebaseAttempt={status:"submitted_once",at:new Date().toISOString()};save(s);
  const op=await request(c,`https://firebase.googleapis.com/v1beta1/projects/${PROJECT}:addFirebase`,"POST",{});
  check(/^operations\//.test(op.name),"Unexpected Firebase operation");s.firebaseAttempt.operation=op.name;save(s);
  console.log(JSON.stringify({status:"FIREBASE_OPERATION_RECORDED",operation:op.name}));
}
async function pollFirebase(c) {
  const s=readState();await verifyProject(c,s);check(s.firebaseAttempt?.operation,"Missing Firebase operation");
  const op=await request(c,`https://firebase.googleapis.com/v1beta1/${s.firebaseAttempt.operation}`);
  check(!op.error,`Firebase setup failed: ${JSON.stringify(op.error)}`);
  if(!op.done){console.log(JSON.stringify({status:"FIREBASE_PENDING"}));return;}
  const p=await request(c,`https://firebase.googleapis.com/v1beta1/projects/${PROJECT}`);
  check(p.projectId===PROJECT && p.projectNumber===s.projectNumber,"Firebase identity mismatch");
  s.firebaseAttempt.status="verified_complete";s.firebaseVerified=true;save(s);
  console.log(JSON.stringify({status:"FIREBASE_ADDED",project:PROJECT,projectNumber:p.projectNumber}));
}
async function enableServices(c) {
  const s=readState();await verifyProject(c,s);check(s.firebaseVerified && s.billingVerified,"Services require verified Firebase/billing");
  check(!s.servicesAttempt,"Service enablement already attempted; inspect operation");
  const serviceIds=["firebase.googleapis.com","firebasehosting.googleapis.com","firebaserules.googleapis.com",
    "identitytoolkit.googleapis.com","firestore.googleapis.com","cloudfunctions.googleapis.com",
    "cloudbuild.googleapis.com","artifactregistry.googleapis.com","run.googleapis.com","eventarc.googleapis.com",
    "pubsub.googleapis.com","iam.googleapis.com","iamcredentials.googleapis.com","logging.googleapis.com",
    "serviceusage.googleapis.com","storage.googleapis.com"];
  s.servicesAttempt={at:new Date().toISOString(),serviceIds};save(s);
  const op=await request(c,`https://serviceusage.googleapis.com/v1/projects/${s.projectNumber}/services:batchEnable`,"POST",{serviceIds});
  check(/^operations\//.test(op.name),"Unexpected services operation");s.servicesAttempt.operation=op.name;save(s);
  console.log(JSON.stringify({status:"SERVICE_ENABLEMENT_RECORDED",operation:op.name}));
}
async function pollServices(c) {
  const s=readState();await verifyProject(c,s);check(s.servicesAttempt?.operation,"Missing services operation");
  const op=await request(c,`https://serviceusage.googleapis.com/v1/${s.servicesAttempt.operation}`);
  check(!op.error,`Service setup failed: ${JSON.stringify(op.error)}`);
  if(!op.done){console.log(JSON.stringify({status:"SERVICES_PENDING"}));return;}
  const enabled=await list(c,`https://serviceusage.googleapis.com/v1/projects/${s.projectNumber}/services?filter=state:ENABLED&pageSize=200`,"services");
  check(s.servicesAttempt.serviceIds.every(id=>enabled.some(v=>v.config?.name===id && v.state==="ENABLED")),"Required service not enabled");
  s.servicesVerified=true;save(s);console.log(JSON.stringify({status:"REQUIRED_SERVICES_ENABLED",count:s.servicesAttempt.serviceIds.length}));
}
async function createSite(c) {
  const s=readState();await verifyProject(c,s);check(s.servicesVerified && !s.siteAttempt,"Site creation gate or retry blocked");
  const url=`https://firebasehosting.googleapis.com/v1beta1/projects/${PROJECT}/sites`;
  const existing=await list(c,url,"sites");
  check(existing.length<=1,"Unexpected pre-existing Hosting sites; no fallback");
  let site;
  if(existing.length===1) {
    // addFirebase created exactly the approved site's name in this owned project.
    site=existing[0];s.siteAttempt={at:new Date().toISOString(),source:"recorded_addFirebase_operation"};
  } else {
    await request(c,`${url}?siteId=${PROJECT}&validateOnly=true`,"POST",{});
    s.siteAttempt={at:new Date().toISOString(),source:"explicit_create"};save(s);
    site=await request(c,`${url}?siteId=${PROJECT}`,"POST",{});
  }
  check([`projects/${s.projectNumber}/sites/${PROJECT}`,`projects/${PROJECT}/sites/${PROJECT}`].includes(site.name) && site.defaultUrl===`https://${PROJECT}.web.app` && site.type==="DEFAULT_SITE","Unexpected Hosting site identity/type");
  s.site=site;s.siteVerified=true;save(s);console.log(JSON.stringify({status:"EXACT_DEFAULT_HOSTING_SITE_CREATED",site:site.name,url:site.defaultUrl}));
}
async function createApps(c) {
  const s=readState();await verifyProject(c,s);check(s.siteVerified && !s.appOperations,"App-registration gate or retry blocked");
  check((await list(c,`https://firebase.googleapis.com/v1beta1/projects/${PROJECT}:searchApps?pageSize=100`,"apps")).length===0,"Unexpected existing app registrations");
  s.appOperations={};save(s);
  for(const [platform,data] of [
    ["android",{displayName:"Fatoora Original Staging Android",packageName:"com.fujika.fatoora.original.staging"}],
    ["web",{displayName:"Fatoora Original Staging Web"}],
  ]) {
    s.appOperations[platform]={status:"submitted_once",at:new Date().toISOString()};save(s);
    const op=await request(c,`https://firebase.googleapis.com/v1beta1/projects/${PROJECT}/${platform}Apps`,"POST",data);
    check(/^operations\//.test(op.name),"Unexpected registration operation");s.appOperations[platform].operation=op.name;save(s);
  }
  console.log(JSON.stringify({status:"APP_REGISTRATION_OPERATIONS_RECORDED"}));
}
async function pollApps(c) {
  const s=readState();await verifyProject(c,s);check(s.appOperations,"No recorded app operations");
  for(const platform of ["android","web"]) {
    const entry=s.appOperations[platform];check(entry?.operation,"Missing recorded registration operation");
    const op=await request(c,`https://firebase.googleapis.com/v1beta1/${entry.operation}`);
    check(!op.error,`App registration failed: ${JSON.stringify(op.error)}`);
    if(!op.done){console.log(JSON.stringify({status:"APP_REGISTRATION_PENDING",platform}));return;}
    const app=op.response;
    check(app?.projectId===PROJECT && app.appId?.startsWith(`1:${s.projectNumber}:${platform}:`) &&
      app.displayName===`Fatoora Original Staging ${platform==="web"?"Web":"Android"}` &&
      (platform!=="android" || app.packageName==="com.fujika.fatoora.original.staging"),"App registration target mismatch");
    entry.appId=app.appId;entry.status="verified_complete";save(s);
  }
  const m=JSON.parse(fs.readFileSync(manifestPath));
  for(const p of ["web","android"])m[p].appId=s.appOperations[p].appId;
  fs.writeFileSync(manifestPath,JSON.stringify(m,null,2)+"\n");
  s.appsVerified=true;save(s);console.log(JSON.stringify({status:"APPS_CREATED_AND_PINNED",android:m.android.appId,web:m.web.appId}));
}
async function sdkConfigs(c) {
  const s=readState();await verifyProject(c,s);check(s.appsVerified,"Registered apps required");
  for(const platform of ["android","web"]) {
    const appId=s.appOperations[platform].appId;
    const raw=await request(c,`https://firebase.googleapis.com/v1beta1/projects/${PROJECT}/${platform}Apps/${appId}/config`);
    let cfg;
    if(platform==="android") {
      const native=Buffer.from(raw.configFileContents,"base64");
      const parsed=JSON.parse(native.toString("utf8"));
      check(parsed.project_info?.project_id===PROJECT && parsed.project_info.project_number===s.projectNumber && parsed.client?.length===1 &&
        parsed.client[0].client_info?.mobilesdk_app_id===appId && parsed.client[0].client_info?.android_client_info?.package_name==="com.fujika.fatoora.original.staging","Native SDK target mismatch");
      const nativePath=path.join(root,"android/app/src/staging/google-services.json");
      fs.mkdirSync(path.dirname(nativePath),{recursive:true});
      check(!fs.existsSync(nativePath),"Refusing native SDK overwrite");fs.writeFileSync(nativePath,native,{flag:"wx"});
      cfg={apiKey:parsed.client[0].api_key?.[0]?.current_key,appId,projectId:PROJECT,messagingSenderId:s.projectNumber,
        storageBucket:parsed.project_info.storage_bucket||""};
    } else {cfg=raw;check(cfg.projectId===PROJECT && cfg.appId===appId && cfg.messagingSenderId===s.projectNumber,"Web SDK target mismatch");}
    check(typeof cfg.apiKey==="string" && cfg.apiKey.length>20,"Missing returned SDK API key");
    const defines={FATOORA_ENV:"staging",FIREBASE_PROJECT_ID:PROJECT,FIREBASE_PROJECT_ID_CONFIRM:PROJECT,
      FIREBASE_API_KEY:cfg.apiKey,FIREBASE_APP_ID:appId,FIREBASE_MESSAGING_SENDER_ID:s.projectNumber,
      FIREBASE_STORAGE_BUCKET:cfg.storageBucket||"",FIREBASE_AUTH_DOMAIN:cfg.authDomain||""};
    const target=path.join(root,`config/firebase/staging.${platform}.json`);
    check(!fs.existsSync(target),"Refusing Dart SDK overwrite");fs.writeFileSync(target,JSON.stringify(defines,null,2)+"\n",{flag:"wx"});
    s[`${platform}ConfigSha256`]=hash(fs.readFileSync(target));save(s);
  }
  s.sdkVerified=true;save(s);console.log(JSON.stringify({status:"IGNORED_NATIVE_AND_DART_SDK_CONFIGS_SAVED",storageBucketProvisioned:false}));
}
async function createDatabase(c) {
  const s=readState();await verifyProject(c,s);check(s.servicesVerified && !s.databaseAttempt,"Database creation gate or retry blocked");
  const url=`https://firestore.googleapis.com/v1/projects/${PROJECT}/databases`;
  check((await list(c,url,"databases")).length===0,"Unexpected existing database");
  s.databaseAttempt={at:new Date().toISOString()};save(s);
  const op=await request(c,`${url}?databaseId=%28default%29`,"POST",{locationId:"nam5",type:"FIRESTORE_NATIVE",databaseEdition:"STANDARD"});
  check(op.name?.startsWith(`projects/${PROJECT}/databases/`),"Unexpected database operation");
  s.databaseAttempt.operation=op.name;save(s);console.log(JSON.stringify({status:"DATABASE_CREATION_RECORDED",operation:op.name}));
}
async function pollDatabase(c) {
  const s=readState();await verifyProject(c,s);check(s.databaseAttempt?.operation,"Missing database operation");
  const op=await request(c,`https://firestore.googleapis.com/v1/${s.databaseAttempt.operation}`);
  check(!op.error,`Database creation failed: ${JSON.stringify(op.error)}`);
  if(!op.done){console.log(JSON.stringify({status:"DATABASE_PENDING"}));return;}
  const db=await request(c,`https://firestore.googleapis.com/v1/projects/${PROJECT}/databases/(default)`);
  check(db.name===`projects/${PROJECT}/databases/(default)` && db.locationId==="nam5" && db.type==="FIRESTORE_NATIVE" && db.databaseEdition==="STANDARD","Database identity/location mismatch");
  s.databaseVerified=true;save(s);console.log(JSON.stringify({status:"DATABASE_CREATED_AND_VERIFIED",database:db.name,location:db.locationId,edition:db.databaseEdition}));
}
async function initializeAuth(c) {
  const s=readState();await verifyProject(c,s);check(s.siteVerified && s.appsVerified && !s.authAttempt,"Auth initialization gate or retry blocked");c.quotaProjectId=PROJECT;
  s.authAttempt={at:new Date().toISOString(),requestId:crypto.randomUUID()};save(s);
  const op=await request(c,"https://firebase.googleapis.com/v1alpha/firebase:provisionFirebaseApp","POST",{
    parent:`projects/${PROJECT}`,appNamespace:s.appOperations.web.appId,webInput:{},requestId:s.authAttempt.requestId,
    firebaseAuthInput:{emailAuthProviderMode:"PROVIDER_ENABLED",anonymousAuthProviderMode:"PROVIDER_DISABLED",googleSigninProviderMode:"PROVIDER_DISABLED"},
  });
  check(/^operations\//.test(op.name),"Unexpected Auth operation");s.authAttempt.operation=op.name;save(s);
  console.log(JSON.stringify({status:"EMAIL_PASSWORD_INITIALIZATION_RECORDED",operation:op.name}));
}
async function pollAuth(c) {
  const s=readState();await verifyProject(c,s);check(s.authAttempt?.operation,"Missing Auth operation");c.quotaProjectId=PROJECT;
  const op=await request(c,`https://firebase.googleapis.com/v1beta1/${s.authAttempt.operation}`);
  check(!op.error,`Auth initialization failed: ${JSON.stringify(op.error)}`);
  if(!op.done){console.log(JSON.stringify({status:"AUTH_PENDING"}));return;}
  const url=`https://identitytoolkit.googleapis.com/admin/v2/projects/${PROJECT}/config`;
  const authorizedDomains=[`${PROJECT}.firebaseapp.com`,`${PROJECT}.web.app`];
  await request(c,`${url}?updateMask=authorizedDomains`,"PATCH",{authorizedDomains});
  const cfg=await request(c,url);
  check(cfg.signIn?.email?.enabled && cfg.signIn.email.passwordRequired && !cfg.signIn?.anonymous?.enabled && !cfg.signIn?.phoneNumber?.enabled &&
    cfg.authorizedDomains.length===2 && authorizedDomains.every(d=>cfg.authorizedDomains.includes(d)),"Auth configuration mismatch");
  const providers=await list(c,`https://identitytoolkit.googleapis.com/admin/v2/projects/${PROJECT}/defaultSupportedIdpConfigs`,"defaultSupportedIdpConfigs");
  check(!providers.some(v=>v.enabled),"Unexpected OAuth provider enabled");
  s.authVerified=true;s.authAttempt.status="verified_complete";save(s);console.log(JSON.stringify({status:"EMAIL_PASSWORD_AUTH_VERIFIED",authorizedDomains,subtype:cfg.subtype}));
}
async function identities(c) {
  const s=readState();await verifyProject(c,s);check(s.authVerified && s.databaseVerified,"Foundation verification required");c.quotaProjectId=PROJECT;
  const iamUrl=`https://cloudresourcemanager.googleapis.com/v3/projects/${PROJECT}`;
  const prior=await request(c,`${iamUrl}:getIamPolicy`,"POST",{});
  const owners=prior.bindings?.find(b=>b.role==="roles/owner")?.members||[];
  check(owners.length===1 && owners[0]==="user:jayatwehtrading@gmail.com","Unexpected bootstrap project owner");
  check(!prior.bindings.some(b=>b.members?.some(v=>v==="allUsers"||v==="allAuthenticatedUsers"||
    (v.startsWith("serviceAccount:") && !v.includes(PROJECT) && !v.includes(s.projectNumber)))),"Cross-project/public project IAM binding detected");
  const deployer=`fatoora-staging-deployer@${PROJECT}.iam.gserviceaccount.com`;
  const runtime=`${s.projectNumber}-compute@developer.gserviceaccount.com`;
  for(const service of ["pubsub.googleapis.com","eventarc.googleapis.com"]) {
    const op=await request(c,`https://serviceusage.googleapis.com/v1beta1/projects/${s.projectNumber}/services/${service}:generateServiceIdentity`,"POST",{});
    check(op.done && !op.error && op.response?.email?.includes(s.projectNumber),"Managed service identity is not ready");
  }
  const saUrl=`https://iam.googleapis.com/v1/projects/${PROJECT}/serviceAccounts`;
  const accounts=await list(c,saUrl,"accounts");
  check(accounts.some(a=>a.email===runtime && a.projectId===PROJECT),"Missing project-local runtime account");
  const existing=accounts.find(a=>a.email===deployer);
  if(existing)check(existing.description===`Original Fatoora staging provisioning ${s.runId}`,"Unknown deploy identity ownership");
  else {
    check(!s.deployerCreateAttempt,"Uncertain deployer creation; inspect before retry");s.deployerCreateAttempt=true;save(s);
    await request(c,saUrl,"POST",{accountId:"fatoora-staging-deployer",serviceAccount:{displayName:"Original Fatoora staging deployer",description:`Original Fatoora staging provisioning ${s.runId}`}});
  }
  const roleId="fatooraStagingDeploymentTransport";
  const roleName=`projects/${PROJECT}/roles/${roleId}`;
  const includedPermissions=["resourcemanager.projects.getIamPolicy","run.services.getIamPolicy","run.services.setIamPolicy","cloudfunctions.functions.setIamPolicy",
    "serviceusage.services.get","serviceusage.services.list"];
  let role;
  try{role=await request(c,`https://iam.googleapis.com/v1/${roleName}`);}catch(e){if(e.response?.status!==404)throw e;}
  if(role){check(role.description===`Provisioning ${s.runId}` && role.includedPermissions.every(p=>includedPermissions.includes(p)),"Existing deployment role differs");
    if(role.includedPermissions.length!==includedPermissions.length)await request(c,`https://iam.googleapis.com/v1/${roleName}?updateMask=includedPermissions`,"PATCH",{...role,includedPermissions});}
  else await request(c,`https://iam.googleapis.com/v1/projects/${PROJECT}/roles`,"POST",{roleId,role:{title:"Staging deployment transport",description:`Provisioning ${s.runId}`,stage:"GA",includedPermissions}});
  const policy=await request(c,`${iamUrl}:getIamPolicy`,"POST",{});
  const additions=[
    ...["roles/cloudfunctions.developer","roles/datastore.indexAdmin","roles/firebaserules.admin","roles/firebasehosting.admin",
      "roles/firebase.viewer","roles/serviceusage.serviceUsageConsumer","roles/artifactregistry.reader","roles/cloudbuild.builds.viewer",roleName]
      .map(role=>[role,`serviceAccount:${deployer}`]),
    ...["roles/datastore.user","roles/logging.logWriter","roles/eventarc.eventReceiver","roles/run.invoker"]
      .map(role=>[role,`serviceAccount:${runtime}`]),
    ["roles/iam.serviceAccountTokenCreator",`serviceAccount:service-${s.projectNumber}@gcp-sa-pubsub.iam.gserviceaccount.com`],
  ];
  for(const [role,member]of additions){let b=policy.bindings.find(b=>b.role===role&&!b.condition);if(!b){b={role,members:[]};policy.bindings.push(b);}if(!b.members.includes(member))b.members.push(member);}
  await request(c,`${iamUrl}:setIamPolicy`,"POST",{policy,updateMask:"bindings,etag"});
  for(const account of [deployer,runtime,`${PROJECT}@appspot.gserviceaccount.com`]) {
    const url=`${saUrl}/${account}`;
    const policy=await request(c,`${url}:getIamPolicy`,"POST",{});policy.bindings=policy.bindings||[];
    const grants=account===deployer ? [["roles/iam.serviceAccountTokenCreator",owners[0]]] : [["roles/iam.serviceAccountUser",`serviceAccount:${deployer}`]];
    for(const [role,member]of grants){let b=policy.bindings.find(b=>b.role===role&&!b.condition);if(!b){b={role,members:[]};policy.bindings.push(b);}if(!b.members.includes(member))b.members.push(member);}
    await request(c,`${url}:setIamPolicy`,"POST",{policy});
  }
  s.deployer=deployer;s.runtimeServiceAccount=runtime;s.identitiesVerified=true;save(s);
  console.log(JSON.stringify({status:"SCOPED_STAGING_IDENTITIES_CONFIGURED",deployer,runtime,exportedKeys:0,projectEditorGrants:0}));
}
async function verifyIndexes(c) {
  const s=readState();await verifyProject(c,s);check(s.deployments?.rules?.completed,"Rules deployment not complete");
  const indexes=await list(c,`https://firestore.googleapis.com/v1/projects/${PROJECT}/databases/(default)/collectionGroups/-/indexes`,"indexes");
  const expected=JSON.parse(fs.readFileSync(path.join(root,"firestore.indexes.json"))).indexes;
  function key(group,scope,fields){return JSON.stringify([group,scope,fields.filter(f=>f.fieldPath!=="__name__")]);}
  const keys=new Set(indexes.map(i=>key(i.name.split("/collectionGroups/")[1].split("/")[0],i.queryScope,i.fields)));
  check(indexes.length===expected.length && expected.every(i=>keys.has(key(i.collectionGroup,i.queryScope,i.fields))),"Deployed indexes differ from the reviewed artifact");
  check(!indexes.some(i=>i.state==="NEEDS_REPAIR"),"Index creation failed");
  const ready=indexes.filter(i=>i.state==="READY").length;
  if(ready===expected.length){s.indexesVerified=true;save(s);}
  console.log(JSON.stringify({status:ready===expected.length?"REVIEWED_INDEXES_READY":"INDEXES_BUILDING",expected:expected.length,ready}));
}
async function verifyFunctions(c) {
  const s=readState();await verifyProject(c,s);check(s.deployments?.functions?.sourceHashes,"No recorded reviewed Functions artifact");
  const functions=await list(c,`https://cloudfunctions.googleapis.com/v2/projects/${PROJECT}/locations/-/functions`,"functions");
  const source=fs.readFileSync(path.join(root,"functions/src/index.ts"),"utf8");
  const expected=source.match(/export\s*\{([^}]+)\}/s)[1].split(",").map(v=>v.trim()).filter(Boolean);
  check(functions.length===expected.length && expected.every(name=>functions.some(f=>f.name===`projects/${PROJECT}/locations/us-central1/functions/${name}`)),"Deployed exports do not match reviewed source");
  check(functions.every(f=>f.state==="ACTIVE" && f.buildConfig?.runtime==="nodejs22" && f.serviceConfig?.serviceAccountEmail===s.runtimeServiceAccount &&
    f.buildConfig.serviceAccount?.endsWith(s.buildServiceAccount.split("/").at(-1)) && !(f.serviceConfig.minInstanceCount>0) &&
    f.labels?.["firebase-functions-codebase"]===PROJECT && (!f.eventTrigger || f.eventTrigger.eventFilters?.every(v=>v.attribute!=="database" || v.value==="(default)"))),"Function state/runtime/service identity mismatch");
  const sourceVerification=await require("./staging-source-artifact.cjs").verifySourceArtifacts(c,s,functions);
  s.sourceArtifactsVerified=true;s.sourceArtifactHashes=sourceVerification.artifacts.map(a=>a.sha256);
  if(s.runtimeCompatibility?.reviewed)s.runtimeCompatibility.deployed=true;
  s.deployments.functions.completed=true;s.deployments.functions.verification="All exact exports ACTIVE; source archives match; optional deletion policy skipped";
  s.functionsVerified=true;s.functionResources=functions.map(f=>({name:f.name,uri:f.serviceConfig.uri,revision:f.serviceConfig.revision,build:f.buildConfig.build,source:f.buildConfig.source,updateTime:f.updateTime}));save(s);
  console.log(JSON.stringify({status:"REVIEWED_FUNCTIONS_VERIFIED",functions:functions.length,region:"us-central1",runtime:"nodejs22",runtimeIdentity:s.runtimeServiceAccount}));
}
async function callableTransport(c) {
  const s=readState();await verifyProject(c,s);check(s.functionsVerified&&s.sourceArtifactsVerified,"Verified Functions artifact required");
  process.env.GCLOUD_PROJECT=PROJECT;process.env.FIREBASE_CONFIG=JSON.stringify({projectId:PROJECT});
  const endpoints=require(path.join(root,"build/staging/functions/lib/staging-entry.cjs"));
  check(Object.keys(endpoints).length===35,"Unexpected packaged export count");
  const functions=await list(c,`https://cloudfunctions.googleapis.com/v2/projects/${PROJECT}/locations/-/functions`,"functions");
  const deployer=new (load("google-auth-library").Impersonated)({sourceClient:c,targetPrincipal:s.deployer,targetScopes:["https://www.googleapis.com/auth/cloud-platform"],lifetime:600});
  s.callableTransport=s.callableTransport||{before:{}};
  let callables=0,events=0;
  for(const f of functions) {
    const name=f.name.split("/").at(-1),endpoint=endpoints[name]?.__endpoint;
    check(endpoint&&f.state==="ACTIVE"&&f.labels?.["firebase-functions-codebase"]===PROJECT,"Unreviewed service");
    const service=f.serviceConfig.service;
    check(service.startsWith(`projects/${PROJECT}/locations/us-central1/services/`),"Wrong service project");
    const url=`https://run.googleapis.com/v1/${service}`;
    let policy=await request(deployer,`${url}:getIamPolicy`);
    const publicBindings=(policy.bindings||[]).filter(b=>b.members?.includes("allUsers")||b.members?.includes("allAuthenticatedUsers"));
    if(endpoint.callableTrigger) {
      check(!f.eventTrigger&&publicBindings.every(b=>b.role==="roles/run.invoker"&&!b.condition&&!b.members.includes("allAuthenticatedUsers")),"Unexpected callable policy");
      if(!s.callableTransport.before[name]){s.callableTransport.before[name]=policy;save(s);}
      if(!publicBindings.some(b=>b.members.includes("allUsers"))) {
        policy.bindings=policy.bindings||[];
        const binding=policy.bindings.find(b=>b.role==="roles/run.invoker"&&!b.condition);
        if(binding)binding.members.push("allUsers");else policy.bindings.push({role:"roles/run.invoker",members:["allUsers"]});
        await request(deployer,`${url}:setIamPolicy`,"POST",{policy});
      }
      policy=await request(deployer,`${url}:getIamPolicy`);
      check(policy.bindings?.some(b=>b.role==="roles/run.invoker"&&!b.condition&&b.members.includes("allUsers")),"Callable transport not configured");
      callables++;
    }else{check(endpoint.eventTrigger&&f.eventTrigger&&publicBindings.length===0,"Event service must remain private");events++;}
  }
  check(callables===23&&events===12,"Unexpected callable/event service counts");
  s.callableTransport.verified=true;s.callableTransport.at=new Date().toISOString();s.callableTransport.callables=callables;s.callableTransport.privateEventServices=events;save(s);
  console.log(JSON.stringify({status:"CALLABLE_TRANSPORT_CONFIGURED_AND_VERIFIED",callables,privateEventServices:events,applicationAuthorizationUnchanged:true}));
}
async function finalVerification(c) {
  const s=readState();await verifyProject(c,s);const after=await fingerprint(c);
  check(JSON.stringify(s.protectedBefore)===JSON.stringify(after),"Protected metadata changed");
  const billing=await request(c,`https://cloudbilling.googleapis.com/v1/projects/${PROJECT}/billingInfo`);
  check(billing.billingEnabled&&billing.billingAccountName===`billingAccounts/${BILLING}`,"Billing target changed");
  const baseline=JSON.parse(fs.readFileSync(path.join(root,"build/staging-plan/approved-preflight-online.json")));
  const protectedFiles=[".firebaserc","firebase.json","lib/firebase_options.dart","android/app/google-services.json","firestore.rules","firestore.indexes.json","functions/src/index.ts"];
  for(const file of protectedFiles)check(hash(fs.readFileSync(path.join(root,file)))===baseline.localFiles.before[file],`Protected configuration changed: ${file}`);
  const policy=await request(c,`https://cloudresourcemanager.googleapis.com/v3/projects/${PROJECT}:getIamPolicy`,"POST",{});
  // Google creates this internal service agent with its documented legacy role.
  // Do not treat it as an application/deployment identity or guess a replacement.
  const managedLegacyAgent=`serviceAccount:${s.projectNumber}@cloudservices.gserviceaccount.com`;
  check(!policy.bindings.some(b=>["roles/editor","roles/owner"].includes(b.role)&&b.members.some(m=>m.startsWith("serviceAccount:")&&!(b.role==="roles/editor"&&m===managedLegacyAgent))),"Overprivileged application/deployment identity");
  const identities=[s.deployer,s.runtimeServiceAccount,s.buildServiceAccount.split("/").at(-1)];
  for(const email of identities){
    const url=`https://iam.googleapis.com/v1/projects/${PROJECT}/serviceAccounts/${email}`;
    const keys=await list(c,`${url}/keys?keyTypes=USER_MANAGED`,"keys");check(keys.length===0,"Unexpected exported service-account key");
    const saPolicy=await request(c,`${url}:getIamPolicy`,"POST",{});
    check(!(saPolicy.bindings||[]).some(b=>b.condition?.title===s.isolationProbe?.title||b.role===s.isolationProbe?.role),"Temporary isolation probe grant remains");
  }
  check(s.isolationProbe?.removedAt&&s.serviceIsolationVerified,"Service isolation not verified");
  const release=await request(c,`https://firebaserules.googleapis.com/v1/projects/${PROJECT}/releases/cloud.firestore`);
  const ruleset=await request(c,`https://firebaserules.googleapis.com/v1/${release.rulesetName}`);
  check(ruleset.source?.files?.some(f=>f.name==="firestore.rules"&&hash(f.content)===hash(fs.readFileSync(path.join(root,"firestore.rules")))),"Deployed Rules differ from reviewed source");
  s.finalVerification={at:new Date().toISOString(),projectNumber:s.projectNumber,parent:PARENT,billingAccount:BILLING,billingEnabled:true,protectedMetadataUnchanged:true,protectedMetadataFingerprints:after,protectedLocalFilesUnchanged:protectedFiles,serviceAccountExportedKeys:0,temporaryProbeGrants:0,reviewedRulesVerified:true,googleManagedLegacyEditor:policy.bindings.some(b=>b.role==="roles/editor"&&b.members.includes(managedLegacyAgent))?managedLegacyAgent:null};save(s);
  fs.writeFileSync(path.join(root,"build/staging/final-verification.json"),JSON.stringify(s.finalVerification,null,2)+"\n");
  console.log(JSON.stringify({status:"IDENTITY_BILLING_RULES_IAM_AND_PROTECTED_METADATA_VERIFIED",projectNumber:s.projectNumber,protectedMetadataUnchanged:true,exportedKeys:0,temporaryGrants:0}));
}
async function buildIdentity(c) {
  const s=readState();await verifyProject(c,s);check(s.deployments?.functions?.sourceHashes && s.identitiesVerified,"Recorded reviewed artifact and deployment identity required");
  const f=await request(c,`https://cloudfunctions.googleapis.com/v2/projects/${PROJECT}/locations/us-central1/functions/listAccessibleCustomers`);
  check(f.labels?.["firebase-functions-codebase"]===PROJECT,"Unowned failed function");
  const bucket=f.buildConfig?.source?.storageSource?.bucket;
  check(bucket?.startsWith(`gcf-v2-sources-${s.projectNumber}-`),"Unexpected Functions source bucket");
  const bucketInfo=await request(c,`https://storage.googleapis.com/storage/v1/b/${bucket}?fields=name,projectNumber`);
  check(bucketInfo.name===bucket && bucketInfo.projectNumber===s.projectNumber,"Source bucket belongs to another project");
  s.sourceBucket=bucket;save(s);
  const builder=`fatoora-staging-builder@${PROJECT}.iam.gserviceaccount.com`,saBase=`https://iam.googleapis.com/v1/projects/${PROJECT}/serviceAccounts`;
  let account;try{account=await request(c,`${saBase}/${builder}`);}catch(e){if(e.response?.status!==404)throw e;}
  if(account)check(account.description===`Original Fatoora staging builds ${s.runId}`,"Unknown build identity ownership");
  else await request(c,saBase,"POST",{accountId:"fatoora-staging-builder",serviceAccount:{displayName:"Original Fatoora staging builder",description:`Original Fatoora staging builds ${s.runId}`}});
  function add(policy,role,member){policy.bindings=policy.bindings||[];let b=policy.bindings.find(b=>b.role===role&&!b.condition);if(!b){b={role,members:[]};policy.bindings.push(b);}if(!b.members.includes(member))b.members.push(member);return policy;}
  const member=`serviceAccount:${builder}`;
  const projectUrl=`https://cloudresourcemanager.googleapis.com/v3/projects/${PROJECT}`;
  let policy=await request(c,`${projectUrl}:getIamPolicy`,"POST",{});add(policy,"roles/logging.logWriter",member);await request(c,`${projectUrl}:setIamPolicy`,"POST",{policy,updateMask:"bindings,etag"});
  const sourceUrl=`https://storage.googleapis.com/storage/v1/b/${bucket}/iam`;
  policy=await request(c,sourceUrl);add(policy,"roles/storage.objectViewer",member);await request(c,sourceUrl,"PUT",policy);
  const repoUrl=`https://artifactregistry.googleapis.com/v1/projects/${PROJECT}/locations/us-central1/repositories/gcf-artifacts`;
  const repo=await request(c,repoUrl);check(repo.name===`projects/${PROJECT}/locations/us-central1/repositories/gcf-artifacts`,"Artifact repository mismatch");
  policy=await request(c,`${repoUrl}:getIamPolicy`);add(policy,"roles/artifactregistry.writer",member);await request(c,`${repoUrl}:setIamPolicy`,"POST",{policy});
  const builderUrl=`${saBase}/${builder}`;policy=await request(c,`${builderUrl}:getIamPolicy`,"POST",{});add(policy,"roles/iam.serviceAccountUser",`serviceAccount:${s.deployer}`);await request(c,`${builderUrl}:setIamPolicy`,"POST",{policy});
  s.buildServiceAccount=`projects/${PROJECT}/serviceAccounts/${builder}`;s.buildIdentityVerified=true;save(s);
  console.log(JSON.stringify({status:"SEPARATE_SCOPED_BUILD_IDENTITY_CONFIGURED",buildServiceAccount:s.buildServiceAccount,sourceBucket:bucket,artifactRepository:repo.name,runtimePermissionsExpanded:false}));
}
async function repairTrigger(c,name="projectInvoiceSearch") {
  const s=readState();await verifyProject(c,s);check(s.buildIdentityVerified,"Verified dedicated builder required");
  for(const [file,sha]of Object.entries(s.deployments.functions.sourceHashes))check(hash(fs.readFileSync(path.join(root,file)))===sha,"Reviewed source changed during repair");
  const url=`https://cloudfunctions.googleapis.com/v2/projects/${PROJECT}/locations/us-central1/functions/${name}`;
  const f=await request(c,url);
  check(f.state==="FAILED" && !f.serviceConfig && !f.eventTrigger && f.labels?.["firebase-functions-codebase"]===PROJECT,
    "Repair permits only the owned, never-deployed failed placeholder without a service or trigger");
  const canary=await request(c,`https://cloudfunctions.googleapis.com/v2/projects/${PROJECT}/locations/us-central1/functions/listAccessibleCustomers`);
  check(canary.state==="ACTIVE" && canary.buildConfig?.source?.storageSource?.bucket===s.sourceBucket &&
    canary.buildConfig.serviceAccount?.endsWith(s.buildServiceAccount.split("/").at(-1)),"Successful owned builder canary required");
  process.env.GCLOUD_PROJECT=PROJECT;process.env.FIREBASE_CONFIG=JSON.stringify({projectId:PROJECT});
  const compiled=JSON.parse(JSON.stringify(load("./lib/index.js")[name].__endpoint));
  check(/^google\.cloud\.firestore\.document\.v1\.(created|written)(\.withAuthContext)?$/.test(compiled.eventTrigger?.eventType) &&
    compiled.eventTrigger.eventFilters?.database==="(default)" &&
    /^(companies\/\{companyId\}\/|items\/|users\/)/.test(compiled.eventTrigger.eventFilterPathPatterns?.document),"Reviewed trigger differs");
  const fbRoot=path.join(process.env.APPDATA,"npm/node_modules/firebase-tools");
  const fbLoad=require("node:module").createRequire(path.join(fbRoot,"package.json"));
  const endpoint={...compiled,project:PROJECT,region:"us-central1",id:name,entryPoint:name,runtime:"nodejs22",codebase:PROJECT,
    source:canary.buildConfig.source,serviceAccount:s.runtimeServiceAccount,labels:f.labels,
    availableMemoryMb:compiled.availableMemoryMb??256,timeoutSeconds:compiled.timeoutSeconds??60,
    concurrency:compiled.concurrency??canary.serviceConfig.maxInstanceRequestConcurrency??80,cpu:compiled.cpu??canary.serviceConfig.availableCpu??1,
    environmentVariables:{...canary.serviceConfig.environmentVariables,FUNCTION_TARGET:name},eventTrigger:{...compiled.eventTrigger,region:"nam5"}};
  const body=fbLoad("./lib/gcp/cloudfunctionsv2").functionFromEndpoint(endpoint);
  body.buildConfig.serviceAccount=s.buildServiceAccount;body.buildConfig.environmentVariables={GOOGLE_NODE_RUN_SCRIPTS:""};
  check(body.eventTrigger?.triggerRegion==="nam5" && body.buildConfig.source.storageSource.bucket===s.sourceBucket,"Repair target/source mismatch");
  s.triggerRepairs=s.triggerRepairs||{};
  const prior=s.triggerRepairs[name]||(name==="projectInvoiceSearch"?s.triggerRepairAttempt:null);
  if(prior){check(prior.rejectedHttpStatus===400 && !prior.operation,"Trigger repair outcome is uncertain; inspect the recorded operation");s.rejectedRepairRequests=[...(s.rejectedRepairRequests||[]),prior];}
  const attempt={name,at:new Date().toISOString(),requestSha256:hash(JSON.stringify(body))};s.triggerRepairs[name]=attempt;
  if(name==="projectInvoiceSearch")s.triggerRepairAttempt=attempt;save(s);
  const im=new (load("google-auth-library").Impersonated)({sourceClient:c,targetPrincipal:s.deployer,targetScopes:["https://www.googleapis.com/auth/cloud-platform"],lifetime:1800});
  let op;try{op=await request(im,`${url}?updateMask=buildConfig,serviceConfig,eventTrigger,labels`,"PATCH",body);}catch(e){attempt.rejectedHttpStatus=e.response?.status||null;save(s);throw e;}
  check(op.name?.startsWith(`projects/${PROJECT}/locations/us-central1/operations/`),"Unexpected repair operation");
  attempt.operation=op.name;save(s);console.log(JSON.stringify({status:"NONDESTRUCTIVE_FAILED_TRIGGER_REPAIR_SUBMITTED",function:name,operation:op.name}));
}
async function repairRemainingTriggers(c) {
  let s=readState();await verifyProject(c,s);check(s.triggerRepairAttempt?.verified,"The first in-place repair must be verified before expanding");
  process.env.GCLOUD_PROJECT=PROJECT;process.env.FIREBASE_CONFIG=JSON.stringify({projectId:PROJECT});
  const exports=load("./lib/index.js");
  for(const [name,fn]of Object.entries(exports)) {
    if(!fn.__endpoint?.eventTrigger || name==="projectInvoiceSearch")continue;
    const f=await request(c,`https://cloudfunctions.googleapis.com/v2/projects/${PROJECT}/locations/us-central1/functions/${name}`);
    if(f.state==="ACTIVE" && f.eventTrigger)continue;
    await repairTrigger(c,name);
  }
}
async function pollRemainingRepairs(c) {
  const s=readState();await verifyProject(c,s);let pending=0,verified=0;
  for(const attempt of Object.values(s.triggerRepairs||{})) {
    check(attempt.operation,"Missing recorded background repair operation");
    const op=await request(c,`https://cloudfunctions.googleapis.com/v2/${attempt.operation}`);
    check(!op.error,`Background repair failed: ${JSON.stringify(op.error)}`);
    if(!op.done){pending++;continue;}
    const f=await request(c,`https://cloudfunctions.googleapis.com/v2/projects/${PROJECT}/locations/us-central1/functions/${attempt.name}`);
    check(f.state==="ACTIVE" && f.eventTrigger?.triggerRegion==="nam5" && f.labels?.["firebase-functions-codebase"]===PROJECT,"Background repair mismatch");
    attempt.verified=true;verified++;
  }
  save(s);console.log(JSON.stringify({status:pending?"BACKGROUND_REPAIRS_PENDING":"BACKGROUND_REPAIRS_VERIFIED",pending,verified,firstRepairVerified:s.triggerRepairAttempt?.verified}));
}
async function pollTriggerRepair(c) {
  const s=readState();await verifyProject(c,s);check(s.triggerRepairAttempt?.operation,"Missing recorded repair operation");
  const op=await request(c,`https://cloudfunctions.googleapis.com/v2/${s.triggerRepairAttempt.operation}`);
  check(!op.error,`In-place trigger repair failed: ${JSON.stringify(op.error)}`);
  if(!op.done){console.log(JSON.stringify({status:"TRIGGER_REPAIR_PENDING"}));return;}
  const f=await request(c,`https://cloudfunctions.googleapis.com/v2/projects/${PROJECT}/locations/us-central1/functions/projectInvoiceSearch`);
  check(f.state==="ACTIVE" && f.eventTrigger?.eventType==="google.cloud.firestore.document.v1.written" && f.eventTrigger.triggerRegion==="nam5", "In-place trigger repair verification failed");
  s.triggerRepairAttempt.verified=true;save(s);console.log(JSON.stringify({status:"FAILED_TRIGGER_REPAIRED_WITHOUT_DELETION"}));
}
async function isolationProbe(c,finish=false) {
  const s=readState();await verifyProject(c,s);
  const principals=[s.runtimeServiceAccount,s.buildServiceAccount?.split("/").at(-1)];check(principals.every(Boolean),"Missing staging identities");
  const roleId="fatooraStagingIsolationProbe",roleName=`projects/${PROJECT}/roles/${roleId}`;
  if(!finish) {
    let role;try{role=await request(c,`https://iam.googleapis.com/v1/${roleName}`);}catch(e){if(e.response?.status!==404)throw e;}
    if(role)check(role.description===`Isolation probe ${s.runId}` && role.includedPermissions.length===1 && role.includedPermissions[0]==="iam.serviceAccounts.getAccessToken","Probe role ownership mismatch");
    else await request(c,`https://iam.googleapis.com/v1/projects/${PROJECT}/roles`,"POST",{roleId,role:{title:"Staging isolation token probe",description:`Isolation probe ${s.runId}`,stage:"GA",includedPermissions:["iam.serviceAccounts.getAccessToken"]}});
    check(!s.isolationProbe,"Probe already recorded; inspect before resuming");
    s.isolationProbe={title:`staging-isolation-${s.runId}`,expiresAt:new Date(Date.now()+600000).toISOString(),principals,role:roleName};save(s);
  } else check(s.isolationProbe && s.serviceIsolationVerified,"Successful isolation tests required before finishing probe");
  for(const email of principals) {
    const url=`https://iam.googleapis.com/v1/projects/${PROJECT}/serviceAccounts/${email}`;
    const policy=await request(c,`${url}:getIamPolicy`,"POST",{options:{requestedPolicyVersion:3}});policy.version=3;policy.bindings=policy.bindings||[];
    if(finish)policy.bindings=policy.bindings.filter(b=>b.condition?.title!==s.isolationProbe.title);
    else policy.bindings.push({role:roleName,members:["user:jayatwehtrading@gmail.com"],condition:{title:s.isolationProbe.title,expression:`request.time < timestamp('${s.isolationProbe.expiresAt}')`}});
    await request(c,`${url}:setIamPolicy`,"POST",{policy});
  }
  if(finish){s.isolationProbe.removedAt=new Date().toISOString();save(s);}
  console.log(JSON.stringify({status:finish?"TEMPORARY_PROBE_GRANTS_REMOVED":"TEN_MINUTE_RESOURCE_SCOPED_PROBE_ENABLED",serviceAccounts:principals.length,keysExported:0}));
}
async function main() {
  const action=process.argv[2];check(process.argv.length===3,"One explicit action required");
  if(action==="verify-local"){console.log(JSON.stringify({status:"LOCAL_STAGING_TARGETS_VERIFIED",...validateLocal()}));return;}
  const m=context();const c=await client();
  if(action==="preflight")await preflight(c,m);
  else if(action==="create")await create(c);
  else if(action==="poll-create")await pollCreate(c);
  else if(action==="link-billing")await linkBilling(c);
  else if(action==="add-firebase")await addFirebase(c);
  else if(action==="poll-firebase")await pollFirebase(c);
  else if(action==="enable-services")await enableServices(c);
  else if(action==="poll-services")await pollServices(c);
  else if(action==="create-site")await createSite(c);
  else if(action==="create-apps")await createApps(c);
  else if(action==="poll-apps")await pollApps(c);
  else if(action==="sdk-configs")await sdkConfigs(c);
  else if(action==="inspect-auth") {const s=readState();await verifyProject(c,s);c.quotaProjectId=PROJECT;const config=await request(c,`https://identitytoolkit.googleapis.com/admin/v2/projects/${PROJECT}/config`);console.log(JSON.stringify({name:config.name,signIn:config.signIn,authorizedDomains:config.authorizedDomains,subtype:config.subtype},null,2));}
  else if(action==="inspect-iam") {const s=readState();await verifyProject(c,s);console.log(JSON.stringify({policy:await request(c,`https://cloudresourcemanager.googleapis.com/v3/projects/${PROJECT}:getIamPolicy`,"POST",{}),serviceAccounts:await list(c,`https://iam.googleapis.com/v1/projects/${PROJECT}/serviceAccounts`,"accounts")},null,2));}
  else if(action==="inspect-build") {const s=readState();await verifyProject(c,s);const build=await request(c,`https://cloudbuild.googleapis.com/v1/projects/${PROJECT}/locations/us-central1/builds/5298cb06-56c2-45b9-bd16-af985126b238`);console.log(JSON.stringify({id:build.id,status:build.status,statusDetail:build.statusDetail,failureInfo:build.failureInfo,warnings:build.warnings,serviceAccount:build.serviceAccount,source:build.source,options:build.options},null,2));const policy=await request(c,`https://cloudresourcemanager.googleapis.com/v3/projects/${PROJECT}:getIamPolicy`,"POST",{});console.log(JSON.stringify({managedRoles:policy.bindings.filter(b=>b.members?.some(v=>v.includes("gcp-sa-eventarc")||v.includes("gcf-admin")))}));}
  else if(action==="inspect-latest-build") {const s=readState();await verifyProject(c,s);const builds=await request(c,`https://cloudbuild.googleapis.com/v1/projects/${PROJECT}/locations/us-central1/builds?pageSize=1`);const b=builds.builds?.[0];check(b,"Missing build");console.log(JSON.stringify({id:b.id,status:b.status,serviceAccount:b.serviceAccount,failureInfo:b.failureInfo},null,2));c.quotaProjectId=PROJECT;const logs=await request(c,"https://logging.googleapis.com/v2/entries:list","POST",{resourceNames:[`projects/${PROJECT}`],filter:`resource.type="build" AND resource.labels.build_id="${b.id}" AND severity>=ERROR`,pageSize:10,orderBy:"timestamp desc"});console.log(JSON.stringify(logs.entries?.map(e=>({severity:e.severity,text:e.textPayload,json:e.jsonPayload}))||[],null,2));}
  else if(action==="inspect-failed-trigger") {const s=readState();await verifyProject(c,s);const f=await request(c,`https://cloudfunctions.googleapis.com/v2/projects/${PROJECT}/locations/us-central1/functions/projectInvoiceSearch`);console.log(JSON.stringify({name:f.name,state:f.state,eventTrigger:f.eventTrigger,serviceConfig:f.serviceConfig,labels:f.labels,stateMessages:f.stateMessages},null,2));process.env.GCLOUD_PROJECT=PROJECT;process.env.FIREBASE_CONFIG=JSON.stringify({projectId:PROJECT});console.log(JSON.stringify({reviewedEndpoint:load("./lib/index.js").projectInvoiceSearch.__endpoint},null,2));}
  else if(action==="create-database")await createDatabase(c);
  else if(action==="poll-database")await pollDatabase(c);
  else if(action==="initialize-auth")await initializeAuth(c);
  else if(action==="poll-auth")await pollAuth(c);
  else if(action==="identities")await identities(c);
  else if(action==="verify-indexes")await verifyIndexes(c);
  else if(action==="verify-functions")await verifyFunctions(c);
  else if(action==="configure-callable-transport")await callableTransport(c);
  else if(action==="build-identity")await buildIdentity(c);
  else if(action==="repair-failed-trigger")await repairTrigger(c);
  else if(action==="poll-trigger-repair")await pollTriggerRepair(c);
  else if(action==="repair-remaining-triggers")await repairRemainingTriggers(c);
  else if(action==="poll-remaining-repairs")await pollRemainingRepairs(c);
  else if(action==="start-isolation-probe")await isolationProbe(c);
  else if(action==="finish-isolation-probe")await isolationProbe(c,true);
  else if(action==="verify-service-isolation") {const s=readState();await verifyProject(c,s);for(const principal of [s.runtimeServiceAccount,s.deployer,s.buildServiceAccount?.split("/").at(-1)]) {check(principal,"Missing scoped identity");const im=new (load("google-auth-library").Impersonated)({sourceClient:c,targetPrincipal:principal,targetScopes:["https://www.googleapis.com/auth/cloud-platform"],lifetime:600});for(const p of [FORBIDDEN[0],FORBIDDEN[2]]){const permissions=await request(im,`https://cloudresourcemanager.googleapis.com/v1/projects/${p}:testIamPermissions`,"POST",{permissions:["resourcemanager.projects.get","datastore.entities.get","datastore.entities.create","cloudfunctions.functions.update"]});check(!(permissions.permissions||[]).length,"Staging principal can access a protected project");}}s.serviceIsolationVerified=true;save(s);console.log(JSON.stringify({status:"ALL_THREE_STAGING_IDENTITIES_DENIED_BOTH_PROTECTED_PROJECTS"}));}
  else if(action==="enable-extension-inspection") {const s=readState();await verifyProject(c,s);const op=await request(c,`https://serviceusage.googleapis.com/v1/projects/${s.projectNumber}/services/firebaseextensions.googleapis.com:enable`,"POST",{});s.extensionsInspectionOperation=op.name;save(s);console.log(JSON.stringify({status:"STAGING_CLI_INSPECTION_DEPENDENCY_RECORDED",operation:op.name,extensionsInstalled:0}));}
  else if(action==="enable-billing-inspection") {const s=readState();await verifyProject(c,s);const op=await request(c,`https://serviceusage.googleapis.com/v1/projects/${s.projectNumber}/services/cloudbilling.googleapis.com:enable`,"POST",{});s.billingInspectionOperation=op.name;save(s);console.log(JSON.stringify({status:"STAGING_BILLING_INSPECTION_DEPENDENCY_RECORDED",operation:op.name}));}
  else if(action==="verify-extensions") {const s=readState();await verifyProject(c,s);const extensions=await list(c,`https://firebaseextensions.googleapis.com/v1beta/projects/${PROJECT}/instances`,"instances");check(extensions.length===0,"Unexpected installed extension");s.extensionsVerified=true;save(s);console.log(JSON.stringify({status:"NO_INSTALLED_EXTENSIONS_VERIFIED"}));}
  else if(action==="inspect-foundation") {const s=readState();await verifyProject(c,s);console.log(JSON.stringify({
    sites:await list(c,`https://firebasehosting.googleapis.com/v1beta1/projects/${PROJECT}/sites`,"sites"),
    apps:await list(c,`https://firebase.googleapis.com/v1beta1/projects/${PROJECT}:searchApps?pageSize=100`,"apps"),
    databases:await list(c,`https://firestore.googleapis.com/v1/projects/${PROJECT}/databases`,"databases")},null,2));}
  else if(action==="verify")await finalVerification(c);
  else throw Error("Unsupported action");
}
if(require.main===module)main().catch(e=>{console.error(JSON.stringify({status:"BLOCKED",code:e.code,httpStatus:e.response?.status,
  message:e.response?.data?.error?.message || e.message}));process.exitCode=1;});
module.exports={context,request,verifyProject,client,readState,save,hash,check,list,validateLocal,PROJECT,PARENT,BILLING,FORBIDDEN};
