"use strict";
// Real staging requests only. No successful business transactions or test history.
const fs=require("node:fs"),path=require("node:path"),crypto=require("node:crypto");
const {context,validateLocal,verifyProject,client,readState,save,check,request,PROJECT,FORBIDDEN}=require("./staging-cloud.cjs");
const {sdk,getPassword,emptyHistory}=require("./staging-seed.cjs");
const root=path.resolve(__dirname,".."),load=require("node:module").createRequire(path.join(root,"functions/package.json"));
const COMPANY="default_company",EMAIL="admin@fatoora.com";
const docs=`https://firestore.googleapis.com/v1/projects/${PROJECT}/databases/(default)/documents`;
async function http(url,{method="GET",data,token,key}={}) {
  const parsed=new URL(url);check(parsed.protocol==="https:" &&
    (["identitytoolkit.googleapis.com","firestore.googleapis.com"].includes(parsed.hostname)||parsed.hostname===`us-central1-${PROJECT}.cloudfunctions.net`),"Unexpected acceptance endpoint");
  check(!parsed.hostname.startsWith("us-central1-")||parsed.hostname===`us-central1-${PROJECT}.cloudfunctions.net`,"Wrong callable target");
  if(parsed.hostname==="firestore.googleapis.com")check(parsed.pathname.startsWith(`/v1/projects/${PROJECT}/`),"Wrong Firestore target");
  if(key)parsed.searchParams.set("key",key);
  const r=await fetch(parsed,{method,headers:{...(data?{"Content-Type":"application/json"}:{}),...(token?{Authorization:`Bearer ${token}`}:{})},
    body:data?JSON.stringify(data):undefined,signal:AbortSignal.timeout(60000)});
  const raw=await r.text();let body;
  try{body=JSON.parse(raw);}catch{throw Error(`Non-JSON acceptance response: ${parsed.hostname}${parsed.pathname} HTTP ${r.status} (${r.headers.get("content-type")})`);}
  return {status:r.status,body};
}
async function signin(key,password){return http("https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword",{method:"POST",key,data:{email:EMAIL,password,returnSecureToken:true}});}
async function callable(name,data,token){return http(`https://us-central1-${PROJECT}.cloudfunctions.net/${name}`,{method:"POST",data:{data},token});}
function requireError(r,statuses){check(r.body.error && statuses.includes(r.body.error.status),`Unexpected callable denial: ${r.status}/${r.body.error?.status}`);}
function syntheticForeignToken(aud){const encode=v=>Buffer.from(JSON.stringify(v)).toString("base64url");return `${encode({alg:"RS256",typ:"JWT",kid:"synthetic-not-a-real-key"})}.${encode({aud,iss:`https://securetoken.google.com/${aud}`,sub:"synthetic-isolation-test",iat:Math.floor(Date.now()/1000),exp:Math.floor(Date.now()/1000)+300})}.${crypto.randomBytes(32).toString("base64url")}`;}
async function rollback(s,db,auth) {
  await db.doc(`users/${s.adminUid}`).update({active:false});await auth.updateUser(s.adminUid,{disabled:true});await auth.revokeRefreshTokens(s.adminUid);
  s.adminActivated=false;s.acceptance={...s.acceptance,backendPassed:false,rollback:"owned admin disabled/profile inactive/tokens revoked"};save(s);
}
async function main(){
  check(process.argv.length===3 && process.argv[2]==="backend","Explicit backend acceptance action required");
  context();validateLocal();const s=readState(),c=await client();await verifyProject(c,s);
  check(s.seedVerified && s.functionsVerified && s.indexesVerified,"Verified seed/backend required before activation");
  const cfg=JSON.parse(fs.readFileSync(path.join(root,"config/firebase/staging.web.json")));
  const {db,auth,app}=await sdk(c),checks={};
  try {
    await emptyHistory(db);
    const profile=db.doc(`users/${s.adminUid}`);
    let account=await auth.getUser(s.adminUid);
    if(!s.adminActivated) {
      check((await profile.get()).get("active")===false,"Unexpected preactivation profile state");
      if(account.disabled){const denied=await signin(cfg.FIREBASE_API_KEY,getPassword());check(denied.status===400 && denied.body.error?.message==="USER_DISABLED","Initially disabled account did not reject login");checks.disabledLoginDenied=true;}
      s.adminActivationAttempt={at:new Date().toISOString()};save(s);
      if(account.disabled)await auth.updateUser(s.adminUid,{disabled:false});
      const inactive=await signin(cfg.FIREBASE_API_KEY,getPassword());check(inactive.status===200 && inactive.body.localId===s.adminUid,"Independent admin authentication failed");
      check((await http(`${docs}/items`,{token:inactive.body.idToken,key:cfg.FIREBASE_API_KEY})).status===403,"Inactive application profile unexpectedly has catalog access");
      requireError(await callable("getCashOpeningBalance",{companyId:COMPANY,fromInclusive:"2026-11-01T00:00:00Z"},inactive.body.idToken),["PERMISSION_DENIED"]);
      checks.inactiveProfileDenied=true;
      await profile.update({active:true,updatedAt:load("firebase-admin/firestore").FieldValue.serverTimestamp()});
      s.adminActivated=true;save(s);
    }
    const wrong=await signin(cfg.FIREBASE_API_KEY,crypto.randomBytes(32).toString("base64url"));
    check(wrong.status===400 && ["INVALID_LOGIN_CREDENTIALS","INVALID_PASSWORD"].includes(wrong.body.error?.message),"Wrong password was not rejected");checks.wrongPasswordDenied=true;
    const login=await signin(cfg.FIREBASE_API_KEY,getPassword());check(login.status===200 && login.body.localId===s.adminUid,"Staging admin login failed");
    const token=login.body.idToken,claims=await auth.verifyIdToken(token,true);
    check(claims.aud===PROJECT && claims.iss===`https://securetoken.google.com/${PROJECT}` && claims.uid===s.adminUid,"ID token identity/issuer/audience mismatch");checks.loginIssuerAudienceVerified=true;
    const catalog=await http(`${docs}/items?pageSize=1000`,{token,key:cfg.FIREBASE_API_KEY});
    check(catalog.status===200 && catalog.body.documents?.length===91,"Admin client cannot read the 91 definitions");
    check(catalog.body.documents.filter(d=>d.fields.active.booleanValue&&!d.fields.deleted.booleanValue).length===90,"Active catalog count mismatch");
    checks.adminCatalogRead={definitions:91,active:90,deleted:1};
    for(const collection of ["invoices","cash_balances","cash_movements","stock_movements","financial_ledger_entries"]) {
      const r=await http(`${docs}/companies/${COMPANY}/${collection}`,{token,key:cfg.FIREBASE_API_KEY});check(r.status===200 && !(r.body.documents||[]).length,`Admin client read failed or history exists: ${collection}`);
    }
    checks.invoiceInventoryCashHistoryReadsEmpty=true;
    const users=await http(`${docs}/users`,{token,key:cfg.FIREBASE_API_KEY});check(users.status===200&&users.body.documents?.length===1,"Admin user-management read failed");checks.adminUserManagementRead=true;
    const sample=catalog.body.documents.find(d=>d.fields.active.booleanValue&&!d.fields.deleted.booleanValue);
    const write=await http(`${docs}:commit`,{method:"POST",token,key:cfg.FIREBASE_API_KEY,data:{writes:[{
      update:{name:sample.name,fields:{active:sample.fields.active}},updateMask:{fieldPaths:["active"]},
      updateTransforms:[{fieldPath:"updatedAt",setToServerValue:"REQUEST_TIME"}],currentDocument:{exists:true},
    }]}});check(write.status===200,"Admin catalog update permission failed");checks.adminCatalogSameValueUpdate=true;
    const anonymous=await http(`${docs}/items`,{key:cfg.FIREBASE_API_KEY});check(anonymous.status===403,"Anonymous catalog access was not denied");
    requireError(await callable("getDashboardSnapshot",{},undefined),["UNAUTHENTICATED"]);checks.anonymousDenied=true;
    const foreignCompany=await http(`${docs}/companies/staging-acceptance-foreign/invoices`,{token,key:cfg.FIREBASE_API_KEY});check(foreignCompany.status===403,"Cross-company read was not denied");
    requireError(await callable("getCashOpeningBalance",{companyId:"staging-acceptance-foreign",fromInclusive:"2026-11-01T00:00:00Z"},token),["PERMISSION_DENIED"]);checks.crossCompanyDenied=true;
    for(const p of [FORBIDDEN[0],FORBIDDEN[2]]) {
      const r=await http(`${docs}/items`,{token:syntheticForeignToken(p),key:cfg.FIREBASE_API_KEY});check([401,403].includes(r.status),"Foreign-project synthetic token was accepted");
    }
    checks.foreignProjectSyntheticTokensDenied=true;
    const dashboard=await callable("getDashboardSnapshot",{companyId:COMPANY,from:"2026-11-01T00:00:00Z",to:"2026-11-30T23:59:59Z"},token);
    check(dashboard.status===200 && dashboard.body.result,"Real dashboard callable failed");
    for(const key of ["totalSales","invoiceCount","customerCount","totalReceivables","receiptCount","totalExpenses","companyCash","repCashOutstanding","cashInHand"])check(dashboard.body.result[key]===0,`Unexpected dashboard balance: ${key}`);
    checks.dashboardAllBusinessTotalsZero=true;
    const cash=await callable("getCashOpeningBalance",{companyId:COMPANY,fromInclusive:"2026-11-01T00:00:00Z"},token);
    check(cash.status===200&&cash.body.result?.openingBalance===0&&cash.body.result.companyCashOpening===0&&cash.body.result.repCashOpening===0,"Real empty-ledger cash-opening callable failed");checks.cashOpeningZero=true;
    const openings=await callable("getFinancialLedgerOpeningBalances",{companyId:COMPANY,fromInclusive:"2026-11-01T00:00:00Z",salesRepId:"",accountKeys:["company_cash"]},token);
    check(openings.status===200&&openings.body.result?.openings?.every(o=>o.balance===0),"Real ledger opening read failed");checks.ledgerOpeningZero=true;
    requireError(await callable("confirmInvoice",{companyId:COMPANY,invoiceId:`staging-acceptance-missing-${s.runId}`},token),["NOT_FOUND"]);checks.missingInvoiceSafelyRejected=true;
    requireError(await callable("adjustStock",{companyId:COMPANY,idempotencyKey:"short"},token),["INVALID_ARGUMENT"]);checks.invalidInventoryAdjustmentRejected=true;
    check(s.serviceIsolationVerified && s.isolationProbe?.removedAt,"Actual service-identity isolation tests and removal of temporary probe grants must pass first");
    checks.runtimeDeployerBuilderDeniedBothProtectedProjects=true;
    const policy=await request(c,`https://cloudresourcemanager.googleapis.com/v3/projects/${PROJECT}:getIamPolicy`,"POST",{});
    check(!policy.bindings.some(b=>b.members?.includes(`user:${EMAIL}`)),"Application Admin received a Google Cloud IAM role");checks.applicationAdminHasNoCloudIamGrant=true;
    await emptyHistory(db);checks.noBusinessHistoryCreated=true;
    s.acceptance={backendPassed:true,at:new Date().toISOString(),checks};save(s);
    fs.writeFileSync(path.join(root,"build/staging/acceptance-backend.json"),JSON.stringify(s.acceptance,null,2)+"\n");
    console.log(JSON.stringify({status:"REAL_STAGING_BACKEND_ACCEPTANCE_PASSED",checks,credentialsLogged:false}));
  }catch(e){if(s.adminActivationAttempt)await rollback(s,db,auth);throw e;}
  finally{await db.terminate();await load("firebase-admin/app").deleteApp(app);}
}
if(require.main===module)main().catch(e=>{console.error(JSON.stringify({status:"BLOCKED",code:e.code,message:e.message}));process.exitCode=1;});
