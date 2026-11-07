// Exercise the staged runtime with an isolated data directory on the current platform.
import { spawn } from 'node:child_process';
import { mkdtemp, rm } from 'node:fs/promises';
import { createServer } from 'node:net';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { setTimeout as delay } from 'node:timers/promises';

const listener = createServer();
await new Promise((resolve, reject) => listener.once('error', reject).listen(0, '127.0.0.1', resolve));
const port = listener.address().port;
await new Promise((resolve, reject) => listener.close(error => error ? reject(error) : resolve()));
const data = await mkdtemp(join(tmpdir(), 'scrawl-desktop-smoke-'));
const runtime = resolve(process.env.SCRAWL_RUNTIME_DIR || 'src-tauri/desktop-runtime');
const app = join(runtime, 'app');
const node = join(runtime, process.platform === 'win32' ? 'node.exe' : 'node');
const instance = `smoke-${process.pid}`;
const base = `http://127.0.0.1:${port}`;
const child = spawn(node, [join(app, 'dist/server/index.js')], {
  cwd: app,
  env: { ...process.env, PORT: String(port), HOST: '127.0.0.1', PUBLIC_URL: base, DATA_DIR: data, SCRAWL_DESKTOP_INSTANCE: instance },
  stdio: ['ignore', 'pipe', 'pipe'],
});
let logs = '';
child.stdout.on('data', chunk => { logs += chunk; });
child.stderr.on('data', chunk => { logs += chunk; });
try {
  let ready = false;
  for (let i = 0; i < 100; i++) {
    if (child.exitCode !== null) throw new Error(`Server exited early (${child.exitCode}): ${logs}`);
    try {
      const health = await fetch(`${base}/healthz`, { signal: AbortSignal.timeout(500) });
      if (health.ok && health.headers.get('x-scrawl-instance') === instance) { ready = true; break; }
    } catch { /* Server still starting. */ }
    await delay(100);
  }
  if (!ready) throw new Error(`Server did not start: ${logs}`);
  const page = await fetch(base);
  if (!page.ok || !(await page.text()).includes('<div id="root">')) throw new Error('Editor page missing');
  const fontsResponse = await fetch(`${base}/fonts/scrawl/manifest.json`);
  if (!fontsResponse.ok) throw new Error('Font manifest missing');
  const fonts = await fontsResponse.json();
  if (fonts.length !== 5) throw new Error('Expected five Scrawl fonts');
  for (const font of fonts) for (const subset of font.subsets) {
    const response = await fetch(`${base}/fonts/scrawl/${encodeURIComponent(subset.file)}`);
    const bytes = new Uint8Array(await response.arrayBuffer());
    if (!response.ok || String.fromCharCode(...bytes.slice(0, 4)) !== 'wOF2') throw new Error(`Font asset missing or invalid: ${subset.file}`);
  }
  const created = await fetch(`${base}/api/boards`, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ folder: '', name: 'Smoke board' }) });
  if (created.status !== 201) throw new Error(`Board creation failed: ${created.status} ${await created.text()}`);
  const tree = await fetch(`${base}/api/tree`);
  if (!tree.ok || !(await tree.text()).includes('Smoke board')) throw new Error('Created board missing from tree');
  const mcp = await fetch(`${base}/mcp`, { method: 'POST', headers: { 'content-type': 'application/json', accept: 'application/json, text/event-stream' }, body: JSON.stringify({ jsonrpc: '2.0', id: 1, method: 'tools/list' }) });
  if (!mcp.ok || !(await mcp.text()).includes('add_elements')) throw new Error(`MCP tools unavailable: ${mcp.status}`);
  const draw = await fetch(`${base}/mcp`, { method: 'POST', headers: { 'content-type': 'application/json', accept: 'application/json, text/event-stream' }, body: JSON.stringify({ jsonrpc: '2.0', id: 2, method: 'tools/call', params: { name: 'add_elements', arguments: { board: 'Smoke board', elements: [{ type: 'rectangle', id: 'shape', x: 10, y: 10, width: 200, height: 100, label: 'Hello Scrawl' }, { type: 'text', id: 'custom-font', x: 20, y: 140, text: 'Inter text', fontFamily: 10101 }] } } }) });
  const result = await draw.json();
  if (!draw.ok || result.error || result.result?.isError) throw new Error(`MCP drawing failed: ${JSON.stringify(result)}`);
  const board = await fetch(`${base}/api/board?id=Smoke%20board`);
  const content = await board.json();
  if (!board.ok || !content.scene.elements.some(element => element.id === 'shape')) throw new Error('MCP drawing was not saved');
  if (!content.scene.elements.some(element => element.id === 'custom-font' && element.fontFamily === 10101)) throw new Error('Custom-font text was not preserved');
  async function callTool(name, args) {
    const response = await fetch(`${base}/mcp`, { method: 'POST', headers: { 'content-type': 'application/json', accept: 'application/json, text/event-stream' }, body: JSON.stringify({ jsonrpc: '2.0', id: 3, method: 'tools/call', params: { name, arguments: args } }) });
    const payload = await response.json();
    if (!response.ok || payload.error || payload.result?.isError) throw new Error(`${name} failed: ${JSON.stringify(payload)}`);
    return payload.result;
  }
  async function readEvents(lastId) {
    const response = await fetch(`${base}/api/events`, { headers: lastId ? { 'Last-Event-ID': lastId } : {}, signal: AbortSignal.timeout(5000) });
    if (!response.ok || !response.body) throw new Error('Event stream unavailable');
    const reader = response.body.getReader();
    const decoder = new TextDecoder();
    let text = '';
    try {
      while (!text.includes('event: ready\n')) {
        const part = await reader.read();
        if (part.done) throw new Error('Event stream closed before checkpoint');
        text += decoder.decode(part.value, { stream: true });
      }
    } finally { await reader.cancel(); }
    const checkpoint = text.match(/id: ([^\n]+)\nevent: ready\n/)?.[1];
    if (!checkpoint) throw new Error('Event stream checkpoint missing');
    return { checkpoint, text };
  }
  const checkpoint = await readEvents();
  await callTool('update_elements', { board: 'Smoke board', updates: [{ id: 'shape', x: 42 }] });
  await callTool('search_library', { queries: ['test'] });
  await callTool('move_board', { from: 'Smoke board', to: 'Folder/Moved board' });
  const replay = await readEvents(checkpoint.checkpoint);
  if (!replay.text.includes('"type":"moved"') || !replay.text.includes('"replayed":true')) throw new Error('Missed board move was not replayed');
  const moved = await fetch(`${base}/api/board?id=Folder%2FMoved%20board`);
  const movedBoard = await moved.json();
  if (!moved.ok || !movedBoard.scene.elements.some(element => element.id === 'shape' && element.x === 42)) throw new Error('Updated board did not survive move');
  await callTool('delete_elements', { board: 'Folder/Moved board', ids: ['shape'] });
  const library = await fetch(`${base}/api/library`);
  if (!library.ok || !Array.isArray((await library.json()).libraryItems)) throw new Error('Library unavailable');
  console.log('Desktop runtime smoke test passed: startup, editor, fonts, boards, MCP drawing/editing/moving, library and persistence.');
} finally {
  if (child.exitCode === null && child.signalCode === null) {
    child.kill();
    await Promise.race([new Promise(resolve => child.once('exit', resolve)), delay(5000)]);
  }
  await rm(data, { recursive: true, force: true, maxRetries: 5, retryDelay: 200 });
}
