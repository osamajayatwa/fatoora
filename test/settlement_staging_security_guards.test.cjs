"use strict";
const {test}=require("node:test"),assert=require("node:assert/strict");
const {guard,addBinding,ACCOUNT,ROLE,PERMISSIONS}=require("../scripts/settlement-staging-security.cjs");
const project="fatoora-original-staging",iam=`https://iam.googleapis.com/v1/projects/${project}`;
test("only four read permissions and a narrowly scoped identity can be added",()=>{
 assert.deepEqual(PERMISSIONS,["datastore.databases.get","datastore.entities.get","datastore.entities.list","firebaseauth.users.get"]);
 const policy={version:1,etag:"synthetic-etag",bindings:[{role:"roles/logging.logWriter",members:["serviceAccount:existing"]}]};
 const next=addBinding(policy,ROLE,`serviceAccount:${ACCOUNT}`);
 guard(`https://cloudresourcemanager.googleapis.com/v3/projects/${project}:setIamPolicy`,"POST",{policy:next});
 assert.deepEqual(next.bindings[0],policy.bindings[0]);assert.equal(policy.bindings.length,1);
 assert.equal(addBinding(next,ROLE,`serviceAccount:${ACCOUNT}`),next);
 assert.throws(()=>addBinding(policy,"roles/owner",`serviceAccount:${ACCOUNT}`));
 assert.throws(()=>addBinding(policy,ROLE,"allUsers"));
});
test("read-only inspection permits only bounded default-company inventory",()=>{
 guard(`https://firestore.googleapis.com/v1/projects/${project}/databases/(default)/documents/companies/default_company:runQuery`,"POST",
   {structuredQuery:{from:[{collectionId:"settlements"}],limit:65}});
});
for(const [name,url,method,data] of [
 ["production identity",iam.replace(project,"fatoora-6b192")+`/serviceAccounts/${ACCOUNT}`,"GET"],
 ["financial write",`https://firestore.googleapis.com/v1/projects/${project}/databases/(default)/documents/companies/default_company/settlements/x`,"PATCH",{}],
 ["new financial transaction",`https://firestore.googleapis.com/v1/projects/${project}/databases/(default)/documents:commit`,"POST",{writes:[]}],
 ["other company",`https://firestore.googleapis.com/v1/projects/${project}/databases/(default)/documents/companies/other:runQuery`,"POST",{structuredQuery:{from:[{collectionId:"settlements"}],limit:65}}],
 ["unbounded query",`https://firestore.googleapis.com/v1/projects/${project}/databases/(default)/documents/companies/default_company:runQuery`,"POST",{structuredQuery:{from:[{collectionId:"settlements"}]}}],
 ["unsafe role",iam+"/roles","POST",{roleId:"fatooraSettlementReadOnly",role:{title:"Settlement evidence read only",stage:"GA",includedPermissions:[...PERMISSIONS,"datastore.entities.update"]}}],
 ["unreviewed policy",`https://cloudresourcemanager.googleapis.com/v3/projects/${project}:setIamPolicy`,"POST",{policy:{etag:"x",bindings:[]}}],
 ["writer identity",iam+"/serviceAccounts","POST",{accountId:"writer",serviceAccount:{displayName:"Settlement evidence read-only runtime"}}],
 ["deletion",iam+`/serviceAccounts/${ACCOUNT}`,"DELETE"],
 ["unexpected endpoint",iam.replace("iam.googleapis.com","other.example.com")+`/serviceAccounts/${ACCOUNT}`,"GET"],
])test(`security tool refuses ${name}`,()=>assert.throws(()=>guard(url,method,data)));
