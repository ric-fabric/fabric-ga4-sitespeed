# Site Speed Measurement — Data Dictionary

Every field collected by the GTM tag and derived in the BigQuery pipeline.
All timings are milliseconds unless stated. "Good / Poor" thresholds are the
Google Core Web Vitals boundaries where they exist.

## Core timing metrics

**ttfb — Time to First Byte**
Time from navigation start until the first byte of the HTML response arrives.
Includes redirect, DNS, connection and server processing time (web-vitals
convention). High TTFB means everything downstream starts late. Good < 800ms,
poor > 1800ms. Diagnose the cause with the breakdown fields below.

**fcp — First Contentful Paint**
Time until the browser first renders any content (text, image, canvas). The
first moment the user sees the page is doing something. Good < 1800ms,
poor > 3000ms.

**lcp — Largest Contentful Paint** *(Core Web Vital)*
Time until the largest content element in the viewport finishes rendering —
the moment the page *feels* loaded. Final value captured at page teardown,
matching CrUX methodology. Good < 2500ms, poor > 4000ms.

**cls — Cumulative Layout Shift** *(Core Web Vital)*
Unitless score measuring how much the page layout jumps around. Calculated
using session windows (shifts less than 1s apart group together, windows cap
at 5s; the score is the worst window) — the same method Chrome uses. Shifts
caused by user interaction are excluded. Good < 0.1, poor > 0.25.

**inp — Interaction to Next Paint** *(Core Web Vital)*
Responsiveness: how long the page takes to visually respond to user input
(clicks, taps, key presses). Reports roughly the 98th-percentile-worst
interaction of the page visit, so one janky interaction among many fast ones
is still surfaced. Null if the user never interacted. Good < 200ms,
poor > 500ms.

**load — Page Load (domComplete)**
Time until the browser considers the page fully loaded, including deferred
resources. A large gap between LCP and load usually indicates heavy
third-party or below-the-fold payloads — the page feels ready long before it
technically finishes. Poor UX proxy on its own; read it alongside the paint
metrics.

**dcl — DOMContentLoaded**
Time until the HTML document is fully parsed and deferred scripts have run.
Relevant on sites where JavaScript frameworks gate interactivity on this
event.

## TTFB breakdown

**redirect_time**
Time spent following redirects before the final URL. Anything consistently
above 0 on landing pages means redirect chains (http→https→www→final) are
taxing every visit — a classic silent TTFB killer.

**dns_time**
Time resolving the domain name. Usually near 0 for repeat visitors (cached).
Consistently high values across visitors suggest slow DNS hosting.

**connect_time**
Time establishing the TCP connection and TLS handshake. Near 0 on reused
connections. High values point at server distance (no CDN) or TLS config.

## Page weight

**decoded_size** *(bytes)*
Total uncompressed size of all resources the browser could measure. What the
device actually had to process.

**transfer_size** *(bytes)*
Total bytes over the wire (compressed, and 0 for cache hits). What the
network actually carried. The gap between decoded and transfer indicates
compression effectiveness and cache usage.

**requests**
Total number of resources the page loaded. High counts (150+) usually mean
tag/third-party bloat.

**tao_blocked**
Number of cross-origin resources that report no size data because their
server doesn't send a `Timing-Allow-Origin` header. These resources are
invisible to the byte counts above, so decoded/transfer sizes are a floor,
not a census. Also works as a rough third-party bloat counter. If a client's
own CDN shows up here, adding `Timing-Allow-Origin: *` to it fixes the
blind spot.

**cache_hit_ratio** *(0–1)*
Share of *measurable* resources served from browser cache. Calculated only
over resources with visible size data (TAO-blocked resources excluded from
the denominator). High values on repeat visits are healthy; low values
everywhere suggest poor cache headers.

## Context dimensions

**lcp_element**
Which element was the LCP — `TAG#id` or `TAG:filename` (e.g. `IMG:hero.webp`,
`DIV:banner.svg` for background images/facades). Turns "LCP is slow" into
"this specific element is slow". Group by page template to find each
template's LCP driver.

**connection_type**
Chrome's effective connection classification: `slow-2g`, `2g`, `3g`, `4g`.
Important: this is a measured speed bucket, not the actual network technology
— "4g" is the top bucket and includes WiFi, fibre and 5G. Use it to isolate
genuinely slow connections (`3g` and below), not to classify networks.
Null on Safari and Firefox.

**rtt** *(ms)*
Estimated round-trip time of the connection, rounded to the nearest 25ms for
privacy. Meaningful at the high end (250ms+ = genuinely laggy connection).

**downlink** *(Mbps)*
Estimated bandwidth, capped at 10 by Chrome for privacy. Treat 10 as
"10 or better".

**nav_type**
How the page was reached: `navigate` (normal), `reload`, `back_forward`.
Reloads and back/forward navigations have unrepresentative (cache-warm)
timings — filter to `navigate` for headline analysis.

**was_hidden** *(boolean)*
True if the tab was backgrounded at any point during load. Browsers defer
rendering for background tabs, corrupting paint metrics. Exclude these
sessions from analysis (typically 5–10% of loads).

## Derived fields (BigQuery pipeline)

**landing_path / page_template**
The path of the first measured page of the session, and its template bucket
(Homepage / PLP / PDP / Checkout — customised per site). Template-level
grouping is where per-page analysis becomes actionable, since fixes ship at
template level.

**lcp_bucket / ttfb_bucket**
The metric floored into fixed-width buckets (250ms / 200ms), capped at
8000ms / 4000ms so the long tail collapses into a single overflow bucket.
The x-axis of the distribution-vs-conversion charts.

**converted** *(boolean)*
Whether the session contained a `purchase` event.

**revenue**
Total purchase revenue of the session.

**session_cr** *(views)*
Converting sessions ÷ measured sessions for the grouping. Session-scoped,
so it reconciles with GA4's session conversion rate, not user-scoped rates.

**p75 (views)**
75th percentile — the value 75% of sessions beat. The industry-standard
summary statistic for performance (used by CrUX and PageSpeed Insights)
because averages are distorted by the slow tail. "p75 LCP of 3.1s" means a
quarter of sessions waited longer than 3.1s.

## Collection notes

- One event per page load, reported at page teardown (tab hidden or
  pagehide) so LCP, CLS and INP are final values consistent with CrUX.
- Initial page loads only — SPA route changes are not measured.
- Sampling is configurable in the GTM tag (`SAMPLE_RATE`); all analysis is
  distribution-based, so sampling does not bias results.
- Sessions ending in a browser crash or OS tab kill are lost (low single
  digits, uniform across fast and slow sessions).
