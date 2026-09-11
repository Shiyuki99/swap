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

test('uses zero counters for missing, empty, malformed, null, or invalid input', () => {
  const { StatsStore } = require('../stats-store');

  for (const contents of [null, '', '{not json', 'null', '[]']) {
    const filePath = statsPath();
    if (contents !== null) fs.writeFileSync(filePath, contents);
    const store = new StatsStore(filePath, { logger: { error() {} } });
    assert.deepEqual(store.snapshot(), { postApiSession: 0, getSession: 0 });
  }
});

test('replaces invalid counter values with zero', () => {
  const filePath = statsPath();
  fs.writeFileSync(filePath, JSON.stringify({
    postApiSession: -1,
    getSession: Number.MAX_SAFE_INTEGER + 1,
  }));

  const { StatsStore } = require('../stats-store');
  const store = new StatsStore(filePath, { logger: { error() {} } });

  assert.deepEqual(store.snapshot(), { postApiSession: 0, getSession: 0 });
});

test('returns a defensive two-counter snapshot', () => {
  const filePath = statsPath();
  const { StatsStore } = require('../stats-store');
  const store = new StatsStore(filePath, { logger: { error() {} } });

  const snapshot = store.snapshot();
  snapshot.postApiSession = 4;
  snapshot.unrelated = 10;

  assert.deepEqual(store.snapshot(), { postApiSession: 0, getSession: 0 });
});

test('rejects increments that would exceed the safe integer range', () => {
  const filePath = statsPath();
  fs.writeFileSync(filePath, JSON.stringify({
    postApiSession: Number.MAX_SAFE_INTEGER,
    getSession: 0,
  }));
  const { StatsStore } = require('../stats-store');
  const store = new StatsStore(filePath, { logger: { error() {} } });

  assert.throws(() => store.incrementPostApiSession(), RangeError);
  assert.deepEqual(store.snapshot(), {
    postApiSession: Number.MAX_SAFE_INTEGER,
    getSession: 0,
  });
});

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

test('serializes writes and recovers from a failed save', async () => {
  const filePath = statsPath();
  const writeFailure = new Error('injected write failure');
  const errors = [];
  let activeWrites = 0;
  let maximumActiveWrites = 0;
  let writeAttempts = 0;
  const fileSystem = {
    mkdir: fs.promises.mkdir,
    async writeFile(...args) {
      activeWrites += 1;
      maximumActiveWrites = Math.max(maximumActiveWrites, activeWrites);
      writeAttempts += 1;

      try {
        await new Promise((resolve) => setImmediate(resolve));
        if (writeAttempts === 1) throw writeFailure;
        await fs.promises.writeFile(...args);
      } finally {
        activeWrites -= 1;
      }
    },
    rename: fs.promises.rename,
  };
  const { StatsStore } = require('../stats-store');
  const store = new StatsStore(filePath, {
    fileSystem,
    logger: { error(...args) { errors.push(args); } },
  });

  store.incrementPostApiSession();
  store.incrementGetSession();
  await store.flush();

  assert.equal(writeAttempts, 2);
  assert.equal(maximumActiveWrites, 1);
  assert.deepEqual(errors, [[`Error saving ${filePath}:`, writeFailure]]);
  assert.deepEqual(JSON.parse(fs.readFileSync(filePath, 'utf8')), {
    postApiSession: 1,
    getSession: 1,
  });
  assert.deepEqual(store.snapshot(), { postApiSession: 1, getSession: 1 });
});
