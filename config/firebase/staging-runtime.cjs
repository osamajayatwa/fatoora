"use strict";
// Native Firestore compatibility for this staging artifact only.
const project="fatoora-original-staging";
const config=JSON.parse(process.env.FIREBASE_CONFIG||"{}");
const targets=[process.env.GCLOUD_PROJECT,process.env.GOOGLE_CLOUD_PROJECT].filter(Boolean);
if(config.projectId!==project || !targets.length || targets.some(value=>value!==project)) {
  throw new Error("Staging runtime refuses an unapproved Firebase project");
}
const reviewedExports=require("./index.js");
const app=require("firebase-admin/app").getApp();
if(app.options.projectId!==project)throw new Error("Staging runtime SDK project mismatch");
// A missing before-value on a create audit represents an absent field. The
// native SDK must omit it, as in the existing emulator verification setup.
require("firebase-admin/firestore").getFirestore(app).settings({ignoreUndefinedProperties:true});
module.exports=reviewedExports;
