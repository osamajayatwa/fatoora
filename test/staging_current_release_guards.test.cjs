"use strict";
const {test}=require("node:test"),assert=require("node:assert/strict");
const {allowed,canonical,PROJECT}=require("../scripts/staging-release-support.cjs");
test("current release requests refuse protected projects, other sites, credentials and insecure origins",()=>{
 for(const url of [
  "https://firestore.googleapis.com/v1/projects/fatoora-6b192/databases/(default)",
  "https://run.googleapis.com/v2/projects/fatoora-platform-staging/locations/us-central1/services/app",
  "https://cloudfunctions.googleapis.com/v2/projects/961957914773/locations/us-central1/functions",
  "https://firebasehosting.googleapis.com/v1beta1/sites/other-site/versions",
  `http://firestore.googleapis.com/v1/projects/${PROJECT}/databases/(default)`,
  `https://user:secret@firestore.googleapis.com/v1/projects/${PROJECT}/databases/(default)`,
  `https://firestore.googleapis.com/v1/projects/${PROJECT}/projects/fatoora-6b192`,
 ])assert.throws(()=>allowed(url));
});
test("current release targets only dedicated staging API and artifact paths",()=>{
 for(const url of [
  `https://firestore.googleapis.com/v1/projects/${PROJECT}/databases/(default)/collectionGroups/invoices/indexes`,
  `https://cloudfunctions.googleapis.com/v2/projects/${PROJECT}/locations/us-central1/functions/confirmSalesReturn`,
  `https://upload-firebasehosting.googleapis.com/upload/sites/${PROJECT}/versions/immutable/files/hash`,
 ])assert.equal(allowed(url).protocol,"https:");
});
test("revision comparison ignores Eventarc filter order but retains actual trigger changes",()=>{
 const a={eventFilters:[{attribute:"database",value:"(default)"},{attribute:"document",value:"safe"}]};
 assert.deepEqual(canonical(a),canonical({eventFilters:[...a.eventFilters].reverse()}));
 assert.notDeepEqual(canonical(a),canonical({eventFilters:[{attribute:"document",value:"other"}]}));
});
