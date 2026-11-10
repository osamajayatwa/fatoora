"use strict";
const cp=require("node:child_process"),fs=require("node:fs"),path=require("node:path");
const root=path.resolve(__dirname,".."),adb="C:/Users/osama aljayatweh/AppData/Local/Android/Sdk/platform-tools/adb.exe",serial="152143758E021512",pkg="com.fujika.fatoora.original.staging";
const dir=path.join(root,"output/staging-current-20261110/phone");
const run=a=>cp.execFileSync(adb,["-s",serial,...a],{windowsHide:true,timeout:20000,maxBuffer:8388608});
function nodes(xml){return [...xml.matchAll(/<node\b[^>]*>/g)].map(m=>Object.fromEntries([...m[0].matchAll(/([\w-]+)="([^"]*)"/g)].map(m=>[m[1],m[2]])));}
function observe(name){if(!/^[a-z0-9-]{1,45}$/.test(name))throw Error("Invalid capture label");fs.mkdirSync(dir,{recursive:true});run(["shell","uiautomator","dump","/sdcard/fatoora-staging-ui.xml"]);const xml=run(["shell","cat","/sdcard/fatoora-staging-ui.xml"]).toString();
 if(!nodes(xml).some(n=>n.package===pkg))throw Error("Staging app is not in the foreground; no external screen captured");
 fs.writeFileSync(path.join(dir,name+".xml"),xml);fs.writeFileSync(path.join(dir,name+".png"),run(["exec-out","screencap","-p"]));
 fs.writeFileSync(path.join(dir,"latest.xml"),xml);console.log(JSON.stringify(nodes(xml).filter(n=>n.text||n["content-desc"]||n.class==="android.widget.EditText").map(n=>({text:n.password==="true"?"[password]":n.text,description:n["content-desc"],type:n.class,bounds:n.bounds,focused:n.focused})),null,2));
}
const action=process.argv[2];
if(action==="capture")observe(process.argv[3]);
else if(action==="tap") {const [x,y]=process.argv.slice(3,5).map(Number);if(!Number.isInteger(x)||!Number.isInteger(y)||x<0||x>1080||y<0||y>2400)throw Error("Invalid coordinate");run(["shell","input","tap",String(x),String(y)]);observe(process.argv[5]);}
else if(action==="back") {run(["shell","input","keyevent","KEYCODE_BACK"]);observe(process.argv[3]);}
else if(action==="choose") {
 run(["shell","uiautomator","dump","/sdcard/fatoora-staging-ui.xml"]);
 const current=nodes(run(["shell","cat","/sdcard/fatoora-staging-ui.xml"]).toString());
 const found=current.filter(n=>n.package===pkg&&n.class==="android.widget.Button"&&n["content-desc"]===process.argv[3]);
 if(found.length!==1)throw Error("Unique observed staging navigation button required");
 const b=[...found[0].bounds.matchAll(/\d+/g)].map(m=>Number(m[0]));if(b[3]-b[1]<30)throw Error("Navigation button is not sufficiently visible");
 run(["shell","input","tap",String(Math.floor((b[0]+b[2])/2)),String(Math.floor((b[1]+b[3])/2))]);observe(process.argv[4]);
}
else if(action==="email"||action==="password") {
 run(["shell","uiautomator","dump","/sdcard/fatoora-staging-ui.xml"]);const current=nodes(run(["shell","cat","/sdcard/fatoora-staging-ui.xml"]).toString());
 const focused=current.find(n=>n.package===pkg&&n.class==="android.widget.EditText"&&n.focused==="true");
 if(!focused||(action==="password")!==(focused.password==="true"))throw Error("Expected staging login field is not focused");
 let value="admin@fatoora.com";
 if(action==="password")value=cp.execFileSync("powershell.exe",["-NoProfile","-ExecutionPolicy","Bypass","-File",path.join(root,"scripts/staging-password.ps1"),"-Mode","Unprotect"],{input:fs.readFileSync(path.join(root,".staging/fatoora-original-staging/admin-password.dpapi"),"utf8"),encoding:"utf8",windowsHide:true}).trim();
 const quoted="'"+value.replace(/'/g,"'\\''")+"'";
 try{run(["shell","input","text",quoted]);}catch{throw Error("Staging credential input failed");}
 console.log(JSON.stringify({status:"ENTERED",field:action}));
} else throw Error("Explicit bounded phone action required");
