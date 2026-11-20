// Serves the Godot engine's two big downloads (index.wasm and index.pck) to its
// loader in index.js faster than the plain files would:
//
// - index.wasm comes from index.wasm.gz (about 10 MB instead of 38 MB) and is
//   unzipped in the browser as it arrives, so the engine still compiles while
//   it downloads and the loading bar (which counts unzipped bytes against the
//   sizes in GODOT_CONFIG) still fills.
// - Both files are kept in the Cache API under the build's version, so a player
//   who comes back for tomorrow's circuit starts without downloading them again.
//   A new build has a new version; the old cache is deleted.
//
// Godot's loader fetches both files with the global fetch, so this wraps
// window.fetch for exactly those two names. Whatever fails (no
// DecompressionStream, storage blocked in the web view, a failed download)
// falls back to the plain file, which is what the loader would have fetched
// anyway.

const CACHE_PREFIX = 'fws-engine-';
const WASM = 'index.wasm';
const WASM_GZ = 'index.wasm.gz';
const PCK = 'index.pck';

type Chunk = Uint8Array<ArrayBuffer>;
type Bytes = ReadableStream<Chunk>;

export function serveEngineFiles(version: string): void {
  const plainFetch = window.fetch.bind(window);
  const cacheName = CACHE_PREFIX + version;
  let cachePromise: Promise<Cache | null> | null = null;

  function openCache(): Promise<Cache | null> {
    cachePromise ??= (async () => {
      try {
        return await caches.open(cacheName);
      } catch {
        return null;   // no Cache API here (or storage is blocked): download every time
      }
    })();
    return cachePromise;
  }

  /** `path` from this build's cache, else from the network (and then cached). */
  async function cachedFetch(path: string): Promise<Response> {
    const cache = await openCache();
    if (cache) {
      try {
        const hit = await cache.match(path);
        if (hit) {
          console.info(`[engine] ${path} from the cache`);
          return hit;
        }
      } catch {
        // A broken cache is just a miss.
      }
    }
    const response = await plainFetch(path);
    if (cache && response.ok) {
      // Stored once the whole body has arrived; an interrupted download stores nothing.
      cache.put(path, response.clone()).catch(() => undefined);
    }
    return response;
  }

  /** Forgets a cached file that turned out to be broken, so the next start downloads it. */
  function forget(path: string): void {
    void openCache().then((cache) => cache?.delete(path)).catch(() => undefined);
  }

  async function fetchWasm(): Promise<Response> {
    let zipped: Response;
    try {
      zipped = await cachedFetch(WASM_GZ);
    } catch {
      return plainFetch(WASM);
    }
    if (!zipped.ok || !zipped.body) return plainFetch(WASM);
    const body = await unzipIfNeeded(zipped.body, () => forget(WASM_GZ));
    // instantiateStreaming insists on this type; the loader copies these headers.
    return new Response(body, { headers: { 'Content-Type': 'application/wasm' } });
  }

  void dropOtherVersions(cacheName);

  const canUnzip = typeof DecompressionStream === 'function';
  window.fetch = (input, init) => {
    if (init === undefined && input === WASM && canUnzip) return fetchWasm();
    if (init === undefined && input === PCK) return cachedFetch(PCK);
    return plainFetch(input, init);
  };
}

/**
 * The body unzipped if it starts with the gzip signature, else unchanged (in
 * case a server already undid the gzip on the way). `onError` runs if the
 * unzip fails partway, e.g. on a damaged cached copy.
 */
async function unzipIfNeeded(body: Bytes, onError: () => void): Promise<Bytes> {
  const reader = body.getReader();
  const first = await reader.read();
  const head = first.value;
  const whole: Bytes = new ReadableStream<Chunk>({
    start(controller) {
      if (head) controller.enqueue(head);
      if (first.done) controller.close();
    },
    async pull(controller) {
      const { done, value } = await reader.read();
      if (done) controller.close();
      else controller.enqueue(value);
    },
    cancel(reason) {
      return reader.cancel(reason);
    },
  });
  const gzipped = head !== undefined && head[0] === 0x1f && head[1] === 0x8b;
  return gzipped ? watchErrors(whole.pipeThrough(new DecompressionStream('gzip')), onError) : whole;
}

/** Passes `stream` through, calling `onError` if reading it fails. */
function watchErrors(stream: Bytes, onError: () => void): Bytes {
  const reader = stream.getReader();
  return new ReadableStream<Chunk>({
    async pull(controller) {
      try {
        const { done, value } = await reader.read();
        if (done) controller.close();
        else controller.enqueue(value);
      } catch (error) {
        onError();
        controller.error(error);
      }
    },
    cancel(reason) {
      return reader.cancel(reason);
    },
  });
}

/** Deletes engine caches left by older builds (each one holds ~10 MB). */
async function dropOtherVersions(keep: string): Promise<void> {
  try {
    for (const name of await caches.keys()) {
      if (name.startsWith(CACHE_PREFIX) && name !== keep) await caches.delete(name);
    }
  } catch {
    // No Cache API: nothing was stored.
  }
}
