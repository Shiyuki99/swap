const assert = require('node:assert/strict');
const childProcess = require('node:child_process');
const { once } = require('node:events');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { after, test } = require('node:test');

const temporaryDirectory = fs.mkdtempSync(path.join(os.tmpdir(), 'swap-server-module-'));
const statsFile = path.join(temporaryDirectory, 'stats.json');
const hadStatsFileOverride = Object.hasOwn(process.env, 'SWAP_STATS_FILE');
const originalStatsFileOverride = process.env.SWAP_STATS_FILE;
process.env.SWAP_STATS_FILE = statsFile;

const serverModule = require('../server');

after(() => {
  serverModule.stopCleanup?.();
  if (hadStatsFileOverride) {
    process.env.SWAP_STATS_FILE = originalStatsFileOverride;
  } else {
    delete process.env.SWAP_STATS_FILE;
  }
  fs.rmSync(temporaryDirectory, { recursive: true, force: true });
});

test('exports the Express app with a StatsStore configured from the environment', () => {
  assert.equal(typeof serverModule.app, 'function');
  assert.equal(typeof serverModule.startServer, 'function');
  assert.equal(typeof serverModule.stopCleanup, 'function');
  assert.equal(serverModule.app.locals.statsStore.filePath, statsFile);
});

test('startServer listens on an ephemeral port', async () => {
  const listener = serverModule.startServer(0);

  try {
    await once(listener, 'listening');
    const address = listener.address();

    assert.equal(typeof address, 'object');
    assert.ok(address);
    assert.equal(typeof address.port, 'number');
    assert.ok(address.port > 0);
  } finally {
    await new Promise((resolve, reject) => {
      listener.close((error) => (error ? reject(error) : resolve()));
    });
  }
});

test('importing the module exits without retaining a production listener', () => {
  const child = childProcess.spawnSync(process.execPath, ['-e', "require('./server')"], {
    cwd: path.join(__dirname, '..'),
    env: {
      ...process.env,
      SWAP_STATS_FILE: path.join(temporaryDirectory, 'child-stats.json'),
    },
    encoding: 'utf8',
    timeout: 5_000,
  });

  assert.equal(child.error, undefined);
  assert.equal(child.status, 0, child.stderr);
});
