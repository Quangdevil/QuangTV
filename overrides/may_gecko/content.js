// A typed native search command; no eval, URL execution, or page-to-native bridge.
const port=browser.runtime.connectNative('mayControl');
port.onMessage.addListener(message=>{
 if(message?.op!=='search'||typeof message.query!=='string'||message.query.length>2000)return;
 const input=document.getElementById('tube-query'),form=document.getElementById('tube-search');
 if(input&&form){input.value=message.query;input.dispatchEvent(new Event('input',{bubbles:true}));form.requestSubmit();}
});
