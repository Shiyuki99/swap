# Server Security Review — 2026-09-11

## Scope and result

Reviewed the Express server, EJS templates, public files, session protocol, statistics persistence, tracked sensitive-data patterns, and the production dependency tree. The source review is point-in-time only; reverse-proxy, TLS, firewall, process-manager, and server access-log configuration were not present in this repository.

`npm audit --omit=dev` was run against the locked production tree. It reports six affected packages: four high, one moderate, one low, and no critical findings. An audit finding indicates that a vulnerable package is installed; it does not by itself prove the application exposes every vulnerable code path.

## Findings

### High — update the rate-limiting dependency immediately

`express-rate-limit` 8.2.1 is directly installed and is affected by an IPv4-mapped IPv6 rate-limit bypass. Its `ip-address` 10.0.1 dependency also has a trust-boundary/SSRF advisory. This is particularly relevant because the service uses the package to protect session creation and reads in `server/server.js`.

- Advisory: [GHSA-46wh-pxpv-q5gq](https://github.com/advisories/GHSA-46wh-pxpv-q5gq)
- Advisory: [GHSA-mwp4-54f8-5fhr](https://github.com/advisories/GHSA-mwp4-54f8-5fhr)
- Fix: update `express-rate-limit`, regenerate the lockfile, then test limiting with the real IPv4/IPv6 and reverse-proxy topology.

### High — profile-link validation allows unsafe URL schemes

`isValidUrlForPlatform` in `server/server.js` accepts a link when it merely contains an expected hostname substring. A value such as `javascript:...instagram.com/...` can pass validation. The session template then copies the supplied link into an anchor `href` in browser JavaScript (`server/views/session.ejs`), creating a stored script-URL/open-link risk.

Fix: parse input using `new URL`, require `https:`, compare the normalized hostname against a per-platform allowlist, and reject credentials, nonstandard ports, and all non-web schemes. Add regression tests for `javascript:`, `data:`, hostname lookalikes, and valid official hosts.

### High dependency advisories — update the Express tree in a dedicated change

The locked runtime tree also contains:

- `path-to-regexp` 8.3.0: route-pattern DoS advisories ([GHSA-j3q9-mxjg-w52f](https://github.com/advisories/GHSA-j3q9-mxjg-w52f), [GHSA-27v5-c462-wpq7](https://github.com/advisories/GHSA-27v5-c462-wpq7)); it is used by Express's router. The current route patterns are simple, but the vulnerable version should still be upgraded.
- `brace-expansion` 2.0.2: several expansion DoS advisories. Its current path is `ejs -> jake -> filelist -> minimatch -> brace-expansion`, so it is less directly exposed to HTTP input but remains a production dependency.
- `qs` 6.15.0: three moderate DoS advisories, installed through Express/body-parser. Current code uses the JSON parser rather than explicitly stringifying attacker data, but the locked package is affected.
- `body-parser` 2.2.2: a low DoS advisory for invalid size-limit configuration. The current `express.json({ limit: '2kb' })` value is valid, which limits practical exposure, but the package should move to a fixed version with the rest of the tree.

All have fixes available according to the audit. Treat the update as a separate, tested dependency-security commit rather than using an unreviewed force-fix.

### Medium — security headers and CSP are absent

The server does not set a Content-Security-Policy, `X-Content-Type-Options`, `Referrer-Policy`, or comparable headers. The inline JavaScript and style blocks mean a strict CSP needs deliberate work rather than an arbitrary middleware default.

Fix: move inline code to static files or use nonces, then introduce Helmet (or equivalent explicit headers). Start with `Referrer-Policy: no-referrer`, a restrictive `frame-ancestors`, and `nosniff` after compatibility testing.

### Medium — rate-limit correctness depends on undeclared proxy topology

The application has no `trust proxy` configuration or deployment documentation. Behind a reverse proxy, leaving it unset can collapse many users to one address; trusting too broadly can let clients spoof identity headers.

Fix: document the deployed proxy chain and set the exact trusted hop count or addresses. Exercise the limit with production-like `X-Forwarded-For` and IPv6 traffic after the dependency upgrade.

### Medium — session identifiers and signatures are not type/format constrained

`POST /api/session` checks only truthiness before storing `sessionId` and `token`. The app generates eight-character, lowercase alphanumeric values, but the server accepts arbitrary JSON types and lengths. The 2 KiB body limit and session cap reduce impact, yet strict validation is needed at the trust boundary.

Fix: require bounded strings matching the application protocol, reject non-strings before map access, and consider increasing the signature entropy in a backward-compatible protocol revision.

### Low — secrets and personal data can reach logs and URLs

Creation logs include session IDs and profile names. The signature is in a query string by protocol design, so it can reach reverse-proxy access logs, browser history, screenshots, and copied links. The five-minute TTL and HTTPS reduce but do not eliminate exposure.

Fix: stop logging profile names, redact `sig` in infrastructure logs, set a no-referrer policy, and consider a fragment- or post-based authorization design in a future protocol version.

### Low — static dotfile serving is broader than necessary

`express.static` permits dotfiles to support `/.well-known/assetlinks.json`. This exposes any future dotfile placed under `server/public`.

Fix: deny dotfiles by default and explicitly serve the required asset-links file.

### Resolved in this change — personal statistics are removed

The prior statistics schema stored user names and app-open counts. The new `StatsStore` persists and exposes only aggregate successful `POST /api/session` and authorized GET-session counters. Legacy session totals migrate, while user names and app-open data do not.

## Remediation order

1. Update the dependency tree and validate rate limiting in the actual proxy/IPv6 deployment.
2. Replace substring link validation with parsed HTTPS hostname allowlists and add exploit-regression tests.
3. Add strict session input validation and standard security headers.
4. Reduce logs and query-token exposure, then narrow static dotfile access.

This review intentionally does not apply the unrelated remediation changes above.
