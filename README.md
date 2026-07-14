## GTM Implementation

There are two ways to get this into your container. Option A is faster if
you're comfortable importing containers; Option B gives you full manual
control (useful if you want to merge into an existing workspace without an
import, or want to see exactly what's being created).

### Option A — Import the container file (recommended)

1. In GTM, go to **Admin > Import Container**.
2. Choose `gtm-site-speed-import.json`.
3. Select your target workspace.
4. Choose **Merge**, and pick **Rename conflicting tags/triggers/variables**
   if prompted (unlikely on a clean container).
5. Confirm the import.

This creates:
- 1 Custom HTML tag (`CHTML - Site Speed to DL`) firing on **All Pages**
- 1 Custom Event trigger (`Site Speed - Event Trigger`, listens for the
  `site_speed` event)
- 1 GA4 Event tag (`GA4 - Site Speed Event`) firing on that trigger
- 21 Data Layer Variables (one per metric, listed below)

**You still need to do one thing manually:** the GA4 event tag references
`{{GA4 - Measurement ID}}` and `{{GA4 - Basic Settings}}` variables which are
specific to your own GA4 setup and aren't included in the import. Open
`GA4 - Site Speed Event` after importing and point these at your existing
GA4 Configuration tag/variable (or hardcode your Measurement ID).

### Option B — Build it manually

**1. Create the Custom HTML tag**
- New Tag > **Custom HTML**
- Paste in the contents of `gtm-site-speed-custom-html.html`
- Trigger: **All Pages** (or Initialization, if you prefer it to fire before
  other tags)
- Tag firing priority / sequencing isn't required — the script just sets up
  listeners and pushes to the dataLayer at page teardown.

**2. Create the Custom Event trigger**
- New Trigger > **Custom Event**
- Event name: `site_speed`
- This fires whenever the script above pushes its `site_speed` event.

**3. Create 21 Data Layer Variables**

All are **Data Layer Variable**, version 2, "Set Default Value" left unchecked.
Name each one exactly as below (or update the GA4 tag's parameter mapping if
you use different names) and set the **Data Layer Variable Name** as shown:

| Variable name | Data Layer Variable Name |
|---|---|
| Site Speed - TTFB | `siteSpeedMeasurement.ttfb` |
| Site Speed - FCP | `siteSpeedMeasurement.fcp` |
| Site Speed - LCP | `siteSpeedMeasurement.lcp` |
| Site Speed - CLS | `siteSpeedMeasurement.cls` |
| Site Speed - INP | `siteSpeedMeasurement.inp` |
| Site Speed - Page Load | `siteSpeedMeasurement.load` |
| Site Speed - DCL | `siteSpeedMeasurement.dcl` |
| Site Speed - Redirect Time | `siteSpeedMeasurement.redirect_time` |
| Site Speed - DNS Time | `siteSpeedMeasurement.dns_time` |
| Site Speed - Connect Time | `siteSpeedMeasurement.connect_time` |
| Site Speed - Decoded Size | `siteSpeedMeasurement.decoded_size` |
| Site Speed - Transfer Size | `siteSpeedMeasurement.transfer_size` |
| Site Speed - Requests | `siteSpeedMeasurement.requests` |
| Site Speed - TAO Blocked | `siteSpeedMeasurement.tao_blocked` |
| Site Speed - Cache Hit Ratio | `siteSpeedMeasurement.cache_hit_ratio` |
| Site Speed - LCP Element | `siteSpeedMeasurement.lcp_element` |
| Site Speed - Connection Type | `siteSpeedMeasurement.connection_type` |
| Site Speed - RTT | `siteSpeedMeasurement.rtt` |
| Site Speed - Downlink | `siteSpeedMeasurement.downlink` |
| Site Speed - Nav Type | `siteSpeedMeasurement.nav_type` |
| Site Speed - Was Hidden | `siteSpeedMeasurement.was_hidden` |

**4. Create the GA4 Event tag**
- New Tag > **GA4 Event**
- Configuration: your existing GA4 Configuration tag/settings variable
- Event Name: `site_speed`
- Event Parameters: add one row per variable above, using the field names
  from the Data Dictionary as the parameter name (e.g. parameter `ttfb` →
  value `{{Site Speed - TTFB}}`, parameter `lcp_element` →
  value `{{Site Speed - LCP Element}}`, and so on for all 21).
- Trigger: **Site Speed - Event Trigger** (created in step 2)

**5. Preview and publish**
- Use GTM Preview mode, load a page, then close the tab or switch tabs to
  trigger `pagehide`/`visibilitychange` — you should see a `site_speed` event
  fire with the `siteSpeedMeasurement` object populated, followed by the GA4
  event tag firing.
- Check the event lands in GA4 DebugView before publishing.

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
