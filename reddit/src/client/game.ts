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

// The wait is the tutorial: the controls as the same key caps / thumb pads the
// game's own legend shows (ui/hud_style.gd KEYBOARD_LEGEND / TOUCH_LEGEND).
// A cap is a key ("W", "SHIFT", "<", ">") or, on touch, a pad: "F" (front, red)
// or "R" (rear, gold) or nothing (either pad), then an arrow ("<>", "^", "v").
const KEYBOARD_LEGEND: [string[], string][] = [
  [['W', 'S'], 'Drive'],
  [['A', 'D'], 'Front'],
  [['<', '>'], 'Rear'],
  [['SHIFT'], 'Boost'],
  [['SPACE'], 'Drift'],
  [['ESC'], 'Pause'],
];
const TOUCH_LEGEND: [string[], string][] = [
  [['F<>'], 'Front'],
  [['R<>'], 'Rear'],
  [['^'], 'Drive'],
  [['F^', 'R^'], 'Boost'],
  [['v'], 'Drift'],
  [['Fv', 'Rv'], 'Brake'],
];
const ARROWS: Record<string, string[]> = {
  '<': ['8,2 3,6 8,10'],
  '>': ['4,2 9,6 4,10'],
  '^': ['2,8 6,3 10,8'],
  v: ['2,4 6,9 10,4'],
  '<>': ['5,3 1,6 5,9', '7,3 11,6 7,9'],
};

function arrow(token: string): SVGSVGElement {
  const ns = 'http://www.w3.org/2000/svg';
  const svg = document.createElementNS(ns, 'svg');
  svg.setAttribute('viewBox', '0 0 12 12');
  svg.setAttribute('aria-hidden', 'true');
  for (const points of ARROWS[token] ?? []) {
    const shape = document.createElementNS(ns, 'polygon');
    shape.setAttribute('points', points);
    svg.append(shape);
  }
  return svg;
}

function cap(token: string, touch: boolean): HTMLElement {
  const node = document.createElement('span');
  if (touch) {
    const side = token[0] === 'F' ? 'front' : token[0] === 'R' ? 'rear' : 'any';
    node.className = `pad ${side}`;
    node.append(arrow(side === 'any' ? token : token.slice(1)));
  } else {
    node.className = 'key';
    if (token in ARROWS) node.append(arrow(token));
    else node.textContent = token;
  }
  return node;
}

function buildLegend(box: HTMLElement, touch: boolean): void {
  for (const [caps, action] of touch ? TOUCH_LEGEND : KEYBOARD_LEGEND) {
    const pair = document.createElement('span');
    pair.className = 'pair';
    for (const token of caps) pair.append(cap(token, touch));
    const word = document.createElement('span');
    word.className = 'word';
    word.textContent = action;
    pair.append(word);
    box.append(pair);
  }
}

buildLegend(el('loader-hint'), matchMedia('(pointer: coarse)').matches);

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
