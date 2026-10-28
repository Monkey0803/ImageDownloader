#!/usr/bin/env node
const { spawnSync } = require('node:child_process');
const path = require('node:path');

const helper = path.join(__dirname, 'lib/make-library-fixtures.py');
const run = spawnSync('python3', [helper], { stdio: 'inherit' });
if (run.error) {
  process.stderr.write('Python 3 with Pillow is required: ' + run.error.message + '\n');
  process.exit(1);
}
process.exit(run.status ?? 1);
