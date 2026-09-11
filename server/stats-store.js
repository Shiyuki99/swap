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
  constructor(filePath, { fileSystem = fs.promises, logger = console } = {}) {
    this.filePath = filePath;
    this.temporaryPath = `${filePath}.${process.pid}.tmp`;
    this.fileSystem = fileSystem;
    this.logger = logger;
    this.stats = loadStats(filePath, { logger });
    this.pendingWrite = Promise.resolve();
  }

  incrementPostApiSession() {
    this.increment('postApiSession');
  }

  incrementGetSession() {
    this.increment('getSession');
  }

  increment(counter) {
    if (this.stats[counter] === Number.MAX_SAFE_INTEGER) {
      throw new RangeError(`${counter} cannot exceed Number.MAX_SAFE_INTEGER`);
    }

    this.stats[counter] += 1;
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

  snapshot() {
    return { ...this.stats };
  }
}

module.exports = { StatsStore, loadStats };
