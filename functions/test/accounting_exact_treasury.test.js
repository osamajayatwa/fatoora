const {test,after}=require("node:test");const assert=require("node:assert/strict");
if(!/^127\.0\.0\.1:\d+$/.test(process.env.FIRESTORE_EMULATOR_HOST||""))throw new Error("Exact treasury tests require loopback.");
const{initializeApp,deleteApp}=require("firebase-admin/app");const{getFirestore}=require("firebase-admin/firestore");
const{accountingFoundationFixture}=require("./helpers/accounting_foundation_fixture");
const app=initializeApp({projectId:"demo-fatoora-phase2d"},"exact-treasury-test"),db=getFirestore(app);after(()=>deleteApp(app));
test("native settlement preserves 30-digit units and explicitly withholds unrepresentable legacy values",async()=>{
 const f=await accountingFoundationFixture(db),opening="800000000000000000000000000000",amount="100000000000000000000000000001",headId="large-synthetic-opening",batch=db.batch();
 const shared={companyId:f.companyId,cashAccount:"rep_cash",treasuryAccountId:`rep_${f.rep}`,salesRepId:f.rep,holderType:"representative",holderUid:f.rep,currency:"JOD",moneyScale:3,accountSequence:1};
 batch.set(db.doc(`${f.root}/cash_balances/rep_${f.rep}`),{...shared,id:`rep_${f.rep}`,amount:null,amountUnits:opening,legacyAmountCoverage:"not_representable",lastMovementId:headId,syntheticOpeningId:headId});
 batch.set(db.doc(`${f.root}/cash_movements/${headId}`),{...shared,id:headId,bookId:f.bookId,syntheticOpening:true,cutoverDate:"2026-11-10",direction:"in",amountUnits:opening,balanceBeforeUnits:"0",balanceAfterUnits:opening});
 batch.set(db.doc(`${f.b}/synthetic_openings/${headId}`),{companyId:f.companyId,bookId:f.bookId,treasuryAccountId:`rep_${f.rep}`,amountUnits:opening,currency:"JOD",moneyScale:3,cutoverDate:"2026-11-10",syntheticOnly:true});await batch.commit();
 const input={amount:undefined,amountUnits:amount},posted=await f.post(input),journal=(await db.doc(`${f.b}/journal_entries/${posted.result.journalId}`).get()).data().journal;
 assert.equal(journal.debitUnits,amount);const balance=(await db.doc(`${f.root}/cash_balances/rep_${f.rep}`).get()).data();assert.equal(balance.amountUnits,(BigInt(opening)-BigInt(amount)).toString());assert.equal(balance.amount,null);
 const projection=(await db.doc(`${f.root}/financial_ledger_entries/settlement_settlement_operation-first_transfer`).get()).data();assert.equal(projection.amount,null);assert.equal(projection.reportStatus,"exact_reader_required");
 assert.throws(()=>require("../lib/trusted/financial_ledger_reporting").buildLedgerDerivedProjection(projection.id,projection),/schemaVersion/);
 assert.deepEqual((await f.post(input)).result,posted.result);
 await f.post({operationId:"large-followup",idempotencyKey:"large-followup-key",amount:"0.001"});assert.equal((await db.doc(`${f.root}/cash_balances/rep_${f.rep}`).get()).data().amountUnits,(BigInt(opening)-BigInt(amount)-1n).toString());
});
test("treasury uses book precision independently of quantity and unit-price scales",async()=>{
 const f=await accountingFoundationFixture(db,{moneyScale:6}),r=await f.post({amount:"1.234567"});
 const journal=(await db.doc(`${f.b}/journal_entries/${r.result.journalId}`).get()).data().journal;assert.equal(journal.moneyScale,6);assert.equal(journal.debitUnits,"1234567");
 assert.equal((await db.doc(`${f.root}/cash_balances/company_cash`).get()).data().amountUnits,"21234567");
 await assert.rejects(f.post({operationId:"wrong-scale",idempotencyKey:"wrong-scale-key",moneyScale:3}));
});
