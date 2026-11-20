// Checks the engine download shim (engine-files.ts) with a fake network and a
// fake Cache API: the unzipped engine is byte-for-byte the original, a second
// start downloads nothing, and every failure falls back to the plain file.

import assert from 'node:assert/strict';
import { test } from 'node:test';
import { gzipSync } from 'node:zlib';
import { serveEngineFiles } from './engine-files.ts';

// A stand-in engine: the wasm signature, then enough bytes for many chunks.
const WASM = new Uint8Array(300_000);
WASM.set([0x00, 0x61, 0x73, 0x6d, 0x01, 0x00, 0x00, 0x00]);
for (let i = 8; i < WASM.length; i++) WASM[i] = (i * 7919) % 251;
const WASM_GZ = new Uint8Array(gzipSync(WASM));
const PCK = new Uint8Array([1, 2, 3, 4, 5]);

class FakeCache {
  readonly files = new Map<string, { body: ArrayBuffer; type: string }>();
  async match(path: string): Promise<Response | undefined> {
    const file = this.files.get(path);
    return file && new Response(file.body.slice(0), { headers: { 'Content-Type': file.type } });
  }
  async put(path: string, response: Response): Promise<void> {
    const body = await response.arrayBuffer();
    this.files.set(path, { body, type: response.headers.get('Content-Type') ?? '' });
  }
  async delete(path: string): Promise<boolean> {
    return this.files.delete(path);
  }
}

class FakeCaches {
  readonly stores = new Map<string, FakeCache>();
  async open(name: string): Promise<FakeCache> {
    let cache = this.stores.get(name);
    if (!cache) this.stores.set(name, (cache = new FakeCache()));
    return cache;
  }
  async keys(): Promise<string[]> {
    return [...this.stores.keys()];
  }
  async delete(name: string): Promise<boolean> {
    return this.stores.delete(name);
  }
}

type Files = Record<string, Uint8Array | number>;

/** Installs a fake window.fetch over `files` (a number = that HTTP status) and the shim. */
function setUp(files: Files, options: { caches?: FakeCaches | null; unzip?: boolean } = {}) {
  const requests: string[] = [];
  const fakeWindow = {
    fetch: async (input: unknown): Promise<Response> => {
      const path = String(input);
      requests.push(path);
      const file = files[path];
      if (file === undefined || typeof file === 'number') {
        return new Response('not found', { status: typeof file === 'number' ? file : 404 });
      }
      return new Response(file.slice(), { headers: { 'Content-Type': 'application/octet-stream' } });
    },
  };
  const cacheStorage = options.caches === undefined ? new FakeCaches() : options.caches;
  const brokenCaches = {
    open: () => Promise.reject(new Error('storage blocked')),
    keys: () => Promise.reject(new Error('storage blocked')),
  };
  const decompression = globalThis.DecompressionStream;
  Object.assign(globalThis, {
    window: fakeWindow,
    caches: cacheStorage ?? brokenCaches,
    DecompressionStream: options.unzip === false ? undefined : decompression,
  });
  try {
    serveEngineFiles('v2');
  } finally {
    Object.assign(globalThis, { DecompressionStream: decompression });
  }
  const load = async (path: string) => {
    const response = await fakeWindow.fetch(path);
    return { response, bytes: new Uint8Array(await response.arrayBuffer()) };
  };
  return { requests, caches: cacheStorage, load, fetch: fakeWindow.fetch };
}

/** Lets the shim's fire-and-forget cache writes finish. */
async function settle(): Promise<void> {
  for (let i = 0; i < 20; i++) await new Promise((resolve) => setImmediate(resolve));
}

test('index.wasm is index.wasm.gz unzipped, typed for streaming compile', async () => {
  const { requests, load } = setUp({ 'index.wasm.gz': WASM_GZ, 'index.wasm': WASM });
  const { response, bytes } = await load('index.wasm');
  assert.equal(response.headers.get('Content-Type'), 'application/wasm');
  assert.deepEqual(bytes, WASM);
  assert.deepEqual(requests, ['index.wasm.gz']);
});

test('a second start downloads nothing', async () => {
  const { requests, load } = setUp({ 'index.wasm.gz': WASM_GZ, 'index.pck': PCK });
  await load('index.wasm');
  await load('index.pck');
  await settle();
  assert.deepEqual((await load('index.wasm')).bytes, WASM);
  assert.deepEqual((await load('index.pck')).bytes, PCK);
  assert.deepEqual(requests, ['index.wasm.gz', 'index.pck']);
});

test('a missing index.wasm.gz falls back to index.wasm', async () => {
  const { requests, load } = setUp({ 'index.wasm.gz': 404, 'index.wasm': WASM });
  assert.deepEqual((await load('index.wasm')).bytes, WASM);
  assert.deepEqual(requests, ['index.wasm.gz', 'index.wasm']);
});

test('without DecompressionStream the plain index.wasm is fetched', async () => {
  const { requests, load } = setUp({ 'index.wasm.gz': WASM_GZ, 'index.wasm': WASM }, { unzip: false });
  assert.deepEqual((await load('index.wasm')).bytes, WASM);
  assert.deepEqual(requests, ['index.wasm']);
});

test('blocked storage still serves the small download, every time', async () => {
  const { requests, load } = setUp({ 'index.wasm.gz': WASM_GZ }, { caches: null });
  assert.deepEqual((await load('index.wasm')).bytes, WASM);
  await settle();
  assert.deepEqual((await load('index.wasm')).bytes, WASM);
  assert.deepEqual(requests, ['index.wasm.gz', 'index.wasm.gz']);
});

test('a body a server already unzipped passes through unchanged', async () => {
  const { load } = setUp({ 'index.wasm.gz': WASM });
  assert.deepEqual((await load('index.wasm')).bytes, WASM);
});

test('a damaged cached engine is forgotten, so the next start downloads it again', async () => {
  const caches = new FakeCaches();
  const cache = await caches.open('fws-engine-v2');
  const damaged = new Uint8Array(2_000).fill(7);
  damaged.set(WASM_GZ.subarray(0, 40));
  cache.files.set('index.wasm.gz', { body: damaged.buffer, type: 'application/gzip' });
  const { load } = setUp({ 'index.wasm.gz': WASM_GZ }, { caches });
  await assert.rejects(load('index.wasm'));
  await settle();
  assert.equal(cache.files.has('index.wasm.gz'), false);
});

test('other requests pass through and older engine caches are deleted', async () => {
  const caches = new FakeCaches();
  await caches.open('fws-engine-v1');
  await caches.open('someone-else');
  const { requests, fetch } = setUp({ 'splash.js': PCK, 'index.wasm': WASM }, { caches });
  await fetch('splash.js');
  await settle();
  assert.deepEqual(requests, ['splash.js']);
  assert.deepEqual(await caches.keys(), ['someone-else']);
});
