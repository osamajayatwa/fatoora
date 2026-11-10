/** Dedicated deployment entry: exporting this file cannot redeploy posting.
 * Runtime IAM grants reads only. Normal application exports remain separate. */
import {initializeApp} from "firebase-admin/app";
import {getFirestore} from "firebase-admin/firestore";
import {getAuth} from "firebase-admin/auth";
import {createStagingSettlementReadTarget} from "./trusted/settlement_read_target";
import {verifySettlementReadRuntime} from "./trusted/settlement_runtime_canary";
initializeApp();
getFirestore().settings({host: "firestore.googleapis.com:443", ssl: true});
const db = getFirestore(), target = createStagingSettlementReadTarget(db);
void verifySettlementReadRuntime(db, getAuth(), target).then(
  () => console.info(JSON.stringify({event: "settlement_reader_canary_passed", securityDocumentReads: 3, authReads: 1, financialReads: 0, writes: 0})),
  () => console.error(JSON.stringify({event: "settlement_reader_canary_failed", financialReads: 0, writes: 0})),
);
export {getSettlementBreakdown} from "./trusted/settlement_transport";
