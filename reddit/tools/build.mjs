// Bundles the web view scripts into public/ and the Devvit server into
// dist/server/. `--watch` keeps rebuilding; `devvit playtest` runs that mode
// (see "scripts" in devvit.json) and re-uploads on every change.
//
// The Godot engine files in public/ are produced separately by
// tools/export-godot.mjs, because they only change when the game does.

import { fileURLToPath } from 'node:url';
import * as esbuild from 'esbuild';

const root = fileURLToPath(new URL('..', import.meta.url));
const watch = process.argv.includes('--watch');

/** @type {import('esbuild').BuildOptions} */
const shared = {
  absWorkingDir: root,
  bundle: true,
  minify: !watch,
  logLevel: 'info',
};

/** @type {import('esbuild').BuildOptions} */
const client = {
  ...shared,
  entryPoints: ['src/client/splash.ts', 'src/client/game.ts'],
  outdir: 'public',
  format: 'esm',
  platform: 'browser',
  target: 'es2020',
};

/** @type {import('esbuild').BuildOptions} */
const server = {
  ...shared,
  entryPoints: ['src/server/index.ts'],
  outfile: 'dist/server/index.cjs',
  format: 'cjs',
  platform: 'node',
  target: 'node22',
};

if (watch) {
  const contexts = await Promise.all([esbuild.context(client), esbuild.context(server)]);
  await Promise.all(contexts.map((context) => context.watch()));
} else {
  await Promise.all([esbuild.build(client), esbuild.build(server)]);
}
