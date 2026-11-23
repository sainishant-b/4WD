// Exports the Godot project (the parent folder) with its "Web" preset and
// installs the result into public/ for the Devvit web view. Then writes the
// circuits' shapes into src/client/tracks.ts for the post's start screen.
//
// Godot's own index.html is thrown away: it boots the engine from an inline
// <script>, which Reddit's CSP blocks. Only the engine settings are lifted out
// of it, into public/godot-config.js; public/game.html + src/client/game.ts
// are the replacement shell.
//
// The engine (index.wasm, ~38 MB) is also written gzipped as index.wasm.gz
// (~10 MB): Devvit uploads web-view files as they are, so this is the only way
// to be sure players download the small one. game.ts unzips it in the browser
// and keeps it in the Cache API under ENGINE_VERSION (a hash of the build), so
// a returning player downloads nothing. The raw index.wasm stays as the
// fallback for browsers without DecompressionStream.
//
// Usage: node tools/export-godot.mjs
//   GODOT=<path to a Godot 4 editor binary> overrides the lookup below.
//
// Godot 4.7 on Windows can finish an export and then never exit (seen
// 2026-11-22, on older commits too: it prints its exit warnings and hangs), so
// each Godot run here is watched: once its output is all there it gets a grace
// period, then that Godot (and only it) is stopped and the script carries on.

import { spawn, spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { copyFileSync, existsSync, mkdirSync, readdirSync, readFileSync, rmSync, statSync, writeFileSync } from 'node:fs';
import { homedir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { constants as zlib, gzipSync } from 'node:zlib';

const root = fileURLToPath(new URL('..', import.meta.url));
const project = join(root, '..');
const exportDir = join(root, '.export');
const publicDir = join(root, 'public');

/** Engine files the web view needs; everything else in the export is unused. */
const ENGINE_FILES = [
  'index.js',
  'index.wasm',
  'index.pck',
  'index.audio.worklet.js',
  'index.audio.position.worklet.js',
];

function findGodot() {
  if (process.env.GODOT) return process.env.GODOT;

  // The official Windows zip unpacks to a folder holding
  // Godot_v4.x-stable_win64.exe and a _console.exe twin; prefer the console
  // build so export errors reach this terminal.
  const downloads = join(homedir(), 'Downloads');
  const found = [];
  const visit = (dir, depth) => {
    for (const name of readdirSync(dir)) {
      const path = join(dir, name);
      const isDir = statSync(path, { throwIfNoEntry: false })?.isDirectory() ?? false;
      if (isDir && depth > 0 && /^Godot_v4/i.test(name)) visit(path, depth - 1);
      else if (!isDir && /^Godot_v4.*\.exe$/i.test(name)) found.push(path);
    }
  };
  if (existsSync(downloads)) visit(downloads, 1);
  found.sort((a, b) => Number(/_console\.exe$/i.test(b)) - Number(/_console\.exe$/i.test(a)));
  return found[0] ?? 'godot';
}

const godot = findGodot();
console.log(`Godot: ${godot}`);

/**
 * Runs Godot with `args` and waits for it to exit. If `finished()` has been
 * true for `graceMs` and Godot is still running, its process tree is stopped
 * and the run counts as a success (see the note at the top).
 */
function runGodot(args, finished, graceMs = 20_000) {
  return new Promise((resolve, reject) => {
    const child = spawn(godot, args, { stdio: 'inherit' });
    let finishedAt = 0;
    let stopped = false;
    const watch = setInterval(() => {
      if (!finished()) return;
      finishedAt ||= Date.now();
      if (stopped || Date.now() - finishedAt < graceMs) return;
      stopped = true;
      console.warn('Godot finished its work but has not exited; stopping it.');
      if (process.platform === 'win32') {
        spawnSync('taskkill', ['/PID', String(child.pid), '/T', '/F'], { stdio: 'ignore' });
      } else {
        child.kill('SIGKILL');
      }
    }, 1000);
    child.on('error', (error) => {
      clearInterval(watch);
      reject(error);
    });
    child.on('exit', (code, signal) => {
      clearInterval(watch);
      if (code === 0 || stopped) resolve();
      else reject(new Error(`Godot exited with ${code ?? signal}`));
    });
  });
}

rmSync(exportDir, { recursive: true, force: true });
mkdirSync(exportDir, { recursive: true });

await runGodot(
  ['--headless', '--path', project, '--export-release', 'Web', join(exportDir, 'index.html')],
  () => ['index.html', ...ENGINE_FILES].every((file) => existsSync(join(exportDir, file))),
);

for (const file of ENGINE_FILES) {
  const from = join(exportDir, file);
  if (!existsSync(from)) throw new Error(`Godot export did not produce ${file}`);
  copyFileSync(from, join(publicDir, file));
}

const html = readFileSync(join(exportDir, 'index.html'), 'utf8');
const config = /const GODOT_CONFIG = (\{.*\});/.exec(html)?.[1];
if (!config) throw new Error('GODOT_CONFIG not found in the exported index.html');
if (/const GODOT_THREADS_ENABLED = true/.test(html)) {
  throw new Error('The Web preset has thread support on; Reddit web views cannot run threaded builds.');
}
// The engine gzipped (see the top of this file), and a version for the
// browser's engine cache: it changes whenever the engine or the game does.
const wasm = readFileSync(join(publicDir, 'index.wasm'));
writeFileSync(
  join(publicDir, 'index.wasm.gz'),
  gzipSync(wasm, { level: zlib.Z_BEST_COMPRESSION, memLevel: 9 }),
);
const engineVersion = createHash('sha256')
  .update(wasm)
  .update(readFileSync(join(publicDir, 'index.pck')))
  .digest('hex')
  .slice(0, 16);

writeFileSync(
  join(publicDir, 'godot-config.js'),
  '// Generated by tools/export-godot.mjs. Do not edit.\n' +
    `const GODOT_CONFIG = ${config};\n` +
    '// Names the browser cache that keeps index.wasm.gz and index.pck (src/client/engine-files.ts).\n' +
    `const ENGINE_VERSION = ${JSON.stringify(engineVersion)};\n`,
);

for (const file of [...ENGINE_FILES, 'index.wasm.gz', 'godot-config.js']) {
  const megabytes = statSync(join(publicDir, file)).size / 1_048_576;
  console.log(`  public/${file}  ${megabytes.toFixed(2)} MB`);
}

// The circuits' shapes for the post's start screen, straight from the game, so
// the splash's track picture always matches the road (src/client/tracks.ts).
const tracksFile = join(root, 'src', 'client', 'tracks.ts');
const shapesFrom = Date.now();
await runGodot(
  ['--headless', '--path', project, '-s', join(root, 'tools', 'track-shapes.gd'), '--', tracksFile],
  () => (statSync(tracksFile, { throwIfNoEntry: false })?.mtimeMs ?? 0) >= shapesFrom,
  5_000,
);
