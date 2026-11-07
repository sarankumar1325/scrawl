import { mkdtemp, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { expect, it } from 'vitest';
import { createConverter } from '../server/convert';

it('terminates a timed-out worker, rejects its pending requests, and starts a fresh one', async () => {
  const dir = await mkdtemp(join(tmpdir(), 'scrawl-worker-test-'));
  const worker = join(dir, 'worker.cjs');
  try {
    await writeFile(worker, `const { parentPort } = require('node:worker_threads'); parentPort.on('message', ({id, skeletons}) => { if (!skeletons[0].hang) parentPort.postMessage({id, ok:true, elements:skeletons}); });`);
    const convert = createConverter(worker, 500);
    const first = convert([{ hang: true }]);
    const second = convert([{ hang: true }]);
    const results = await Promise.allSettled([first, second]);
    expect(results.every(result => result.status === 'rejected' && /timed out/.test(String(result.reason)))).toBe(true);
    await expect(convert([{ id: 'recovered' }])).resolves.toEqual([{ id: 'recovered' }]);
  } finally {
    await rm(dir, { recursive: true, force: true });
  }
});
