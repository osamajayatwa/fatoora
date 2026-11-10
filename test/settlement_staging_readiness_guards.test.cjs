"use strict";
const {test}=require("node:test"),assert=require("node:assert/strict");
const {assertReadRequest:guard,LIMITS}=require("../scripts/settlement-staging-readiness.cjs");
const project="fatoora-original-staging",company=`https://firestore.googleapis.com/v1/projects/${project}/databases/(default)/documents/companies/default_company`;
const query={structuredQuery:{from:[{collectionId:"settlements"}],select:{fields:[{fieldPath:"status"}]},limit:64}};
test("only exact dedicated staging metadata and projected company reads are accepted",()=>{
 guard(company);guard(`https://firestore.googleapis.com/v1/projects/${project}/databases/(default)`);
 guard(company+":runQuery","POST",query);
 guard(`https://cloudresourcemanager.googleapis.com/v3/projects/${project}:getIamPolicy`,"POST",{});
 assert.equal(LIMITS.returnedDocuments,512);assert.equal(LIMITS.countLimit,16001);
});
for(const [name,url,method,data] of [
 ["production",company.replace(project,"fatoora-6b192"),"GET"],
 ["other staging",company.replace(project,"fatoora-platform-staging"),"GET"],
 ["other company",company.replace("default_company","other"),"GET"],
 ["document patch",company,"PATCH",{}],
 ["financial commit",company.split("/documents")[0]+"/documents:commit","POST",{writes:[]}],
 ["callable invocation",`https://us-central1-${project}.cloudfunctions.net/getSettlementBreakdown`,"POST",{}],
 ["deployment",`https://cloudfunctions.googleapis.com/v2/projects/${project}/locations/us-central1/functions`,"POST",{}],
 ["sign in","https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword","POST",{}],
 ["unbounded query",company+":runQuery","POST",{structuredQuery:{...query.structuredQuery,limit:10000}}],
 ["offset read amplification",company+":runQuery","POST",{structuredQuery:{...query.structuredQuery,offset:100000}}],
 ["unreviewed fields",company+":runQuery","POST",{structuredQuery:{...query.structuredQuery,select:{fields:[{fieldPath:"customerSnapshot"}]}}}],
 ["user enumeration",`https://firestore.googleapis.com/v1/projects/${project}/databases/(default)/documents:runQuery`,"POST",{structuredQuery:{from:[{collectionId:"users"}],select:{fields:[{fieldPath:"uid"}]},limit:64}}],
 ["alternate origin",company.replace("firestore.googleapis.com","other.example.com"),"GET"],
])test(`inspection refuses ${name}`,()=>assert.throws(()=>guard(url,method,data)));
