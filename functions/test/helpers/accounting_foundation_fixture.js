const {randomUUID}=require("node:crypto");
const {readFileSync}=require("node:fs");
const {join}=require("node:path");
const {Timestamp}=require("firebase-admin/firestore");
const {accountingConfigurationTransaction}=require("../../lib/trusted/accounting_configuration");
const {postFoundationCashSettlement,recoverFoundationCashSettlement}=require("../../lib/trusted/accounting_settlement");
async function accountingFoundationFixture(db,{moneyScale=3}={}){
 const companyId=`foundation-${randomUUID()}`,admin=`${companyId}-admin`,rep=`${companyId}-rep`,bookId="foundation-book";
 const root=`companies/${companyId}`,b=`${root}/books/${bookId}`;
 const batch=db.batch();batch.set(db.doc(root),{id:companyId,active:true});
 for(const[uid,role]of[[admin,"admin"],[rep,"sales_rep"]])batch.set(db.doc(`users/${uid}`),{uid,name:uid,companyId,role,active:true,approvalStatus:"approved"});
 await batch.commit();
 const configuration=JSON.parse(readFileSync(join(__dirname,"../../../test/fixtures/accounting_configuration.json"),"utf8"));
 configuration.moneyScale=moneyScale;
 const configured=await accountingConfigurationTransaction(db,admin,{action:"save",companyId,bookId,expectedRevision:0,requestId:"configure-foundation",configuration});
 const snapshot=(await db.doc(b).get()).data();const setup=db.batch();
 setup.update(db.doc(b),{mode:"reconstruction",configurationLocked:true,foundationEngineEmulatorEnabled:true,foundationPostingLaneCount:4});
 setup.set(db.doc(`${b}/journal_definitions/cash-settlements-v1`),{id:"cash-settlements-v1",companyId,bookId,revisionId:"definition-v1",active:true,
  currency:"JOD",moneyScale,numberingPolicy:"source_identity",allowedActions:["rep_to_company_cash"],allowedSourceTypes:["settlements"],allowedControls:["cash"]});
 for(const[representative,amount]of[[true,100],[false,20]]){
  const units=(BigInt(amount)*10n**BigInt(moneyScale)).toString();
  const id=representative?`rep_${rep}`:"company_cash",headId=representative?"synthetic-rep-opening":"synthetic-company-opening";
  const common={companyId,cashAccount:representative?"rep_cash":"company_cash",treasuryAccountId:id,salesRepId:representative?rep:"",
   holderType:representative?"representative":"company",holderUid:representative?rep:companyId,currency:"JOD",moneyScale,accountSequence:1};
  setup.set(db.doc(`${root}/cash_balances/${id}`),{...common,id,amount,amountUnits:units,lastMovementId:headId,syntheticOpeningId:headId});
  setup.set(db.doc(`${root}/cash_movements/${headId}`),{...common,id:headId,bookId,syntheticOpening:true,cutoverDate:"2026-11-10",
   direction:"in",amountUnits:units,balanceBeforeUnits:"0",balanceAfterUnits:units,amount,balanceBefore:0,balanceAfter:amount});
  setup.set(db.doc(`${b}/synthetic_openings/${headId}`),{companyId,bookId,treasuryAccountId:id,amountUnits:units,currency:"JOD",moneyScale,cutoverDate:"2026-11-10",syntheticOnly:true});
 }
 await setup.commit();
 const date=Timestamp.fromDate(new Date("2026-11-10T10:00:00Z"));
 const input={companyId,bookId,idempotencyKey:"request-first",operationId:"operation-first",salesRepId:rep,amount:"1.234",...(moneyScale===3?{}:{moneyScale}),settlementDate:{seconds:date.seconds,nanoseconds:date.nanoseconds},notes:"Synthetic acceptance",expectedConfigurationDigest:snapshot.configurationDigest};
 const enabled={enableEmulatorPosting:true};
 return{companyId,admin,rep,bookId,root,b,input,configured,
  post:(overrides={},uid=admin,database=db,options=enabled)=>postFoundationCashSettlement(database,uid,{...input,...overrides},options),
  recover:(overrides={},uid=admin,database=db,options=enabled)=>recoverFoundationCashSettlement(database,uid,{...input,...overrides},options)};
}
module.exports={accountingFoundationFixture};
