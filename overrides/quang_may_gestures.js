// Only a trusted double tap on a Mây video changes playback. No native bridge.
(() => {
  if (window.__quangMayGestures) return;
  window.__quangMayGestures = true;
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
