const assert = require('node:assert/strict');
const { once } = require('node:events');
const fs = require('node:fs');
const http = require('node:http');
const os = require('node:os');
const path = require('node:path');
const { after, describe, test } = require('node:test');

const moduleTemporaryDirectory = fs.mkdtempSync(path.join(os.tmpdir(), 'swap-server-module-'));
const hadStatsFileOverride = Object.hasOwn(process.env, 'SWAP_STATS_FILE');
const originalStatsFileOverride = process.env.SWAP_STATS_FILE;
process.env.SWAP_STATS_FILE = path.join(moduleTemporaryDirectory, 'stats.json');

const { app, sessions, stopCleanup } = require('../server');
const { StatsStore } = require('../stats-store');

if (hadStatsFileOverride) {
  process.env.SWAP_STATS_FILE = originalStatsFileOverride;
} else {
  delete process.env.SWAP_STATS_FILE;
}

async function request(listener, method, route, body) {
  const address = listener.address();
  const payload = body === undefined ? undefined : JSON.stringify(body);

  return new Promise((resolve, reject) => {
    const req = http.request({
      host: '127.0.0.1',
      port: address.port,
      path: route,
      method,
      headers: payload === undefined ? {} : {
        'content-type': 'application/json',
        'content-length': Buffer.byteLength(payload),
      },
    }, (res) => {
      res.setEncoding('utf8');
      let responseBody = '';
      res.on('data', (chunk) => { responseBody += chunk; });
      res.on('end', () => resolve({
        statusCode: res.statusCode,
        body: responseBody,
      }));
    });

    req.on('error', reject);
    if (payload !== undefined) req.write(payload);
    req.end();
  });
}

async function close(listener) {
  await new Promise((resolve, reject) => {
    listener.close((error) => (error ? reject(error) : resolve()));
  });
}

async function withServer(run) {
  const temporaryDirectory = fs.mkdtempSync(path.join(os.tmpdir(), 'swap-server-http-'));
  const store = new StatsStore(path.join(temporaryDirectory, 'stats.json'), {
    logger: { error() {} },
  });
  const listener = app.listen(0, '127.0.0.1');
  app.locals.statsStore = store;
  sessions.clear();

  try {
    await once(listener, 'listening');
    await run({ listener, store });
  } finally {
    await store.flush();
    await close(listener);
    sessions.clear();
    fs.rmSync(temporaryDirectory, { recursive: true, force: true });
  }
}

after(() => {
  stopCleanup();
  fs.rmSync(moduleTemporaryDirectory, { recursive: true, force: true });
});

describe('session-only HTTP statistics', { concurrency: 1 }, () => {
  test('counts only successful POST /api/session requests', async () => {
    await withServer(async ({ listener, store }) => {
      const invalidResponse = await request(listener, 'POST', '/api/session', {});

      assert.equal(invalidResponse.statusCode, 400);
      assert.deepEqual(store.snapshot(), { postApiSession: 0, getSession: 0 });

      const validResponse = await request(listener, 'POST', '/api/session', {
        sessionId: 'created-session',
        token: 'created-token',
        profile: {
          id: 'profile-id',
          name: 'Alice',
          socialLinks: { github: 'alice' },
        },
      });

      assert.equal(validResponse.statusCode, 201);
      assert.deepEqual(store.snapshot(), { postApiSession: 1, getSession: 0 });
    });
  });

  test('aggregates only successful authorized HTML and JSON session reads', async () => {
    await withServer(async ({ listener, store }) => {
      sessions.set('seeded-session', {
        token: 'correct-token',
        profile: {
          id: 'seeded-profile',
          name: 'Bob',
          socialLinks: { github: 'bob' },
        },
        createdAt: Date.now(),
      });

      const forbiddenHtml = await request(
        listener,
        'GET',
        '/view/seeded-session?sig=wrong-token',
      );
      const missingJson = await request(
        listener,
        'GET',
        '/api/session/missing-session?sig=correct-token',
      );

      assert.equal(forbiddenHtml.statusCode, 403);
      assert.equal(missingJson.statusCode, 404);
      assert.deepEqual(store.snapshot(), { postApiSession: 0, getSession: 0 });

      const htmlResponse = await request(
        listener,
        'GET',
        '/view/seeded-session?sig=correct-token',
      );
      const jsonResponse = await request(
        listener,
        'GET',
        '/api/session/seeded-session?sig=correct-token',
      );

      assert.equal(htmlResponse.statusCode, 200);
      assert.equal(jsonResponse.statusCode, 200);
      assert.deepEqual(store.snapshot(), { postApiSession: 0, getSession: 2 });
    });
  });

  test('publishes exactly the two session counters as JSON', async () => {
    await withServer(async ({ listener, store }) => {
      store.incrementPostApiSession();
      store.incrementGetSession();

      const response = await request(listener, 'GET', '/api/stats');

      assert.equal(response.statusCode, 200);
      assert.deepEqual(JSON.parse(response.body), {
        postApiSession: 1,
        getSession: 1,
      });
    });
  });

  test('renders exactly the two session counter labels on the public stats page', async () => {
    await withServer(async ({ listener }) => {
      const response = await request(listener, 'GET', '/stats');

      assert.equal(response.statusCode, 200);
      assert.match(response.body, /POST \/api\/session/);
      assert.match(response.body, /GET session/);
      assert.doesNotMatch(response.body, /App Opens/i);
      assert.doesNotMatch(response.body, /Unique Users/i);
    });
  });

  test('does not expose the legacy app-open tracking endpoint', async () => {
    await withServer(async ({ listener }) => {
      const response = await request(listener, 'POST', '/api/track/open', {
        userId: 'legacy-user',
      });

      assert.equal(response.statusCode, 404);
    });
  });
});
