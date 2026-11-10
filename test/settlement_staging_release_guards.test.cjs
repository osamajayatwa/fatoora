"use strict";
const {test}=require("node:test"),assert=require("node:assert/strict");
const {guard}=require("../scripts/settlement-staging-release.cjs");
const project="fatoora-original-staging",base=`https://cloudfunctions.googleapis.com/v2/projects/${project}/locations/us-central1/functions`;
for(const [name,url,method,data] of [
 ["whole backend",base,"POST",{}],
 ["existing writer",base+"?functionId=recordCashSettlement","POST",{}],
 ["production",base.replace(project,"fatoora-6b192")+"?functionId=getSettlementBreakdown","POST",{}],
 ["invalid service account",base+"?functionId=getSettlementBreakdown","POST",{name:`projects/${project}/locations/us-central1/functions/getSettlementBreakdown`,buildConfig:{},serviceConfig:{serviceAccountEmail:"writer"}}],
 ["financial document",`https://firestore.googleapis.com/v1/projects/${project}/databases/(default)/documents/companies/default_company/cash_balances/rep_x?currentDocument.exists=false`,"PATCH",{}],
 ["control activation",`https://firestore.googleapis.com/v1/projects/${project}/databases/(default)/documents/internal_read_controls/settlement_breakdown?currentDocument.exists=false`,"PATCH",{name:`projects/${project}/databases/(default)/documents/internal_read_controls/settlement_breakdown`,fields:{enabled:{booleanValue:true}}}],
 ["existing endpoint policy",`https://run.googleapis.com/v2/projects/${project}/locations/us-central1/services/recordcashsettlement:setIamPolicy`,"POST",{}],
 ["hosting change",`https://firebasehosting.googleapis.com/v1beta1/sites/${project}/releases`,"POST",{}],
 ["Rules change",`https://firebaserules.googleapis.com/v1/projects/${project}/releases/cloud.firestore`,"PATCH",{}],
])test(`single-function release refuses ${name}`,()=>assert.throws(()=>guard(url,method,data)));
