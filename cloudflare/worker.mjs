// Public-content reader. Keep authenticated Facebook/Telegram sessions in the native browser.
const AD_HOSTS = ['doubleclick.net','googlesyndication.com','googleadservices.com','exoclick.com','juicyads.com','popads.net','popcash.net','adsterra.com','propellerads.com','trafficjunky.net','tsyndicate.com','highperformanceformat.com','highperformancegate.com'];
export function adHost(host) { return AD_HOSTS.some(domain => host === domain || host.endsWith('.'+domain)); }
export function targetUrl(value, env, workerOrigin) {
  const url = new URL(value);
  if (!['https:','http:'].includes(url.protocol) || url.username || url.password || (url.port && !['80','443'].includes(url.port)) || url.origin === workerOrigin) throw new Error('Invalid target');
  const host = url.hostname.toLowerCase();
  if (!host.includes('.') || /[\[\]:]/.test(host) || /^\d+(\.\d+){3}$/.test(host) || /\.(localhost|local|internal|lan)$/.test(host)) throw new Error('Private targets not supported');
  const allowed = String(env.ALLOWED_HOSTS || '').split(',').map(s=>s.trim().toLowerCase()).filter(Boolean);
  if (!allowed.some(domain=>domain.startsWith('*.') ? host.endsWith(domain.slice(1)) && host !== domain.slice(2) : host === domain)) throw new Error('Target not allowlisted');
  return url;
}
export function rewriteUrl(value, base, origin) {
  if (!value || value.startsWith('#') || /^(data:|blob:|mailto:|tel:)/i.test(value)) return value;
  if (/^javascript:/i.test(value)) return '#';
  const url = new URL(value, base);
  if (!['http:','https:'].includes(url.protocol)) return '#';
  if (url.origin === origin && url.pathname === '/proxy') return url.href;
  const hash = url.hash; url.hash = '';
  return origin+'/proxy?url='+encodeURIComponent(url.href)+hash;
}
export function rewriteCss(text, base, origin) {
  return text.replace(/url\(\s*(['"]?)([^)'"\s]+)\1\s*\)/gi,(_,quote,url)=>`url("${rewriteUrl(url,base,origin).replaceAll('"','%22')}")`)
    .replace(/@import\s+(['"])([^'"]+)\1/gi,(_,quote,url)=>`@import "${rewriteUrl(url,base,origin)}"`);
}
export function rewriteHls(text, base, origin) {
  return text.split(/\r?\n/).map(line=>line.startsWith('#') ? line.replace(/URI="([^"]+)"/g,(_,url)=>`URI="${rewriteUrl(url,base,origin)}"`) : line.trim() ? rewriteUrl(line.trim(),base,origin) : line).join('\n');
}
function htmlEscape(value) { return value.replaceAll('&','&amp;').replaceAll('"','&quot;').replaceAll('<','&lt;').replaceAll('>','&gt;'); }
export class Elements {
  constructor(base, origin) { this.base=base; this.origin=origin; }
  element(el) {
    const tag=el.tagName.toLowerCase();
    const marker=(el.getAttribute('id')||'')+' '+(el.getAttribute('class')||'');
    const resources=['src','href','data-src'].map(a=>el.getAttribute(a)).filter(Boolean);
    if (['script','iframe','div'].includes(tag) && (/\b(advertisement|adsbygoogle|ad-container|ad-slot|popunder|sponsored)\b/i.test(marker) || resources.some(value=>{try{return adHost(new URL(value,this.base).hostname)}catch{return false}}))) { el.remove();return; }
    if (tag==='base' || tag==='meta' && /^(refresh|content-security-policy)$/i.test(el.getAttribute('http-equiv')||'')) { el.remove();return; }
    if (tag==='input' && el.getAttribute('type')?.toLowerCase()==='password') { el.setAttribute('disabled',''); el.setAttribute('placeholder','Dùng trình duyệt trực tiếp để đăng nhập'); }
    if(tag==='form') {
      const original=new URL(el.getAttribute('action')||this.base,this.base).href;
      if ((el.getAttribute('method')||'get').toLowerCase()==='get') { el.setAttribute('action',this.origin+'/proxy'); el.append(`<input type="hidden" name="url" value="${htmlEscape(original)}">`,{html:true}); }
      else { el.setAttribute('action',rewriteUrl(original,this.base,this.origin)); el.setAttribute('onsubmit','return false'); }
    }
    for(const attr of ['href','src','poster','data-src','formaction']) {
      const value=el.getAttribute(attr);
      if(value!==null) { el.setAttribute(attr,rewriteUrl(value,this.base,this.origin)); if (['script','link'].includes(tag)) el.removeAttribute('integrity'); }
    }
    const srcset=el.getAttribute('srcset');
    if(srcset && !srcset.trim().startsWith('data:')) el.setAttribute('srcset',srcset.split(',').map(part=>{const [url,...size]=part.trim().split(/\s+/);return [rewriteUrl(url,this.base,this.origin),...size].join(' ')}).join(', '));
    const style=el.getAttribute('style'); if(style)el.setAttribute('style',rewriteCss(style,this.base,this.origin));
    if(tag==='a'){el.removeAttribute('target');el.setAttribute('rel','noreferrer');}
  }
}
const jwksCache = new Map();
function decode64(value) { return Uint8Array.from(atob(value.replaceAll('-','+').replaceAll('_','/')), c=>c.charCodeAt(0)); }
async function authorized(request, env) {
  if(!/^[a-z0-9-]+$/.test(env.CF_ACCESS_TEAM||'') || !env.CF_ACCESS_AUD) return false;
  const jwt=request.headers.get('CF-Access-Jwt-Assertion'); if(!jwt || jwt.length>16000)return false;
  try {
    const parts=jwt.split('.'); if(parts.length!==3)return false;
    const header=JSON.parse(new TextDecoder().decode(decode64(parts[0]))); const claim=JSON.parse(new TextDecoder().decode(decode64(parts[1])));
    const issuer='https://'+env.CF_ACCESS_TEAM+'.cloudflareaccess.com'; const now=Date.now()/1000;
    if(header.alg!=='RS256' || claim.iss!==issuer || !(claim.exp>now) || claim.nbf>now+30 || !(Array.isArray(claim.aud)?claim.aud:[claim.aud]).includes(env.CF_ACCESS_AUD))return false;
    let cached=jwksCache.get(issuer);
    if(!cached || cached.until<Date.now()){ const response=await fetch(issuer+'/cdn-cgi/access/certs');if(!response.ok)return false;cached={keys:(await response.json()).keys,until:Date.now()+300000};jwksCache.set(issuer,cached); }
    const jwk=cached.keys.find(key=>key.kid===header.kid);if(!jwk)return false;
    const key=await crypto.subtle.importKey('jwk',jwk,{name:'RSASSA-PKCS1-v1_5',hash:'SHA-256'},false,['verify']);
    return await crypto.subtle.verify('RSASSA-PKCS1-v1_5',key,decode64(parts[2]),new TextEncoder().encode(parts[0]+'.'+parts[1]));
  } catch{return false;}
}
export default {
  async fetch(request, env) {
    const current=new URL(request.url);
    if (!await authorized(request,env)) return new Response('Cần Cloudflare Access được cấu hình đúng cho Worker cá nhân.',{status:403,headers:{'Cache-Control':'no-store'}});
    if (!['GET','HEAD'].includes(request.method)) return new Response('Worker chỉ đọc nội dung công khai. Dùng trình duyệt/proxy native cho đăng nhập và thao tác tài khoản.',{status:405});
    if(current.pathname!=='/proxy' || !current.searchParams.get('url')) return new Response('Dùng /proxy?url=https%3A%2F%2Ften-mien-trong-allowlist',{status:400});
    let target;
    try { target=targetUrl(current.searchParams.get('url'),env,current.origin); for(const [key,value]of current.searchParams)if(key!=='url')target.searchParams.append(key,value); } catch { return new Response('Tên miền không được phép hoặc URL không hợp lệ.',{status:403}); }
    if(adHost(target.hostname))return new Response(null,{status:204});
    const headers=new Headers();
    for(const name of ['Accept','Accept-Language','Sec-WebSocket-Protocol','Range','If-Range','If-None-Match','If-Modified-Since'])if(request.headers.has(name))headers.set(name,request.headers.get(name));
    headers.set('User-Agent',env.UPSTREAM_USER_AGENT || (request.headers.get('User-Agent')||'Mozilla/5.0').replace('; wv','').replace(' Version/4.0',''));
    // Do not forward Cloudflare Access assertions, account cookies or Authorization upstream.
    if(request.headers.get('Upgrade')?.toLowerCase()==='websocket') headers.set('Upgrade','websocket');
    let upstream;
    try { upstream=await fetch(target.href,{method:request.method,headers,redirect:'manual'}); } catch { return new Response('Không kết nối được trang đích.',{status:502}); }
    if(upstream.status===101)return upstream;
    const out=new Headers(upstream.headers); for(const key of ['Set-Cookie','Content-Security-Policy','Content-Security-Policy-Report-Only','X-Frame-Options','Access-Control-Allow-Origin','Access-Control-Allow-Credentials'])out.delete(key);
    out.set('Cache-Control','private, no-store');out.set('Referrer-Policy','no-referrer');out.set('X-Content-Type-Options','nosniff');
    if(out.has('Location'))out.set('Location',rewriteUrl(out.get('Location'),target.href,current.origin));
    const type=out.get('Content-Type')||'';
    if(request.method==='HEAD' || upstream.status===204 || upstream.status===304)return new Response(null,{status:upstream.status,headers:out});
    if(type.includes('text/html')) {
      out.delete('Content-Length');out.delete('Content-Encoding');out.delete('ETag');
      out.set('Content-Security-Policy',"default-src 'self' data: blob:; script-src 'self' 'unsafe-inline' 'unsafe-eval'; style-src 'self' 'unsafe-inline'; connect-src 'self'; form-action 'self'; worker-src 'none'; object-src 'none'; base-uri 'self'; frame-ancestors 'self'");
      return new HTMLRewriter().on('*',new Elements(target.href,current.origin)).on('body',{element(el){el.prepend('<div style="padding:8px;background:#fff3cd;color:#222;font:13px sans-serif">Worker đọc nội dung công khai. Đăng nhập Facebook/Telegram bằng trình duyệt native trong QuangTV.</div>',{html:true})}}).transform(new Response(upstream.body,{status:upstream.status,headers:out}));
    }
    if(type.includes('text/css') || type.includes('mpegurl') || target.pathname.endsWith('.m3u8')) {
      out.delete('Content-Length');out.delete('Content-Encoding');out.delete('ETag');
      const text=await upstream.text();return new Response(type.includes('text/css')?rewriteCss(text,target.href,current.origin):rewriteHls(text,target.href,current.origin),{status:upstream.status,headers:out});
    }
    // MP4, images and other binary bodies remain streamed, including 206/Content-Range.
    return new Response(upstream.body,{status:upstream.status,headers:out});
  }
};
