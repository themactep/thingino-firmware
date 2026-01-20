const u='//'+window.location.host;
const p=document.querySelector('progress');
let s=0;
function t(){s+=1;p.value=s;(s===p.max)?g():setTimeout(t,1000);}
function g(){(async()=>{await fetch(u,{method:'HEAD',mode:'no-cors'}).then(()=>{window.location.replace(u);}).catch(()=>{s=0;setTimeout(t,1000);})})()}
setTimeout(t, 1000);
