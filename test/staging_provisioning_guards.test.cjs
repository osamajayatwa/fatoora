"use strict";
const test=require("node:test"),assert=require("node:assert/strict");
const {request,PROJECT}=require("../scripts/staging-cloud.cjs");
const {stagingItem}=require("../scripts/staging-seed.cjs");
test("cloud guard prevents both protected projects, lookalike targets and deletions before any SDK request",async()=>{
  let calls=0;const c={request:async()=>{calls++;return {data:{}};}};
  for(const project of ["fatoora-6b192","961957914773","fatoora-platform-staging","813911311333",`${PROJECT}-unapproved`]) {
    await assert.rejects(request(c,`https://firestore.googleapis.com/v1/projects/${project}/databases/(default)/documents:commit`,"POST",{}),{code:"STAGING_GUARD"});
  }
  await assert.rejects(request(c,`https://cloudresourcemanager.googleapis.com/v3/projects/${PROJECT}`,"DELETE"),{code:"STAGING_GUARD"});
  await assert.rejects(request(c,`https://attacker.example/projects/${PROJECT}`,"POST",{}),{code:"STAGING_GUARD"});
  assert.equal(calls,0);
});
test("staging transformation replaces emulator authors and retains definitions/prices with zero inventory",()=>{
  const row={id:"verified-id",data:{id:"verified-id",name:"Catalog definition",code:"SKU",description:"Definition",unit:"unit",price:123.456,taxRate:16,active:true,deleted:false,trackStock:true}};
  const item=stagingItem(row,"new-independent-staging-uid","owned-staging-run");
  assert.equal(item.price,row.data.price);assert.equal(item.id,row.id);
  assert.equal(item.createdBy,"new-independent-staging-uid");assert.equal(item.createdByUid,"new-independent-staging-uid");
  assert.equal(item.stagingProvisioningRunId,"owned-staging-run");assert.equal(Object.hasOwn(item,"localTestCatalogHash"),false);
  for(const field of ["currentStock","openingStock","minStock","costPrice","inventoryValue"])assert.equal(item[field],0);
  assert.equal(item.stockStatus,"out");assert.ok(item.stagingCatalogHash);
});
