# QuangTV Cloudflare public-content reader

This Worker is prepared, not deployed. No Cloudflare credentials, proxy account, fixed US egress IP, or personal cookie jar is embedded.

1. Protect a dedicated Worker custom domain with Cloudflare Access (your account only). Set `workers_dev` false; do not expose an unprotected alternate hostname.
2. Set `CF_ACCESS_TEAM`, `CF_ACCESS_AUD`, and an explicit `ALLOWED_HOSTS` list including required media/CDN domains. Exact hosts and `*.example.com` are supported. IP literals and private/local targets are rejected.
3. Use the official Wrangler CLI, authenticate to your account, add the protected custom-domain route, and deploy this directory. The Worker verifies the Access JWT signature, issuer, audience and expiry; forwarding an invented assertion header does not authorize access.
4. Open `https://YOUR_PROTECTED_HOST/proxy?url=ENCODED_PUBLIC_HTTPS_URL` in QuangTV. Cloudflare Access authenticates the owner before requests reach this Worker.

HTMLRewriter removes known advertising elements/domains and rewrites href/src/form actions/posters/srcset. CSS URLs and HLS playlist/key URLs are rewritten. MP4 and images stream without buffering the whole file; Range requests and 206 responses are retained. Public WebSocket upgrades are forwarded to allowlisted hosts. This is not a generic TCP/SOCKS or fixed-US-IP service.

The Worker intentionally does not forward account cookies, Authorization or Access assertions to upstream sites. POST/account operations and password fields are disabled. Rewriting unrelated authenticated websites onto one origin can destroy cookie/origin isolation. Use QuangTV's native authenticated HTTP/SOCKS proxy for Facebook/Telegram login; do not enter account credentials into proxied HTML.

JavaScript-created URLs, module imports, service workers, signed requests and site CSP/origin requirements cannot be made universally compatible by replacing href/src/action. The content policy blocks direct subresource escape, so some dynamic pages will fail rather than silently bypass the Worker. Script-driven top-level navigation can still leave this reader: a Worker cannot transparently become a universal browser proxy. QuangTV's native proxy remains the network transport for authenticated sites.

No deployment, live Cloudflare HTMLRewriter test or Facebook/Telegram session test has been performed by merely running the local unit tests. Before enabling on a real domain, test allowed/denied hosts, Access sign-in, one HTML page, CSS, a byte-range MP4 and nested HLS.
