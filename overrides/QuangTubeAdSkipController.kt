package app.tvviewer.player

import android.webkit.WebView

/** Best-effort click on YouTube's visible, enabled Skip Ad button. */
internal class QuangTubeAdSkipController(private val webView: WebView) {
    private val handler = android.os.Handler(android.os.Looper.getMainLooper())
    private var running = false
    private val tick = object : Runnable {
        override fun run() {
            if (!running) return
            webView.evaluateJavascript(SKIP_SCRIPT, null)
            handler.postDelayed(this, 800)
        }
    }

    fun start() {
        if (running) return
        running = true
        handler.post(tick)
    }

    fun stop() {
        running = false
        handler.removeCallbacks(tick)
    }

    private companion object {
        // No DOM mutation, injected styles, playback seeking, or ad-video manipulation.
        val SKIP_SCRIPT = """
            (() => {
              const selectors = [
                '.ytp-ad-skip-button',
                '.ytp-ad-skip-button-modern',
                '.ytp-skip-ad-button',
                'button.ytp-ad-skip-button',
                'button[aria-label="Skip Ads"]',
                'button[aria-label="Skip Ad"]',
                'button[aria-label="Bỏ qua quảng cáo"]'
              ];
              for (const selector of selectors) {
                const button = document.querySelector(selector);
                if (!button || button.disabled) continue;
                const rect = button.getBoundingClientRect();
                const style = getComputedStyle(button);
                if (rect.width > 0 && rect.height > 0 &&
                    style.visibility !== 'hidden' && style.display !== 'none') {
                  button.click();
                  break;
                }
              }
            })();
        """.trimIndent()
    }
}
