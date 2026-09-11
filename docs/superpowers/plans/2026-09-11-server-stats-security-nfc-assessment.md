# Server Stats, Security Review, and NFC Assessment Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace personal usage analytics with two public session counters, unify authorization for both session-read representations, and deliver evidence-backed server security and NFC ownership reports.

**Architecture:** A focused `StatsStore` owns legacy migration, in-memory counters, queued atomic JSON persistence, and the two-field public snapshot. Express continues serving HTML and JSON from separate routes, but both routes use one authorization function and one successful-read counter. Security and NFC work remain read-only assessments documented separately from production changes.

**Tech Stack:** Node.js 25 built-in test runner and `fetch`, Express 5/EJS, JSON-file persistence, Flutter/Dart and Android Kotlin source inspection, npm audit.

**Execution constraint:** The user explicitly requested work on the repository's current primary branch without a worktree. In this clone that branch is named `main`; nothing will be pushed.

---

## File Map

- Create `server/stats-store.js`: own the two-counter schema, legacy loading, increments, and queued atomic persistence.
- Create `server/test/stats-store.test.js`: unit-test migration and persistence independently of Express.
- Create `server/test/server-module.test.js`: prove the server is importable for endpoint tests without binding the production port.
- Create `server/test/server.test.js`: exercise the public endpoints against a real ephemeral HTTP listener.
- Modify `server/server.js`: consume `StatsStore`, share session authorization, remove personal analytics, and expose a testable app lifecycle.
- Modify `server/views/stats.ejs`: render only the two public route counters.
- Modify `server/package.json`: add the built-in Node test command without adding test libraries.
- Modify `README.md`: document both GET representations and the two-counter stats contract.
- Create `docs/security/2026-09-11-server-security-review.md`: record prioritized findings and remediation advice.
- Create `docs/nfc/2026-09-11-flutter-nfc-hce-assessment.md`: record legal reuse, technical reuse, rewrite boundaries, and modernization advice.
- Do not modify, stage, or commit `server/stats.json`; it contains a pre-existing user change.

### Task 1: Establish the Server Baseline

**Files:**
- Inspect: `server/package.json`
- Inspect: `server/package-lock.json`
- Inspect: `server/server.js`

- [ ] **Step 1: Install exactly the locked dependencies**

Run: `cd server && npm ci`

Expected: exit 0 and dependencies installed under ignored `server/node_modules/`, without changing `package-lock.json`.

- [ ] **Step 2: Verify the current server parses**

Run: `cd server && node --check server.js`

Expected: exit 0 with no output.

- [ ] **Step 3: Capture the dependency-security baseline**

Run: `cd server && npm audit --omit=dev --json`

Expected: exit 1 with the already observed six findings: four high, one moderate, one low, and no critical findings. Save the package names and advisory URLs in notes for Task 5; do not run `npm audit fix` because remediation is outside the approved scope.

### Task 2: Build the Two-Counter Stats Store

**Files:**
- Create: `server/test/stats-store.test.js`
- Create: `server/stats-store.js`

- [ ] **Step 1: Write failing loading and migration tests**

Create `server/test/stats-store.test.js` with isolated temporary directories:

```js
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { afterEach, test } = require('node:test');

const temporaryDirectories = [];

function statsPath() {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'swap-stats-'));
  temporaryDirectories.push(directory);
  return path.join(directory, 'stats.json');
}

afterEach(() => {
  while (temporaryDirectories.length > 0) {
    fs.rmSync(temporaryDirectories.pop(), { recursive: true, force: true });
  }
});

test('loads the old session total and initializes the new read total', () => {
  const filePath = statsPath();
  fs.writeFileSync(filePath, JSON.stringify({
    totalSessionsCreated: 20,
    totalAppOpens: 9,
    uniqueUsers: { alice: true },
  }));

  const { StatsStore } = require('../stats-store');
  const store = new StatsStore(filePath, { logger: { error() {} } });

  assert.deepEqual(store.snapshot(), { postApiSession: 20, getSession: 0 });
});

test('uses zero counters for missing, empty, or malformed input', () => {
  const { StatsStore } = require('../stats-store');

  for (const contents of [null, '', '{not json']) {
    const filePath = statsPath();
    if (contents !== null) fs.writeFileSync(filePath, contents);
    const store = new StatsStore(filePath, { logger: { error() {} } });
    assert.deepEqual(store.snapshot(), { postApiSession: 0, getSession: 0 });
  }
});
```

- [ ] **Step 2: Run the tests and verify the RED state**

Run: `cd server && node --test test/stats-store.test.js`

Expected: FAIL with `Cannot find module '../stats-store'`.

- [ ] **Step 3: Implement the minimal loading behavior**

Create `server/stats-store.js`:

```js
const fs = require('node:fs');
const path = require('node:path');

const EMPTY_STATS = Object.freeze({ postApiSession: 0, getSession: 0 });

function asCounter(value) {
  return Number.isSafeInteger(value) && value >= 0 ? value : 0;
}

function loadStats(filePath, { readFileSync = fs.readFileSync, logger = console } = {}) {
  try {
    const stored = JSON.parse(readFileSync(filePath, 'utf8'));
    return {
      postApiSession: asCounter(stored.postApiSession ?? stored.totalSessionsCreated),
      getSession: asCounter(stored.getSession),
    };
  } catch (error) {
    if (error.code !== 'ENOENT') logger.error(`Error loading ${filePath}:`, error);
    return { ...EMPTY_STATS };
  }
}

class StatsStore {
  constructor(filePath, { logger = console } = {}) {
    this.filePath = filePath;
    this.logger = logger;
    this.stats = loadStats(filePath, { logger });
  }

  snapshot() {
    return { ...this.stats };
  }
}

module.exports = { StatsStore, loadStats };
```

- [ ] **Step 4: Add a failing persistence test**

Append to `server/test/stats-store.test.js`:

```js
test('serializes increments and atomically persists only the public schema', async () => {
  const filePath = statsPath();
  const { StatsStore } = require('../stats-store');
  const store = new StatsStore(filePath, { logger: { error() {} } });

  store.incrementPostApiSession();
  store.incrementGetSession();
  store.incrementGetSession();
  await store.flush();

  assert.deepEqual(JSON.parse(fs.readFileSync(filePath, 'utf8')), {
    postApiSession: 1,
    getSession: 2,
  });
  assert.equal(fs.existsSync(`${filePath}.${process.pid}.tmp`), false);
});
```

- [ ] **Step 5: Run the persistence test and verify RED**

Run: `cd server && node --test test/stats-store.test.js`

Expected: the loading tests pass and the persistence test fails because `incrementPostApiSession` is not defined.

- [ ] **Step 6: Implement increments and queued atomic persistence**

Extend the `StatsStore` constructor and class with:

```js
constructor(filePath, { fileSystem = fs.promises, logger = console } = {}) {
  this.filePath = filePath;
  this.temporaryPath = `${filePath}.${process.pid}.tmp`;
  this.fileSystem = fileSystem;
  this.logger = logger;
  this.stats = loadStats(filePath, { logger });
  this.pendingWrite = Promise.resolve();
}

incrementPostApiSession() {
  this.stats.postApiSession += 1;
  this.queueSave();
}

incrementGetSession() {
  this.stats.getSession += 1;
  this.queueSave();
}

queueSave() {
  const snapshot = `${JSON.stringify(this.stats, null, 2)}\n`;
  this.pendingWrite = this.pendingWrite
    .then(async () => {
      await this.fileSystem.mkdir(path.dirname(this.filePath), { recursive: true });
      await this.fileSystem.writeFile(this.temporaryPath, snapshot, 'utf8');
      await this.fileSystem.rename(this.temporaryPath, this.filePath);
    })
    .catch((error) => this.logger.error(`Error saving ${this.filePath}:`, error));
}

async flush() {
  await this.pendingWrite;
}
```

- [ ] **Step 7: Run the stats-store tests and verify GREEN**

Run: `cd server && node --test test/stats-store.test.js`

Expected: three passing tests and zero failures.

- [ ] **Step 8: Commit the isolated stats store**

Run:

```bash
git add server/stats-store.js server/test/stats-store.test.js
git diff --cached --check
git commit -m "feat(server): add session stats store"
```

Expected: only the two listed files are committed; `server/stats.json` stays unstaged.

### Task 3: Make the Express Server Testable

**Files:**
- Create: `server/test/server-module.test.js`
- Modify: `server/server.js:1-57,484-495`

- [ ] **Step 1: Write the failing module-lifecycle test**

Create `server/test/server-module.test.js`:

```js
const assert = require('node:assert/strict');
const { after, test } = require('node:test');

const serverModule = require('../server');

after(() => serverModule.stopCleanup?.());

test('exports the Express app without requiring the production listener', () => {
  assert.equal(typeof serverModule.app, 'function');
  assert.equal(typeof serverModule.startServer, 'function');
  assert.equal(typeof serverModule.stopCleanup, 'function');
});
```

- [ ] **Step 2: Run the lifecycle test and verify RED**

Run: `cd server && timeout 5 node --test --test-force-exit test/server-module.test.js`

Expected: FAIL because the current module exports none of `app`, `startServer`, or `stopCleanup`. The forced exit prevents the current production listener from keeping the failed test alive.

- [ ] **Step 3: Add an import-safe lifecycle and connect StatsStore**

In `server/server.js`, import `StatsStore`, retain the Express app and sessions map, replace the old analytics block with an app-local store, retain a cleanup handle, and guard production startup:

```js
const { StatsStore } = require('./stats-store');

const statsFile = process.env.SWAP_STATS_FILE || path.join(__dirname, 'stats.json');
app.locals.statsStore = new StatsStore(statsFile);

const cleanupTimer = setInterval(() => {
  const now = Date.now();
  for (const [id, session] of sessions) {
    if (now - session.createdAt > SESSION_TTL_MS) sessions.delete(id);
  }
}, 60 * 1000);
cleanupTimer.unref();

function stopCleanup() {
  clearInterval(cleanupTimer);
}

function startServer(port = PORT) {
  return app.listen(port, '0.0.0.0', () => {
    console.log(`SWAP Web Server running on port ${port}`);
  });
}

if (require.main === module) startServer();

module.exports = { app, sessions, startServer, stopCleanup };
```

Remove the original unassigned cleanup interval, the `fs` import, `appStats`, legacy loading, `saveStats`, and the unconditional `app.listen` block. Do not yet change route behavior beyond replacing the store initialization; Task 4 supplies the behavior tests first.

- [ ] **Step 4: Run the lifecycle and stats-store tests**

Run: `cd server && node --test test/server-module.test.js test/stats-store.test.js`

Expected: four passing tests and zero failures.

- [ ] **Step 5: Commit the testability refactor**

Run:

```bash
git add server/server.js server/test/server-module.test.js
git diff --cached --check
git commit -m "refactor(server): expose testable app lifecycle"
```

Expected: only the two listed files are committed.

### Task 4: Implement and Expose Exactly Two Session Counters

**Files:**
- Create: `server/test/server.test.js`
- Modify: `server/server.js:211-426`
- Modify: `server/views/stats.ejs:94-124`
- Modify: `server/package.json:6-10`
- Modify: `README.md:108-121`

- [ ] **Step 1: Write failing HTTP behavior tests**

Create `server/test/server.test.js`:

```js
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { after, afterEach, before, beforeEach, describe, test } = require('node:test');
const { StatsStore } = require('../stats-store');
const { app, sessions, stopCleanup } = require('../server');

let listener;
let baseUrl;
let testDirectory;

const profile = {
  id: 'profile-1',
  name: 'Alice',
  profileName: 'Personal',
  socialLinks: { github: 'alice' },
};

async function request(pathname, options) {
  return fetch(`${baseUrl}${pathname}`, options);
}

before(async () => {
  listener = app.listen(0, '127.0.0.1');
  await new Promise((resolve) => listener.once('listening', resolve));
  baseUrl = `http://127.0.0.1:${listener.address().port}`;
});

beforeEach(() => {
  sessions.clear();
  testDirectory = fs.mkdtempSync(path.join(os.tmpdir(), 'swap-server-'));
  app.locals.statsStore = new StatsStore(path.join(testDirectory, 'stats.json'), {
    logger: { error() {} },
  });
});

afterEach(async () => {
  await app.locals.statsStore.flush();
  fs.rmSync(testDirectory, { recursive: true, force: true });
});

after(async () => {
  await new Promise((resolve, reject) => listener.close((error) => error ? reject(error) : resolve()));
  stopCleanup();
});

describe('public session statistics', { concurrency: 1 }, () => {
  test('counts only successful POST /api/session creations', async () => {
    const invalid = await request('/api/session', {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({}),
    });
    assert.equal(invalid.status, 400);

    const created = await request('/api/session', {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ sessionId: 'session1', token: 'secret1', profile }),
    });
    assert.equal(created.status, 201);
    assert.deepEqual(app.locals.statsStore.snapshot(), {
      postApiSession: 1,
      getSession: 0,
    });
  });

  test('combines successful HTML and JSON session reads under one GET counter', async () => {
    sessions.set('session1', { token: 'secret1', profile, createdAt: Date.now() });

    assert.equal((await request('/view/session1?sig=wrong')).status, 403);
    assert.equal((await request('/api/session/missing?sig=secret1')).status, 404);
    assert.equal(app.locals.statsStore.snapshot().getSession, 0);

    assert.equal((await request('/view/session1?sig=secret1')).status, 200);
    assert.equal((await request('/api/session/session1?sig=secret1')).status, 200);
    assert.equal(app.locals.statsStore.snapshot().getSession, 2);
  });

  test('publishes exactly the two counters as JSON', async () => {
    app.locals.statsStore.incrementPostApiSession();
    app.locals.statsStore.incrementGetSession();

    const response = await request('/api/stats');
    assert.equal(response.status, 200);
    assert.deepEqual(await response.json(), { postApiSession: 1, getSession: 1 });
  });

  test('renders only the two route metrics on the public stats page', async () => {
    const response = await request('/stats');
    const html = await response.text();

    assert.equal(response.status, 200);
    assert.match(html, /POST \/api\/session/);
    assert.match(html, /GET session/);
    assert.doesNotMatch(html, /App Opens|Unique Users/);
  });

  test('does not expose the removed app-open tracker', async () => {
    assert.equal((await request('/api/track/open', { method: 'POST' })).status, 404);
  });
});
```

The cleanup target is always a fresh child of `os.tmpdir()` created by the immediately preceding `beforeEach` hook.

- [ ] **Step 2: Run the HTTP tests and verify RED**

Run: `cd server && node --test test/server.test.js`

Expected failures: the JSON stats response still has three old properties; GET reads do not increment a shared counter; the UI still shows app opens and unique users; `/api/track/open` still exists.

- [ ] **Step 3: Add shared authorization and successful-read tracking**

In `server/server.js`, add one lookup function and format-specific middleware wrappers:

```js
function getAuthorizedSession(sessionId, signature) {
  const session = sessions.get(sessionId);
  if (!session) return { status: 404, error: 'not_found' };
  if (session.token !== signature) return { status: 403, error: 'forbidden' };
  return { status: 200, session };
}

function authorizeSession(renderError) {
  return (req, res, next) => {
    const access = getAuthorizedSession(req.params.sessionId, req.query.sig);
    if (!access.session) return renderError(res, access);

    req.swapSession = access.session;
    req.app.locals.statsStore.incrementGetSession();
    return next();
  };
}

const authorizeHtmlSession = authorizeSession((res, access) => {
  if (access.error === 'not_found') {
    return res.status(404).render('error', {
      title: 'Session Not Found',
      message: 'This swap session does not exist or has expired.',
    });
  }
  return res.status(403).render('error', {
    title: 'Unauthorized',
    message: 'Invalid or missing signature token.',
  });
});

const authorizeJsonSession = authorizeSession((res, access) => res
  .status(access.status)
  .json({ error: access.error === 'not_found' ? 'Session not found' : 'Invalid token' }));
```

Apply `authorizeHtmlSession` to `GET /view/:sessionId` and `authorizeJsonSession` to `GET /api/session/:sessionId`, then replace each route's duplicated lookup/token block with `const session = req.swapSession`. Keep their existing HTML and JSON bodies unchanged.

- [ ] **Step 4: Replace route analytics with the two-counter projection**

After successfully adding a new session in `POST /api/session`, call:

```js
req.app.locals.statsStore.incrementPostApiSession();
```

Delete the `POST /api/track/open` route. Replace both stats projections with:

```js
app.get('/api/stats', viewLimiter, (req, res) => {
  res.json(req.app.locals.statsStore.snapshot());
});

app.get('/stats', viewLimiter, (req, res) => {
  res.render('stats', { stats: req.app.locals.statsStore.snapshot() });
});
```

- [ ] **Step 5: Render only two stat cards**

Replace the cards in `server/views/stats.ejs` with:

```ejs
<div class="stats-grid">
  <div class="stat-card">
    <div class="stat-value"><%= stats.postApiSession %></div>
    <div class="stat-label">POST /api/session</div>
  </div>
  <div class="stat-card">
    <div class="stat-value"><%= stats.getSession %></div>
    <div class="stat-label">GET session</div>
  </div>
</div>
```

Keep `GET session` as the aggregate label because the HTML and JSON representations intentionally contribute to the same counter.

- [ ] **Step 6: Add the test script and update endpoint documentation**

Set the `server/package.json` scripts to:

```json
"scripts": {
  "start": "node server.js",
  "dev": "node server.js",
  "test": "node --test test/*.test.js"
}
```

In `README.md`, add `GET /api/session/:sessionId` as the mobile JSON fallback, retain `GET /view/:sessionId` as the browser representation, document that `/api/stats` and `/stats` are public, and state that both expose only successful create and successful authorized read counts.

- [ ] **Step 7: Run all server tests and verify GREEN**

Run: `cd server && npm test`

Expected: all stats-store, lifecycle, and HTTP tests pass with zero failures.

- [ ] **Step 8: Commit the server behavior**

Run:

```bash
git add server/server.js server/views/stats.ejs server/package.json server/test/server.test.js README.md
git diff --cached --check
git commit -m "feat(server): publish session-only stats"
```

Expected: only the five listed paths are committed; `server/stats.json` stays unstaged.

### Task 5: Write the Server Security Review

**Files:**
- Create: `docs/security/2026-09-11-server-security-review.md`

- [ ] **Step 1: Document the assessment boundary and evidence**

State that the review covered `server/server.js`, all EJS templates, public static files, the lockfile, tracked-file secret patterns, and `npm audit --omit=dev`. Record the exact audit totals and distinguish installed/locked advisories from confirmed reachable application exploits.

- [ ] **Step 2: Record prioritized findings**

Include these findings with file/line evidence and remediation:

1. High: the locked `express-rate-limit` 8.2.1 and transitive `ip-address` versions have rate-limit/trust-boundary advisories; update the lockfile in a dedicated security change and retest proxy behavior.
2. High: `_link` validation uses substring matching and permits non-HTTP schemes containing an expected hostname; the browser copies that value into an anchor `href`. Parse with `new URL`, require HTTPS, and compare normalized hostnames against an allowlist.
3. High dependency exposure: `path-to-regexp`, `brace-expansion`, `qs`, and `body-parser` have audit findings. Note which are request-path dependencies and which need reachability confirmation, then update Express and regenerate the lockfile in a separate remediation.
4. Medium: no explicit CSP or standard security headers. Add Helmet or equivalent headers after moving inline scripts/styles to nonce-able or static assets.
5. Medium deployment risk: rate limiting depends on correct reverse-proxy configuration, but `trust proxy` and the deployment topology are undocumented. Configure one trusted proxy hop only if that matches production.
6. Medium: `sessionId` and `token` accept arbitrary JSON types and lengths. Require bounded ASCII strings matching the app-generated format.
7. Low/privacy: session IDs and profile names are logged; query-string secrets can appear in infrastructure access logs. Remove profile names from logs, redact `sig`, set `Referrer-Policy: no-referrer`, and consider moving authorization away from query strings in a versioned protocol.
8. Low: `express.static(..., { dotfiles: 'allow' })` is broader than needed. Deny dotfiles globally and explicitly serve only `/.well-known/assetlinks.json`.
9. Resolved by this task: persisted unique names and app-open analytics are removed from the stats schema and public response.

- [ ] **Step 3: Add a remediation order**

Recommend: first update dependencies and fix URL validation; second add request validation and security headers; third validate proxy/rate-limit behavior in deployment; fourth reduce logging and query-token exposure. Explicitly state that this task reports but does not apply these unrelated fixes.

### Task 6: Write the NFC Copyability and Modernization Assessment

**Files:**
- Create: `docs/nfc/2026-09-11-flutter-nfc-hce-assessment.md`

- [ ] **Step 1: Record source, maintenance, and license facts**

Document that `flutter_nfc_hce` 0.1.8 is MIT-licensed and therefore can be copied, modified, and redistributed if its copyright and license notice are retained. Note that pub.dev shows it as two years old and the upstream `master` branch's last commit is from September 2023, so the project should own future compatibility rather than rely on upstream releases.

- [ ] **Step 2: Record the current app/package mismatch**

Document that `app/lib/services/nfc_service.dart` claims a URI-record patch is active, while the installed `KHostApduService.kt` still creates `RTD_TEXT` for `text/plain`; the cache-edit workflow is not reproducible and can be erased by package restoration. State that the current app can therefore regress to non-clickable iPhone reads.

- [ ] **Step 3: Quantify what should be reused**

Use these estimates and boundaries:

- Legal reuse: 100% permitted under MIT with attribution.
- Conceptual protocol reuse: roughly 60-70% of the Type 4 Tag APDU constants, NDEF file layout, and read-chunk flow is a useful starting point.
- Direct production copy: roughly 35-45% after removing unsafe lifecycle, persistence, logging, and parsing code.
- Dart API reuse: preserve the small start/stop/support surface, but implement it as an app-owned adapter; do not copy the package's three-layer platform-interface boilerplate unless the code will become a standalone plugin.

- [ ] **Step 4: List required rewrites**

Cover each concrete defect:

- constructing service state by reading files through `this` before Android attaches the service context can throw the upstream issue #5 null-context failure;
- null intent assertions and short APDU slicing can crash the service;
- exact APDU equality and the shared `READ_CAPABILITY_CONTAINER_CHECK` flag are brittle across reader command variants;
- the 255-byte capability value and state-reset behavior need a standards-based decision, informed by upstream PR #3;
- URL NDEF must be a native `RTD_URI` record, not a cache patch over text records;
- `startNfcHce` currently reports success before proving service activation, while support and enabled state are conflated;
- persistence behavior contradicts cleanup behavior and unnecessarily keeps session URLs containing secrets;
- APDU and URL logging exposes the shared session token;
- Android 15 Observe Mode is not automatically required for this non-payment service, but foreground preference, AID conflicts, and screen-off behavior must be tested on API 35+ and major OEMs.

- [ ] **Step 5: Recommend the future owned implementation**

Recommend an in-repository Android implementation with:

- `SwapHostApduService.kt` for validated Type 4 Tag APDU processing only;
- `NdefUriEncoder.kt` as a pure, unit-tested URI record encoder;
- `NfcHceChannel.kt` for Flutter method-channel lifecycle and typed result codes;
- app-owned manifest/service metadata using the current `category="other"` AID;
- no persistent session URL by default;
- Kotlin unit tests for APDU selection, offsets, lengths, malformed commands, and URI bytes;
- device tests on Android 12 through current Android, Samsung/Pixel devices, Android-to-Android readers, and iPhone background URL detection.

Conclude that copying is viable and preferable to continued pub-cache patching, but this should be treated as a controlled rewrite around a reusable protocol core rather than a wholesale copy.

- [ ] **Step 6: Cite primary sources**

Link the package's MIT license/upstream repository, pub.dev release history, upstream issues #2 and #5, upstream PR #3, and Android's official HCE overview/API documentation. Clearly label any compatibility conclusions as inferences from those sources plus the inspected local code.

### Task 7: Final Verification and Report Commit

**Files:**
- Verify: all files listed above
- Preserve: `server/stats.json`

- [ ] **Step 1: Run the full server verification**

Run:

```bash
cd server
npm test
node --check server.js
node --check stats-store.js
```

Expected: all tests pass and both syntax checks exit 0.

- [ ] **Step 2: Re-run the dependency audit**

Run: `cd server && npm audit --omit=dev --json`

Expected: the command may exit 1 because fixes were intentionally out of scope. Confirm the output exactly matches the security report; revise the report if the live advisory set changed.

- [ ] **Step 3: Check repository hygiene and scope**

Run:

```bash
git diff --check
git status --short
git diff -- server/stats.json
git log --oneline -5
```

Expected: no whitespace errors; `server/stats.json` remains the user's only unstaged modification; no NFC production files changed; local commits are ahead of the remote and nothing was pushed.

- [ ] **Step 4: Commit the reports**

Run:

```bash
git add docs/security/2026-09-11-server-security-review.md docs/nfc/2026-09-11-flutter-nfc-hce-assessment.md
git diff --cached --check
git commit -m "docs: report server security and NFC findings"
```

Expected: only the two assessment documents are committed.

- [ ] **Step 5: Verify the final local state**

Run: `git status --short --branch && git log --oneline -5`

Expected: `main` is ahead of `main/main`; `server/stats.json` is still unstaged; implementation and report commits are present; no push occurred.
