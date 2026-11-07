import { spawn } from 'node:child_process';
import { mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { expect, it } from 'vitest';
import { Store } from '../server/store';

it('serializes read-modify-write operations from separate server processes', async () => {
  const dir = await mkdtemp(join(tmpdir(), 'scrawl-lock-test-'));
  try {
    const store = new Store(dir, 'test');
    await store.init();
    await store.create('shared', 'test');
    const worker = (name: string) => new Promise<void>((resolvePromise, reject) => {
      const child = spawn(process.execPath, ['--experimental-strip-types', resolve('test/fixtures/store-writer.mjs'), dir, name], { stdio: ['ignore', 'ignore', 'pipe'] });
      let error = '';
      child.stderr.on('data', chunk => { error += chunk; });
      child.on('error', reject);
      child.on('exit', code => code === 0 ? resolvePromise() : reject(new Error(`worker ${name} exited ${code}: ${error}`)));
    });
    await Promise.all([worker('a'), worker('b')]);
    const ids = (await store.read('shared')).scene.elements.map(element => element.id).sort();
    expect(ids).toEqual(['a-0', 'a-1', 'a-2', 'a-3', 'b-0', 'b-1', 'b-2', 'b-3']);
  } finally {
    await rm(dir, { recursive: true, force: true, maxRetries: 5, retryDelay: 100 });
  }
}, 30_000);
