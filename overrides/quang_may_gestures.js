// Trusted Mây gestures only. No native bridge.
(() => {
  if (window.__quangMayGestures) return;
  window.__quangMayGestures = true;
  // The demo may be paused by an Android/WebView media policy. Let the first
  // light tap start its muted autoplay video, without resuming a user pause.
  const demo = location.hostname === 'may-viet-web-proxy.daquang.workers.dev' && /^\/demo\/?$/.test(location.pathname);
  let demoStarted = false, demoDown = null;
  if (demo) {
    document.addEventListener('playing', e => { if (e.target instanceof HTMLVideoElement) demoStarted = true; }, true);
    document.addEventListener('pointerdown', e => {
      if (e.isTrusted && e.isPrimary !== false) demoDown = {id:e.pointerId,x:e.clientX,y:e.clientY,time:e.timeStamp};
    }, {capture:true,passive:true});
    document.addEventListener('pointercancel', () => { demoDown = null; }, true);
    document.addEventListener('pointerup', e => {
      const down = demoDown; demoDown = null;
      if (!e.isTrusted || demoStarted || !down || down.id !== e.pointerId || e.timeStamp-down.time > 500 || Math.hypot(e.clientX-down.x,e.clientY-down.y) > 12) return;
      if (e.composedPath().some(n => n.matches?.('button,input,a,select,textarea'))) return;
      const video = document.querySelector('video[autoplay]');
      if (video?.paused && video.muted) video.play().then(() => { demoStarted = true; }).catch(() => {});
    }, {capture:true,passive:true});
  }
  // Keep Mây's video AND shadow controls on the same HTML surface. Android's
  // separate custom fullscreen surface can receive touches instead of that UI.
  const requestFullscreen = Element.prototype.requestFullscreen;
  if (requestFullscreen) Element.prototype.requestFullscreen = function(...args) {
    if (this.id === 'may-video-stage' && window.__mayMediaInstalled) return Promise.resolve();
    return requestFullscreen.apply(this, args);
  };
  let previous = null;
  document.addEventListener('pointerup', event => {
    if (!event.isTrusted || !window.__mayMediaInstalled) return;
    const host = document.getElementById('may-browser-controls');
    const path = event.composedPath();
    if (!host || path.includes(host)) return;
    const video = path.find(node => node instanceof HTMLVideoElement);
    if (!video || !Number.isFinite(video.duration) || video.duration <= 0) return;
    const now = performance.now(), box = video.getBoundingClientRect();
    const side = event.clientX < box.left + box.width / 2 ? -1 : 1;
    if (previous && previous.video === video && previous.side === side && now - previous.time < 350 && Math.hypot(event.clientX-previous.x,event.clientY-previous.y) < 48) {
      event.preventDefault();
      video.currentTime = Math.max(0, Math.min(video.duration, video.currentTime + side * 10));
      previous = null;
    } else previous = {video, side, time:now, x:event.clientX, y:event.clientY};
  }, {capture:true, passive:false});
  document.addEventListener('DOMContentLoaded', () => {
    const style = document.createElement('style');
    style.textContent = 'video{touch-action:manipulation}';
    (document.head || document.documentElement).append(style);
  }, {once:true});
})();
