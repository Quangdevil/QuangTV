/* Bundled local transport: no remote messaging or automatic downloads. */
const ads=new Set(['doubleclick.net','googlesyndication.com','googleadservices.com','adnxs.com','taboola.com','outbrain.com','popads.net','popcash.net','exoclick.com','juicyads.com','trafficjunky.net']);
const blocked=url=>{try{let h=new URL(url).hostname;while(h){if(ads.has(h))return true;const i=h.indexOf('.');if(i<0)break;h=h.slice(i+1);}}catch{}return false;};
let lastConfig=null,at=0;
async function config(){if(lastConfig&&Date.now()-at<500)return lastConfig;lastConfig=await browser.runtime.sendNativeMessage('may',{op:'config'});at=Date.now();return lastConfig;}
browser.proxy.onRequest.addListener(async details=>{try{const c=await config();return c.enabled?{type:'http',host:'127.0.0.1',port:Number(c.port)||9,failoverTimeout:0}:{type:'direct'};}catch{return {type:'http',host:'127.0.0.1',port:9,failoverTimeout:0};}},{urls:['<all_urls>']});
browser.webRequest.onBeforeRequest.addListener(d=>({cancel:blocked(d.url)}),{urls:['<all_urls>']},['blocking']);
const pending=new Map();
browser.webRequest.onBeforeSendHeaders.addListener(d=>{if(pending.size>300)pending.clear();const h={};for(const x of d.requestHeaders||[]){const k=x.name.toLowerCase();const names={'user-agent':'User-Agent','referer':'Referer','cookie':'Cookie','authorization':'Authorization'};if(names[k]&&x.value?.length<16000)h[names[k]]=x.value;}pending.set(d.requestId,h);},{urls:['<all_urls>']},['requestHeaders']);
browser.webRequest.onHeadersReceived.addListener(async d=>{const type=(d.responseHeaders||[]).find(h=>h.name.toLowerCase()==='content-type')?.value||'';if(!/^video\/|^audio\/|mpegurl/i.test(type)&&!new URL(d.url).pathname.match(/\.(?:m3u8|mp4|webm|mp3|aac)$/i))return;try{const tab=d.tabId>=0?await browser.tabs.get(d.tabId):null;await browser.runtime.sendNativeMessage('may',{op:'media',url:d.url,page:tab?.url||'',headers:pending.get(d.requestId)||{}});}catch{}},{urls:['<all_urls>']},['responseHeaders']);
const clean=d=>pending.delete(d.requestId);browser.webRequest.onCompleted.addListener(clean,{urls:['<all_urls>']});browser.webRequest.onErrorOccurred.addListener(clean,{urls:['<all_urls>']});
