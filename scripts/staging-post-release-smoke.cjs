"use strict";
const S=require("./staging-release-support.cjs"),cp=require("node:child_process"),assert=require("node:assert/strict");
async function main(){
 const {fs,path,dir,root,PROJECT,read,save,publicRequest}=S,release=read(path.join(dir,"release-state.json"));assert.ok(release.hosting);
 const user=read(path.join(dir,"evidence/ui-login.json"));assert.match(user.uid,/^acceptance-/);
 const encrypted=fs.readFileSync(path.join(dir,"ui-password.dpapi.b64"),"utf8");
 const command="Add-Type -AssemblyName System.Security; $v=[Console]::In.ReadToEnd(); [Console]::Out.Write([Text.Encoding]::UTF8.GetString([Security.Cryptography.ProtectedData]::Unprotect([Convert]::FromBase64String($v),$null,[Security.Cryptography.DataProtectionScope]::CurrentUser)))";
 const password=cp.execFileSync("powershell.exe",["-NoProfile","-NonInteractive","-Command",command],{input:encrypted,encoding:"utf8",windowsHide:true}),cfg=read(path.join(root,"config/firebase/staging.web.json"));
 const origin=`https://${PROJECT}.web.app`;
 const login=JSON.parse((await publicRequest(`https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=${cfg.FIREBASE_API_KEY}`,{method:"POST",headers:{Origin:origin},data:{email:user.email,password,returnSecureToken:true},responseType:"text"})).data);assert.equal(login.localId,user.uid);
 async function call(data,token){const r=await publicRequest(`https://us-central1-${PROJECT}.cloudfunctions.net/getDashboardSnapshot`,{method:"POST",headers:{Origin:origin,...(token?{authorization:`Bearer ${token}`}:{})},data:{data},responseType:"text",validateStatus:()=>true});return {status:r.status,body:JSON.parse(r.data)};}
 const authorized=await call({companyId:"default_company",from:0,to:Date.now()},login.idToken);assert.equal(authorized.status,200);assert.equal(authorized.body.result.totalSales,20.88);
 const anonymous=await call({companyId:"default_company",from:0,to:Date.now()});assert.equal(anonymous.body.error.status,"UNAUTHENTICATED");
 const foreign=read(path.join(dir,"evidence/live-acceptance.json")).results[0].companyId;
 const cross=await call({companyId:foreign,from:0,to:Date.now()},login.idToken);assert.equal(cross.body.error.status,"PERMISSION_DENIED");
 const result={passed:true,at:new Date().toISOString(),project:PROJECT,hostingVersion:release.hosting.version,realPasswordLogin:true,authenticatedReporting:true,anonymousDenied:true,crossCompanyDenied:true,financialWrites:0,browserVisualTest:false};save(path.join(dir,"evidence/post-release-smoke.json"),result);console.log(JSON.stringify({status:"PASS_POST_RELEASE_AUTH_AND_PERMISSIONS",hostingVersion:release.hosting.version}));
}
if(require.main===module)main().catch(S.logError);
