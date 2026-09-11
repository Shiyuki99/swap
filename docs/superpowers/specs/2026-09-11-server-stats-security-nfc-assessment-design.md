# Server Stats, Security Review, and NFC Assessment Design

## Goal

Simplify the server's public usage statistics to two meaningful session metrics, assess the server's security posture, and determine how much of `flutter_nfc_hce` can safely be adopted into the app. Work stays on the existing `main` branch, is committed locally, and is not pushed.

## Scope

### Implemented server behavior

The stats system will persist and publicly expose only these counters:

- successful `POST /api/session` requests that create a session;
- successful, authorized session reads made through either `GET /view/:sessionId` or `GET /api/session/:sessionId`.

The two GET routes remain public and keep their existing response formats. The browser route renders HTML, while the API route returns JSON for the mobile app's HTTP fallback. They will share session lookup and token-authorization logic so their behavior cannot drift, and both will increment the same session-read counter.

Rejected requests do not increment either counter. The public `GET /api/stats` response and `GET /stats` page show only the two counters. App-open and unique-user tracking are removed, including the unused `POST /api/track/open` endpoint.

If an existing stats file uses the old schema, its `totalSessionsCreated` value seeds the new create counter. The new read counter starts at zero because the old server did not record reads. Invalid or empty stats files safely start both counters at zero.

The user's current uncommitted `server/stats.json` change is not staged or included in the commit.

### Security assessment

The assessment covers the server source, templates, routes, validation, session authorization, persistence, HTTP hardening, dependency audit, tracked sensitive data, and deployment-sensitive rate limiting. Findings are ranked by severity with concrete remediation advice. Security fixes are not included in this implementation unless they are necessary for the two-counter change.

### NFC package assessment

The assessment compares the installed `flutter_nfc_hce` 0.1.8 package, the app's integration and manifest, upstream maintenance and licensing, open upstream defects, and current Android HCE requirements. It reports:

- which code and concepts can be reused;
- which parts should be rewritten;
- current incompatibilities and reliability risks;
- a recommended ownership structure for a future in-repository implementation.

No NFC production code is changed in this task.

## Components and Data Flow

The server will retain its existing Express routes. A shared authorized-session lookup unit will validate the session ID and signature, return a consistent lookup result, and leave each route responsible only for its HTML or JSON representation.

After a successful session creation, the create counter increments and is persisted. After either successful authorized GET representation, the read counter increments and is persisted. Stats endpoints read a public projection containing exactly those two numeric values.

Stats persistence remains local JSON storage. Counter updates will be queued, and each save will write a complete snapshot to a sibling temporary file before renaming it over the stats file. This prevents overlapping writes from losing newer values and prevents partial JSON from replacing the last complete snapshot.

## Error Handling

- Missing, expired, or unauthorized sessions retain their existing HTTP status and response format.
- Failed or rejected operations do not affect statistics.
- Missing, empty, malformed, or legacy stats files do not prevent server startup.
- Persistence errors are logged without failing the user-facing session request.

## Testing and Verification

Tests are written before production changes and must first fail for the expected missing behavior. Automated coverage will verify:

- successful creation increments only the create counter;
- rejected creation does not increment it;
- successful HTML and JSON reads share one read counter;
- missing or unauthorized reads do not increment it;
- public JSON stats contain exactly two counters;
- legacy, empty, and malformed stats input initializes safely;
- the stats page renders only the two intended metrics.

Verification includes the complete server test suite, a fresh production dependency audit, syntax or lint checks available in the repository, and inspection of the staged diff before the local implementation commit.

## Deliverables

- tested server stats and shared GET-session logic;
- updated server documentation where endpoint behavior is described;
- prioritized server security report;
- NFC package copyability and modernization report;
- local commits only, with no push and no inclusion of the user's `server/stats.json` change.
