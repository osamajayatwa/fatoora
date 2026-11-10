const {test}=require("node:test");
const assert=require("node:assert/strict");
const {validateAccountingJournal:validate,accountingDigest,accountingEventId,accountingLocalDate,accountingCanonical}=require("../lib/trusted/accounting_journal");
function fixture(){
  const account=(id,type,control="none")=>({id,code:id.toUpperCase(),name:id,parentId:null,accountType:type,normalSide:type==="asset"?"debit":"credit",control,postingAllowed:true,active:true,companyId:"company",bookId:"book",revisionId:"revision_1",currency:"JOD",moneyScale:3});
  return {schemaVersion:1,companyId:"company",bookId:"book",currency:"JOD",moneyScale:3,accountingDate:"2026-11-10",periodId:"nov",journalDefinitionId:"sales",journalDefinitionRevisionId:"definition-v1",configurationDigest:"a".repeat(64),
    source:{system:"fatoora",type:"invoices",id:"sale-1",revision:"1",action:"confirm"},
    debitUnits:"116000",creditUnits:"116000",lines:[
      {id:"ar",account:account("ar","asset","receivable"),debitUnits:"116000",creditUnits:"0",dimensions:{customerId:"customer-1"}},
      {id:"sales",account:account("sales","income"),debitUnits:"0",creditUnits:"100000",dimensions:{}},
      {id:"tax",account:account("tax","liability","tax"),debitUnits:"0",creditUnits:"16000",dimensions:{}}]};
}
test("shared journal handles a complete three-line exact sale/tax intent",()=>{const j=validate(fixture());assert.equal(j.debitUnits,"116000");assert.equal(j.lines.length,3);});
const invalid=[
 ["unbalanced lines",j=>j.lines[1].creditUnits="99999"],["wrong header total",j=>j.debitUnits="0"],
 ["numeric amount",j=>j.lines[0].debitUnits=116000],["leading zero units",j=>j.lines[0].debitUnits="0116000"],
 ["negative units",j=>j.lines[0].creditUnits="-1"],["decimal units",j=>j.lines[0].debitUnits="116000.0"],
 ["exponent units",j=>j.lines[0].debitUnits="1e5"],["oversized units",j=>j.lines[0].debitUnits="1".repeat(31)],
 ["both sides",j=>j.lines[0].creditUnits="1"],["empty line",j=>{j.lines[0].debitUnits="0";}],
 ["one line",j=>j.lines=j.lines.slice(0,1)],["line capacity",j=>j.lines=Array(257).fill(j.lines[0])],
 ["duplicate line IDs",j=>j.lines[1].id=j.lines[0].id],["foreign company",j=>j.lines[0].account.companyId="other"],
 ["foreign book",j=>j.lines[0].account.bookId="other"],["mixed currency",j=>j.lines[0].account.currency="USD"],
 ["mixed precision",j=>j.lines[0].account.moneyScale=2],["inactive account",j=>j.lines[0].account.active=false],
 ["group account",j=>j.lines[0].account.postingAllowed=false],["missing account snapshot",j=>delete j.lines[0].account.code],
 ["wrong control type",j=>j.lines[0].account.accountType="income"],
 ["missing customer",j=>j.lines[0].dimensions={}],["unknown dimension",j=>j.lines[0].dimensions.guessed="bad"],
 ["invalid accounting date",j=>j.accountingDate="2026-02-30"],["client balancing plug",j=>j.plug="1"],
 ["missing treasury holder",j=>{j.lines[0].account.control="cash";j.lines[0].dimensions={treasuryAccountId:"company_cash"};}],
];
for(const[name,change]of invalid)test(`journal rejects ${name}`,()=>{const j=fixture();change(j);assert.throws(()=>validate(j));});
test("exact values beyond numeric storage capacity remain valid canonical journal units",()=>{
 const j=fixture();j.lines=j.lines.slice(0,2);const units="123456789012345678901234567890";
 j.lines[0].debitUnits=units;j.lines[1].creditUnits=units;j.debitUnits=units;j.creditUnits=units;assert.equal(validate(j).debitUnits,units);
});
test("overflow of combined line totals is rejected",()=>{const j=fixture();for(const l of j.lines){if(l.debitUnits!=="0")l.debitUnits="9".repeat(30);if(l.creditUnits!=="0")l.creditUnits="9".repeat(30);}assert.throws(()=>validate(j));});
test("the full 256-line journal capacity is supported",()=>{
 const j=fixture(),debit=j.lines[0],credit=j.lines[1];j.lines=Array.from({length:256},(_,i)=>({...structuredClone(i%2===0?debit:credit),id:`line-${i}`,debitUnits:i%2===0?"1":"0",creditUnits:i%2===1?"1":"0"}));
 j.debitUnits="128";j.creditUnits="128";assert.equal(validate(j).lines.length,256);
});
test("economic identity distinguishes genuine identical sales by source ID",()=>{
 const a=fixture(), b=fixture();b.source.id="sale-2";assert.notEqual(accountingEventId(a.companyId,a.bookId,a.source),accountingEventId(b.companyId,b.bookId,b.source));
 const c={...a.source,revision:"2"};assert.equal(accountingEventId(a.companyId,a.bookId,a.source),accountingEventId(a.companyId,a.bookId,c));
});
test("canonical hashing ignores object insertion order and rejects binary money/undefined",()=>{
 assert.equal(accountingDigest({b:2,a:"1000"}),accountingDigest({a:"1000",b:2}));
 assert.throws(()=>accountingCanonical({money:1.234}));assert.throws(()=>accountingCanonical({unknown:undefined}));
 assert.throws(()=>accountingCanonical({date:new Date()}));
});
test("local accounting dates follow Amman midnight rather than UTC midnight",()=>{
 const at=s=>({seconds:Date.parse(s)/1000,nanoseconds:0});
 assert.equal(accountingLocalDate(at("2026-11-09T20:59:59Z")),"2026-11-09");
 assert.equal(accountingLocalDate(at("2026-11-09T21:00:00Z")),"2026-11-10");
 assert.throws(()=>accountingLocalDate({seconds:1,nanoseconds:1}));
});
module.exports={fixture};
