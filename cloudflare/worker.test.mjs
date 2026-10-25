import test from 'node:test';import assert from 'node:assert/strict';
import worker,{targetUrl,rewriteUrl,rewriteCss,rewriteHls,Elements,adHost} from './worker.mjs';
const origin='https://reader.example.net';const base='https://example.com/path/page';
test('only explicit public domains; reject private hosts, credentials and loops',()=>{
 const env={ALLOWED_HOSTS:'example.com,*.example.com'};
 assert.equal(targetUrl(base,env,origin).hostname,'example.com');
 for(const value of ['http://127.0.0.1/','http://169.254.169.254/','https://localhost/','https://user:pass@example.com/','https://other.net/','https://reader.example.net/'])assert.throws(()=>targetUrl(value,env,origin));
});
test('URLs, CSS, nested HLS and key URIs stay routed',()=>{
 const link=rewriteUrl('../movie.mp4',base,origin);assert.equal(new URL(link).searchParams.get('url'),'https://example.com/movie.mp4');
 assert.equal(rewriteUrl('#part',base,origin),'#part');assert.equal(rewriteUrl('javascript:alert(1)',base,origin),'#');
 assert.match(rewriteCss('body{background:url(../pic.png)}',base,origin),/reader\.example\.net\/proxy/);
 const text=rewriteHls('#EXTM3U\n#EXT-X-KEY:METHOD=AES-128,URI="key.bin"\nsegment.ts\n',base,origin);
 assert.match(text,/URI="https:\/\/reader\.example\.net\/proxy/);assert.match(text,/url=https%3A%2F%2Fexample.com%2Fpath%2Fsegment.ts/);
});
class Element{constructor(tag,attrs={}){this.tagName=tag;this.attrs=attrs;this.removed=false;this.extra=''}getAttribute(k){return this.attrs[k]??null}setAttribute(k,v){this.attrs[k]=v}removeAttribute(k){delete this.attrs[k]}remove(){this.removed=true}append(s){this.extra+=s}}
test('HTML handlers remove ads and rewrite attributes without password forwarding',()=>{
 const h=new Elements(base,origin);const ad=new Element('iframe',{src:'https://ads.exoclick.com/frame'});h.element(ad);assert.equal(ad.removed,true);assert.equal(adHost('cdn.popads.net'),true);
 const video=new Element('video',{src:'movie.mp4',poster:'cover.jpg'});h.element(video);assert.match(video.attrs.src,/reader\.example\.net/);assert.match(video.attrs.poster,/reader\.example\.net/);
 const password=new Element('input',{type:'password'});h.element(password);assert.equal(password.attrs.disabled,'');
 const form=new Element('form',{action:'/search',method:'get'});h.element(form);assert.equal(form.attrs.action,origin+'/proxy');assert.match(form.extra,/name="url"/);
});
test('missing or fabricated Access assertion never triggers an upstream fetch',async()=>{
 const response=await worker.fetch(new Request(origin+'/proxy?url='+encodeURIComponent(base),{headers:{'CF-Access-Jwt-Assertion':'fake.fake.fake'}}),{ALLOWED_HOSTS:'example.com',CF_ACCESS_TEAM:'team',CF_ACCESS_AUD:'aud'});
 assert.equal(response.status,403);
});
test('valid Access JWT streams media and strips upstream credentials',async()=>{
 const pair=await crypto.subtle.generateKey({name:'RSASSA-PKCS1-v1_5',modulusLength:2048,publicExponent:new Uint8Array([1,0,1]),hash:'SHA-256'},true,['sign','verify']);
 const jwk=await crypto.subtle.exportKey('jwk',pair.publicKey);jwk.kid='fixture-key';
 const encode=value=>Buffer.from(JSON.stringify(value)).toString('base64url');
 const head=encode({alg:'RS256',kid:jwk.kid});const claims=encode({iss:'https://fixture-team.cloudflareaccess.com',aud:['fixture-aud'],exp:Date.now()/1000+300});
 const data=head+'.'+claims;const signature=Buffer.from(await crypto.subtle.sign('RSASSA-PKCS1-v1_5',pair.privateKey,new TextEncoder().encode(data))).toString('base64url');
 const previous=globalThis.fetch;let mediaCalls=0;
 globalThis.fetch=async(url,init)=>{
   if(String(url).endsWith('/cdn-cgi/access/certs'))return Response.json({keys:[jwk]});
   mediaCalls++;assert.equal(init.headers.has('Cookie'),false);assert.equal(init.headers.has('Authorization'),false);assert.equal(init.headers.has('CF-Access-Jwt-Assertion'),false);assert.equal(init.headers.get('Range'),'bytes=1-2');
   return new Response(new Uint8Array([2,3]),{status:206,headers:{'Content-Type':'video/mp4','Content-Range':'bytes 1-2/3','Set-Cookie':'upstream=secret'}});
 };
 try {
   const response=await worker.fetch(new Request(origin+'/proxy?url='+encodeURIComponent('https://example.com/video.mp4'),{headers:{'CF-Access-Jwt-Assertion':data+'.'+signature,Cookie:'private=session',Authorization:'private-auth',Range:'bytes=1-2'}}),{ALLOWED_HOSTS:'example.com',CF_ACCESS_TEAM:'fixture-team',CF_ACCESS_AUD:'fixture-aud'});
   assert.equal(response.status,206);assert.equal(response.headers.has('Set-Cookie'),false);assert.deepEqual([...new Uint8Array(await response.arrayBuffer())],[2,3]);assert.equal(mediaCalls,1);
 } finally {globalThis.fetch=previous}
});
