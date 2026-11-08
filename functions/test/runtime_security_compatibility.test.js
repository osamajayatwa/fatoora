"use strict";
const {test}=require("node:test"),assert=require("node:assert/strict"),path=require("node:path");
const {createRequire}=require("node:module"),{spawn}=require("node:child_process"),http=require("node:http"),zlib=require("node:zlib");

test("patched UUID remains CommonJS compatible at every existing SDK caller",()=>{
  for(const parent of ["firebase-admin","google-gax","gaxios","teeny-request","cloudevents"]){
    const load=createRequire(require.resolve(parent));
    const uuid=load("uuid"),id=uuid.v4();
    assert.equal(uuid.validate(id),true);assert.equal(uuid.version(id),4);
    assert.equal(load("uuid/package.json").version,"11.1.1");
  }
});

test("all shipped HTTP handlers resolve the patched parser and proxy packages",()=>{
  for(const parent of ["firebase-functions","@google-cloud/functions-framework"]){
    const load=createRequire(require.resolve(parent));
    assert.equal(load("body-parser/package.json").version,"1.20.9");
    const expressLoad=createRequire(load.resolve("express"));
    assert.equal(expressLoad("proxy-addr/package.json").version,"2.0.8");
    assert.equal(expressLoad("qs/package.json").version,"6.16.1");
  }
  const proxy=require("proxy-addr"),trust=proxy.compile("::ffff:10.0.0.0/8");
  assert.equal(trust("203.0.113.10"),false);
  assert.equal(proxy.compile("10.0.0.0/8")("10.2.3.4"),true);
});

test("malformed compressed body cannot terminate the Functions HTTP parser process",{timeout:12000},async()=>{
  const entry="const express=require('express');const a=express();a.use(express.json());a.post('/',(q,s)=>s.json({ok:true}));a.use((e,q,s,n)=>s.sendStatus(400));const s=a.listen(0,'127.0.0.1',()=>process.stdout.write(String(s.address().port)+'\\n'));";
  const child=spawn(process.execPath,["-e",entry],{cwd:path.resolve(__dirname,".."),stdio:["ignore","pipe","pipe"],windowsHide:true});
  try{
    const port=await new Promise((resolve,reject)=>{child.stdout.once("data",b=>resolve(Number(String(b).trim())));child.once("error",reject);child.once("exit",c=>reject(Error(`parser process exited ${c}`)));});
    assert.ok(port>0);
    await new Promise(resolve=>{
      const request=http.request({host:"127.0.0.1",port,path:"/",method:"POST",headers:{"content-type":"application/json","content-encoding":"gzip"}},response=>{response.resume();response.on("end",resolve);});
      request.on("error",resolve);request.write(zlib.gzipSync(Buffer.from('{"synthetic":true}')));
      setTimeout(()=>request.end(Buffer.from("invalid trailing compressed bytes")),30);
    });
    await new Promise(resolve=>setTimeout(resolve,120));assert.equal(child.exitCode,null);
    const status=await new Promise((resolve,reject)=>{const request=http.request({host:"127.0.0.1",port,path:"/",method:"POST",headers:{"content-type":"application/json"}},r=>{r.resume();r.on("end",()=>resolve(r.statusCode));});request.on("error",reject);request.end('{"synthetic":true}');});
    assert.equal(status,200);
  }finally{child.kill();}
});
