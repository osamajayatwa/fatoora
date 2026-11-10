"use strict";
// Local checks only. Never signs in, calls a cloud project or changes a device.
const fs=require("node:fs"),path=require("node:path"),crypto=require("node:crypto");
const root=path.resolve(__dirname,".."),project="fatoora-original-staging";
function check(ok,message){if(!ok)throw Error(message);}
function verify() {
 const config=JSON.parse(fs.readFileSync(path.join(root,"config/firebase/staging.android.json"),"utf8"));
 const native=JSON.parse(fs.readFileSync(path.join(root,"android/app/src/staging/google-services.json"),"utf8"));
 const c=native.client?.[0],id="1:5438538531:android:560f7feecdb97bf5240296";
 check(config.FATOORA_ENV==="staging"&&config.FIREBASE_PROJECT_ID===project&&config.FIREBASE_PROJECT_ID_CONFIRM===project&&
  config.FIREBASE_MESSAGING_SENDER_ID==="5438538531"&&config.FIREBASE_APP_ID===id,"Pinned staging Dart registration required");
 check(native.project_info?.project_id===project&&native.project_info.project_number==="5438538531"&&native.client.length===1&&
  c.client_info?.mobilesdk_app_id===id&&c.client_info?.android_client_info?.package_name==="com.fujika.fatoora.original.staging"&&
  c.api_key?.[0]?.current_key===config.FIREBASE_API_KEY,"Native/Dart staging pairing mismatch");
 check(crypto.createHash("sha256").update(config.FIREBASE_API_KEY).digest("hex")==="20d4663137cc721e0e767177f9a1257ac3c879b4094bc0b4ed1b00ec557d62a1","Unapproved staging key");
 check(config.FATOORA_SETTLEMENT_STAGING_PILOT!==true&&config.FATOORA_SETTLEMENT_STAGING_PILOT!=="true"&&
  config.FATOORA_SETTLEMENT_TRANSPORT_TEST!==true&&config.FATOORA_SETTLEMENT_TRANSPORT_TEST!=="true","Experimental feature or emulator flag in staging configuration");
 const lock=fs.readFileSync(path.join(root,"pubspec.lock"));check(!lock.includes(0),"Dependency lock is corrupted");
 return {project,package:"com.fujika.fatoora.original.staging",financialBreakdown:false,emulators:false};
}
if(require.main===module){try{console.log(JSON.stringify({status:"STAGING_ANDROID_PREFLIGHT_PASS",...verify()}));}catch(e){console.error(e.message);process.exitCode=1;}}
module.exports={verify};
