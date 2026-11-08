"use strict";
const {context,verifyProject,client,readState,request,PROJECT}=require("./staging-cloud.cjs");
const {sdk}=require("./staging-seed.cjs");
(async()=>{context();const s=readState(),c=await client();await verifyProject(c,s);const {db,auth,app}=await sdk(c);
 try {const audits=await db.collection("companies/default_company/audit_events").get(),counts={};
  for(const d of audits.docs){const a=d.data(),key=`${a.entityType}/${a.action}`;counts[key]=(counts[key]||0)+1;}
  console.log(JSON.stringify({auditEvents:audits.size,actions:counts,items:(await db.collection("items").get()).size,adminDisabled:(await auth.getUser(s.adminUid)).disabled,profileActive:(await db.doc(`users/${s.adminUid}`).get()).get("active")},null,2));
  const logs=await request(c,"https://logging.googleapis.com/v2/entries:list","POST",{resourceNames:[`projects/${PROJECT}`],filter:`resource.type="cloud_run_revision" AND severity>=ERROR AND timestamp>="${s.seedAttempt.at}"`,pageSize:30,orderBy:"timestamp desc"});
  const errors=new Map();for(const e of logs.entries||[]){const message=e.jsonPayload?.errorMessage||e.protoPayload?.status?.message||e.textPayload||e.jsonPayload?.message;if(message&&!message.includes('business_audit_write_failed'))errors.set(message,(errors.get(message)||0)+1);}
  console.log(JSON.stringify({uniqueErrors:Object.fromEntries(errors)},null,2));
 }finally{await db.terminate();const load=require('node:module').createRequire(require('node:path').resolve(__dirname,'../functions/package.json'));await load('firebase-admin/app').deleteApp(app);}
})().catch(e=>{console.error(JSON.stringify({code:e.code,message:e.message}));process.exitCode=1;});
