// Expanded game view: boots the Godot web export and gives it a small bridge
// (`window.FWS`) to the Devvit server.
//
// This replaces the inline <script> of Godot's default HTML shell, which
// Reddit's web view CSP would block. `Engine` comes from index.js and
// `GODOT_CONFIG` + `ENGINE_VERSION` from godot-config.js, both loaded before
// this module. The engine files themselves come gzipped and cached through
// engine-files.ts.

import type { InitResponse } from '../shared/api.ts';
import { serveEngineFiles } from './engine-files.ts';

type GodotEngine = {
  startGame(overrides: { onProgress(current: number, total: number): void }): Promise<void>;
};

declare const Engine: {
  new (config: Record<string, unknown>): GodotEngine;
  getMissingFeatures(options: { threads: boolean }): string[];
};
declare const GODOT_CONFIG: Record<string, unknown>;
/** Hash of the exported engine; missing in a build made before index.wasm.gz existed. */
declare const ENGINE_VERSION: string | undefined;

/** What the Godot side sees through JavaScriptBridge.get_interface("FWS"). */
type Bridge = {
  /** JSON text of GET /api/init, or "" until it arrives (or if it failed). */
  init: string;
  /**
   * Which screen to open first: "" for the normal start, or "leaderboard"
   * when the player tapped Leaderboard on the post (or ?screen=leaderboard).
   */
  screen: string;
  /**
   * Calls the Devvit server and hands the response body to `done` as text
   * ("" on any failure). Godot passes a JavaScriptBridge callback as `done`.
   */
  request(method: string, path: string, body: string, done: (text: string) => void): void;
};

declare global {
  interface Window {
    FWS: Bridge;
  }
}

function el(id: string): HTMLElement {
  const node = document.getElementById(id);
  if (!node) throw new Error(`missing #${id}`);
  return node;
}

const loader = el('loader');
const loaderText = el('loader-text');
const loaderFill = el('loader-fill');

async function requestText(method: string, path: string, body: string): Promise<string> {
  try {
    const response = await fetch(path, {
      method,
      headers: body ? { 'Content-Type': 'application/json' } : undefined,
      body: body || undefined,
    });
    return response.ok ? await response.text() : '';
  } catch (error) {
    console.error(`${method} ${path} failed`, error);
    return '';
  }
}

// The splash page leaves a note here before it opens the game; read it once.
const SCREEN_KEY = 'fws-screen';
let startScreen = new URLSearchParams(location.search).get('screen') ?? '';
try {
  startScreen = startScreen || (localStorage.getItem(SCREEN_KEY) ?? '');
  localStorage.removeItem(SCREEN_KEY);
} catch {
  // Storage can be unavailable in a locked-down web view; start normally.
}

window.FWS = {
  init: '',
  screen: startScreen,
  request(method, path, body, done) {
    void requestText(method, path, body).then(done);
  },
};

// Fetch the daily data while the engine downloads, so the game has it on boot.
void requestText('GET', '/api/init', '').then((text) => {
  window.FWS.init = text;
  if (text) {
    const init = JSON.parse(text) as InitResponse;
    loaderText.textContent = `Loading Daily Circuit #${init.day}`;
  }
});

// The wait is the tutorial: one line about the controls the player will use.
el('loader-hint').textContent = matchMedia('(pointer: coarse)').matches
  ? 'Left thumb steers the front wheels, right thumb the rear. Push up to drive.'
  : 'A / D turn the front wheels. Left / Right arrows turn the rear wheels. W to drive.';

function fail(error: unknown): void {
  console.error(error);
  loader.classList.add('failed');
  loaderText.textContent =
    error instanceof Error ? error.message : 'The game could not start on this device.';
}

const missing = Engine.getMissingFeatures({ threads: false });
if (missing.length > 0) {
  fail(new Error(`This browser is missing: ${missing.join(', ')}`));
} else {
  if (typeof ENGINE_VERSION === 'string') serveEngineFiles(ENGINE_VERSION);
  new Engine(GODOT_CONFIG)
    .startGame({
      onProgress(current, total) {
        if (current > 0 && total > 0) {
          loaderFill.style.width = `${Math.min(100, (current / total) * 100)}%`;
        }
      },
    })
    .then(() => loader.classList.add('done'), fail);
}
