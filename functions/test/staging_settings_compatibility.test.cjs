"use strict";
const {test}=require("node:test"),assert=require("node:assert/strict"),fs=require("node:fs"),cp=require("node:child_process");
const {initializeTestEnvironment,assertFails,assertSucceeds}=require("@firebase/rules-unit-testing");
const {doc,setDoc,updateDoc,serverTimestamp,getDoc}=require("firebase/firestore");
const defaults={invoicePrefix:"INV",receiptPrefix:"REC",quotationPrefix:"QUO",salesReturnPrefix:"RET",defaultDueDays:0,defaultTaxPercent:0,allowDiscount:true,allowSalesRepPriceEdit:true};
assert.match(process.env.FIRESTORE_EMULATOR_HOST||"",/^127\.0\.0\.1:\d+$/);
for(const [name,rules]of [["original",cp.execFileSync("git",["show","HEAD:firestore.rules"],{encoding:"utf8"})],["current",fs.readFileSync("../firestore.rules","utf8")]]){
 test(`${name} Rules: existing incomplete settings deny drafts; additive defaults restore only authorized invoices`,async()=>{
  const [host,port]=process.env.FIRESTORE_EMULATOR_HOST.split(":"),env=await initializeTestEnvironment({projectId:`demo-config-repair-${name}`,firestore:{host,port:Number(port),rules}});
  try{
   await env.withSecurityRulesDisabled(async ctx=>{
    const db=ctx.firestore();for(const uid of ["rep","other"])await setDoc(doc(db,"users",uid),{uid,name:uid,role:"sales_rep",active:true,approvalStatus:"approved",companyId:"default_company"});
    await setDoc(doc(db,"companies/default_company/customers/customer"),{id:"customer",companyId:"default_company",active:true,createdByUid:"rep",assignmentVersion:1,assignedToUid:"rep"});
    await setDoc(doc(db,"companies/default_company/settings/app"),{schemaVersion:1,companyId:"default_company",companySettings:{name:"Existing staging",country:""},jofotaraStatusSettings:{enabled:false},stagingProvisioningRunId:"retained"});
   });
   const db=env.authenticatedContext("rep").firestore(),draft={id:"draft",companyId:"default_company",invoiceNumber:"INV-2026-000001",invoiceStatus:"draft",createdByUid:"rep",createdByName:"rep",createdByRole:"sales_rep",createdAt:serverTimestamp(),updatedAt:serverTimestamp(),salesRepId:"rep",salesRepName:"rep",customerId:"customer",items:[{lineType:"custom",quantity:1,unitPrice:1}],subtotal:1,totalDiscount:0,totalTax:0,grandTotal:1,paidAmount:0,remainingAmount:1,returnStatus:"none",returnedTotal:0,returnedSubtotal:0,returnedDiscount:0,returnedTax:0,returnedReceivableAmount:0,customerCreditAmount:0,cashRefundAmount:0,returnInvoiceIds:[],latestReturnAt:null,receiptIds:[],lastReceiptId:"",isLocked:false,financialPosted:false,financialPostedAt:null,financialPostedByUid:"",financialPostedByName:"",customerTransactionIds:[],cashMovementIds:[],inventoryPosted:false,inventoryPostedAt:null,inventoryPostedByUid:"",inventoryPostedByName:"",inventoryMovementIds:[],stockSourceType:"salesRep",stockSourceSalesRepId:"rep",searchKeywords:[]};
   await assertFails(setDoc(doc(db,"companies/default_company/invoices/draft"),draft));
   await env.withSecurityRulesDisabled(async ctx=>{await updateDoc(doc(ctx.firestore(),"companies/default_company/settings/app"),{documentSettings:defaults});});
   await assertSucceeds(setDoc(doc(db,"companies/default_company/invoices/draft"),draft));
   await assertFails(setDoc(doc(env.authenticatedContext("other").firestore(),"companies/default_company/invoices/other"),{...draft,id:"other",createdByUid:"other",salesRepId:"other",stockSourceSalesRepId:"other"}));
   await assertFails(getDoc(doc(env.unauthenticatedContext().firestore(),"companies/default_company/invoices/draft")));
   await env.withSecurityRulesDisabled(async ctx=>{const d=await getDoc(doc(ctx.firestore(),"companies/default_company/settings/app"));assert.equal(d.data().stagingProvisioningRunId,"retained");assert.equal(d.data().jofotaraStatusSettings.enabled,false);await updateDoc(d.ref,{"documentSettings.invoicePrefix":"CUSTOM"});});
   await assertFails(setDoc(doc(db,"companies/default_company/invoices/other-number"),{...draft,id:"other-number"}));
  }finally{await env.cleanup();}
 });
}
module.exports={defaults};
