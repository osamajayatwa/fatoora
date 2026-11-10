"use strict";
const S=require("./staging-release-support.cjs"),Q=require("./settlement-staging-security.cjs");
const {PROJECT,NUMBER,root,path,save,check,logError}=S;
const app="1:5438538531:android:560f7feecdb97bf5240296",base=`https://firebase.googleapis.com/v1beta1/projects/${PROJECT}/androidApps/${app}`;
const hashes={SHA_256:"8f19c3002be031b4204d51287f6ad71096b097dfb5e7f4be081400c8ffbf96ab",SHA_1:"9bf28c717508843f295a4ac3d1020215eced3570"};
const normal=s=>s.replaceAll(":","").toLowerCase();
function guard(url,method="GET",data){
 check(method==="GET"&&[base,base+"/sha",`https://firebaseappcheck.googleapis.com/v1/projects/${NUMBER}/apps/${app}/playIntegrityConfig`,`https://firebaseappcheck.googleapis.com/v1/projects/${NUMBER}/services`].includes(url)||
  method==="POST"&&url===base+"/sha"&&Object.keys(data||{}).sort().join(",")==="certType,shaHash"&&hashes[data.certType]===normal(data.shaHash),"Only the existing staging app and observed debug certificate are permitted");
}
async function run(){const c=await Q.connection();const api=async(url,method="GET",data)=>{guard(url,method,data);return(await c.reader.request({url,method,data,retry:false,timeout:30000})).data;};
 const registration=await api(base);check(registration.appId===app&&registration.packageName==="com.fujika.fatoora.original.staging","Android registration mismatch");
 let before=await api(base+"/sha"),added=[];
 for(const [certType,shaHash]of Object.entries(hashes))if(!(before.certificates||[]).some(c=>c.certType===certType&&normal(c.shaHash)===shaHash)){
  await api(base+"/sha","POST",{certType,shaHash});added.push(certType);
 }
 const after=await api(base+"/sha");check(Object.entries(hashes).every(([t,h])=>(after.certificates||[]).some(c=>c.certType===t&&normal(c.shaHash)===h)),"Signing certificate registration failed");
 const integrity=await api(`https://firebaseappcheck.googleapis.com/v1/projects/${NUMBER}/apps/${app}/playIntegrityConfig`);
 const services=await api(`https://firebaseappcheck.googleapis.com/v1/projects/${NUMBER}/services`);
 const result={project:PROJECT,packageName:registration.packageName,appId:app,debugSha256:hashes.SHA_256,debugSha1:hashes.SHA_1,registered:true,addedCertificateTypes:added,
  playIntegrityConfiguration:integrity,serviceEnforcement:services.services?.map(s=>({name:s.name,enforcementMode:s.enforcementMode})),providerBypass:false,serverEnforcementChanged:false};
 save(path.join(root,"output/staging-current-20261110/android-registration.json"),result);
 console.log(JSON.stringify({status:"ANDROID_REGISTRATION_VERIFIED",registeredDebugCertificate:true,addedCertificateTypes:added,appCheckEnforcementChanged:false}));
}
if(require.main===module)run().catch(logError);
module.exports={guard};
