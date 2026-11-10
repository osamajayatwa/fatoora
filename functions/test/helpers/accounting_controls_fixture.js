const {Timestamp,FieldValue}=require("firebase-admin/firestore");
const {accountingFoundationFixture}=require("./accounting_foundation_fixture");
const {accountingDigest}=require("../../lib/trusted/accounting_journal");
const {accountingDomainWitness}=require("../../lib/trusted/accounting_effects");
const {postAccountingTransaction,recoverAccountingTransaction}=require("../../lib/trusted/accounting_posting");
const {prepareCustomerCharge}=require("../../lib/trusted/confirm_invoice");
const {prepareCustomerReceipt,prepareCustomerCreditApplication}=require("../../lib/trusted/create_receipt");
const {prepareCustomerReturnCredit,prepareCustomerReceivableReduction,prepareCustomerReturnControls}=require("../../lib/trusted/confirm_sales_return");
const {prepareExactCashChange}=require("../../lib/trusted/cash_ledger");
const {prepareExactInventoryChanges}=require("../../lib/trusted/inventory");
async function controlsFixture(db,{stockCount=1}={}){
 const f=await accountingFoundationFixture(db),customerId="customer-controls",setup=db.batch();
 setup.set(db.doc(`${f.root}/customers/${customerId}`),{id:customerId,companyId:f.companyId,name:"Synthetic customer",active:true});
 const partyPath=`${f.b}/party_positions/${customerId}`,party={schemaVersion:1,id:customerId,companyId:f.companyId,bookId:f.bookId,customerId,currency:"JOD",moneyScale:3,
  receivableUnits:"0",returnCreditUnits:"0",signedDebtUnits:"0",accountSequence:1,syntheticOpeningId:"customer-zero",updatedAt:FieldValue.serverTimestamp()};
 setup.set(db.doc(partyPath),party);setup.set(db.doc(`${f.b}/synthetic_openings/customer-zero`),{companyId:f.companyId,bookId:f.bookId,syntheticOnly:true,cutoverDate:"2026-11-10",createdAt:FieldValue.serverTimestamp(),positions:{[accountingDigest(partyPath)]:accountingDomainWitness(party)}});
 const scope={companyId:f.companyId,bookId:f.bookId,revisionId:"definition-v1",active:true,currency:"JOD",moneyScale:3,numberingPolicy:"source_identity"};
 setup.set(db.doc(`${f.b}/journal_definitions/customer-controls-v1`),{...scope,id:"customer-controls-v1",allowedActions:["charge","receipt","return_credit","apply_credit","return_reduction","return_split"],
  allowedSourceTypes:["invoices","receipts","sales_returns","customer_credit_applications"],allowedControls:["cash","receivable","customer_credit","none"]});
 setup.set(db.doc(`${f.b}/journal_definitions/stock-controls-v1`),{...scope,id:"stock-controls-v1",postingKind:"quantity",allowedActions:["transfer","sale","return","count","receipt"],allowedSourceTypes:["inventory_transfers","invoices","sales_returns","stock_adjustments"],allowedControls:[]});
 const itemIds=[],openingGroups=[];
 for(let i=0;i<stockCount;i++){
  const itemId=`${f.companyId}-item-${i}`;itemIds.push(itemId);
  for(const warehouse of[true,false]){
   const positionPath=warehouse?`items/${itemId}`:`${f.root}/rep_inventory_balances/${f.rep}_${itemId}`;
   const openingId=`stock-opening-${Math.floor(openingGroups.length/32)}`,headId=`opening_${accountingDigest(positionPath)}`,units=warehouse?"100000000":"0";
   let d;
   if(warehouse)d={id:itemId,companyId:f.companyId,name:"Quantity-only item",unit:"piece",active:true,deleted:false,trackStock:true,warehouseId:"warehouse-main",price:7.5,
    currentStock:100,currentStockUnits:units,stockBookId:f.bookId,stockQuantityScale:6,stockSequence:1,lastStockMovementId:headId,stockOpeningId:openingId,stockUpdatedAt:FieldValue.serverTimestamp()};
   else d={id:`${f.rep}_${itemId}`,companyId:f.companyId,bookId:f.bookId,itemId,salesRepId:f.rep,unit:"piece",quantityScale:6,quantityUnits:units,quantity:0,
    accountSequence:1,lastMovementId:headId,syntheticOpeningId:openingId,quantityUpdatedAt:FieldValue.serverTimestamp()};
   setup.set(db.doc(positionPath),d);
   const projection=warehouse?Object.fromEntries(["companyId","currentStock","currentStockUnits","stockBookId","stockQuantityScale","stockSequence","lastStockMovementId","stockOpeningId"].map(k=>[k,d[k]])):d;
   openingGroups.push({openingId,path:positionPath,projection:accountingDomainWitness(projection)});
   setup.set(db.doc(`${f.root}/${warehouse?"stock_movements":"rep_inventory_movements"}/${headId}`),{id:headId,companyId:f.companyId,bookId:f.bookId,itemId,unit:"piece",quantityScale:6,
    holderType:warehouse?"warehouse":"representative",holderId:warehouse?"warehouse-main":f.rep,accountSequence:1,quantityUnits:units,quantityBeforeUnits:"0",quantityAfterUnits:units,direction:"in",syntheticOpening:true});
  }
 }
 for(const id of new Set(openingGroups.map(p=>p.openingId)))setup.set(db.doc(`${f.b}/synthetic_openings/${id}`),{companyId:f.companyId,bookId:f.bookId,syntheticOnly:true,cutoverDate:"2026-11-10",createdAt:FieldValue.serverTimestamp(),
  positions:Object.fromEntries(openingGroups.filter(p=>p.openingId===id).map(p=>[accountingDigest(p.path),p.projection]))});
 await setup.commit();
 function command(kind,id,input){
  const types={charge:"invoices",receipt:"receipts",return_credit:"sales_returns",return_reduction:"sales_returns",return_split:"sales_returns",apply_credit:"customer_credit_applications",transfer:"inventory_transfers",sale:"invoices",return:"sales_returns",count:"stock_adjustments"};
  return {companyId:f.companyId,bookId:f.bookId,requestId:`request-${kind}-${id}`,expectedConfigurationDigest:f.input.expectedConfigurationDigest,
   source:{system:"fatoora",type:types[kind],id:`source-${id}`,revision:"1",action:kind},businessTime:{seconds:Timestamp.fromDate(new Date("2026-11-11T10:00:00Z")).seconds,nanoseconds:0},semantic:{customerId,...input}};
 }
 function adapter(c,kind,input,transform){
  const stock=["transfer","sale","return","count"].includes(kind),cashAmount=kind==="receipt"?input.amountUnits:kind==="charge"?input.initialPaymentUnits:null;
  const cashId=`cash_${accountingDigest(c.source)}`,sourcePath=`${f.root}/${c.source.type}/${c.source.id}`;
  const stockPaths=(input.changes??[]).map(ch=>`${f.root}/${ch.holderType==="warehouse"?"stock_movements":"rep_inventory_movements"}/stock_${accountingDigest([c.source,ch.lineId,ch.itemId,ch.holderType,ch.holderId])}`);
  return{definitionId:stock?"stock-controls-v1":"customer-controls-v1",controlCollections:["open_items","open_item_positions","party_positions","allocations"],
   itemPaths:[...new Set((input.changes??[]).map(ch=>`items/${ch.itemId}`))],domainPaths:[sourcePath,...stockPaths,...(input.changes??[]).filter(ch=>ch.holderType==="representative").map(ch=>`${f.root}/rep_inventory_balances/${ch.holderId}_${ch.itemId}`),
    ...(cashAmount&&cashAmount!=="0"?[`${f.root}/cash_movements/${cashId}`,`${f.root}/cash_balances/company_cash`]:[])],
   async prepare(tx,database,ctx){
    const plans=[],lines=[];
    const account=role=>({...ctx.configuration.accounts.find(a=>a.id===ctx.configuration.mappings[role]),companyId:f.companyId,bookId:f.bookId,revisionId:ctx.revisionId,currency:ctx.configuration.currency,moneyScale:ctx.configuration.moneyScale});
    const counter=(role,units,debit)=>({id:"counter",account:account(role),dimensions:{},debitUnits:debit?units:"0",creditUnits:debit?"0":units});
    if(kind==="charge"){plans.push(await prepareCustomerCharge(tx,database,ctx,{customerId,amountUnits:input.amountUnits,componentId:"principal",dueDate:input.dueDate??"2026-11-20",initialPaymentUnits:input.initialPaymentUnits??"0"}));lines.push(counter("sales",input.amountUnits,false));}
    if(kind==="receipt")plans.push(await prepareCustomerReceipt(tx,database,ctx,{customerId,amountUnits:input.amountUnits}));
    if(kind==="return_credit"){plans.push(await prepareCustomerReturnCredit(tx,database,ctx,{customerId,amountUnits:input.amountUnits,componentId:"paid-return"}));lines.push(counter("salesReturns",input.amountUnits,true));}
    if(kind==="return_reduction"){plans.push(await prepareCustomerReceivableReduction(tx,database,ctx,{customerId,amountUnits:input.amountUnits,chargeItemId:input.chargeItemId}));lines.push(counter("salesReturns",input.amountUnits,true));}
    if(kind==="return_split"){plans.push(await prepareCustomerReturnControls(tx,database,ctx,{customerId,chargeItemId:input.chargeItemId,receivableReductionUnits:input.receivableReductionUnits,creditUnits:input.creditUnits,componentId:"paid-return"}));lines.push(counter("salesReturns",(BigInt(input.receivableReductionUnits)+BigInt(input.creditUnits)).toString(),true));}
    if(kind==="apply_credit")plans.push(await prepareCustomerCreditApplication(tx,database,ctx,{customerId,amountUnits:input.amountUnits,creditItemId:input.creditItemId}));
    if(input.changes)plans.push(await prepareExactInventoryChanges(tx,database,ctx,input.changes));
    if(cashAmount&&cashAmount!=="0"){
     const cash=await prepareExactCashChange(tx,database,ctx,{cashAccount:"company_cash",direction:"in",amountUnits:cashAmount,movementId:cashId});plans.push(cash);
     lines.push({id:"actual-cash",account:account("companyCash"),dimensions:cash.effect.dimensions,debitUnits:cashAmount,creditUnits:"0"});
    }
    for(const p of plans)lines.push(...p.lines??[]);
    const journal=stock?null:{schemaVersion:1,companyId:f.companyId,bookId:f.bookId,currency:ctx.configuration.currency,moneyScale:ctx.configuration.moneyScale,accountingDate:ctx.accountingDate,
     periodId:ctx.periodId,journalDefinitionId:ctx.definitionId,journalDefinitionRevisionId:ctx.definitionRevisionId,configurationDigest:ctx.configurationDigest,source:c.source,lines,
     debitUnits:lines.reduce((n,l)=>n+BigInt(l.debitUnits),0n).toString(),creditUnits:lines.reduce((n,l)=>n+BigInt(l.creditUnits),0n).toString()};
    const prepared={journal,controlEffects:plans.flatMap(p=>p.controlEffects??(p.effect?[p.effect]:[])),stockEffects:plans.flatMap(p=>p.stockEffects??[]),
     writes(binding){return[{method:"create",path:sourcePath,data:{id:c.source.id,companyId:f.companyId,customerId,...input,accounting:binding,createdAt:FieldValue.serverTimestamp()}},...plans.flatMap(p=>p.writes(binding))];}};
    return transform?transform(prepared,ctx):prepared;
   }};
 }
 const operation=(kind,id,input={},overrides={},database=db,uid=f.admin,recovery=false,transform)=>{const c={...command(kind,id,input),...overrides};const a=adapter(c,kind,input,transform);return(recovery?recoverAccountingTransaction:postAccountingTransaction)(database,uid,c,a,{enableEmulatorPosting:true});};
 const transferChanges=(quantityUnits="1250000")=>itemIds.flatMap((itemId,i)=>[{lineId:`line-${i}`,itemId,quantityUnits,direction:"out",holderType:"warehouse",holderId:"warehouse-main",purpose:"transfer"},
  {lineId:`line-${i}`,itemId,quantityUnits,direction:"in",holderType:"representative",holderId:f.rep,purpose:"transfer"}]);
 return{...f,customerId,itemIds,partyPath,operation,transferChanges,itemIdFor:(kind,id)=>`item_${accountingDigest([command(kind,id,{}).source,kind==="charge"?"principal":"paid-return",customerId])}`};
}
module.exports={controlsFixture};
