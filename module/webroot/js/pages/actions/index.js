// TieJia keybox management - adapted for ReZygisk WebUI
import { exec, toast } from '../../kernelsu.js';

// --- TieJia i18n strings ---
var _t={auto:"Auto-update",fp_t:"Fingerprint",fp_s:"Hourly Pixel Canary refresh",kb_t:"Keybox",kb_s:"Hourly check, only writes if newer",status:"Keybox status",ind_t:"Status indicator",ind_s:"Show status prefix in description",rs_t:"Block ROM spoof",rs_s:"Disable PixelProps / pihooks engines",int_t:"Check every",ckbx:"Custom keybox",ck_t:"Custom keybox",ck_s:"Use your own keybox \u2014 auto-fetch off",ck_pick:"Select keybox file",ck_none:"No file selected",ck_have:"keybox.xml",ck_bad:"Not a valid keybox",ck_sel:"Selected keybox:",fm_new:"Newest",fm_old:"Oldest",fm_empty:"Empty folder",fm_cancel:"Cancel"},bt={auto:"\u81EA\u52A8\u66F4\u65B0",fp_t:"\u6307\u7EB9",fp_s:"\u6BCF\u5C0F\u65F6\u4ECE Pixel Canary \u5237\u65B0",kb_t:"Keybox",kb_s:"\u6BCF\u5C0F\u65F6\u68C0\u67E5\uFF0C\u4EC5\u5728\u66F4\u65B0\u65F6\u5199\u5165",status:"Keybox \u72B6\u6001",ind_t:"\u72B6\u6001\u6307\u793A",ind_s:"\u5728\u63CF\u8FF0\u4E2D\u663E\u793A\u72B6\u6001\u524D\u7F00",rs_t:"\u5C4F\u853D ROM \u4F2A\u88C5",rs_s:"\u7981\u7528 PixelProps / pihooks",int_t:"\u68C0\u67E5\u95F4\u9694",ckbx:"\u81EA\u5B9A\u4E49\u5BC6\u94A5",ck_t:"\u81EA\u5B9A\u4E49\u5BC6\u94A5",ck_s:"\u4F7F\u7528\u81EA\u5DF1\u7684\u5BC6\u94A5 \u2014 \u5173\u95ED\u81EA\u52A8\u83B7\u53D6",ck_pick:"\u9009\u62E9\u5BC6\u94A5\u6587\u4EF6",ck_none:"\u672A\u9009\u62E9\u6587\u4EF6",ck_have:"keybox.xml",ck_bad:"\u4E0D\u662F\u6709\u6548\u7684\u5BC6\u94A5\u6587\u4EF6",ck_sel:"\u5DF2\u9009\u5BC6\u94A5\uFF1A",fm_new:"\u6700\u65B0",fm_old:"\u6700\u65E7",fm_empty:"\u7A7A\u6587\u4EF6\u5939",fm_cancel:"\u53D6\u6D88"},vt={auto:"\u0410\u0432\u0442\u043E\u043E\u0431\u043D\u043E\u0432\u043B\u0435\u043D\u0438\u0435",fp_t:"Fingerprint",fp_s:"\u0415\u0436\u0435\u0447\u0430\u0441\u043D\u043E \u0441 Pixel Canary",kb_t:"Keybox",kb_s:"\u0415\u0436\u0435\u0447\u0430\u0441\u043D\u043E \u043F\u0440\u043E\u0432\u0435\u0440\u043A\u0430, \u0437\u0430\u043F\u0438\u0441\u044C \u0442\u043E\u043B\u044C\u043A\u043E \u0435\u0441\u043B\u0438 \u043D\u043E\u0432\u0435\u0435",status:"\u0421\u0442\u0430\u0442\u0443\u0441 keybox",ind_t:"\u0418\u043D\u0434\u0438\u043A\u0430\u0442\u043E\u0440",ind_s:"\u041F\u043E\u043A\u0430\u0437\u044B\u0432\u0430\u0442\u044C \u043F\u0440\u0435\u0444\u0438\u043A\u0441 \u0432 \u043E\u043F\u0438\u0441\u0430\u043D\u0438\u0438",rs_t:"\u0411\u043B\u043E\u043A ROM-\u0441\u043F\u0443\u0444\u0430",rs_s:"\u041E\u0442\u043A\u043B\u044E\u0447\u0438\u0442\u044C PixelProps / pihooks",int_t:"\u0418\u043D\u0442\u0435\u0440\u0432\u0430\u043B",ckbx:"",ck_t:"",ck_s:"",ck_pick:"",ck_none:"",ck_have:"",ck_bad:"",ck_sel:"",fm_new:"",fm_old:"",fm_empty:"",fm_cancel:""},p={en:_t,zh:bt,ru:vt},yt=new Set(["ar","he","fa","ur"]);

function O(){let t=localStorage.getItem("lang");if(t&&t in p)return t;let e=[navigator.language,...navigator.languages||[]];for(let n of e){if(!n)continue;let s=n.split("-")[0].toLowerCase();if(s in p)return s}return"en"}

function z(t){let e=p[t];e&&(document.documentElement.lang=t,yt.has(t)&&(document.documentElement.dir="rtl"),document.querySelectorAll("[data-i]").forEach(n=>{let s=n.dataset.i;s in e&&e[s]&&(n.textContent=e[s])}))}

// TieJia uses ksu.exec with callback pattern; ReZygisk's exec() returns Promise<{errno,stdout,stderr}>
// They are functionally equivalent
function r(t){return exec(t)}

var c="/data/adb/tricky_store",x="/data/adb/modules/tricky_store";

async function q(t){return(await r(`[ -f "${t}" ] && echo 0 || echo 1`)).stdout.trim()==="1"}
async function Y(t){return(await r(`[ -f "${t}" ] && echo 1 || echo 0`)).stdout.trim()==="1"}
async function j(t,e){await r(e?`rm -f "${t}"`:`mkdir -p "${c}" && touch "${t}"`)}
async function J(t,e){await r(e?`mkdir -p "${c}" && touch "${t}"`:`rm -f "${t}"`)}

var X="as_";
function U(t,e){try{let n=localStorage.getItem(X+t);return n!==null?n:e}catch{return e}}
function Z(t,e){try{localStorage.setItem(X+t,e)}catch{}}

var C=c+"/no_auto_fp",$=c+"/no_auto_keybox",T=c+"/no_auto_indicator",N=c+"/no_rom_spoof_block",_=c+"/custom_keybox",d=c+"/keybox.xml",b=c+"/.custom_keybox_name",W=c+"/hourly_interval_sec";

async function v(t,e,n){let s=U(t,"");if(s!==""){e.checked=s==="1";return}if(n?.toggles&&t in n.toggles){e.checked=!!n.toggles[t];return}let o={auto_fp:C,auto_keybox:$,indicator:T,rom_spoof_block:N,custom_keybox:_}[t];o&&(e.checked=t==="custom_keybox"?await Y(o):await q(o))}

function h(t,e,n,s){e.addEventListener("change",async i=>{let o=i.target.checked;s?await J(n,o):await j(n,o),Z(t,o?"1":"0")})}

async function Q(t,e){let n=e?.interval_min;if(n!=null&&n>=1){t.value=String(n);return}let s=U("interval_min","");if(s){t.value=s;return}let i=await r(`cat "${W}" 2>/dev/null`),o=parseInt((i.stdout||"").trim(),10);t.value=String(Number.isFinite(o)&&o>=60?Math.round(o/60):60)}

function tt(t){let e=async()=>{let n=parseInt(t.value,10);(!Number.isFinite(n)||n<1)&&(n=60),t.value=String(n),await r(`mkdir -p "${c}" && echo ${n*60} > "${W}"`),Z("interval_min",String(n))};t.addEventListener("blur",e),t.addEventListener("keydown",n=>{n.key==="Enter"&&n.target.blur()})}

var m={fm_new:"Newest",fm_old:"Oldest",fm_empty:"Empty folder",fm_cancel:"Cancel",ck_pick:"Select keybox file",ck_none:"No file selected",ck_bad:"Not a valid keybox",ck_sel:"Selected keybox:"};
function it(t){m=t}

var et='<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M4 20h16a1 1 0 0 0 1-1V8a1 1 0 0 0-1-1h-8l-2-2H4a1 1 0 0 0-1 1v13a1 1 0 0 0 1 1z"/></svg>',xt='<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M14 3v4a1 1 0 0 0 1 1h4"/><path d="M17 21H7a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h7l5 5v11a2 2 0 0 1-2 2z"/></svg>',g=t=>"'"+String(t).replace(/'/g,"'\\''")+"'",E=t=>t.replace(/[&<>"]/g,e=>({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;"})[e]||e),rt=t=>new Promise(e=>setTimeout(e,t)),R=t=>{if(!t)return"";let e=new Date(t*1e3),n=s=>String(s).padStart(2,"0");return e.getFullYear()+"-"+n(e.getMonth()+1)+"-"+n(e.getDate())},ct=t=>t>=1048576?(t/1048576).toFixed(1)+" MB":t>=1024?(t/1024).toFixed(1)+" KB":t+" B",at="/storage/emulated/0",a=at,S=0,w=[],F=document.getElementById("fm"),u=document.getElementById("fmList"),I=document.getElementById("fmPath"),ht=document.getElementById("fmSortLbl"),L=[{lbl:"A\u2013Z",cmp:(t,e)=>t.name.localeCompare(e.name)},{lbl:"Z\u2013A",cmp:(t,e)=>e.name.localeCompare(t.name)},{lbl:"",cmp:(t,e)=>e.mtime-t.mtime},{lbl:"",cmp:(t,e)=>t.mtime-e.mtime}];L[2].lbl=m.fm_new||"Newest";L[3].lbl=m.fm_old||"Oldest";

function Et(){let t=a.split("/").filter(Boolean),e="",n=t.map(s=>(e+="/"+s,`<span class="fm-seg" data-p="${E(e)}">${E(s)}</span>`));I.innerHTML=n.length?n.join('<span class="fm-sep">\u203A</span>'):'<span class="fm-seg" data-p="/">/</span>',I.scrollLeft=I.scrollWidth}

async function lt(t){let e="cd "+g(t)+" 2>/dev/null && stat -c '%F\t%s\t%Y\t%n' * 2>/dev/null",n=await r(e),s=[];return(n.stdout||"").split("\n").forEach(i=>{if(!i)return;let o=i.split("\t");if(o.length<4)return;let l=o[0]==="directory";!l&&!o[0].startsWith("regular")||s.push({dir:l,size:parseInt(o[1],10)||0,mtime:parseInt(o[2],10)||0,name:o.slice(3).join("\t")})}),s}

function A(t){ht.textContent=L[S].lbl,Et();let e=L[S].cmp,n=t.filter(o=>o.dir).sort(e),s=t.filter(o=>!o.dir).sort(e),i="";a!=="/"&&(i+='<div class="fm-item" data-up="1"><div class="fm-ic dir">'+et+'</div><div class="fm-info"><div class="fm-nm">..</div></div></div>'),!n.length&&!s.length&&(i+='<div class="fm-empty">'+E(m.fm_empty||"Empty folder")+"</div>");for(let o of[...n,...s]){let l=o.dir?R(o.mtime):ct(o.size)+" \xB7 "+R(o.mtime);i+='<div class="fm-item" data-dir="'+(o.dir?"1":"0")+'" data-name="'+E(o.name)+'"><div class="fm-ic '+(o.dir?"dir":"")+'">'+(o.dir?et:xt)+'</div><div class="fm-info"><div class="fm-nm">'+E(o.name)+'</div><div class="fm-sub">'+l+"</div></div>"}u.innerHTML=i,u.scrollTop=0}

async function H(){u.classList.add("switching");let t=lt(a);await rt(90),w=await t,A(w),requestAnimationFrame(()=>u.classList.remove("switching"))}
async function wt(){u.classList.add("switching"),await rt(90),A(w),requestAnimationFrame(()=>u.classList.remove("switching"))}
function nt(){a!=="/"&&(a=a.replace(/\/[^/]*$/,"")||"/",H())}

async function Lt(t,e){if(((await r("head -c 4096 "+g(t)+" 2>/dev/null | grep -qi -e Keybox -e AndroidAttestation && echo ok || echo bad")).stdout||"").trim()!=="ok"){let o=document.getElementById("ckSize");o.textContent=m.ck_bad||"Not a valid keybox",B();return}await r("mkdir -p "+g(c)+" && cp -f "+g(t)+" "+g(d)+" && chmod 600 "+g(d)+" && printf '%s' "+g(e)+" > "+g(b)),B();let s=document.getElementById("ckName"),i=document.getElementById("ckDel");s.textContent=(m.ck_sel||"Selected keybox:")+" "+e,s.classList.add("ck-sel"),i.hidden=!1}

async function ot(){a=at,F.hidden=!1,u.classList.remove("switching"),u.innerHTML="",w=await lt(a),A(w)}
function B(){F.hidden=!0}

function dt(){document.getElementById("fmUp").addEventListener("click",nt),document.getElementById("fmSort").addEventListener("click",()=>{S=(S+1)%L.length,wt()}),document.getElementById("fmClose").addEventListener("click",B),I.addEventListener("click",t=>{let e=t.target.closest(".fm-seg");e&&e.dataset.p&&e.dataset.p!==a&&(a=e.dataset.p,H())}),F.addEventListener("click",t=>{t.target===F&&B()}),u.addEventListener("click",t=>{let e=t.target.closest(".fm-item");if(!e)return;if(e.dataset.up){nt();return}let n=e.dataset.name,s=(a==="/"?"":a)+"/"+n;e.dataset.dir==="1"?(a=s,H()):Lt(s,n)}),document.getElementById("ckPick").addEventListener("click",ot),document.getElementById("ckName").addEventListener("click",ot)}

var mt="";
function ut(t){mt=t}

async function P(){let t=document.getElementById("ckName"),e=document.getElementById("ckSize"),n=document.getElementById("ckDel"),i=((await r(`[ -s "${d}" ] && echo "$(wc -c < "${d}")|$(stat -c %Y "${d}" 2>/dev/null)" || echo "0|"`)).stdout||"").trim().split("|"),o=parseInt(i[0],10)||0,l=parseInt(i[1],10)||0;if(o>0){let k=(await r(`cat "${b}" 2>/dev/null`)).stdout.trim();k||(k=mt||"keybox.xml"),t.textContent=(m.ck_sel||"Selected keybox:")+" "+k,t.classList.add("ck-sel"),e.textContent=ct(o)+" \xB7 "+R(l),n.hidden=!1}else t.textContent=m.ck_pick||"Select keybox file",t.classList.remove("ck-sel"),e.textContent=m.ck_none||"No file selected",n.hidden=!0}

async function ft(t){let e=document.getElementById("statusRow"),n=document.getElementById("statusVal");if(t?.description&&/[\uD83D\uDFE2\uD83D\uDD34\uD83D\uDFE1\u26AB\u26AA]/.test(t.description)){n.textContent=t.description,e.hidden=!1;return}let i=((await r(`grep -m1 '^description=' "${x}/module.prop" 2>/dev/null | sed -e 's/^description=//' | awk '{print $1}'`)).stdout||"").trim();i&&/[\uD83D\uDFE2\uD83D\uDD34\uD83D\uDFE1\u26AB\u26AA]/.test(i)?(n.textContent=i,e.hidden=!1):e.hidden=!0}

async function gt(t){let e=document.getElementById("ver");if(t?.version){e.textContent=t.version;return}let n=await r(`grep '^version=' "${x}/module.prop" 2>/dev/null | cut -d= -f2-`);e.textContent=n.stdout.trim()||"v?"}

function kt(t){document.getElementById("kbName").textContent=t||""}
function K(t){document.getElementById("ckFileRow").classList.toggle("ck-open",t);let n=document.getElementById("kb").closest(".row");n&&n.classList.toggle("disabled",t)}

async function pt(t){t||await r(`sh "${x}/status_fetch.sh" strip`);let n=((await r(`grep -m1 '^description=' "${x}/module.prop" 2>/dev/null | sed -e 's/^description=//' | awk '{print $1}'`)).stdout||"").trim(),s=document.getElementById("statusRow"),i=document.getElementById("statusVal");n&&/[\uD83D\uDFE2\uD83D\uDD34\uD83D\uDFE1\u26AB\u26AA]/.test(n)?(i.textContent=n,s.hidden=!1):s.hidden=!0}

// --- Main initialization ---
var D=O();z(D);var f=p[D];f&&it({fm_new:f.fm_new,fm_old:f.fm_old,fm_empty:f.fm_empty,fm_cancel:f.fm_cancel,ck_pick:f.ck_pick,ck_none:f.ck_none,ck_bad:f.ck_bad,ck_sel:f.ck_sel});

async function It(){let t=await(window.__statusPromise||Promise.resolve(null));await gt(t),await ft(t);let e=t?.keybox?.source||"";ut(e),kt(e);let n=document.getElementById("fp"),s=document.getElementById("kb"),i=document.getElementById("ind"),o=document.getElementById("rs"),l=document.getElementById("int");await v("auto_fp",n,t),await v("auto_keybox",s,t),await v("indicator",i,t),await v("rom_spoof_block",o,t),h("auto_fp",n,C,!1),h("auto_keybox",s,$,!1),h("indicator",i,T,!1),h("rom_spoof_block",o,N,!1),i.addEventListener("change",async M=>{await pt(M.target.checked)}),await Q(l,t),tt(l);let k=document.getElementById("ck");await v("custom_keybox",k,t),K(k.checked),await P(),k.addEventListener("change",async M=>{let y=M.target.checked;await r(y?`mkdir -p "${_}" `:`rm -f "${_}"`),y?await r(`mkdir -p "/data/adb/tricky_store" && touch "${_}"`):await r(`rm -f "${_}"`),K(y);try{localStorage.setItem("as_custom_keybox",y?"1":"0")}catch{}y||(await r(`rm -f "${d}" "${b}"`),await P())}),document.getElementById("ckDel").addEventListener("click",async()=>{await r(`rm -f "${d}" "${b}"`),await P()}),dt()}

window.__statusPromise = fetch('/status.json').then(r => r.ok ? r.json() : null).catch(() => null);

let _initialized = false;

export async function loadOnce() {}

export async function loadOnceView() {
  if (_initialized) return;
  _initialized = true;

  // Initialize DOM-dependent variables (IDs are only correct after revertHTMLUnuse)
  F=document.getElementById("fm");
  u=document.getElementById("fmList");
  I=document.getElementById("fmPath");
  ht=document.getElementById("fmSortLbl");
  L=[{lbl:"A\u2013Z",cmp:(t,e)=>t.name.localeCompare(e.name)},{lbl:"Z\u2013A",cmp:(t,e)=>e.name.localeCompare(t.name)},{lbl:"",cmp:(t,e)=>e.mtime-t.mtime},{lbl:"",cmp:(t,e)=>t.mtime-e.mtime}];
  L[2].lbl=m.fm_new||"Newest";
  L[3].lbl=m.fm_old||"Oldest";

  setTimeout(It, 10);
}

export async function onceViewAfterUpdate() {}

export async function load() {}
