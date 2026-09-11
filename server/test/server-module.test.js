const assert = require('node:assert/strict');
const { after, test } = require('node:test');
const serverModule = require('../server');

after(() => serverModule.stopCleanup?.());

test('exports the Express app without requiring the production listener', () => {
  assert.equal(typeof serverModule.app, 'function');
  assert.equal(typeof serverModule.startServer, 'function');
  assert.equal(typeof serverModule.stopCleanup, 'function');
});
