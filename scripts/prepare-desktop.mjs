// Stage a self-contained Node runtime and production server for this OS/architecture.
// Preserve unchanged files so Tauri and Cargo can reuse their incremental builds.
import { mkdirSync, rmSync, copyFileSync, chmodSync, existsSync, readFileSync, readdirSync, statSync, writeFileSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { join, resolve } from 'node:path';
import { devNull } from 'node:os';

const root = resolve(import.meta.dirname, '..');
const runtime = join(root, 'src-tauri', 'desktop-runtime');
const cacheFile = join(root, 'src-tauri', '.desktop-cache.json');
const app = join(runtime, 'app');
mkdirSync(app, { recursive: true });

function copyChanged(source, target) {
  if (existsSync(target)) {
    const a = statSync(source), b = statSync(target);
    if (a.size === b.size && readFileSync(source).equals(readFileSync(target))) return;
  }
  copyFileSync(source, target);
}
function syncTree(source, target) {
  mkdirSync(target, { recursive: true });
  const entries = readdirSync(source, { withFileTypes: true });
  const names = new Set(entries.map(entry => entry.name));
  for (const entry of readdirSync(target, { withFileTypes: true })) {
    if (!names.has(entry.name)) rmSync(join(target, entry.name), { recursive: true, force: true });
  }
  for (const entry of entries) {
    const from = join(source, entry.name), to = join(target, entry.name);
    if (entry.isDirectory()) {
      if (existsSync(to) && !statSync(to).isDirectory()) rmSync(to, { force: true });
      syncTree(from, to);
    } else if (entry.isFile()) {
      if (existsSync(to) && statSync(to).isDirectory()) rmSync(to, { recursive: true, force: true });
      copyChanged(from, to);
    } else throw new Error(`Unexpected staged asset: ${from}`);
  }
}

// These files are useful to TypeScript tooling and source-level debugging, but
// are not executed by the bundled server. Keep package metadata and licenses.
function pruneRuntimeMetadata(directory) {
  let count = 0;
  for (const entry of readdirSync(directory, { withFileTypes: true })) {
    const path = join(directory, entry.name);
    if (entry.isDirectory()) count += pruneRuntimeMetadata(path);
    else if (entry.isFile() && (/\.d\.[cm]?ts$/.test(entry.name) || /\.[cm]?[jt]s\.map$/.test(entry.name))) {
      rmSync(path);
      count++;
    }
  }
  return count;
}

syncTree(join(root, 'dist'), join(app, 'dist'));
for (const file of ['package.json', 'package-lock.json']) copyChanged(join(root, file), join(app, file));
let cache = {};
try { cache = JSON.parse(readFileSync(cacheFile, 'utf8')); } catch { /* First build. */ }
const depKey = createHash('sha256').update(readFileSync(join(root, 'package-lock.json')))
  .update(`${process.platform}:${process.arch}:${process.version}:prune-runtime-metadata-v1`).digest('hex');
if (cache.depKey !== depKey || !existsSync(join(app, 'node_modules'))) {
  // Invalidate first, so an interrupted install will be retried next time.
  rmSync(cacheFile, { force: true });
  const npm = process.platform === 'win32' ? 'npm.cmd' : 'npm';
  const env = { ...process.env };
  for (const key of Object.keys(env)) if (key.toLowerCase() === 'npm_config_allow_scripts') delete env[key];
  const result = spawnSync(npm, ['ci', '--omit=dev', '--ignore-scripts', '--no-audit', '--no-fund', '--loglevel=error', `--userconfig=${devNull}`], {
    cwd: app, stdio: 'inherit', env, shell: process.platform === 'win32',
  });
  if (result.status !== 0) throw new Error(`Installing desktop runtime dependencies failed: ${result.error ?? result.status}`);
  const count = pruneRuntimeMetadata(join(app, 'node_modules'));
  console.log(`Removed ${count} development metadata files from the packaged runtime.`);
  cache.depKey = depKey;
} else console.log('Reusing staged production dependencies.');
const node = join(runtime, process.platform === 'win32' ? 'node.exe' : 'node');
const nodeStat = statSync(process.execPath);
const stripNode = process.env.SCRAWL_STRIP_NODE === '1';
if (stripNode && process.platform !== 'darwin') throw new Error('SCRAWL_STRIP_NODE is currently supported only on macOS.');
const nodeKey = `${process.execPath}:${nodeStat.size}:${nodeStat.mtimeMs}:strip=${stripNode}`;
if (cache.nodeKey !== nodeKey || !existsSync(node)) {
  // A failed or interrupted strip/sign must never leave a cached broken runtime.
  rmSync(cacheFile, { force: true });
  copyChanged(process.execPath, node);
  if (process.platform !== 'win32') chmodSync(node, 0o755);
  if (stripNode) {
    for (const [cmd, args] of [['strip', ['-x', node]], ['codesign', ['--force', '--sign', '-', node]]]) {
      const result = spawnSync(cmd, args, { stdio: 'inherit' });
      if (result.status !== 0) throw new Error(`${cmd} failed: ${result.error ?? result.status}`);
    }
    const check = spawnSync(node, ['--version'], { encoding: 'utf8' });
    if (check.status !== 0 || check.stdout.trim() !== process.version) throw new Error('The stripped Node runtime did not pass its version check.');
    console.log('Stripped and ad-hoc signed the staged Node runtime.');
  }
  cache.nodeKey = nodeKey;
} else console.log('Reusing staged Node runtime.');
writeFileSync(cacheFile, JSON.stringify(cache));
