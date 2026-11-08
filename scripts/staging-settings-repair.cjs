"use strict";
// Add only absent numbering defaults; never replace existing configuration.
const S=require("./staging-release-support.cjs"),{fs,path,root,dir,PROJECT,load,check,hash,read,save,canonical,connect,logError}=S;
const {sdk}=require("./staging-current-release.cjs"),assert=require("node:assert/strict");
const documentPath="companies/default_company/settings/app";
async function main(){
 check(process.argv.length===2,"Only the dedicated staging additive repair is supported");
 const bytes=fs.readFileSync(path.join(dir,"evidence/settings-compatibility.log")),log=bytes[0]===255?bytes.toString("utf16le").slice(1):bytes.toString();check(/# pass 2\b/.test(log)&&/# fail 0\b/.test(log),"Original/current Rules configuration regression must pass");
 const source=fs.readFileSync(path.join(root,"lib/features/settings/data/models/document_settings_model.dart"),"utf8"),block=source.match(/static const DocumentSettingsModel defaults = DocumentSettingsModel\(([\s\S]*?)\);/)[1];
 const defaults=Object.fromEntries([...block.matchAll(/(\w+):\s*([^,\r\n]+),/g)].map(([,key,value])=>[key,value.startsWith("'")?value.slice(1,-1):value==="true"?true:value==="false"?false:Number(value)]));
 assert.deepEqual(defaults,{invoicePrefix:"INV",receiptPrefix:"REC",quotationPrefix:"QUO",salesReturnPrefix:"RET",defaultDueDays:0,defaultTaxPercent:0,allowDiscount:true,allowSalesRepPriceEdit:true});
 const {reader}=await connect(),{app,db}=await sdk(reader),ref=db.doc(documentPath),proofFile=path.join(dir,"evidence/settings-repair.json");
 try{
  let proof=fs.existsSync(proofFile)?read(proofFile):null;
  if(!proof){
   const snapshot=await ref.get(),before=snapshot.data(),beforeHash=hash(Buffer.from(JSON.stringify(canonical(before))));
   check(beforeHash===read(path.join(dir,"evidence/data-before.json")).documents[documentPath].hash,"Existing configuration changed since preservation baseline");
   check(before.documentSettings===undefined,"Existing numbering settings must never be overwritten");
   save(path.join(dir,"rollback/settings-before-additive-repair.json"),canonical(before));
   save(path.join(dir,"settings-repair.review.json"),{project:PROJECT,documentPath,operation:"add absent documentSettings only",defaults,sourceModelSha256:hash(Buffer.from(source)),existingValuesChanged:0,permissionChanges:0,financialBalanceWrites:0});
   await db.runTransaction(async transaction=>{
    const current=await transaction.get(ref);check(hash(Buffer.from(JSON.stringify(canonical(current.data()))))===beforeHash,"Concurrent settings modification; repair stopped");
    transaction.update(ref,{documentSettings:defaults});
   });
   const after=await ref.get(),data=after.data(),retained={...data};delete retained.documentSettings;
   assert.deepEqual(canonical(retained),canonical(before));assert.deepEqual(data.documentSettings,defaults);
   proof={project:PROJECT,documentPath,beforeHash,afterHash:hash(Buffer.from(JSON.stringify(canonical(data)))),addedFields:["documentSettings"],allOriginalFieldValuesPreserved:true,permissionChanges:0,financialBalanceWrites:0,committedAt:after.updateTime.toDate().toISOString(),passed:false};save(proofFile,proof);
  }
  for(let attempt=0;attempt<60;attempt++){
   const events=await db.collection("companies/default_company/audit_events").where("entityId","==","app").get();
   const event=events.docs.find(d=>d.get("entityType")==="settings"&&(d.get("changes")||[]).some(c=>c.field==="documentSettings"));
   if(event){proof.passed=true;proof.auditEventId=event.id;save(proofFile,proof);console.log(JSON.stringify({status:"PASS_ADDITIVE_CONFIGURATION_REPAIR",addedFields:proof.addedFields,originalValuesPreserved:true,permissionsChanged:0,auditEventId:event.id}));return;}
   await new Promise(r=>setTimeout(r,1000));
  }
  throw Error("Configuration repaired but its audit event has not been confirmed; activation remains held");
 }finally{await db.terminate();await load("firebase-admin/app").deleteApp(app);}
}
if(require.main===module)main().catch(logError);
