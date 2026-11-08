"use strict";
const test=require("node:test"),assert=require("node:assert/strict"),fs=require("node:fs"),path=require("node:path"),vm=require("node:vm"),crypto=require("node:crypto");
const root=path.resolve(__dirname,".."),load=require("node:module").createRequire(path.join(root,"functions/package.json"));
const runtime=fs.readFileSync(path.join(root,"config/firebase/staging-runtime.cjs"),"utf8"),passed=[];
const {Firestore}=load("@google-cloud/firestore");
test("native SDK reproduces the create-audit failure and omits absent before-values with the staging setting",async()=>{
 const {buildAuditEvent}=load("./lib/audit/audit_event_builder.js"),{ENTITY_CONFIGS}=load("./lib/audit/entity_audit_config.js");
 const event=buildAuditEvent({sourceEventId:"native-serialization-regression",eventTime:"2026-11-05T00:00:00Z",authType:"service_account",companyId:"default_company",entityId:"fixture",entityPath:"items/fixture",config:ENTITY_CONFIGS.items,after:{name:"Fixture",code:"SKU",price:12,active:true,deleted:false,currentStock:0}});
 const normal=new Firestore({projectId:"demo-staging-runtime-serializer"}),compatible=new Firestore({projectId:"demo-staging-runtime-serializer",ignoreUndefinedProperties:true});
 try {assert.throws(()=>normal.batch().create(normal.doc("audit/fixture"),event),/undefined/);
  assert.doesNotThrow(()=>compatible.batch().create(compatible.doc("audit/fixture"),event));
  const encoded=compatible._serializer.encodeFields({changes:event.changes});
  for(const value of encoded.changes.arrayValue.values)assert.equal(Object.hasOwn(value.mapValue.fields,"before"),false);
 }finally{await normal.terminate();await compatible.terminate();}
 passed.push("native-create-audit-serialization");
});
test("runtime adapter refuses either protected project before loading any SDK or app code",()=>{
 for(const project of ["fatoora-6b192","fatoora-platform-staging"]){let calls=0;assert.throws(()=>vm.runInNewContext(runtime,{process:{env:{GCLOUD_PROJECT:project,FIREBASE_CONFIG:JSON.stringify({projectId:project})}},module:{exports:{}},require:()=>{calls++;}}),/unapproved/);assert.equal(calls,0);}
 passed.push("protected-runtime-targets-refused");
});
test("staging adapter preserves exports and configures only native serialization",()=>{
 const exports={existingCallable:()=>{},existingAudit:()=>{}},settings=[];
 const module={exports:{}};
 vm.runInNewContext(runtime,{process:{env:{GCLOUD_PROJECT:"fatoora-original-staging",FIREBASE_CONFIG:JSON.stringify({projectId:"fatoora-original-staging"})}},module,
  require:id=>id==="./index.js"?exports:id==="firebase-admin/app"?{getApp:()=>({options:{projectId:"fatoora-original-staging"}})}:{getFirestore:()=>({settings:value=>settings.push(JSON.parse(JSON.stringify(value)))})}});
 assert.equal(module.exports,exports);assert.deepEqual(settings,[{ignoreUndefinedProperties:true}]);passed.push("unchanged-exports-staging-only-setting");
});
test.after(()=>{fs.mkdirSync(path.join(root,"build/staging"),{recursive:true});fs.writeFileSync(path.join(root,"build/staging/runtime-compatibility-tests.json"),JSON.stringify({passed:passed.length===3,checks:passed,adapterSha256:crypto.createHash("sha256").update(runtime).digest("hex")},null,2)+"\n");});
